# Research Laboratory Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development. Work remains in the current authorized checkout; no commits or publishing.

**Goal:** 首页实验室、论文式课题、独立可复现 Godot 实验和未来研究规范。
**Architecture:** JSON catalog + bundled Markdown papers + isolated SubViewport demos through existing menu/router.
**Tech Stack:** Godot 4.7.2 / GDScript / existing production presentation components.
**Spec:** `docs/superpowers/specs/2026-10-14-research-laboratory-design.md`.

## Global Constraints

- Preserve current tail, ocean, gameplay, 3D deck crew and existing dirty work.
- No save/settings mutation for laboratory entry. No browser or external server dependency.
- Report planned/observed/historical facts separately; report files exported under assets/research.
- Only root runs GPU captures. Child tests headless only.

## Review Focus

- Repeated entry/return and stale generation must use the existing router authority.
- Changing topics or leaving an experiment must release all demo resources.
- Reports and demos remain available in exported packages, without docs dependencies.
- Pause and A/B must not change experiment time, pose or tail owner.
- Unverified subjects must not appear as verified implementations.

## Tasks

- [x] Menu/router implementer: public `laboratory` intent and GDScript scene path, same startup lifecycle; regression coverage for menu visibility, no persistence and return. Root provides Laboratory class. Existing --start-game modes remain unchanged unless laboratory added with explicit intent and capture tests.
- [x] Demo implementer: `game/research/demos/hull_contact_experiment.gd`, documented interfaces in spec; test pause/reset/enable/ship kind/scenario. Native presentation reuse; narrow independent experiment, no production changes.
- [x] Research writer: five bundled papers plus `docs/research/README.md` and `TOPIC_TEMPLATE.md`; cite actual local sources, results and limits. No invented results; report metadata contract from root.
- [x] Root: catalog, paper reader, lab UI/controls, runtime lifecycle tests, export filter, root AGENTS research rule. Fail a catalog/menu test before implementation; use child tests for demo boundaries.
- [x] Root: affected headless suites, independent spec/code review, actual GPU captures from main menu into laboratory/paper/demo; inspect images and verify packaged report presence.
- [x] Final delivery: concise user instructions, actual evidence, boundaries, no unrelated algorithm changes.
