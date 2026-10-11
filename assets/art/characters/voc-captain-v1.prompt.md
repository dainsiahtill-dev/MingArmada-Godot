# voc-captain v1 generation prompts

Mode: built-in image_gen; transparent_background: true for both calls. Exactly two attempts: initial generation, then a single framing edit. Fictional character; no asserted historical likeness.

Style references inspected: docs/art/concepts/sailing-combat-direction-v1.png and apps/game-client/public/art/characters/zheng-captain-v1.png. Initial generation used descriptive guidance, no reference/edit target argument.

Initial source: C:/Users/dains/.codex/generated_images/01a120ee-c343-7c40-984a-0ce886209e37/exec-3555ef4b-9707-4937-883f-ca4aa906e532.png
Final source: C:/Users/dains/.codex/generated_images/01a120ee-c343-7c40-984a-0ce886209e37/exec-f2f2212a-f2b6-4b36-a7fb-5dfb6026b5f2.png

## Initial prompt

```text
Use case: stylized-concept
Asset type: production transparent dialogue and duel portrait PNG for Ming Armada.
Primary request: ONE original fictional Dutch VOC ship captain age 45, maritime East Asia circa 1661. Original fictional character, not an authentic historical likeness.
Style/medium: cinematic painterly stylized-realistic high-end game concept portrait; finely observed natural weathered skin, textured wool and linen and subtle hand-painted edges, physical material realism. Match the existing Zheng captain quality: rich desaturated indigo, subdued teal cool fill, timber brown and restrained warm rust/cinnabar accents, warm sunset rim lighting, no flat cartoon or anime outlines.
Subject: weathered stern confident Dutch man with natural anatomically convincing proportions, short beard. Restrained historically inspired circa-1661 dark wool coat and waistcoat over linen shirt. Plain broad brim felt hat of the mid-17th century, without a later tricorn. A period sword hilt visible at the waist and a small rolled command document held naturally. Tasteful practical seafaring officer rather than extravagant costume.
Composition/framing: one waist-up three-quarter character turned slightly to the viewer's left, face fully readable, complete hat, shoulders, sleeves and both hands entirely contained. Single compact portrait centered in a portrait canvas with broad genuine transparent space surrounding the whole silhouette: at least 20% of canvas width from each left/right edge to the silhouette and at least 15% above the hat. Character occupies roughly 58-60% of canvas width, about 72% of canvas height. Include clean lower torso edge and transparent space below as well. Never crop hat, shoulders, hands or sleeves. No full-frame zoom.
Scene/backdrop: actual transparent alpha outside the character, including arm gaps; no opaque pixels or tinted matte in the background, no simulated checkerboard.
Lighting/mood: warm sunset rim light with cool teal reflected fill, stern assured opponent, grounded human expression.
Constraints: no later tricorn hat, no modern or gothic clothes, no Caribbean pirate costume, no skull/crossbones, no eye patch, no fantasy armor, no duplicate subject, no scenery, no floor, no shadow plate, no decorative frame, no UI, no icons, no lettering, no watermark. Real clean alpha cutout.
```

## Targeted framing edit

Input: initial source above, supplied through referenced_image_paths.

```text
Use case: precise-object-edit
Edit target: the supplied original fictional Dutch VOC captain portrait.
Required single targeted change: make a SMALLER PORTRAIT IN A LARGER TRANSPARENT CANVAS. Uniformly scale down the existing intact subject to exactly 58% of canvas width and 70% of canvas height, centered, leaving visibly enormous clear alpha margins on ALL FOUR sides (at least 20% left/right, 15% top/bottom). Preserve the full wide brim hat, shoulders, both sleeves, both hands, rolled document, sword hilt and lower torso without cropping. This is production framing for a game UI that needs room around the portrait. Do not auto-crop to the silhouette or zoom back into the character.
Invariants: keep this exact character identity, stern weathered face, beard, three-quarter left-facing pose, restrained indigo/dark wool coat/waistcoat, linen shirt, broad brim felt hat, document, sword and hands, painterly PBR textures and warm rim/cool fill lighting unchanged. Only change scale and canvas breathing room.
Background: genuine transparent alpha, no opaque matte, no painted checkerboard, no color backdrop, no shadow plate, no frame, no text. Preserve alpha transparency. No other changes.
```

Final PNG copied byte-for-byte to voc-captain-v1.png. Generated alpha preserved, including very low-alpha peripheral specks. No manual background removal, resampling, compositing or cropping.
