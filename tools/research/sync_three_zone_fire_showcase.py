"""Sync the verified H5 experiment without upgrading production's r1 status."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "web/gameplay-journal/content"
SOURCE = "docs/design/2026-10-29-naval-world/37-three-zone-fire-experiment.md"


def update():
    gameplay_path = CONTENT / "gameplay.json"
    media_path = CONTENT / "media.json"
    gameplay = json.loads(gameplay_path.read_text(encoding="utf-8"))
    media = json.loads(media_path.read_text(encoding="utf-8"))
    fire = next(row for row in gameplay["features"] if row["id"] == "fire")
    fire["description"] = (
        "主菜单的“火攻交锋”已可进入：操纵福船接敌，投送有限火攻载荷。"
        "本船起火时，在操船栏点击一次“扑救火灾”，水手自动调派，火灭后自动归位。"
        "现有扑救准备只读显示；用尽时同一按钮可让队伍返回。"
        "首、中、尾渐进蔓延已在原实验室完成连续画面验证，可选择三区初始火点观察；"
        "正式战斗目前仍为单热区，提桶泼水动作尚未制作。"
    )
    gameplay["updates"] = [row for row in gameplay["updates"] if row["title"] != "让火从一处逐渐延开"]
    gameplay["updates"].insert(0, {
        "date": "2026-10-29", "title": "火势开始沿甲板展开",
        "description": "原实验室新增首、中、尾三区候选：局部起火先传邻区，四人扑救可阻断本夹具的传播，储备耗尽后仍会燃烧。四组连续GPU采集、暂停、近景、重置和退出均已核对；图集新增真实实验近景。正式海战尚未接分区命中，船员扑火动作与生涯保存仍待制作。",
        "status": "experiment", "source": SOURCE,
    })
    # The build keeps old dist files; only update the whitelist, never delete.
    if not any(row["id"] == "fire-spread" for row in media):
        for row in media:
            if row.get("gallery", True) and row.get("galleryOrder", 0) >= 1:
                row["galleryOrder"] += 1
        media.insert(2, {
            "id": "fire-spread", "galleryTitle": "火从船尾，逐渐延开", "galleryOrder": 1,
            "sourcePath": "docs/research/evidence/ship-fire-control/zones-gpu-02/frames/stern-spread-near.png",
            "fileName": "fire-spread-experiment.png", "kind": "experiment",
            "caption": "首、中、尾渐进蔓延 · 独立实验GPU近景，尚未接入正式战斗",
            "alt": "25秒受控实验，左船三个甲板区域燃烧，右船扑救后无活火；两船共享各自单份工作与储备账",
            "sourceDocument": SOURCE, "width": 1220, "height": 494,
        })
    gameplay["updatedAt"] = "2026-10-29"
    for path, value in [(gameplay_path, gameplay), (media_path, media)]:
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("THREE_ZONE_SHOWCASE_SYNC features=%d media=%d" % (len(gameplay["features"]), len(media)))


if __name__ == "__main__":
    update()
