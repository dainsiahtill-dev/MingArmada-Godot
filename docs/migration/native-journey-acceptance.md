# Continuous native Mingqi journey probe

This is a bounded diagnostic of the first natural voyage, not acceptance of the
complete campaign journey. The complete chain remains unproven until actual
delivery, weakening by real cannon shots, boarding, prize crewing, return-port
repair/treatment/incorporation, convoy-002 delivery, return to Kinmen, and isolated
disk checkpoint/continue are observed in the same continuous runtime.

Run the probe from the migration repository:

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script tools/verify-native-journey.gd
```

The tool uses `MingqiRuntime`, the actual `mingqi_geography.json`, and
`HeightField.configure_ports()` with its default shoal shelf enabled. It starts a
fresh default campaign and uses only `runtime.command` and accepted
`runtime.advance(1/60)` ticks. Every business command carries the current revision
and a unique process-specific command ID. Every tick drains runtime events.
No vessels are teleported, no crew/hull/cargo/state are edited, no fake receipts
are supplied, and no elapsed time is skipped. No default checkpoint is read or
written. Output is limited to a unique ignored `build/native-journey/<pid>-<start>`
directory. Any future checkpoint test must use a unique explicit Storage path in
that directory, never Storage's default slot.

The probe accepts convoy-001, departs, navigates the flagship through the catalog's
actual deep-route waypoints, and orders the fast escort to protect the flagship.
The grain ships retain the campaign/native bridge's own voyage navigation.
The current implementation stops after the first settled delivery result or on
failure/budget/stop, and always labels the entire journey **incomplete**. It does
not implement a fabricated successful combat/port/second-convoy tail.

Limits: 300,000 ms wall time and 1,800 accepted simulation seconds. Progress
snapshots every 30 accepted seconds preserve ship position, velocity, hull, crew,
heading, sail deployment, route planner output, voyages, contracts, and runtime
eligibility. `events.jsonl` and `receipt.json` are direct runtime observations.
A cooperative `build/native-journey/STOP` file stops the next tick so GPU
performance measurement can run without competing headless CPU work.

## Actual execution observations

2026-10-11, engine `4.7.2.stable.official.ed1daf0bf`, evidence directory
`build/native-journey/34908-511`:

- Actual accept, depart, navigate, and protect commands returned successful domain
  receipts. The accept loaded 40 grain and charged 50 silver through campaign rules.
- At 30 accepted seconds, grain-b and the fast escort had zero sail deployment and
  low drift speed. At 60 seconds that remained visible. This initially suggested
  an autopilot low-speed-turn problem.
- At 90 seconds both recovered naturally: grain-b sailed at 1.53 m/s, fast at
  2.53 m/s. Grain-a had advanced to route leg 1. These observations **do not prove a
  permanent navigation deadlock**; the earlier suspicion was retracted.
- The flagship reached the first waypoint's 30 m transition threshold at 140
  seconds and received the next real navigate command. At 180 seconds it had
  recovered from the turn and sailed at 2.50 m/s.
- At 180 seconds, grain-a was `(156.79, -173.94)`, grain-b `(101.28, -173.98)`,
  both hull 100 and underway on the second route leg. First-convoy ETA estimates
  were approximately 344.68 / 371.00 simulation seconds. Delivery was not yet
  observed. 180 accepted seconds consumed about 170.7 seconds of wall time;
  this is headless diagnostic timing, not GPU/FPS acceptance.

Two earlier tool development runs (`19772-644`, `36940-645`) ended before any
accepted ticks: newly added Dictionary dot keys became StringName values and were
rejected by the strict plain-data command codec. The tool now uses explicit String
keys. These retained failed probes do not indicate a campaign bug.

The bounded run exited 1 with `wall-budget-exhausted`: **301.616666666721 accepted
seconds, 18,097 fixed ticks, 49 drained native events, 300,008 ms wall time**.
The exit reflects the diagnostic limit, not a fabricated settled-contract result.
Natural movement and transient slow turning must not be described as a completed
first convoy or a permanent source-level navigation defect.

Real enemy solid-shot hits began at 233.016666666744 accepted seconds, with native
events recording hull/crew/sail damage. Grain-a subsequently sank; its voyage is
`lost` and its 20 grain is lost. Grain-b survived the bounded run at hull 36, able
crew 12, still underway near `(214.96, -176.67)`. Kinmen grain stock remained zero.
The flagship ended near `(148.70, -162.83)` and the fast escort near
`(94.81, -218.45)`, both hull 100. The enemy remained hull 100. Convoy-001 was still
active and had no claim settlement. No delivery, player cannon weakening,
boarding, prize crewing, repair/treatment/incorporation, convoy-002, or disk
continue was performed or claimed.

The first probe used only navigation plus fast-ship protection of the flagship;
it did not issue player fire or an interception order. This proves that this
particular passive escort strategy lets cargo ships enter enemy firing range
before the escorts arrive. It does **not** prove the full player-controlled
campaign is impossible. The next smallest diagnostic is to start another fresh
default campaign and use real fast-ship interception, positioning, ammunition,
and broadside fire before the grain ships reach that danger area. Observe native
hit receipts, then actual boarding predicates, without changing vessel state.

`receipt.json` and the original `events.jsonl` remain unchanged. Later tool edits
only reduce console snapshot verbosity, retain all future native event types,
and report receipt-write failures; the executed run drained every tick but
printed selected combat/collision event types. The latest tool passed Godot's
real `--check-only` parser validation. The complete voyage acceptance remains
open.

## Prepared active escort strategy (not yet executed)

The tool accepts `--strategy=passive` (default) and `--strategy=active-escort`.
Options follow Godot's user-argument separator:

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script tools/verify-native-journey.gd -- --strategy=active-escort --wall-seconds=900
```

