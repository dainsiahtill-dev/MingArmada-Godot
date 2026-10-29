"""Publish only explicitly labelled framework-preview images to the journal."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "web/gameplay-journal/content"
SOURCE = "docs/design/2026-10-29-naval-world/40-mainline-framework-delivery.md"
PREFIX = "docs/research/evidence/story-campaign-flow/framework-gpu-02/frames/"
path = CONTENT / "media.json"
media = json.loads(path.read_text(encoding="utf-8"))
new_ids = {"mainline-preview", "regional-preview"}
if not any(row["id"] in new_ids for row in media):
    for row in media:
        if row.get("gallery", True):
            row["galleryOrder"] = row.get("galleryOrder", 0) + 2
rows = [
    {"id":"mainline-preview", "galleryTitle":"先把整条航程连起来", "galleryOrder":0,
     "sourcePath":PREFIX + "complete-000.png", "fileName":"mainline-framework-preview.png", "kind":"experiment",
     "caption":"24章全程编排 · 合成进度实验，非真实任务通关",
     "alt":"实验室的24章总览从郑芝龙篇接到郑成功篇，画面常驻非真实任务通关提示",
     "sourceDocument":SOURCE, "width":1220, "height":582},
    {"id":"regional-preview", "galleryTitle":"远方的人，有自己的诉求", "galleryOrder":1,
     "sourcePath":PREFIX + "detail-038.png", "fileName":"regional-story-preview.png", "kind":"experiment",
     "caption":"满剌噶与柔佛章节内容 · 合成进度实验，港口与王庭任务尚待接入",
     "alt":"1644年章节框架分别显示满剌噶港务与柔佛王庭的诉求、范围和目标，合成实验标记清晰",
     "sourceDocument":SOURCE, "width":1220, "height":582},
]
media = rows + [row for row in media if row["id"] not in new_ids]
path.write_text(json.dumps(media, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
path = CONTENT / "gameplay.json"
page = json.loads(path.read_text(encoding="utf-8"))
entry = next(row for row in page["updates"] if row["title"] == "先把整条航程连起来")
entry["description"] = "24章、30阶段与渐进教学已进入可执行内容／进度框架；实验室可看父子主线、琉球／满剌噶等地区剧情与合成结算。五个相关测试文件及真实入口的合成GPU采集已核对，图集同步。真实任务适配、世界资产交棒和全程实际通关仍待接线。"
entry["source"] = SOURCE
path.write_text(json.dumps(page, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("MAINLINE_MEDIA_SYNC images=%d synthetic-previews=2 actual-gameplay-complete=false" % len(media))
