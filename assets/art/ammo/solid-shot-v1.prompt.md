# Solid shot icon v1

Generator: built-in image_gen. Transparent background requested in both calls. Final selected output: second call.

## Initial prompt

```text
Use case: stylized-concept
Asset type: production game inventory ammunition icon for MingArmada, a historical 1661 Chinese sailing combat game. Single square transparent PNG cutout.
Primary request: exactly three cast-iron round cannon balls, arranged as a compact triangular stack: one ball above and behind, two side-by-side below and slightly forward, each sphere clearly distinguishable. A close three-quarter view, with a readable strong silhouette at 64 pixels.
Style/medium: original cinematic painterly stylized realism, a polished hand-painted historical prop matching the previously viewed approved maritime scene. Restrained fine material texture; dark charcoal weathered iron with subtle pitting and small worn metallic highlights, not overly shiny chrome.
Composition/framing: centered complete stack of three equal-size cannon balls, occupying roughly 70-76 percent of a square canvas, at least 10 percent fully transparent margin on every side. No clipping. Clean antialiased edges.
Lighting/mood: warm golden rim light from upper left; restrained cool muted teal fill on lower/right surfaces, clear internal value separation, no glow.
Scene/backdrop: genuine transparent background, alpha outside object; no scenery, no floor, no ground plane, no ambient surrounding haze or shadow plate. Only three touching cannon balls visible.
Text: none.
Constraints: historical solid shot, no symbols, no UI panel, no border, no frame, no watermark, no barrel, no cannon, no guns, no modern ammunition, no gunpowder sack, no fourth ball, no painted checkerboard, no circular badge, no drop shadow. Preserve genuine transparency.
```

Initial generated source: `C:/Users/dains/.codex/generated_images/01a1209d-a7e9-7451-b4dc-4901a4c72f34/exec-19250b9e-113c-4216-8be2-00ff347f5148.png`.

## Edit prompt

```text
Use case: precise-object-edit
Edit target: the generated transparent icon containing exactly three cast iron cannon balls in a triangular stack.
Change only framing and edge cleanliness: make the whole stack smaller within the square canvas and precisely center it, with at least 15 percent completely transparent clear margin on ALL four sides. Keep all nonzero alpha pixels inside the central 70 percent of the square. Remove any stray pixels, faint haze, red/yellow edge specks, colored edge fringing and surrounding shadow.
Preserve exactly three equal-size cannon balls, one above and behind two below and forward, their weathered dark charcoal iron, painterly realistic texture, warm upper-left golden highlights and cool subtle teal shading. Preserve complete shape, readable silhouette at 64 pixels, internal shadows only between balls. Do not add any text, frames, symbols, badge, border, ground, floor, scenery, glow, cast shadow, weapon or modern ammunition. Genuine transparent background with clean antialiased cutout edges; outside the three cannon balls alpha must be exactly zero.
```

Edit target: initial generated source. Final generated source: `C:/Users/dains/.codex/generated_images/01a1209d-a7e9-7451-b4dc-4901a4c72f34/exec-f6ee19d0-df23-432e-8658-96acc111f04c.png`.

## Validation

- Saved PNG: 1254 x 1254, RGBA, 819505 bytes; alpha minimum 0, maximum 255.
- Main silhouette at alpha >= 8: bounds (288, 334, 971, 967), leaving more than 22 percent margin on every side.
- Strict nonzero-alpha bounds: (57, 214, 1190, 1074). Faint alpha 1-7 residual pixels remain outside the visible silhouette, so a strict 10 percent completely zero-alpha margin is not achieved.
- Final image inspected. Exactly three weathered iron spheres, warm upper-left light and cool teal shading, no text, panel, scenery, weapon, or modern ammunition. The visible stack is centered slightly below vertical center. Two generation calls used; no manual pixel edits.
