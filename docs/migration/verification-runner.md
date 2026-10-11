# Godot verification runner

From `C:/Users/dains/Documents/Git/ming-armada`:

```powershell
rtk proxy node tools/verify-godot.mjs
```

The runner discovers every `tests/test_*.gd` recursively, sorts them, and runs each script sequentially with the installed native Godot executable. Every subprocess uses `rtk proxy`; Godot uses `--headless --path <project> --script res://tests/...` with a 60-second limit per invocation. On Windows a timed-out process tree is stopped through `rtk proxy taskkill`. Windows are hidden, so verification does not open repeated editor or game windows.

The default executable is `C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`. Override with `GODOT_EXE` or `--godot <absolute-path>`. `--timeout-ms` accepts 1000–60000. `--filter <filename-substring>` runs a focused subset; its evidence explicitly records the filter and all discovered tests, so it cannot be mistaken for full-suite acceptance.

```powershell
rtk proxy node tools/verify-godot.mjs --self-test
rtk proxy node tools/verify-godot.mjs --filter layer_boundaries
```

Godot may print a `SCRIPT ERROR` and still exit zero. A passing run therefore requires all of these:

- Process exits zero without a timeout or launch error.
- Full stdout and stderr contain no `SCRIPT ERROR:`, `ERROR:`, parse/compile error, or failed script/resource load.
- Exactly one completion line starts with that test's own printed marker and reports `failures=0` or `PASS (0)`.

The marker comes from the script's completion `print` containing `failures` or `PASS`. A new test without a supported completion print fails verification. Engine startup alone, another test's marker, duplicated completions, and a nonzero failure count all fail. Eleven built-in assertions exercise these acceptance cases before any suite run, including errors after a printed pass. These self-tests were first run against exit-code-only acceptance and failed on the zero-exit script-error case.

`docs/migration/evidence/verification.json` records actual version output, discovered tests, each invocation, complete stdout/stderr, exit code, duration, timeout state, completion identity, rejection reasons, and aggregate status. Each invocation overwrites this file with its own scope. The runner returns nonzero if version probing or any selected test fails. Console output shows one concise verdict per test; exact diagnostics remain in JSON.

`tests/test_layer_boundaries.gd` scans GDScript, shaders/includes, scenes, and resources under the four documented roots. Contracts reference only contracts. Physics references only its own module and contracts; numerical physics cannot own native scene nodes, rendering resources, or the native physics server. Jolt adapters under `physics_engine/impacts` may use native bodies, joints, and injected `Callable` samplers. Scene code references only its own module, contracts, and assets. Terrain's native static collision representation is allowed; imports of physics rules or game code are rejected. Domain references only domain and contracts and cannot use native scene/UI/rendering/physics types. Registered `class_name` references and relative literal imports receive the same checks as absolute imports.

The guard strips comments and quoted data before native type and clock checks. All guarded roots reject engine process callbacks, input access, and direct wall-clock access; ocean shaders/includes reject `TIME`. The composing runtime supplies consumed simulation time and callbacks. Eight independent forbidden/allowed source fixtures prove the scanner's decisions, including relative imports, shader time, comments, injected callbacks, and the native Jolt exception. The initial empty scanner failed six rejection fixtures before implementation.

Static scanning cannot prove the target of dynamically assembled resource paths or a callback's downstream behavior. Runtime tests and review still cover those paths. Headless tests also do not replace actual Godot viewport screenshots, interactive controls, full gameplay loops, export verification, or the migration acceptance matrix.
