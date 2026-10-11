import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

// Combine retained human review manifests; never turn filename matches into
// asserted runtime roles. Original PNGs are read, never modified or copied.
const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const source = 'C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk';
const read = relative => JSON.parse(fs.readFileSync(path.join(project, relative), 'utf8'));
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const inputs = ['provenance/pirates-water-library-pak0-3.json', 'provenance/pirates-water-library-pak4-8.json'];
const [early, late] = inputs.map(read);
const supplied = new Set(read('provenance/pirates-water-textures.json').assets.map(a => path.resolve(a.source_path)));
const dispositions = { recommend: 'recommended', recommended: 'recommended', backup: 'backup', reference_only: 'reference_only', related: 'reference_only', reject_render: 'excluded', reject: 'excluded', archive: 'archive' };
const assets = [...early.assets, ...late.assets].map(a => {
  if (!dispositions[a.disposition]) throw new Error(`Unknown disposition ${a.disposition}`);
  return { ...a, disposition: dispositions[a.disposition], original_review_disposition: a.disposition,
    notes: [...new Set(a.notes.split('; ').map(s => s.trim()).filter(Boolean))].join('; '),
    original_runtime_role_verified: false,
    previously_supplied: supplied.has(path.resolve(a.source_path)),
    use_status: 'research_candidate_not_newly_bound_by_this_library_scan' };
}).sort((a, b) => a.source_path.localeCompare(b.source_path));
const byPath = new Map(assets.map(a => [path.resolve(a.source_path), a]));
if (byPath.size !== assets.length) throw new Error('Duplicate candidate source path');
const inventory = [];
const pakCounts = {};
for (let i = 0; i <= 8; i++) {
  const pak = `Pak${i}`;
  const directory = path.join(source, pak);
  const files = fs.readdirSync(directory).filter(n => /\.png$/i.test(n)).sort();
  pakCounts[pak] = files.length;
  for (const filename of files) {
    const p = path.join(directory, filename);
    const bytes = fs.readFileSync(p);
    const digest = sha(bytes);
    const a = byPath.get(path.resolve(p));
    if (a && a.sha256 !== digest) throw new Error(`Source hash mismatch: ${p}`);
    inventory.push({ pak, filename, source_path: p.replaceAll('\\', '/'), byte_length: bytes.length, sha256: digest,
      review_class: a?.disposition ?? 'overview_only_not_selected', category: a?.category ?? null });
  }
}
if (inventory.length !== 3840 || assets.length !== 486) throw new Error('Inventory changed: rerun visual review');
const inventoryPaths = new Set(inventory.map(a => path.resolve(a.source_path)));
for (const p of byPath.keys()) if (!inventoryPaths.has(p)) throw new Error(`Candidate outside current inventory: ${p}`);
const counts = {};
for (const a of assets) counts[a.disposition] = (counts[a.disposition] ?? 0) + 1;
const art = assets.filter(a => ['recommended', 'backup'].includes(a.disposition));
const duplicates = new Map();
for (const a of assets) {
  const group = duplicates.get(a.sha256) ?? [];
  group.push(a.source_path); duplicates.set(a.sha256, group);
}
const manifest = {
  schema_version: 1, assembled_at_utc: new Date().toISOString(), source_root: source,
  scope: 'All 3840 PNG filenames and visual overview reviewed by two specialists; selected candidates separately inspected in RGB and alpha. Static resource dependencies distinguished from unknown original runtime/GPU selection.',
  original_game_executed: false, original_source_modified: false, new_product_bindings_from_this_scan: false,
  counts: { all_png: inventory.length, pak_counts: pakCounts, classified_records: assets.length,
    dispositions: counts, recommended_and_backup: art.length, new_recommended_and_backup: art.filter(a => !a.previously_supplied).length,
    human_reviewed_pages: early.actual_reviewed_page_count + late.scan_counts.keyword_candidate_pages_reviewed + late.scan_counts.unmatched_overview_pages_reviewed + late.scan_counts.supplement_candidate_pages_reviewed },
  review_manifests: inputs.map(p => ({ path: p, sha256: sha(fs.readFileSync(path.join(project, p))) })),
  limitations: ['Overview thumbnails do not prove the role of arbitrary encoded or featureless textures.',
    'Original Caribbean shoreline/maps are reference data; not generic Ming-era sea art.',
    'Numbered families are candidate variants; continuous animation not established without a controller binding.',
    'PNG previews and static NIF/shader references do not verify original-game draw calls.',
    'The initial 27 bindings are recorded separately; this scan does not import or apply another 96 textures.'],
  duplicate_byte_groups: [...duplicates].filter(([, paths]) => paths.length > 1).map(([sha256, source_paths]) => ({ sha256, source_paths })),
  assets, inventory
};
const json = 'provenance/pirates-water-library.json';
fs.writeFileSync(path.join(project, json), JSON.stringify(manifest, null, 2) + '\n');
const columns = ['pak', 'filename', 'width', 'height', 'disposition', 'category', 'confidence', 'alpha_min', 'alpha_max', 'alpha_nonzero_fraction', 'rgb_constant', 'previously_supplied', 'notes', 'source_path', 'sha256'];
const cell = value => `"${String(value ?? '').replaceAll('"', '""')}"`;
fs.writeFileSync(path.join(project, 'docs/migration/pirates-water-library.csv'), '\uFEFF' + [columns, ...assets.map(a => columns.map(c => a[c]))].map(row => row.map(cell).join(',')).join('\r\n') + '\r\n');
console.log('WATER_LIBRARY_ASSEMBLED ' + JSON.stringify(manifest.counts));
