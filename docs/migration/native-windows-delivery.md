# Native Windows delivery preparation

2026-10-11: official Godot 4.7.2 stable standard export templates downloaded and
cryptographically verified. This preparation does not assert that a playable
release has been exported or launched.

Run from this repository:

```powershell
rtk proxy node tools/prepare-windows-templates.mjs
```

The tool checks the exact stable tag, asset name, official GitHub asset digest,
size, and URL before downloading. It validates the whole archive before extracting
only Windows x86_64 binaries, console wrappers, shared template data, and version
metadata. Outputs remain under ignored `build/tools/godot-4.7.2`; it never installs
templates into the user's profile. Existing partial/corrupt archives fail closed
and identify their exact path rather than silently replacing evidence. An existing
valid archive is rehashed and reused.

Verified [official release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable),
release ID 372477026, asset `Godot_v4.7.2-stable_export_templates.tpz`:

- Archive: 1,281,349,702 bytes; SHA256 `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011`.
- Debug: `res://build/tools/godot-4.7.2/templates/windows_debug_x86_64.exe`,
  103,176,704 bytes; SHA256 `51498b72b3a237f882ebd7d1787f06a4bc1eaf0572daab93837adcfd3cfdc107`.
- Release: `res://build/tools/godot-4.7.2/templates/windows_release_x86_64.exe`,
  109,268,480 bytes; SHA256 `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`.
- Both matching console wrappers and `icudt_godot.dat` are extracted. The complete
  size/hash receipt is `build/tools/godot-4.7.2/verification.json`.
- Template version file reads `4.7.2.stable`. The installed editor reports
  `4.7.2.stable.official.ed1daf0bf`. The user's Roaming Godot export-template
  directory contained no files when inspected; no profile files were changed.

The preset owner can use these exact debug/release paths as custom templates.
Preserve D3D12, Forward+, Jolt, and x86_64. The [Godot Windows export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html)
describes the executable and project pack delivery. With the current separate-PCK
configuration, deliver the entire export directory, including every emitted DLL
and data file, rather than copying only the EXE. Runtime needs neither Node.js nor
a browser; Node is solely a preparation/verification tool.

## Package and release gates

The current preset excludes `docs/*`, `tests/*`, `tools/*`,
`assets/provenance/*`, and `.superpowers/*`, but uses all resources plus `*.json`.
Before delivery, also exclude `build/*`: preparation artifacts, receipts, and
future native QA outputs must never enter the project pack. Audit the actual
exported resource directory, including nested exclusions; matching source filter
strings alone does not prove pack contents. Preserve runtime JSON fixtures and
imported assets that production scenes need.

Production QA/dev authorization must come from engine editor/debug features and
trusted entry ownership. User arguments `--dev` and `--qa`, direct scene loads,
and injected startup dictionaries must not expose developer-only modes in a
release template. The preparatory audit found direct argument trust in
`main_scene.gd`, direct startup-option trust in `visual_qa.gd` and `ship_book.gd`,
and dictionary trust in `game_router.gd`. The main implementation owner is
responsible for repairing and testing those entry boundaries before export.

## Standalone launch acceptance plan

After import/tests/gates pass, export debug and release with the installed exact
editor via RTK `--headless --path <repo> --export-debug/--export-release
"Windows Desktop" <absolute-output.exe>`. Check exit status **and** logs for
script/resource/export errors, and hash the emitted package. This preparatory task
has not run those commands.

Use a fresh ignored `build/windows-acceptance/<run-id>` directory containing
`empty-cwd`, `roaming`, `local`, and `evidence`. A launcher should spawn
`rtk proxy <absolute-release-exe>` with `cwd=empty-cwd`, `windowsHide=true`, and
child-only `APPDATA=roaming`, `LOCALAPPDATA=local`, and absolute `--log-file`.
Do not change process-global or persisted user environment variables. Godot
4.7.2 Windows resolves user data from APPDATA and cache from LOCALAPPDATA in
[the exact engine source](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/windows/os_windows.cpp).
Its checked CLI help has no `--user-data-dir` option; do not rely on that invented
flag to isolate real saves. Do not pass `--path` pointing back to source when
testing the standalone export.

Launch the release from that empty working directory with the exported package
beside its EXE. Capture real native viewport evidence of the default menu, both
career entries, practice and ship-book scenes, persistence/continue, responsive
narrow layouts, and return-to-menu. Use `--write-movie <absolute-evidence.png>
--quit-after <bounded-frames>` for bounded real viewport PNG evidence where useful;
the engine help marks movie writing available to release templates. Interactions
still need actual game controls and observed resulting state. Run negative
release launches with `-- --qa --dev` and confirm QA/practice developer entries
remain unavailable. Inspect the isolated user directory to prove settings/save
writes stay there. Validate D3D12/Forward+ and Jolt from actual launch logs, and
inspect PNGs before accepting visual output. A headless startup is insufficient
evidence for the viewport or GPU path.

No GPU launch, export, package-content inspection, or standalone interaction
acceptance was performed by this preparation task. Those remain release gates.
