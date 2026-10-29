"""Derive the pre-registered R14b tools without altering frozen R14 code."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def once(text,a,b):
    if text.count(a)!=1:raise ValueError('expected unique text: '+a[:80])
    return text.replace(a,b,1)
def fresh(path,text):
    with (ROOT/path).open('x',encoding='utf-8',newline='\n') as f:f.write(text)
def main():
    text=(ROOT/'tools/blender/build_hero_fuchuan_r14.py').read_text(encoding='utf8').replace('r14','r14b').replace('R14','R14B')
    text=text.replace('R14B-DECK-HATCH-BRIEF.md','R14-DECK-HATCH-BRIEF.md')
    text=once(text,"rectangles=[(-1.10,-.92,-1.35,1.35),(.92,1.10,-1.35,1.35),(-.92,.92,-1.35,-1.17),(-.92,.92,1.17,1.35)]", "rectangles=[(-.925,-.745,-1.125,1.125),(.745,.925,-1.125,1.125),(-.745,.745,-1.125,-.945),(-.745,.745,.945,1.125)]")
    text=once(text,'vertices.append((x,-z,y+.03));vertices.append((x,-z,y+.55))','vertices.append((x,-z,y+.03));vertices.append((x,-z,deck(0,center)+.34))')
    text=once(text,"'outer':[2.2,2.7],'heightAboveDeck':[.03,.55]", "'outer':[1.85,2.25],'heightAboveDeck':[.03,.34],'topHeightReference':'deck center'")
    fresh('tools/blender/build_hero_fuchuan_r14b.py',text)
    pack=(ROOT/'tools/blender/pack_hero_r14_coamings.py').read_text(encoding='utf8').replace('r14','r14b').replace('R14','R14B')
    fresh('tools/blender/pack_hero_r14b_coamings.py',pack)
    verify=(ROOT/'tools/research/verify_hero_r14_coamings.py').read_text(encoding='utf8').replace('r14','r14b').replace('R14','R14B')
    verify=once(verify,"-2.2)>1e-5 or abs(max(p[2] for p in pos)-min(p[2] for p in pos)-2.7)>1e-5", "-1.85)>1e-5 or abs(max(p[2] for p in pos)-min(p[2] for p in pos)-2.25)>1e-5")
    verify=once(verify,'height=y-deck(x,z);max_error=max(max_error,min(abs(height-.03),abs(height-.55)))', 'height=y-deck(x,z);max_error=max(max_error,min(abs(height-.03),abs(y-(deck(0,zcenter)+.34))))')
    verify=once(verify,'abs(x)<.919 and abs(z-zcenter)<1.169','abs(x)<.744 and abs(z-zcenter)<.944')
    verify=once(verify,"'outer':[2.2,2.7]", "'outer':[1.85,2.25]")
    fresh('tools/research/verify_hero_r14b_coamings.py',verify)
    clearance=(ROOT/'tools/research/verify_hero_r14_static_clearance.py').read_text(encoding='utf8').replace('r14','r14b').replace('R14','R14B')
    fresh('tools/research/verify_hero_r14b_static_clearance.py',clearance)
    test=(ROOT/'tests/test_hero_fuchuan_r14_obstacles.gd').read_text(encoding='utf8').replace('r14','r14b').replace('R14','R14B')
    test=once(test,'absf(box.size.x-2.2)<.001 and absf(box.size.z-2.7)<.001','absf(box.size.x-1.85)<.001 and absf(box.size.z-2.25)<.001')
    test=test.replace('obstacles-03.json','obstacles-01.json')
    fresh('tests/test_hero_fuchuan_r14b_obstacles.gd',test)
    print('HERO_R14B_TOOLS_CREATED')
if __name__=='__main__':main()
