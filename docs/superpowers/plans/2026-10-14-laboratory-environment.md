# Laboratory Environment Implementation Plan

Goal: 既有三篇环境论文各有独立可运行研究场景，完善统一宿主，保存新证据。
Spec: `docs/superpowers/specs/2026-10-14-laboratory-environment-design.md`。
Execution: parallel scoped agents, root integration/GPU, independent review; no commits/publication.

- [ ] Ocean implementer owns ocean_surface_experiment.gd, test_laboratory_ocean.gd and ocean-surface.md; initial RED and GREEN, no production changes.
- [ ] Shore implementer owns shore_surf_experiment.gd, test_laboratory_shore.gd and shore-surf.md; same contracts and independent control factors.
- [ ] Weather implementer owns weather_shadow_experiment.gd, test_laboratory_weather.gd and weather-shadow.md; original source rules, no invented native parity.
- [ ] Root owns generic host controls, single-step/capture, catalog registrations and affected existing tests; explicit defaults, no stale hull fields.
- [ ] Root executes fresh affected suites, independent review, GPU fixed sequences and same-state A/B, package-only checks; saves uniquely named evidence.
- [ ] Update paper actual results and limits, workflow references, delivery source hashes and reproducible commands. Mark final feature scope, carry prior8failures as prior audit only.
