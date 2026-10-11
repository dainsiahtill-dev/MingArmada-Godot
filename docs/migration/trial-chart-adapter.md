# Default sailing trial chart adapter

The configured main scene remains `game/scenes/sailing_trial/sailing_trial.tscn`.
Both default launch and F6 now create the common compact nautical chart in the
top-right corner. The scene exposes `mini_chart`, `expanded_chart`, and
`chart_layer` for the same presentation and evidence tooling used by other
native sailing scenes.

The adapter supplies a detached chart packet with one real player ship:
`playerId: trial`, `ships[0].id: trial`, `team: player`, and `visual.position`
and `visual.heading` taken from the accepted sailing runtime snapshot. Terrain
and ports use the same configured height field and geography as the 3D world.
No enemy marks, sample ship positions, route simulation, or waypoint authority
are added to the trial runtime.

Clicking the compact Control, or pressing M, opens the geographic chart with
the caption `试航模式 · 航位显示`. Its chart surface ignores mouse input; the
backdrop consumes clicks, and the actual close Button remains interactive.
The trial has no Navigator, so the expanded view cannot issue waypoints.
Opening the chart saves the previous runtime pause value and sends the
existing pause command with `value: true`. Closing through the Button, M, or
Esc restores that saved value. Early key handling also catches focused GUI
Esc, accepts physical-key and keycode-only events, and prevents Space from
releasing the modal pause. HUD commands are blocked while this modal is open.

The common compact visibility rule remains active: hide while the modal is
open, while the trial HUD is hidden, and in logical viewports narrower than
820px or shorter than 480px. Expanded layout reserves space for the caption
and close control and follows the shared chart's changing intrinsic minimum.
The 120Hz runtime, camera modes, and capture route/shore-loop paths remain in
their existing implementations. Teardown disposes both chart views and
restores a modal-owned pause before removing the scene.

Focused verification on Godot 4.7.2:

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/test_sailing_input.gd
```

The initial test-first run failed because the default trial had no compact
Control. The completed focused run reports
`SAILING_INPUT_TESTS assertions=49 failures=0`, including existing native
input checks and actual trial Controls. Coverage includes real physics
movement and heading, detached positions, compact click, close Button,
read-only full-chart click, running/paused state restoration, focused Esc,
physical M and keycode fallback, modal Space, hidden HUD, and logical viewport
sizes 1280×720, 800×600, and 800×480. The test disables project canvas scaling
to exercise those logical resize thresholds directly. It makes no GPU visual
or performance claim. Full-suite and GPU acceptance belong to the root task.

CodeGraph discovery was unavailable for this unindexed project; the parent
task established that condition and delegated focused RTK source reads.
