# Complete UI Detail Pass

> Existing approved scope continues: finish all 72 clickable UI screens and their needed art. The user explicitly prioritizes UI detail before model production. Preserve the current game and worktree; no commit or Godot gameplay replacement.

**Goal:** Correct the sparse, repetitive presentation across all screen groups, deliver purposeful art and interaction states, and count the real 3D production requirements separately.

**Architecture:** Keep the three renderer boundaries and shared GameUI contract. Root owns common state, accessibility, review shell and 21 world screens; independent workers own 23 ship/crew/combat screens, 28 life/trade/story screens and the deduplicated model ledger. Model and image counts remain separate.

**Tech stack:** Native HTML/CSS/JS, built-in ImageGen for new raster assets, CUA browser screenshots, Node VM verification.

- [x] Preserve first-pass screenshots and document concrete page defects before replacing previews.
- [x] Complete each of the 23 ship screens and 28 life screens, with a per-page change record and meaningful local preview states.
- [x] Complete the 21 world screens: save/load truth, chapter and scene selection, dialogue reading, map/destination selection, route preparation, weather, encounter and laboratory details.
- [x] Generate and inspect distinct crew portraits, ship inspection alternatives and location art; save original prompts and adoption records. Reuse adopted narrative imagery where it fits.
- [x] Implement market stock and weighted cargo constraints, one-person-one-post, recruit records, unique wage payment, actual notification history and contract hand-in feedback. Verify action contracts with meaningful state tests.
- [x] Improve shared visual rhythm, text readability, focus/keyboard handling, status feedback, table selection, consistent actions and responsive layout.
- [x] Audit actual model files/providers, create the production model ledger and show its counts, phases, existing-resource evidence and page mapping in the review tool.
- [x] Re-render and inspect all 72 default screens, check all listed preview states in VM and representative states in browser, re-export all page images and review contact sheets.
- [x] Re-run strict resource/page/preview verification and document the actual UI completion boundary and remaining game integration work.

Accepted direction: historical, restrained and cinematic. Screen art is not a substitute for usable live text and controls. No decorative noise, duplicate captain faces for different crew or empty columns masquerading as complete design. A passed script is not proof of Steam release quality; browser inspection and user review remain necessary.
