# Naval simulation

Native detached authority for the frozen source `packages/naval-core`: encounter, commands, ownership, navigation/orders, cannons, projectiles, collision/damage and outcomes. Dependencies are `modules/contracts`, `modules/physics_engine` and this module. No Nodes, game imports, scene references, UI callbacks or network authority.

Entry: `encounter.gd`, `new(config)`, `command`, `step`, `snapshot`, `drain_events`, `reconcile_ships`. Source camelCase methods also remain callable. Exact API, accepted-time behavior, injected coastal sampler and source-oracle evidence are in `docs/migration/naval-implementation.md`.