`--wall-seconds` must be an integer from 1 through 1,800; default is 300. The
accepted-time limit remains 1,800 seconds and every advance remains 1/60. Invalid
and unknown options fail closed. No time-scale change is made. The wall ceiling
applies to the whole probe and bounds each active stage. GPU measurement must
finish before launching this probe or its Godot parser check.

The prepared strategy selects chain ammunition for fast and gives it a real
campaign `protect` order targeting grain-a. After the enemy is actually present
in the native snapshot, the flagship selects chain ammunition and receives a real
`intercept` order against that observed enemy. Within 240 m it switches to `focus`
for broadside positioning. At 80 m it selects grape. Explicit fire is queued only
after observing live cooldown, ammunition, ballistic range and broadside arc.
Every actual fire and hit is retained as a native event. Rejections stay visible.

Source audit: protect (when threatened), intercept, focus and keep-distance request
autonomous firing. The encounter executes it only with an actual target in the
selected ammunition's range/arc. Prepare-boarding suppresses fire and caps sails
at 0.4. Orders do not allocate prize crews or distribute boarding personnel.
Campaign boarding progression gathers eligible nearby participants and applies
attrition through continuous rules; the tool never edits those counts.

Weakening thresholds use the current catalog profile. The tool requires a real
escort hit plus hull <=65% or able crew <=60% of complement before recording
weakening. It then issues prepare-boarding, waits for actual runtime eligibility,
starts real boarding, and commands bow/deck/helm advance. Zero-able-crew enemies
cannot be order targets, so that case uses canonical navigate to approach and
cancel fire orders. Real outcomes and the winning-receipt predicate are logged.
Even a boarding win reports prize/port/second-convoy/disk-continue **unproven**;
an enemy sunk first reports that real failed prize condition.

This active branch was prepared during GPU measurement and has not yet been
parsed or executed. The earlier parser pass covers the prior passive version.
No active receipt, weakening, boarding, allocation or completed journey is claimed.
