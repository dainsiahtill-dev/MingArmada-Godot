"""Create independent R10a2 variants by guarded, reviewed source substitutions."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPECS = [
    ('tools/blender/build_hero_fuchuan_r10a.py', 'tools/blender/build_hero_fuchuan_r10a2.py', [
        ('formula.breadth(v,w,.06)', 'formula.breadth(v,w,.20)', 1),
        ('formula.surface(u,v,h,w,b,.06)', 'formula.surface(u,v,h,w,b,.20)', 1),
        ("'coefficient':.06", "'coefficient':.20", 1),
    ]),
    ('tools/blender/pack_hero_r10_sail.py', 'tools/blender/pack_hero_r10a2_sail.py', [
        ("'coefficient':.06", "'coefficient':.20", 1),
    ]),
    ('tools/research/verify_hero_r10_sail_delta.py', 'tools/research/verify_hero_r10a2_sail_delta.py', [
        ("author.get('coefficient')==.06", "author.get('coefficient')==.20", 1),
        ('predicted=.06*width', 'predicted=.20*width', 1),
        ('delta=.06*width', 'delta=.20*width', 1),
        ('0.06 formula', '0.20 formula', 1),
        ('declared 0.06 shoulder', 'declared 0.20 shoulder', 1),
    ]),
]


def transform(text, changes):
    for old, new, count in changes:
        if text.count(old) != count:
            raise ValueError(f'expected {count} occurrences of {old!r}, found {text.count(old)}')
        text = text.replace(old, new)
    return text.replace('r10a', 'r10a2').replace('R10a', 'R10a2').replace('R10A', 'R10A2')


def main():
    prepared = [(ROOT / dst, transform((ROOT / src).read_text(encoding='utf-8'), changes))
                for src, dst, changes in SPECS]
    if any(path.exists() for path, _ in prepared):
        raise FileExistsError('all R10a2 tool paths must be fresh')
    for path, text in prepared:
        with path.open('x', encoding='utf-8', newline='\n') as f:
            f.write(text)
        print(path.relative_to(ROOT))


if __name__ == '__main__':
    main()
