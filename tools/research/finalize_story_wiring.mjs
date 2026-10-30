import { createHash } from "node:crypto";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

// Aggregates the story-executor-wiring evidence batch into one report with
// per-source sha256 hashes. Create-only (wx): retained runs are never merged
// away. Mirrors tools/research/finalize_mainline_framework.mjs conventions.

const root = resolve(import.meta.dirname, "..", "..");
const evidenceDir = resolve(root, "docs/research/evidence/story-campaign-flow");
const runs = [
  "wiring-full-suite-02.json",
  "wiring-repo-suite-01.json",
  "voyage-gpu-03/process-result.json",
  "voyage-guard-02/process-result.json",
  "wiring-live-04.json",
  "wiring-duel-01.json",
  "wiring-cat-test_story_land_minigame.json",
  "wiring-fix-test_layer_boundaries.json",
  "wiring-fix2-test_maritime_entry.json",
  "wiring-fix2-test_menu_consolidation.json",
];
const testSources = [
  "tests/test_story_world_session.gd",
  "tests/test_story_scenario_catalog.gd",
  "tests/test_story_fact_adapter.gd",
  "tests/test_story_sailing_adapter.gd",
  "tests/test_story_trade_adapter.gd",
  "tests/test_story_escort_adapter.gd",
  "tests/test_story_naval_adapter.gd",
  "tests/test_story_boarding_adapter.gd",
  "tests/test_story_land_adapter.gd",
  "tests/test_story_port_adapter.gd",
  "tests/test_story_handoff.gd",
  "tests/test_story_voyage_walkthrough.gd",
  "tests/test_story_save_restore.gd",
  "tests/test_story_fixture_isolation.gd",
  "tests/test_story_entry.gd",
  "tests/test_story_live_engagements.gd",
  "tests/test_story_duel_minigame.gd",
  "tests/test_story_land_minigame.gd",
  "tests/story_walkthrough_support.gd",
  "game/runtime/story_runtime.gd",
  "game/runtime/story_encounter_coordinator.gd",
  "game/domain/story_world/story_world_session.gd",
  "game/domain/story_campaign/fact_adapter.gd",
  "game/domain/story_campaign/scenarios.gd",
  "tools/research/capture_story_voyage_gpu.gd",
  "tools/research/run_story_voyage_gpu.mjs",
];

const sha256 = (data) => createHash("sha256").update(data).digest("hex");
const summary = [];
for (const name of runs) {
  const path = resolve(evidenceDir, name);
  if (!existsSync(path)) {
    summary.push({ file: name, present: false });
    continue;
  }
  const raw = readFileSync(path, "utf8");
  const parsed = JSON.parse(raw);
  const results = (parsed.runs ?? []).map((run) => ({
    test: run.test,
    passed: run.passed,
    durationMs: run.durationMs,
    completionMarker: run.completionMarker,
  }));
  summary.push({
    file: name,
    present: true,
    sha256: sha256(raw),
    filter: parsed.filter ?? "",
    summary: parsed.summary ?? null,
    results,
  });
}
const sources = testSources.map((rel) => ({
  path: rel,
  sha256: existsSync(resolve(root, rel)) ? sha256(readFileSync(resolve(root, rel))) : null,
}));

const outPath = resolve(evidenceDir, "wiring-final-02.json");
const report = {
  schemaVersion: 1,
  batch: "story-executor-wiring-02-full-improvement",
  scope:
    "Doc 38 steps 3+4-slice: category executors with real settlements (incl. live gunnery, duel/land victories), real-trade-funded voyage, regional charter branches, and the first real-entry GPU/input acceptance slice. Not the full 30-stage GPU playthrough.",
  producedAt: "run-batch",
  runs: summary,
  testSources: sources,
  limits: [
    "walkthrough uses documented fixture poses, cargo endowments, 2x speed and 0.35x reload multipliers (engine caps) and calm sea",
    "GPU acceptance slice covers the opening segment only; full-voyage GPU/keyboard acceptance remains step-4 continuation",
    "repo-suite retains pre-existing REDs (crew_work x2, mingqi_fire x2), machine-slow 60s timeouts and stale evidence-dir guards",
    "economy depth, balance, art and fire-zone wiring remain thin or postponed",
  ],
};
writeFileSync(outPath, JSON.stringify(report, null, 2), { flag: "wx" });
console.log("wrote", outPath);
