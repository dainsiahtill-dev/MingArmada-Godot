"""Static checks for the design archive; never claims runtime or balance proof."""
from pathlib import Path
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
DESIGN = Path(__file__).resolve().parent
RESEARCH = ROOT / 'docs/research/2026-10-29-naval-tactics'
BIO_RESEARCH = ROOT / 'docs/research/2026-10-29-zheng-chenggong'
paths = sorted([*DESIGN.glob('*.md'), *RESEARCH.glob('*.md'), *BIO_RESEARCH.glob('*.md'),
                ROOT / 'PRODUCT.md', ROOT / 'CONTEXT.md', ROOT / 'docs/narrative/README.md'])
errors, file_records = [], []
texts = {}
local_links = 0
for path in paths:
    raw = path.read_bytes()
    content = raw.decode('utf-8-sig')
    texts[path] = content
    relative = path.relative_to(ROOT).as_posix()
    if '\ufffd' in content:
        errors.append(f'{relative}: replacement character')
    for number, line in enumerate(content.splitlines(), 1):
        if line.rstrip() != line:
            errors.append(f'{relative}:{number}: trailing whitespace')
    for target in re.findall(r'\[[^\]]+\]\(([^\n)]+)\)', content):
        if target.startswith(('http:', 'https:', 'mailto:', '#')):
            continue
        target = target.split('#', 1)[0]
        if target:
            local_links += 1
            if not (path.parent / target).resolve().exists():
                errors.append(f'{relative}: broken local link {target}')
    definitions = set(re.findall(r'^\[([^\]]+)\]:', content, re.M))
    for ref in re.findall(r'\]\[([^\]]+)\]', content):
        if ref not in definitions:
            errors.append(f'{relative}: unresolved Markdown reference {ref}')
    file_records.append({'path': relative, 'lines': len(content.splitlines()),
                         'sha256': hashlib.sha256(raw).hexdigest()})

groups = {}


def group(name, path, pattern, expected, section=None):
    if path not in texts:
        errors.append(f'{name}: missing canonical document {path.name}')
        groups[name] = set()
        return
    content = texts[path]
    if section:
        start, end = section
        if start not in content or end not in content.split(start, 1)[1]:
            errors.append(f'{name}: canonical section missing')
            groups[name] = set()
            return
        content = content.split(start, 1)[1].split(end, 1)[0]
    ids = re.findall(pattern, content, re.M)
    groups[name] = set(ids)
    if len(ids) != expected or len(set(ids)) != expected:
        errors.append(f'{name}: expected {expected} unique definitions, got {len(ids)}/{len(set(ids))}')


table_groups = [
    ('WPN-', RESEARCH / 'weapons-and-firearms.md', 28),
    ('WJ-C', RESEARCH / 'wujing-core-coverage.md', 25),
    ('WJ-S', RESEARCH / 'wujing-core-coverage.md', 5),
    ('SHIP-', DESIGN / 'WORLD-AND-GAMEPLAY.md', 20),
    ('CAREER-', DESIGN / 'careers-factions-and-economy.md', 10),
    ('WORLD-BOARD-', DESIGN / 'careers-factions-and-economy.md', 8),
    ('HERO-ROLE-', DESIGN / 'heroes-and-companions.md', 24),
    ('CREW-', DESIGN / 'crew-professions-and-shipboard-life.md', 36),
    ('HREL-', DESIGN / 'hero-roster-and-relationships.md', 13),
    ('WREL-', DESIGN / 'world-bible-and-regions.md', 12),
    ('REG-', DESIGN / 'world-bible-and-regions.md', 7),
]
for prefix, path, expected in table_groups:
    section = ('### 3.1 弓弩、投射器与普通载荷', '## 4.') if prefix == 'WPN-' else None
    group(prefix, path, r'^\|\s*[*`]{0,2}(' + prefix + r'[0-9]+)', expected, section)
group('HERO-SYS-', DESIGN / 'heroes-and-companions.md', r'^\*\*(HERO-SYS-[0-9]+)', 12)
group('NPC-H', DESIGN / 'hero-roster-and-relationships.md', r'^## (NPC-H[0-9]+)', 12)
group('MISSION-', DESIGN / 'mission-chains-and-encounters.md', r'^### (MISSION-[0-9]+)', 24)
group('world_nodes', DESIGN / 'world-bible-and-regions.md', r'^### `([^`]+)`', 13)
group('POL-', DESIGN / 'world-bible-and-regions.md', r'^\| `(POL-[A-Z]+)`', 7)
group('NPC-R', DESIGN / 'rival-captains-and-bounties.md', r'^## (NPC-R[0-9]+)', 6)
group('CASE-R', DESIGN / 'rival-captains-and-bounties.md', r'^\| `(CASE-R[0-9]+)`', 3)
group('CH-', DESIGN / 'dual-protagonist-campaign.md', r'^#{2,3}\s+(CH-[0-9]+)', 24)
group('taiwan_phases', BIO_RESEARCH / 'taiwan-campaign-phases.md', r'^### (T[0-9]{2})\b', 10)

