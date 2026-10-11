# Chain shot v1

Built-in image_gen; transparent_background: true. Style reference inspected: docs/art/concepts/sailing-combat-direction-v1.png.

## Initial generation prompt

```text
Use case: stylized-concept
Asset type: ONE square transparent game inventory ammunition icon for MingArmada, a cinematic sailing combat game set around 1661 off the Chinese coast.
Primary request: CHAIN SHOT, a single complete period ammunition prop: exactly two small dark cast iron cannonball ends joined by a short heavy iron chain. The thick chain forms a compact relaxed shallow curve, angled diagonally from lower left to upper right. Both spherical end weights must be unmistakably visible, with a readable sequence of complete interlocking oval chain links between them.
Style/medium: original cinematic painterly stylized realism; a polished hand-painted historical game prop, matching the visual language of detailed weathered dark ship metal, antique warm brass-like highlights, and cool teal maritime fill seen in the sailing game concept. Render only the ammunition prop.
Composition/framing: centered complete prop, compact bold silhouette, readable at 64px; generous >=10% completely transparent margin on every side; no cropping. Slight three-quarter view for iron volume, clear separation between both end weights and links.
Lighting/mood: upper-left warm rim light and restrained cool teal fill. Strong enough value contrast for readability; subtle worn warm iron edge highlights.
Materials/textures: matte near-black cast iron, worn warm metallic edges, restrained roughness and age, physically joined chain links, avoid glossy plastic.
Scene/backdrop: genuinely transparent background with real alpha; isolated cutout; no environment.
Constraints: exactly one chain-shot prop with two spherical iron ends; no gun, no barrel, no hands, no text, no frame, no background, no floor, no shadow plate, no watermark, no modern ammunition. All negative space including gaps inside links must be transparent.
```

## Targeted edit prompt

Edit target: `C:/Users/dains/.codex/generated_images/01a1209d-d3d4-7dc3-9173-a37b1c8037a0/exec-03b7868b-4af6-4726-8b5c-8bc3bf28ff31.png`

```text
Use case: precise-object-edit
Asset type: transparent game ammunition icon.
Input image 1 is the edit target, a complete two-ball chain-shot prop.
Change ONLY framing and edge cleanup: preserve the exact two iron spherical end weights, all complete connected heavy oval chain links, relaxed diagonal curve, materials, original warm upper-left highlights, cool teal fill, painterly rendering, and proportions. Make the entire prop smaller and center it in the square canvas so ALL visible/nontransparent pixels of the complete object fit inside a central bounding box with at least 12% genuinely transparent margin on all four sides. Remove any detached edge specks or stray alpha artifacts. Make gaps between links truly transparent. Keep the prop large enough to read clearly at 64px.
Background must be real full alpha transparency, including all unused canvas; do not replace it with black or a checkerboard. No added items, background, floor, shadow plate, text, border, frame, gun, barrel, watermark. Do not change the design or pose.
```

Final generated source: `C:/Users/dains/.codex/generated_images/01a1209d-d3d4-7dc3-9173-a37b1c8037a0/exec-303f6895-2ca6-4666-9ab1-1b551ebd65fd.png`
