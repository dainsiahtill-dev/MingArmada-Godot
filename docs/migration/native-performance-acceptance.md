# Native performance acceptance runner

This tool prepares Task 5/12 performance evidence. **GPU benchmark has not been run**; headless dry-run validates parsing and percentile arithmetic only. No FPS, stability, or resource-release acceptance is claimed by that check.

Run each command sequentially with all other GPU capture/benchmark activity idle. Keep the Godot window visible and focused throughout the measured interval. Actual source QA scenes use `visual_qa.tscn`, source `benchmark` (three vessels) and `fleet` (six vessel types). The tool instantiates that scene directly; main-menu navigation is covered by separate entry acceptance tools.

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --path C:/Users/dains/Documents/Git/ming-armada --script res://tools/benchmark-native.gd -- --scenario=benchmark --quality=balanced --cycles=3
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --path C:/Users/dains/Documents/Git/ming-armada --script res://tools/benchmark-native.gd -- --scenario=fleet --quality=balanced --cycles=3
```

Each run uses 20 seconds actual wall-clock warmup followed by 60 seconds actual wall-clock sampling. Three-vessel completion retains the product's own 80-second benchmark phase and automatic `benchmark` pause. Interrupted three-vessel runs stop after 110 wall seconds if that authority cannot complete. The six-vessel adapter stops observing at 80 wall seconds without changing the product timer, encounter, or pause behavior. Entry/import time and three optional real entry/dispose cycles are additional. `--cycles=0..10`, `--quality=low|balanced|high`, `--output=res://...` are supported; the viewport is 1600×900. No manual `_process`, fixed ticks, fabricated rendering timings, or simulation fast-forward are used.

Source QA deliberately uses actual `realistic` handling at playback 1. The detached Settings object keeps product defaults (`balanced` quality, persisted `assisted` handling), while source QA's settings wrapper ignores product handling. The report records both settings and effective handling to prevent ambiguity. Settings writes use a `user://tests/native-performance-<processId>-<scenario>-settings.json` path. No career is opened and no production save file is read or modified.

Outputs under `docs/migration/evidence/native-performance/`:

- `<scenario>-frame-diagnostics.json`: actual scene `export_diagnostics()` output, raw source FrameDiagnostics intervals, completed-frame CPU association, source metrics, native actors, engine and GPU metadata.
- `<scenario>-acceptance.json`: every observed wall interval, inclusion and validity flags, focused/visible/pause state, mean/p95/p99/worst interval and FPS, engine process/physics monitor distributions, native advanced ticks/consumed simulation time, per-second crew/live Jolt/chunk/resource snapshots and real repeated disposal counts.
- `<scenario>-viewport.png`: actual viewport screenshot taken after the measurement loop stops and before measured scene disposal. Acceptance JSON `viewportCapture` records absolute path, SHA256, dimensions, stop/capture timestamps and success. `frame_post_draw` synchronization and `get_image()` occur only after sampling; no synchronous GPU readback occurs in the measured window. Screenshot/hash failure invalidates the run. No write-movie or fixed-FPS capture is used.

The independent observer preserves 20-inclusive/80-exclusive wall sampling including long intervals crossing boundaries; it does not clip or erase slow frames. For the three-vessel source window, `sourceFrameDiagnosticsMetrics` and the export remain authoritative. For six vessels source diagnostics include the full run because source fleet has no benchmark phase; use the adapter's wall sampling metrics for its 60-second window. Process/physics values are engine monitor measurements and may lag one frame; they are neither exclusive per-scene timings nor GPU timings. GPU completion/render-submit timings remain JSON `null` because the engine path does not expose verified measurements.

Any observed blur/unfocused window, hidden window, external pause, timeout, export failure, wrong actor count, or missing source automatic pause marks the complete run invalid. All intervals remain in the file, including invalid intervals; their numerical summary is diagnostic and must not be accepted as a clean performance result. The tool never automatically resumes and never removes interruption intervals. Focus the window, then rerun a new complete 20+60 second process if interrupted. This strict rule also means a startup focus failure may invalidate an unattended run.

The native window is unresizable during this run, but validity also depends on actual per-frame audit. Each raw interval includes `fixedLoad` and `fixedLoadChanges`; `expectedFixedLoad` records the initial configuration. Window size, logical viewport, actual render texture size, content scaling, all Settings fields (including quality), effective handling/playback, scenario/generation, tactical view, MSAA/3D scaling, physics tick rate, engine FPS/time scale and VSync must stay fixed throughout warmup and sampling. Any difference permanently marks the run invalid, even if restored later. Initial window/viewport/render texture dimensions must actually be 1600×900. Resize and setting transitions remain in raw evidence rather than being dropped from metrics.

Windows initialization locks the window style first, waits three actual process frames, then requests 1600×900 client/content dimensions and waits three actual rendered frames. Up to four bounded calibration attempts precede benchmark restart and the 20-second warmup. Actual dimensions are read back after draw; unresolved dimensions abort before timing rather than relaxing audit. `setupAudit` preserves calibration observations. `--setup-only` executes this visible initialization and prints actual fixed load plus native snapshot; it does not write benchmark artifacts or measure FPS, and headless usage remains rejected:

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --path C:/Users/dains/Documents/Git/ming-armada --script res://tools/benchmark-native.gd -- --setup-only --scenario=benchmark
```

Actual short visible setup verification on Intel Arc 130T / D3D12 completed in 7.46 seconds, exit 0: first calibration attempt read Window 1600×900, logical viewport 1600×900 and actual render texture 1600×900. The earlier failed 80-second run remains invalid evidence; this setup check does not replace a new full performance run.

Resource evidence follows the timed run: actual `queue_free`, twelve actual process frames, then repeated instantiate / twelve frames / queue_free / twelve frames. Each cycle records before/during/after Node, object, resource, orphan, static/video memory and active physics counts plus instance validity. Inspect these counts for retained Nodes/orphans and growth across cycles; first-use resource caches and memory allocators can remain resident, so these values do not by themselves establish a leak or leak freedom. Short lifecycle cycles establish disposal evidence, not another long-duration performance test.

Parser/statistics check (safe while GPU work is idle or busy; no rendering benchmark):

```powershell
rtk proxy C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe --headless --path C:/Users/dains/Documents/Git/ming-armada --script res://tools/benchmark-native.gd -- --dry-run
```

Verified with Godot 4.7.2: exit 0, `NATIVE_BENCHMARK_DRY_RUN parser/statistics only; no performance evidence; failures=0`. Headless invocation without `--dry-run` is rejected. CodeGraph discovery was unavailable because this target was already confirmed UNINDEXED by the parent task; RTK source fallback was used without indexing.

Fixed-load regression was verified red then green using only headless dry-run: before implementing audit, window/viewport/quality/handling/playback mutations produced five explicit failures and exit 1; after implementation, unchanged load passes, each mutation is detected, a resize followed by restore retains all three records and a persistent invalid reason, nested Settings changes/restarts/missing settings are detected, and dry-run exits 0. This validates the acceptance classifier, not GPU performance.

Acceptance remains open until both visible runs complete with valid evidence, the raw diagnostics are reviewed, and actual Node/resource release results are assessed. There is no promise or inferred claim of 60 FPS.
