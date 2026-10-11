# spices v1 generation prompts

Mode: built-in image_gen; transparent_background: true. Two attempts: initial generation and targeted edit.

Style references previously visually inspected: docs/art/concepts/sailing-combat-direction-v1.png and apps/game-client/public/art/characters/zheng-captain-v1.png. Initial generation uses descriptive style guidance, no reference/edit target argument.

Initial source: C:/Users/dains/.codex/generated_images/01a120ee-c343-7c40-984a-0ce886209e37/exec-97fcf30e-4f8a-4325-80ba-c3167a151e99.png
Final source: C:/Users/dains/.codex/generated_images/01a120ee-c343-7c40-984a-0ce886209e37/exec-0a2f59c7-474a-4954-beb5-91edbabe6209.png

## Initial prompt

```text
Use case: stylized-concept
Asset type: production transparent inventory game prop icon for Ming Armada, circa 1661 maritime trade.
Style/medium: cinematic painterly stylized-realistic PBR concept art with natural textured materials, warm upper-left rim light and cool teal fill, restrained indigo/earth brown/cinnabar palette matching the approved sailing-combat direction. Detailed realistic material but strong simple compact silhouette readable at 64 pixels.
Composition/framing: ONE centered compact grouped prop, square canvas, object visibly occupies ONLY 55-65% of width and 55-65% of height. Leave enormous genuine transparent space around ALL FOUR sides (at least 18% side margins). Do not zoom or crop to the prop. Three-quarter view from slightly above. No scene, no floor or ground, no cast shadow plate, no backdrop.
Background: genuine alpha transparent outside the object, no opaque matte, no fake checkerboard pixels.
Constraints: no UI frame, no icons beyond this prop, no lettering, no watermark, no modern manufacturing equipment, no plastic, no other scene objects, no scenery. Preserve genuine alpha.
Subject: One small coarse cloth spice pouch slightly open containing cinnamon sticks, two star-anise pods and a modest mound of peppercorns. Some cinnamon and star anise visibly rest at the lip. Compact cohesive warm earth-brown silhouette, no scattered floor arrangement. Recognizable spices trade good.
```

## Targeted edit

Input: initial source above, supplied through referenced_image_paths.

```text
Use case: precise-object-edit
Edit target: supplied transparent spices trade good icon.
Required single targeted change: uniformly scale the intact grouped prop smaller to precisely 60% of the square canvas's LONGEST visible dimension. Center it and leave generous transparent space on all sides, at least 20% around its longest dimension. Preserve natural object proportions. Do not automatically crop canvas or zoom into the object.
Invariants: keep exact objects, arrangement, material texture, color, camera angle, warm upper-left rim and cool teal fill, painterly PBR polish unchanged. Only change scale and position within canvas.
Background: genuine transparent alpha, no opaque matte, no checkerboard painted into pixels, no floor, no cast shadow plate, no UI/text/frame/watermark. Preserve alpha. No other changes.
```

Final PNG copied byte-for-byte to spices-v1.png. Original alpha preserved, including any extremely low-alpha peripheral specks. No manual image editing, cropping, resampling, background removal or compositing.
