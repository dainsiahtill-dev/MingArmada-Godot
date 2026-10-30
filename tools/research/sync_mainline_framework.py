"""Register the contract-only mainline study and keep the showcase honest."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DESIGN = "docs/design/2026-10-29-naval-world/38-mainline-first-framework.md"
REGIONAL = "docs/design/2026-10-29-naval-world/39-regional-stories-and-learning.md"


def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def write(path, value):
    (ROOT / path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def update():
    catalog = read("assets/research/catalog.json")
    catalog["topics"] = [t for t in catalog["topics"] if t["id"] != "story-campaign-flow"]
    catalog["topics"].insert(0, {
        "id": "story-campaign-flow", "title": "两代人的全程主线框架", "category": "剧情与玩法编排",
        "abstract": "24章与30阶段的合成进度、失败恢复、交棒与终章条件；仅为框架合同，真实世界动作、资产交接与整条通关仍待接入。",
        "status": "researching", "retrospective": False,
        "paper": "res://assets/research/papers/story-campaign-flow.md", "demo": "story-campaign-flow",
        "sources": ["res://game/domain/story_campaign/data/zheng_family_v1.json", "res://game/domain/story_campaign/catalog.gd", "res://game/domain/story_campaign/progress.gd", "res://game/research/demos/story_campaign_flow_experiment.gd"],
        "evidence": ["res://docs/research/evidence/story-campaign-flow/final-regression-01.json", "res://docs/research/evidence/story-campaign-flow/framework-gpu-02/process-result.json"],
    })
    write("assets/research/catalog.json", catalog)
    gd_path = ROOT / "game/research/catalog.gd"
    gd = gd_path.read_text(encoding="utf-8")
    token = '"story-campaign-flow":"res://game/research/demos/story_campaign_flow_experiment.gd",'
    if token not in gd:
        gd = gd.replace("const DEMO_PATHS := {", "const DEMO_PATHS := {" + token, 1)
        gd_path.write_text(gd, encoding="utf-8")

    path = "web/gameplay-journal/content/gameplay.json"
    page = read(path)
    campaign = next(f for f in page["features"] if f["id"] == "campaign")
    campaign.update({
        "title": "一片海，两代人的主线", "status": "planned",
        "summary": "先走完一段航程，再学会照看更大的世界。",
        "description": "主线按玩法学习重排为父子两代：先操船、小额买卖、劫掠与护送，再学同伴、军令、海外关系和船队，最后组合守港、撤离、补给与台湾战役。24章、30阶段已进入可校验的内容与进度框架；真实任务适配、资产交棒和从头到尾通关尚在制作。剧情会随实际体验继续修改。",
        "playerChoices": ["在具体航次里学新本领，再用旧本领解决更复杂的目标", "在琉球、满剌噶等地区履行有成本的承诺，决定与谁合作", "带着前代留下的人船和旧账，接续郑成功的航程"],
        "tradeoff": "框架先检查目标、成败、恢复和传承能否连起来；没有把内容预览或合成进度当作真实任务通关。",
        "related": ["trade", "escort", "piracy", "heroes", "diplomacy"], "imageKey": "hero", "source": DESIGN,
    })
    diplomacy = {
        "id": "diplomacy", "title": "王府、商馆与地方的人", "category": "世界", "status": "planned",
        "summary": "一封引荐信，只能打开一扇有条件的门。",
        "description": "琉球王府、柔佛王使、满剌噶港务、暹罗王臣与日本—吕宋商人网络，各有需要守住的航路和人。任务计划包括救助使船、护送、通商复核、货权查证和采购；谈妥之后仍要实际交付。地方统治者与港口控制按章节年代区分，会面和对白为原创剧情。",
        "playerChoices": ["救回使船并护送抵达，再争取有限通商许可", "承担一段有范围的担保，或通过查证和分段运输处理争货", "延续父篇的商业承诺，或由子篇重新谈条件、另找航路"],
        "tradeoff": "担保占资金，护送占运力，改线占补给；关系提供机会，不会免费送货、送舰或抹去旧债。",
        "related": ["campaign", "trade", "escort", "heroes"], "imageKey": "atlas", "source": REGIONAL,
    }
    page["features"] = [campaign, diplomacy] + [f for f in page["features"] if f["id"] not in ["campaign", "diplomacy"]]
    page["storyOverview"]["heroLead"] = "从郑芝龙的谋生、劫掠与经商，到郑成功的守港、重建与台湾战役；沿途与琉球、满剌噶等地的人建立有代价的关系。"
    page["storyOverview"]["paragraphs"][0] = "郑芝龙最初只想让一船人有饭吃、有港可靠。你将从短途操船起步，逐步接触劫掠、买卖和护镖：挣来的钱换成新帆，救下的人日后可能替你掌舵。航路渐渐伸向琉球、满剌噶和其他港市，王府、商人、船工各有诉求；一份引荐、一趟使船、一张旧货单，会改变下一段生意和归航。地区会面与私人故事为原创情节，不冒称两位主角真实亲访每港。"
    page["storyOverview"]["note"] = "主线内容与进度框架制作中，尚未形成全部真实任务可通关版本。剧情按玩家理解与逐渐难度继续调整，历史锚点和原创情节分别说明。"
    page["storyOverview"]["source"] = DESIGN
    page["chapters"] = [
        {"year":"约1623—1626", "title":"借来的帆", "protagonist":"郑芝龙", "description":"从一艘旧船和一趟短运学起，辨认该靠近谁、该保护谁；第一笔买卖让下次出海有了自己的本金。", "mechanic":"操船、目标识别与劫掠、小额贸易、护送；每次只引入一项主要新规则。", "status":"planned"},
        {"year":"1628—1635", "title":"旗与名", "protagonist":"郑芝龙", "description":"一名愿意同行的人、一份朝廷的军令，让海上的伙伴开始面对不同责任。料罗与后续征讨组合已学过的本领。", "mechanic":"基础同伴、有限军令、保卫友船与征讨目标；难度来自多目标和不同职责。", "status":"planned"},
        {"year":"约1636—1646", "title":"岸上的家与远方的港", "protagonist":"郑芝龙 → 郑成功", "description":"琉球使船、柔佛王使、满剌噶旧凭证连着远方的人，也连着家中的旧账。父子分途后，留下的是实际到场的人船与未完承诺。", "mechanic":"许可、查证、远航补给、撤离与一次交棒；新主角须重新赢得信任。", "status":"planned"},
        {"year":"1646—1653前后", "title":"自己的旗", "protagonist":"郑成功", "description":"先让旧船重新载人出海，再为部众筹粮、守港，以海贸支撑战旗。父篇留下的联系带来机会，也会追问承诺。", "mechanic":"有成本的恢复、护粮、港口保卫、水陆目标与多港贸易。", "status":"planned"},
        {"year":"1650年代中后段—1661", "title":"大江与回头路", "protagonist":"郑成功", "description":"同伴带船出任务，风灾与战局考验接应。北伐的挫折之后，重要的是把人带回，筹好下一次横渡所需。", "mechanic":"基础分队、救援、撤退、有限采购；用旧能力应对更长航段与补给压力。", "status":"planned"},
        {"year":"1661—1662", "title":"让归路通向岸上", "protagonist":"郑成功", "description":"台湾战役拆成渡海、登陆、反击、两座城的交接与围城、补给和援军，再到谈降撤离与接收。真正收束要等所有阶段条件成立。", "mechanic":"T01—T10连续目标，综合运输、护航、海陆战与履约；不是击沉一舰便宣告完成。", "status":"planned"},
    ]
    title = "先把整条航程连起来"
    page["updates"] = [u for u in page["updates"] if u["title"] != title]
    page["updates"].insert(0, {"date":"2026-10-29", "title":title, "description":"开发顺序调整为全主线与各玩法粗闭环优先。24章、30阶段、父子交棒、台湾十阶段及渐进教学已进入可执行框架；琉球、柔佛、满剌噶等关系线加入内容。当前仅内容和进度合同，真实任务、资产传承和全程通关尚待接线。", "status":"experiment", "source":DESIGN})
    page["updatedAt"] = "2026-10-29"
    write(path, page)
    print("MAINLINE_FRAMEWORK_SYNC chapters=24 stages=30 showcase_features=%d" % len(page["features"]))


if __name__ == "__main__":
    update()
