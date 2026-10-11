# wood v1 generation prompts

Mode: built-in image_gen; transparent_background: true. Two attempts: initial generation and targeted edit.

Style references previously visually inspected: docs/art/concepts/sailing-combat-direction-v1.png and apps/game-client/public/art/characters/zheng-captain-v1.png. Initial generation uses descriptive style guidance, no reference/edit target argument.

Initial source: C:/Users/dains/.codex/generated_images/01a120ee-c343-7c40-984a-0ce886209e37/exec-37cb81db-aef9-4db7-9f49-dd82953912d9.png
Final source: C:/Users/dains/.codex/generated_images/01a120ee-c343-7c40-984a-0ce886209e37/exec-efb43171-dfa9-4519-bd31-ec999747b1f6.png

## Initial prompt

```text
Use case: stylized-concept
Asset type: production transparent inventory game prop icon for Ming Armada, circa 1661 maritime trade.
Style/medium: cinematic painterly stylized-realistic PBR concept art with natural textured materials, warm upper-left rim light and cool teal fill, restrained indigo/earth brown/cinnabar palette matching the approved sailing-combat direction. Detailed realistic material but strong simple compact silhouette readable at 64 pixels.
Composition/framing: ONE centered compact grouped prop, square canvas, object visibly occupies ONLY 55-65% of width and 55-65% of height. Leave enormous genuine transparent space around ALL FOUR sides (at least 18% side margins). Do not zoom or crop to the prop. Three-quarter view from slightly above. No scene, no floor or ground, no cast shadow plate, no backdrop.
Background: genuine alpha transparent outside the object, no opaque matte, no fake checkerboard pixels.
Constraints: no UI frame, no icons beyond this prop, no lettering, no watermark, no modern manufacturing equipment, no plastic, no other scene objects, no scenery. Preserve genuine alpha.
Subject: Exactly three short weathered shipbuilding timber planks stacked in a compact bundle and bound together with rough natural hemp rope. Warm aged wood grain, sawed end grain, no nails, no tools. Recognizable wood trade good.
```

## Targeted edit

Input: initial source above, supplied through referenced_image_paths.

```text
Use case: precise-object-edit
Edit target: the supplied transparent bundled ship timber icon.
Only correction: reduce bundle to EXACTLY THREE individual ship planks, arranged one above another (three single planks stacked vertically, never two planks side-by-side per layer), bound together by the same hemp rope. Preserve weathered warm wood, clear end grain, natural hemp material, three-quarter camera, warm upper-left rim and cool teal fill. Make the complete compact bundle smaller on the square canvas, longest visible dimension exactly 60% of canvas and centered with 20% transparent side margins, maintaining natural proportions. No auto-crop/zoom.
Genuine alpha transparent outside the prop. No floor, no shadow plate, no backdrop, no drawn checkerboard, no lettering/UI/frame/watermark, no extra objects. Preserve generated alpha. No other style changes.
```

Final PNG copied byte-for-byte to wood-v1.png. Original alpha preserved, including any extremely low-alpha peripheral specks. No manual image editing, cropping, resampling, background removal or compositing.
