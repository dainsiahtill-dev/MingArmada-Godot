# Native release development gates

Source authority: frozen `9ad6a44` checkout under
`C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada`.
`App.svelte` delegates to `GameEntry.svelte`; `GameEntry`, `MainMenu` and
`ShipViewer` authorize QA/practice/LOD UI using build facts
`import.meta.env.DEV || import.meta.env.MODE === 'qa'`. Runtime arguments are
requests, not build authorization. Native policy follows the approved delivery
gate in `native-windows-delivery.md` and the migration design specification.

`game/runtime/development_access.gd` centralizes the equivalent native policy:

| Actual debug build | Actual editor feature | Developer environment |
| --- | --- | --- |
| false | false | denied |
| false | true | permitted |
| true | false | permitted |
| true | true | permitted |

Only the pure truth-table function accepts facts as arguments. Production
`host_allows()` always reads `OS.is_debug_build()` and `OS.has_feature("editor")`.
Startup dictionaries cannot supply or override either fact.

- Main scene resolves exact `--dev` / `--qa` user arguments through this host
  gate before constructing the router.
- Router sanitizes dependency flags against actual host facts. QA/practice
  preparation and scene creation independently enforce the host and owner
  flags. Request dictionaries cannot elevate authorization; manually changed
  prepared candidates cannot bypass scene creation.
- Visual QA independently checks the actual host before geography, world or
  inspector initialization. Editor access and debug owner flags retain their
  previous behavior.
- Standalone practice independently reads the actual host before UI/runtime
  startup. Release denial returns `practice-development-only`, marks the scene
  inactive and disables process ticks. Direct scene loading and injected
  startup flags cannot bypass the boundary.
- Ship book remains a public entry. Its `LODControls` visibility requires the
  actual developer environment even if startup options request dev/QA access.

Focused native evidence under installed Godot 4.7.2, headless (actual
`debug=true`, `editor=true`):

- `test_development_access.gd`: RED exit 1 with missing environment boundary;
  separate candidate-forgery regression RED exit 1 before scene-creation gate.
  Final GREEN: 14 assertions, zero failures, exit 0, no engine diagnostics.
- `test_game_router.gd`: 52 assertions, zero failures, exit 0.
- `test_ship_book.gd`: 229 assertions, zero failures, exit 0.
- `test_visual_qa_scene.gd`: 21 assertions, zero failures, exit 0; real weak-hit
  scenario reached four impacts and recovered its nonlethal bodies.
- `test_practice_development_access.gd`: RED missing independent scene boundary,
  3 assertions, one failure, exit 1; GREEN 4 assertions, zero failures, exit 0.
  This test also contains actual-release assertions for denied startup,
  absence of UI/active runtime, and disabled process ticks.
- `test_practice_entries.gd`: 88 assertions, zero failures, exit 0.

The headless editor run proves the policy truth table and current debug/editor
regressions. It does not replace a real release-template export. Root delivery
verification must launch the actual release with `-- --dev --qa`, confirm the
engine reports both trusted facts false, confirm menu QA/practice absence,
developer request and direct QA/practice denial, and public ship-book success
with LOD controls hidden. Direct practice release proof can execute
`test_practice_development_access.gd` through a verification-only release pack
or recreate its scene startup assertions in the external release harness;
production exports exclude tests. Full-suite aggregation and Windows launch evidence belong to
the final delivery owner.

## Actual release automation without editor-only CLI options

The official 4.7.2 release template does not accept the editor's `--script`
entrypoint. An editor process loading the production PCK proves resource health,
but does not establish release engine facts. The production release EXE must
execute the acceptance driver itself.

The shortest verification-only route preserves the complete EXE and PCK bytes:
copy both into a new directory, add an external Node driver and a tiny external
`.tscn`, and put `override.cfg` beside the copied EXE. The file contains only:

```ini
[application]
run/main_scene="C:/absolute/acceptance-directory/acceptance-driver.tscn"
```

This is an official project-settings mechanism, not an external release CLI
script. [Godot 4.7.2 source, lines 689-703](https://github.com/godotengine/godot/blob/4.7.2-stable/core/config/project_settings.cpp#L689-L703)
loads project settings from the located PCK, then reads both `res://override.cfg`
and EXE-adjacent `override.cfg` when overrides are compiled in and
`application/config/disable_project_settings_override` is false.
[ProjectSettings documentation](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html)
also documents exported-project overrides next to the binary. The production
project does not set the disabling option; its engine default is false.

`tools/migration/create-acceptance-copy.gd` prepares this directory under the
headless editor and refuses existing output directories. Pass absolute
`--exe`, `--pack`, `--driver` and `--out` user arguments. The driver must extend
Node and load fixed `res://game/scenes/main/main_scene.tscn` from the production
PCK. Launch the resulting EXE normally from an empty working directory with an
isolated profile; only driver-specific user arguments follow `--`. Root owns
the actual GPU launch and runtime proof.

`acceptance-copy-proof.json` explicitly labels `scope=verification driver`,
records source hashes before/after preparation, and checks copied EXE/PCK hashes.
`productionResourceHashes.match` derives from entire-PCK SHA256 identity: every
production resource necessarily has the same bytes. It does not falsely claim
individual-resource enumeration. No PCK repack or production entry change is
needed. The receipt separately records `releaseExecuted=false`; release
debug/editor facts, actual Controls and screenshots require the later driver
run. This verification copy proves release behavior of byte-identical production
resources under a controlled external entry; ordinary production-entry launch
remains separately identified in delivery evidence.
