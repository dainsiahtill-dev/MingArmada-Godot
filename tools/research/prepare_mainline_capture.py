"""Finalize direct-source coverage before the final UI fixture capture."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
runner = ROOT / "tools/research/run_story_campaign_gpu.mjs"
text = runner.read_text(encoding="utf-8")
line = "SOURCES.push('tools/research/capture_ship_fire_gpu.gd');\n"
if line not in text:
    text = text.replace("const OPTIONAL_SOURCES = [];", line + "const OPTIONAL_SOURCES = [];", 1)
text = text.replace(
    "Scripted actual menu/laboratory; 5 GPU samples per accepted second; controlled fire accounts and complete VFX expiry, same-tick cameras, pauses, reset and disposal. PNG and decoded RGBA verified. Direct-source freeze only; no manual play, game FPS, live-ballistic/campaign/production acceptance.",
    "Actual Main/Laboratory synthetic progress fixtures, four samples per accepted second; chapter details, pauses, reset and disposal. PNG and decoded RGBA verified. No actual tasks, world asset transfer, manual play, campaign persistence or gameplay completion. Direct-source freeze includes inherited capture; not all transitive/imported assets.",
)
runner.write_text(text, encoding="utf-8")
path = ROOT / "assets/research/catalog.json"
catalog = json.loads(path.read_text(encoding="utf-8"))
topic = next(row for row in catalog["topics"] if row["id"] == "story-campaign-flow")
topic["evidence"] = [
    "res://docs/research/evidence/story-campaign-flow/final-regression-01.json",
    "res://docs/research/evidence/story-campaign-flow/framework-gpu-02/process-result.json",
]
path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("MAINLINE_CAPTURE_PREPARED inherited-capture=covered synthetic-scope=explicit")
