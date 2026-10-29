"""Read-only regression for the flat-water camera fixture, never edits evidence."""
import json
import sys
from pathlib import Path
from PIL import Image

frames=Path(sys.argv[1])
report=json.loads((frames/'capture-result.json').read_text(encoding='utf-8'))
frame=frames/'battle-000.png'
im=Image.open(frame).convert('RGBA')
# Camera looks down on uninterrupted water. HUD occupies the top/bottom strips.
# The old stale projection left transparent holes through the central sea area.
pixels=[im.getpixel((int(im.width*(0.1+0.8*x/15)),int(im.height*(0.25+0.4*y/15)))) for y in range(16) for x in range(16)]
opaque=sum(p[3]>=250 for p in pixels)
valid=opaque==256
print(json.dumps({'valid':valid,'frame':str(frame),'opaqueCentralSamples':opaque,'samples':256,'scope':'Flat-water tick-zero coverage regression only; not broad art or performance approval.'}))
raise SystemExit(0 if valid else 1)
