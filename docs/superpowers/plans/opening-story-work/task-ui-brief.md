# UI task: opening story journal

Read this first; it is the requirements. Writable repository C:/Users/dains/Documents/Git/ming-armada. User wants fun story/gameplay; sea/island/particles are deferred until REA finishes. Every shell command starts rtk. No subagents, git mutations, GPU, performance work or graphics changes. Preserve dirty work. No CodeGraph index in current session.

## Ownership

Modify only `game/ui/mingqi/mingqi_interface.gd`; optionally create `game/ui/mingqi/opening_story_panel.gd` to keep journal code small; add `tests/test_opening_story_ui.gd`. Root owns runtime and capture scripts; domain worker owns opening_story.gd/Campaign/SaveCodec.

## Input contract

`packet.story` plain data (absent old test packets must remain usable):

- chapter `{id,title,summary}`
- objective `{id,title,detail,panel}` (panel story/convoy/port/boarding/ship)
- scenes `Array[{id,title,npc:{id,name,role},text:Array[String],status:"available"|"completed"|"locked",selectedChoiceId:String,reply:String,choices:Array[{id,label,consequence,silverCost,enabled,reason}]}]`
- relations `Array[{id,name,role,stance}]`
- history `Array[{id,sceneId,choiceId,message,simTime}]`
- debt `{principal,creditorName,canRepay,reason}`
- Root adds runtime `eligibility.story:{sceneId:{ok,reason}}`, `eligibility.repayDebt:{ok,reason}` to combine native dock/authority; trust model choice.enabled AND native eligibility; reject runtime error/loading/disposed as other UI does.

## Result

Add `story` navigation tab labelled 航海日志. Reuse existing native theme, operation ScrollContainer and guarded `_button`/`_send` lifecycle. Show one concise current objective in HUD, button to open its existing target panel; it never performs a mission itself. Journal shows story premise (owned承家号/borrowed明旗号), actual next action, available scene with original NPC dialogues, each choice with clear resource/route/reputation effect. Completed choices show outcome; locked scene reveals reasonable next prerequisite, not walls of future spoilers.

Scene IDs: old-ledger (settle-wages80 / keep-reserve0), pilot-plan (hire-pilot45 / stay-deep0), first-return (crew-dividend80 / buy-intelligence60 / keep-capital0). UI does not hardcode business effects or mutate campaign; view fields are authority. `story-choice` button intent `{type:"story-choice",sceneId,choiceId}` gains commandId/revision through original `_send`. Stable node names `story_choice_<sceneId>_<choiceId>`.

Add debt form in journal: positive integer quantity1..min(principal,silver); payment button `repay_debt` intent `{type:"repay-debt",quantity}` through original guarded send. Native guard disabled reason visible; when principal0 show 已还清 and disable inputs/pay. No support/credit farming language, no fictional completed achievement. Personality/stance and last meaningful history entries use readable connected copy.

Rebuild signature must incorporate meaningful story scene status/choice gate changes (not entire continuously changing simtime). Refresh labels/cost availability without losing input/focus each tick. Preserve all old tabs/tests/menus/held-key captures and rejection of stale/remounted callbacks. Graceful no-story packet fallback.

Tests RED/GREEN: emits correct intent/revision, actual affordability/native gates, disabled full debt, absent-story fallback, visible objective link, stale generation/remount callback rejection, scene completion update, long text scrolling at1280×720 and1600×900. No GPU launch; Root performs actual native UI capture/visual acceptance.

Write full implementation/report/commands/outputs in `task-ui-report.md` here; reply concise status/count/concerns. Do not modify other worker files.
