"""Diagnostic catalogue only; no source or game texture transformation."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[2]
source = Path('C:/Games/Pirates-REA-Reference-20261011/preview/images/fpk')
choices = [('Pak4', 'wake3unique.dds.png'), ('Pak6', 'fx_water_splash_004.dds.png'),
           ('Pak1', 'fx_streakin_001.dds.png'), ('Pak5', 'fx_mist_01.dds.png'),
           ('Pak5', 'fx_water_drop_01.dds.png'), ('Pak3', 'fx_water_splash_03_circular.dds.png'),
           ('Pak0', 'surfsmall.dds.png'), ('Pak6', 'caust01.dds.png')]
width, row_height = 1024, 192
sheet = Image.new('RGB', (width, 64 + len(choices) * row_height), '#18272e')
draw = ImageDraw.Draw(sheet)
font = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 19)
small = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 15)
draw.text((22, 18), 'Water library shortlist | original RGB / alpha mask', fill='white', font=font)
for index, (pak, name) in enumerate(choices):
    y = 64 + index * row_height
    with Image.open(source / pak / name) as original:
        rgba = original.convert('RGBA')
        rgb = rgba.convert('RGB'); alpha = rgba.getchannel('A').convert('RGB')
        for image, x, title in [(rgb, 642, 'RGB'), (alpha, 838, 'ALPHA')]:
            image.thumbnail((150, 152), Image.Resampling.NEAREST)
            draw.rectangle((x-6, y+23, x+156, y+180), fill='#070e11')
            sheet.paste(image, (x + (150-image.width)//2, y+26 + (152-image.height)//2))
            draw.text((x, y+2), title, fill='#91cdd4', font=small)
        draw.text((22, y+44), pak + '/' + name, fill='white', font=font)
        lo, hi = rgba.getchannel('A').getextrema()
        draw.text((22, y+77), f'{rgba.width} x {rgba.height} | stored alpha {lo}..{hi}', fill='#bdd1d0', font=small)
        draw.line((18, y+row_height-2, width-18, y+row_height-2), fill='#3d565e')
output = root / 'docs/migration/evidence/water-library-shortlist.png'
sheet.save(output)
print(str(output))
