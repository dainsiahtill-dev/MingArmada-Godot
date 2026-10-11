# merchant-woman v1 generation prompts

Mode: built-in image_gen; transparent_background: true for both calls. Exactly two attempts: initial generation, then a single framing edit. Fictional character; no asserted historical likeness.

Style references inspected: docs/art/concepts/sailing-combat-direction-v1.png and apps/game-client/public/art/characters/zheng-captain-v1.png. Initial generation used descriptive guidance, no reference/edit target argument.

Initial source: C:/Users/dains/.codex/generated_images/01a120ee-c343-7c40-984a-0ce886209e37/exec-cbec611e-5cb4-435a-94ce-665b67297d9e.png
Final source: C:/Users/dains/.codex/generated_images/01a120ee-c343-7c40-984a-0ce886209e37/exec-14c0825b-1968-4c82-a9e9-4c11b7f75c5b.png

## Initial prompt

```text
Use case: stylized-concept
Asset type: production transparent dialogue portrait PNG for Ming Armada.
Primary request: ONE original fictional Chinese Fujian silk merchant woman, age 32, Southern Ming maritime world circa 1661. Original fictional character, not an authentic historical likeness.
Style/medium: cinematic painterly stylized-realistic high-end game concept portrait; finely observed natural skin, textured woven cloth and subtle hand-painted edges, physical material realism. Match the existing Zheng captain quality: rich indigo, subdued teal cool fill, timber brown and restrained cinnabar accents, warm sunset rim lighting, no flat cartoon or anime outlines.
Subject: practical warm confident woman with natural anatomically convincing proportions, serene lively face, modest Ming cross-collar robe in refined indigo and earth tones with restrained cinnabar woven trim. Simple period hair bun and one understated hairpin. She holds a small wrapped silk sample naturally in both hands at waist level. Modest merchant, tasteful unostentatious period clothing.
Composition/framing: one waist-up three-quarter character turned slightly to the viewer's right, face fully readable, complete hair bun, shoulders, sleeves and both hands entirely contained. Single compact portrait centered in a portrait canvas with broad genuine transparent space surrounding the whole silhouette: at least 20% of canvas width from each left/right edge to the silhouette and at least 15% above the head. Character occupies roughly 58-60% of canvas width, about 72% of canvas height. Include a clean lower torso edge and transparent space below as well. Never crop head, shoulders, hands or sleeves. No full-frame zoom.
Scene/backdrop: actual transparent alpha outside the character, including arm gaps; no opaque pixels or tinted matte in the background, no simulated checkerboard.
Lighting/mood: warm sunset rim light with cool teal reflected fill, approachable, warm and assured.
Constraints: no Qing hairstyle, no queue, no modern clothing, no fantasy armor, no revealing costume, no duplicate subject, no scenery, no floor, no shadow plate, no decorative frame, no UI, no icons, no lettering, no watermark. Real clean alpha cutout.
```

## Targeted framing edit

Input: initial source above, supplied through referenced_image_paths.

```text
Use case: precise-object-edit
Edit target: the supplied original fictional Ming Fujian silk merchant woman portrait.
Required single targeted change: make a SMALLER PORTRAIT IN A LARGER TRANSPARENT CANVAS. Uniformly scale down the existing intact subject to exactly 58% of canvas width and 70% of canvas height, centered, leaving visibly enormous clear alpha margins on ALL FOUR sides (at least 20% left/right, 15% top/bottom). Preserve the full head, shoulders, both sleeves, both hands holding silk and lower torso without cropping. This is production framing for a game UI that needs room around the portrait. Do not auto-crop to the silhouette or zoom back into the character.
Invariants: keep this exact character identity, face, expression, three-quarter right-facing pose, cross-collar indigo/cinnabar Ming robe, hair bun and pin, wrapped silk sample, hands, painterly PBR textures and warm rim/cool fill lighting unchanged. Only change scale and canvas breathing room.
Background: genuine transparent alpha, no opaque matte, no painted checkerboard, no color backdrop, no shadow plate, no frame, no text. Preserve alpha transparency. No other changes.
```

Final PNG copied byte-for-byte to merchant-woman-v1.png. Generated alpha preserved, including very low-alpha peripheral specks. No manual background removal, resampling, compositing or cropping.
