# Interrupted intermediate ownership validation

The controller started the strict unfiltered 103-script runner in session 9221 on the first ownership/sail-protection implementation. Its new arrival test passed, and all completed scripts shown by the runner passed. This was **not a completed full-suite acceptance**.

During the independent review, P2 identified malformed native `ships` input being dereferenced before the new ownership context's structural validation. The controller verified its own Node process PID31788, parent9388, exact `tools/verify-godot.mjs --godot ...Godot_v4.7.2...` command, and stopped that runner to permit the scoped correction. No editor, user game, source or user save was stopped or deleted. An already-launched headless test was allowed to finish.

Final current-source acceptance requires a new complete strict run after the P2 guard and regression test freeze. This intermediate run is not counted as 103/103 or substituted for that final run. The earlier completed pre-ownership 103/103 run remains separately preserved as `full-suite-arrival-before-rudder-review.json`; its coverage gap is retained.