# Every fully qualified design ID refers to a definition, not just another mention.
for path, content in texts.items():
    for prefix, defined in groups.items():
        if prefix in ('world_nodes', 'POL-', 'taiwan_phases'):
            continue
        for referenced in set(re.findall(r'\b' + re.escape(prefix) + r'[0-9]+\b', content)):
            if referenced not in defined:
                errors.append(f'{path.name}: undefined {referenced}')

mission_text = texts.get(DESIGN / 'mission-chains-and-encounters.md', '')
mission_edges = {}
mission_blocks = re.findall(r'^### (MISSION-[0-9]+)[^\n]*\n(.*?)(?=^### MISSION-|^## |\Z)', mission_text, re.M | re.S)
for mission_id, body in mission_blocks:
    result_lines = [line for line in body.splitlines() if '**四种结果／后继：**' in line]
    if len(result_lines) != 1 or any(label not in result_lines[0] for label in ('胜：', '部：', '撤：', '败：')):
        errors.append(f'{mission_id}: four outcome descriptions missing')
    mission_edges[mission_id] = sorted(set(re.findall(r'MISSION-[0-9]+', '\n'.join(result_lines))))

chapter_text = texts.get(DESIGN / 'dual-protagonist-campaign.md', '')
chapter_blocks = re.findall(r'^### (CH-[0-9]+)[^\n]*\n(.*?)(?=^### CH-|^## |\Z)', chapter_text, re.M | re.S)
chapter_fields = ['动机／冲突', '首引／复用', '3D 情景', '两条策略', '胜／部／败后继续', '章末人物／期待']
for chapter, body in chapter_blocks:
    for field in chapter_fields:
        if f'**{field}：**' not in body:
            errors.append(f'{chapter}: missing chapter field {field}')

roster_text = texts.get(DESIGN / 'hero-roster-and-relationships.md', '')
people = dict(re.findall(r'^## (NPC-H[0-9]+)[^\n]*\n(.*?)(?=^## |\Z)', roster_text, re.M | re.S))
relation_rows = re.findall(r'^\| (HREL-[0-9]+) \| (NPC-H[0-9]+) ↔ (NPC-H[0-9]+) \|', roster_text, re.M)
degree = {person: 0 for person in people}
for relation, left, right in relation_rows:
    if left == right:
        errors.append(f'{relation}: self relation')
    for person in (left, right):
        if person not in people or relation not in people[person]:
            errors.append(f'{relation}: missing reciprocal reference in {person}')
        else:
            degree[person] += 1
for person, count in degree.items():
    if count < 2:
        errors.append(f'{person}: fewer than two stated relationships')

coverage = texts.get(RESEARCH / 'wujing-core-coverage.md', '')
volumes = re.findall(r'^\| (?:\[)?(?:前|后)[一二三四五六七八九十]+', coverage, re.M)
if len(volumes) != 40:
    errors.append('Wujing: expected 40 nominal volume rows')

source_paths = ['game/domain/mingqi/campaign.gd', 'game/domain/mingqi/catalog.gd',
                'game/data/mingqi_geography.json', 'assets/data/cartography/atlas_places.json']
sources = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in source_paths}
report = {
    'scope': 'documentation-only', 'date': '2026-10-29', 'files': file_records,
    'localLinksChecked': local_links, 'counts': {key: len(value) for key, value in groups.items()},
    'nominalVolumeRows': len(volumes), 'heroRelationDegrees': degree, 'missionReferenceEdges': mission_edges,
    'sourceReadSnapshots': sources, 'errors': errors, 'runtimeValidation': 'not-run',
    'limitations': ['Local links checked for existence, not fragment rendering.',
                    'External source accuracy and historical interpretation require human review.',
                    'Outcome labels and reference graph do not prove executable transitions or balance.'],
}
(DESIGN / 'document-check.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'files': len(paths), 'localLinksChecked': local_links, 'counts': report['counts'],
                  'nominalVolumeRows': len(volumes), 'errors': errors}, ensure_ascii=False))
sys.exit(bool(errors))
