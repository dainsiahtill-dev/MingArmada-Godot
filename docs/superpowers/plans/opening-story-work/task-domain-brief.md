# Domain task: consequential opening story

Read this first; it is the requirements. Repository C:/Users/dains/Documents/Git/ming-armada. User selected autonomous local development, now focused on story/gameplay while external REA handles sea/island. Every shell command starts rtk. No subagents, git mutations, GPU, performance work or graphics edits. Preserve inherited dirty work. Existing CodeGraph index is unavailable; no repeat query.

## Ownership

Create `game/domain/mingqi/opening_story.gd`; modify only `game/domain/mingqi/campaign.gd`, `game/domain/persistence/save_codec.gd`; add `tests/test_opening_story.gd`, `tests/test_opening_story_save.gd`. Root owns MingqiRuntime. Another worker owns UI.

## Public interface

`OpeningStory.project(state: Dictionary) -> Dictionary` returns detached plain JSON data:

- `chapter:{id:"opening-1650",title:"旧账新帆",summary:String}`.
- `objective:{id:String,title:String,detail:String,panel:String}`; panel is story/convoy/port/boarding/ship. Derived actual offered/active/finished/claimed first and second contract; no hidden auto-completion or new chapterId state.
- `scenes:Array` with `{id,title,npc:{id,name,role},text:Array[String],status:"available"|"completed"|"locked",selectedChoiceId:String,reply:String,choices:Array[{id,label,consequence,silverCost,enabled,reason}]}`. IDs below. Completed scene choices remain visible but disabled.
- `relations:Array[{id,name,role,stance:String}]`, original NPCs Xu Fu (许福, old sailor), Chen Ahai (陈阿海, pilot), Lin steward (林管事). Stance depends on real choices/convoy casualties; do not claim hired people physically spawned.
- `history:Array[{id,sceneId,choiceId,message,simTime}]` from actual story-choice receipts.
- `debt:{principal,creditorName:"林家商行",canRepay:bool,reason:String}` domain readiness only (native dock eligibility Root adds).

`OpeningStory.apply(state: Dictionary,scene_id: String,choice_id: String) -> Dictionary`: mutate only Campaign's candidate clone after all preconditions and affordability checks; return `{ok:true,message:String,details:Dictionary}` or `{ok:false,reason:String}`. You may add internal pure helpers; no Campaign/SaveCodec preload cycle.

## Choices

All once-only per scene, canonical receipt ID `campaignId+":story:"+sceneId`. BUSINESS adds strict `story-choice` intent `{type,commandId,expectedRevision,sceneId,choiceId}`. Use Campaign idempotency/revision/native projection, not another authority. NEEDS_NATIVE includes story-choice and repay-debt; true safe dock via Campaign `_safe_dock` before any story action; relevant port must equal currentPortId.

- old-ledger: xiamen; convoy-001 offered/active and both original grain voyages still loading. settle-wages costs80, crewSupport+10; keep-reserve costs0, crewSupport-4.
- pilot-plan: xiamen; convoy-001 active, both grain voyages loading. hire-pilot costs45, merchantCredit+1; sets both routeId to xiamen-kinmen-shallow after EACH actual cargo draft passes existing `route_for_vessel`. stay-deep costs0, both deep route. Preserve escortIds, actual pose and flagship permission; use existing `locate_route` in Campaign orchestration if needed. Original NPC is game dialogue, not recovered historic fact.
- first-return: kinmen; convoy-001 genuinely claimed settled/failed. crew-dividend costs80 crewSupport+8; buy-intelligence costs60 militaryTrust+2 merchantCredit+3 adds actual forward-supply stock grain, observedAt=current simulationSeconds, sourceId=canonical receipt ID, confidence=.65; keep-capital costs0. Full, partial, failed actual results create different text, no loss concealment. Choices do not gate existing contracts.

Reputation effects clamp current value -100..100; define canonical details and verify exact chosen definition in SaveCodec. Unknown scene/choice and extra intent fields rejected. Persist choices in new receipts, no story root field required; old v2 state retains exact shape.

`repay-debt` strict intent `{type,commandId,expectedRevision,quantity}`; positive integer <= remaining principal and captain silver, xiamen safe dock. Deduct actual silver and principal; full payoff gives merchantCredit+6 once, partial+0. Canonical receipt ID `campaignId+":repay-debt:"+commandId`; details include amount, before/after principal and credit award. Schema debt principal becomes integer0..400. Save validation must enforce principal =400 minus sum of distinct valid repayment receipt amounts, chronological before/after continuity, full-payoff award onlyonce. No invented debt interest/due-time defaults.

## Tests/evidence

Meaningful RED then GREEN, scoped regression. Cover each branch; two grain routes and permission unchanged, actual shallowness rejection and insufficient money rollback; safe-port native guard; duplicate/stale/extra-fields/early scene reject; receipt/route/state save round trip; old fixtures valid; forged cost/choice/payment/principal/award reject; splitting payments cannot farm credit. Existing fixture/oracle tests must stay valid.

Do not run full suite or overwrite final root verification.json unnecessarily; run exact tests with Godot executable. Write full change/tests/commands/concerns to `task-domain-report.md` in this directory; reply concise status and counts. Root will review/wire/runtime/GPU.
