# Root independent verification notes

The final native RETURN run completed with 15 PNGs, console 801 assertions / 0 failures and capture-result 799 assertions / 0 failures. Root personally inspected all fifteen PNGs using view_image. See native-return-complete/root-visual-inspection.json.

The first independent identity/readback verifier passed 1020 checks. While adding an additional exact pre-save comparison, root mistakenly used a PNG sidecar as exact state. That added assertion failed: sidecars use the capture tool's default JSON.stringify formatting, so enemy position, heading, speed and sail-angle floats have fewer digits than the raw native save. For example, the sidecar enemy x is 334.004233313127, whereas the raw save is 334.0042333131271. This was a verifier input-precision mistake, not a new game-state or GPU failure.

The final verifier uses sidecars only for image identity, viewport, source identity and UI evidence. Exact state evidence remains the immutable confirmed checkpoint, normal UI save bytes, the live full-precision GPU harness comparisons, and the independently checked full-precision CPU normal-export diagnostic. No sidecar was repaired, adopted, encoded as a save, or compared after arbitrary rounding. No production, Codec, journey or GPU artifact was changed.

After correcting that verifier, root ran build/opening-story-qa/verify-final-evidence.py with RTK. Exit 0: 1052 checks / 0 failures. The result is final-evidence-verification.json; it includes the precision boundary explicitly. It verifies the genuine 29/0 journey and checkpoint, the complete 103-script suite, all 9 opening and 15 RETURN images/source identities, exact saved byte hashes, real twenty-grain loading, actual sunk enemy, all 12 original user-slot existence/hash values, exact CPU export semantics, and root's fifteen-image inspection identities.

This evidence does not claim a completed second twenty-grain voyage, all historical chapters, solved port-approach deadlock, measured performance, or verified player engagement. The next-voyage story design and the port-approach pacing audit record those outstanding scopes.
