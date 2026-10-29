"""Original procedural shipping packages. Blender source, GLB exports and render QA.

Launch: rtk proxy python tools/blender/build_cargo_pack_r1.py --launch
No borrowed textures. Dimensions are metres; exported origin is bottom centre.
The forms are creative historical reconstruction, not a dated archaeological claim.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import struct
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/models/cargo_pack/r1'
BLENDER = Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
GOODS = ('grain', 'water', 'wood', 'iron', 'powder', 'cloth', 'silk', 'porcelain', 'tea', 'sugar', 'salt', 'spices')
MATS = {}
PARTS = {}
CURRENT = None
RNG = random.Random(291026)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def material(name, rgb, rough=.7, metal=0):
    import bpy
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*rgb, 1)
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    m.diffuse_color = (*rgb, 1)
    MATS[name] = m


def palette():
    for i, c in enumerate(((.24,.105,.043),(.29,.145,.064),(.35,.18,.078),(.40,.226,.112),(.20,.084,.035))):
        material('wood'+str(i), tuple(v*.72 for v in c), .79)
    for n,c,r,me in (
        ('hemp',(.44,.315,.15),.92,0),('hemp_light',(.60,.47,.28),.94,0),
        ('grain_cloth',(.54,.43,.26),.98,0),('cloth_cream',(.66,.61,.48),.98,0),
        ('cloth_indigo',(.095,.15,.18),.96,0),('cloth_russet',(.32,.15,.09),.94,0),
        ('iron',(.08,.085,.08),.52,.78),('iron_edge',(.15,.16,.15),.4,.82),
        ('grain_gold',(.66,.47,.20),.77,0),('grain_pale',(.78,.62,.32),.8,0),
        ('cinnabar',(.42,.055,.028),.48,0),('powder_wood',(.105,.064,.041),.85,0),
        ('silk_jade',(.12,.30,.25),.34,0),('silk_wine',(.32,.065,.10),.35,0),
        ('silk_oldgold',(.52,.36,.12),.35,0),('silk_ivory',(.72,.65,.46),.35,0),
        ('porcelain',(.76,.79,.68),.19,0),('celadon',(.36,.53,.43),.22,0),
        ('cobalt',(.035,.09,.17),.26,0),('straw',(.49,.36,.16),.95,0),
        ('tea_dark',(.13,.07,.031),.82,0),('tea_leaf',(.25,.27,.11),.83,0),
        ('sugar',(.79,.67,.43),.8,0),('sugar_pale',(.86,.79,.58),.88,0),
        ('salt',(.76,.75,.65),.9,0),('salt_crystal',(.88,.86,.75),.64,0),
        ('terracotta',(.34,.13,.063),.7,0),('jar_olive',(.22,.25,.12),.45,0),
        ('jar_dark',(.15,.11,.075),.48,0),('spice_ochre',(.53,.25,.07),.9,0),
        ('pepper',(.12,.054,.025),.9,0)):
        material(n,c,r,me)


def register(obj, mat):
    import bpy
    obj.data.materials.append(MATS[mat])
    obj.parent = CURRENT
    obj['cargo_good'] = CURRENT['good']
    PARTS[CURRENT['good']].append(obj)
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    CURRENT.users_collection[0].objects.link(obj)
    return obj


def mesh(name, verts, faces, mat, smooth=False):
    import bpy
    data=bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    ob=bpy.data.objects.new(name,data)
    bpy.context.scene.collection.objects.link(ob)
    register(ob,mat)
    if smooth:
        for p in data.polygons:p.use_smooth=True
    return ob


def box(name, loc, size, mat, bevel=.012, rot=None):
    import bpy
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    ob=bpy.context.object;ob.name=name
    ob.scale=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if rot:ob.rotation_euler=rot
    if bevel:
        mod=ob.modifiers.new('Worn eased edges','BEVEL');mod.width=bevel;mod.segments=2
        mod=ob.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return register(ob,mat)


def ball(name, loc, scale, mat, segments=12, rings=8):
    import bpy
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,radius=1,location=loc)
    ob=bpy.context.object;ob.name=name;ob.scale=scale
    for p in ob.data.polygons:p.use_smooth=True
    return register(ob,mat)


def tube(name, points, radius, mat, closed=False, sides=6):
    # Parallel-transport-like frames avoid curve export dependencies.
    from mathutils import Vector
    pts=[Vector(p) for p in points]
    verts=[];faces=[]
    for i,p in enumerate(pts):
        before=pts[(i-1)%len(pts)] if closed or i else pts[0]
        after=pts[(i+1)%len(pts)] if closed or i<len(pts)-1 else pts[-1]
        tangent=(after-before).normalized()
        ref=Vector((0,0,1)) if abs(tangent.z)<.9 else Vector((0,1,0))
        u=tangent.cross(ref).normalized();v=tangent.cross(u).normalized()
        verts += [tuple(p+radius*(u*math.cos(j*math.tau/sides)+v*math.sin(j*math.tau/sides))) for j in range(sides)]
    count=len(pts) if closed else len(pts)-1
    for i in range(count):
        nxt=(i+1)%len(pts)
        for j in range(sides):
            k=(j+1)%sides;faces.append((i*sides+j,nxt*sides+j,nxt*sides+k,i*sides+k))
    if not closed:
        faces.extend([tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+j for j in range(sides))])
    return mesh(name,verts,faces,mat,True)


def ring(name, cx,cy,z,rx,ry,r,mat,n=48):
    return tube(name,[(cx+rx*math.cos(i*math.tau/n),cy+ry*math.sin(i*math.tau/n),z) for i in range(n)],r,mat,True)


def lathe(name, profile, mat, loc=(0,0,0), segments=32, wobble=0, close=True):
    verts=[];faces=[]
    for k,(r,z) in enumerate(profile):
        for i in range(segments):
            a=i*math.tau/segments
            radius=r*(1+wobble*math.sin(5*a+z*9)+wobble*.5*math.sin(9*a-z*7))
            verts.append((loc[0]+radius*math.cos(a),loc[1]+radius*math.sin(a),loc[2]+z))
    for k in range(len(profile)-1):
        for i in range(segments):
            j=(i+1)%segments;faces.append((k*segments+i,k*segments+j,(k+1)*segments+j,(k+1)*segments+i))
    if close:
        faces += [tuple(reversed(range(segments))),tuple((len(profile)-1)*segments+i for i in range(segments))]
    return mesh(name,verts,faces,mat,True)


def rope_rectangle(name, axis, centre, width,height,rad=.013):
    c=list(centre);pts=[]
    for i in range(64):
        a=i*math.tau/64
        # Superellipse rounds the corners without cutting through packages.
        u=math.copysign(abs(math.cos(a))**.32,math.cos(a))*width/2
        v=math.copysign(abs(math.sin(a))**.32,math.sin(a))*height/2
        if axis=='X':pts.append((c[0],c[1]+u,c[2]+v))
        elif axis=='Y':pts.append((c[0]+u,c[1],c[2]+v))
        else:pts.append((c[0]+u,c[1]+v,c[2]))
    tube(name,pts,rad,'hemp',True)
    # An offset second strand produces actual rope relief at arm's length.
    if axis in ('X','Y'):
        shifted=[(x+(.009 if axis=='X' else 0),y+(.009 if axis=='Y' else 0),z) for x,y,z in pts]
        tube(name+' twin strand',shifted,rad*.45,'hemp_light',True,5)


def plank_crate(name,w=.95,d=.67,h=.35,slats=2,mat='wood1'):
    inner_w=w-.08
    for i in range(5):
        # Floor ends sit inside the corner posts: no overlapping coplanar end faces.
        box(name+' floor plank '+str(i),(-inner_w/2+inner_w*(i+.5)/5,0,.055),(inner_w/5-.008,d-.08,.07),'wood'+str(1+i%3),.007)
    for x in (-w/2+.035,w/2-.035):
        for y in (-d/2+.035,d/2-.035):
            box(name+' corner',(x,y,h/2+.04),(.07,.07,h+.03),mat,.008)
    for j in range(slats):
        z=.13+j*max(.09,(h-.11)/max(1,slats-1))
        for y in (-d/2,d/2):box(name+' long side slat',(0,y,z),(w,.04,.073),mat,.008)
        for x in (-w/2,w/2):box(name+' end slat',(x,0,z),(.045,d,.073),mat,.008)
    for x in (-w*.35,w*.35):box(name+' skid',(x,0,.018),(.09,d+.045,.035),'wood0',.006)


def sack(name,loc=(0,0,0),radius=.27,h=.66,mat='grain_cloth',opened=False):
    cx,cy,cz=loc
    profile=[(.61*radius,.025),(.91*radius,.10*h),(radius,.28*h),(.97*radius,.56*h),(.78*radius,.78*h)]
    if opened:profile += [(.71*radius,.91*h),(.73*radius,h),(.64*radius,h+.008),(.60*radius,.87*h)]
    else:profile += [(.46*radius,.86*h),(.28*radius,.92*h),(.32*radius,h),(.10*radius,h*1.02)]
    # The open sack still has a closed underside and an interior below the grain.
    lathe(name+' gathered sack',profile,mat,loc,32,.025,True)
    # Vertical stitched side seam follows the bulging wall.
    seam=[(cx+r*1.015,cy+.005,cz+z) for r,z in profile[:5]]
    tube(name+' raised side seam',seam,.005,'hemp_light')
    for i in range(11):
        z=.12*h+i*.05*h;r=radius*(.92+.07*math.sin(z/h*math.pi))
        tube(name+' stitch '+str(i),[(cx+r,cy-.016,cz+z),(cx+r+.002,cy+.016,cz+z+.008)],.0026,'hemp')
    neck=.88*h if not opened else .95*h
    ring(name+' draw cord',cx,cy,cz+neck,radius*(.38 if not opened else .73),radius*(.38 if not opened else .73),.009,'hemp')
    tube(name+' cord ends',[(cx+.06,cy-radius*.38,cz+neck),(cx+.10,cy-radius*.43,cz+neck-.09),(cx+.13,cy-radius*.4,cz+neck-.13)],.008,'hemp')
    if opened:
        ball(name+' exposed grain mound',(cx,cy,cz+h*.90),(radius*.63,radius*.63,.055),'grain_gold',24,10)
        for i in range(46):
            a=RNG.random()*math.tau;r=math.sqrt(RNG.random())*radius*.59
            z=cz+h*.91+.045*(1-(r/(radius*.65))**2)
            ob=ball(name+' individual grain '+str(i),(cx+math.cos(a)*r,cy+math.sin(a)*r,z),(.019,.009,.008),'grain_pale' if i%3 else 'grain_gold',8,4)
            ob.rotation_euler.z=a


def grain():
    sack('Closed grain sack',(-.23,.11,0),.29,.69)
    sack('Open grain sack',(.25,-.12,0),.255,.49,opened=True)


def barrel(name,r=.35,h=.88,dark=False):
    def rr(t):return r*(.84+.16*math.sin(math.pi*t)**.8)
    levels=[0,.08,.25,.5,.75,.92,1];n=18
    for j in range(n):
        aa=j*math.tau/n+.009;bb=(j+1)*math.tau/n-.009
        verts=[]
        for t in levels:
            for radius,a in ((rr(t),aa),(rr(t),bb),(rr(t)-.027,bb),(rr(t)-.027,aa)):
                verts.append((radius*math.cos(a),radius*math.sin(a),t*h+.035))
        faces=[]
        for k in range(len(levels)-1):
            for q in range(4):faces.append((k*4+q,k*4+(q+1)%4,(k+1)*4+(q+1)%4,(k+1)*4+q))
        faces += [(3,2,1,0),tuple((len(levels)-1)*4+q for q in range(4))]
        mesh(name+' individual stave '+str(j),verts,faces,'powder_wood' if dark else 'wood'+str(j%4))
    for t in (.11,.33,.73,.91):
        z=t*h+.035;radius=rr(t)+.008
        lathe(name+' forged hoop',[(radius-.014,z-.023),(radius+.012,z-.023),(radius+.012,z+.023),(radius-.014,z+.023)],'iron',segments=48)
        for a in (0,math.pi):ball(name+' hoop rivet',(math.cos(a)*(radius+.015),math.sin(a)*(radius+.015),z),(.012,.012,.012),'iron_edge',8,4)
    rad=rr(1)-.011
    lathe(name+' recessed lid',[(rad,.035+h-.027),(rad,.035+h-.014)],'wood1' if not dark else 'powder_wood')
    for x in (-.18,-.09,0,.09,.18):
        if abs(x)>rad:continue
        y=math.sqrt(max(0,rad*rad-x*x))*.97
        tube(name+' lid plank joint',[(x,-y,h+.023),(x,y,h+.023)],.003,'wood0',sides=4)
    lathe(name+' wooden bung',[(.045,h+.022),(.043,h+.04)],'wood3',loc=(.10,0,0),segments=16)


def water():
    barrel('Water cask')
    for x in (-.31,.31):
        tube('Water cask rope handle',[(x,0,.70),(x*1.18,-.06,.62),(x*1.19,.06,.53),(x,0,.49)],.018,'hemp')


def wood():
    for row,ys in enumerate(((-.25,-.075,.10,.275),(-.18,0,.18))):
        for j,y in enumerate(ys):
            z=.09+row*.18;length=1.15+RNG.uniform(-.07,.07)
            box('Squared timber '+str(row)+'-'+str(j),(0,y,z),(length,.17,.17),'wood'+str((row+j)%4),.018)
            for end in (-1,1):
                for a in (.025,.050):
                    tube('Timber exposed growth ring',[(end*(length/2+.001),y+a*math.cos(k*math.tau/20),z+a*.75*math.sin(k*math.tau/20)) for k in range(20)],.0025,'wood0',True,4)
    for x in (-.38,.38):rope_rectangle('Timber bundle lashing','X',(x,.005,.19),.75,.40,.017)


def iron():
    plank_crate('Iron shipping frame',.91,.65,.32,1,'wood0')
    for row in range(2):
        for x in (-.26,0,.26):
            y=(-.135 if row==0 else .135);z=.14
            lo=[(x+u*.115,y+v*.09,z) for u,v in ((-1,-1),(1,-1),(1,1),(-1,1))]
            hi=[(x+u*.085,y+v*.07,z+.16) for u,v in ((-1,-1),(1,-1),(1,1),(-1,1))]
            mesh('Cast iron trapezoid ingot',lo+hi,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'iron')
            box('Ingot upper casting ridge',(x,y,z+.16),(.15,.016,.012),'iron_edge',.003)
    for x in (-.32,.32):rope_rectangle('Iron securing rope','X',(x,0,.19),.67,.37,.014)


def powder():
    barrel('Sealed gunpowder keg',.275,.61,True)
    box('Cinnabar sealing paper across lid',(.01,0,.668),(.12,.43,.009),'cinnabar',.003)
    lathe('Wax seal',[(.047,.670),(.05,.680),(.043,.691)],'cinnabar',loc=(.01,-.07,0),segments=20)
    for dx in (-.014,.014):box('Wax seal incised stroke',(.01+dx,-.07,.693),(.006,.043,.004),'powder_wood',.001)
    rope_rectangle('Powder keg safety binding','Y',(0,0,.34),.60,.68,.010)


def roll(name,cx,cy,cz,length,radius,mat):
    verts=[];faces=[];n=32;m=8
    for k in range(m+1):
        x=cx-length/2+length*k/m
        for j in range(n):
            a=j*math.tau/n;r=radius*(1+.027*math.sin(a*5+k*.8))
            verts.append((x,cy+r*math.cos(a),cz+r*math.sin(a)))
    for k in range(m):
        for j in range(n):faces.append((k*n+j,k*n+(j+1)%n,(k+1)*n+(j+1)%n,(k+1)*n+j))
    faces += [tuple(reversed(range(n))),tuple(m*n+j for j in range(n))]
    mesh(name+' soft cylinder',verts,faces,mat,True)
    for end in (-1,1):
        tube(name+' rolled fabric spiral',[(cx+end*(length/2+.002),cy+(radius*.18+radius*.77*i/72)*math.cos(i*math.pi*4/72),cz+(radius*.18+radius*.77*i/72)*math.sin(i*math.pi*4/72)) for i in range(73)],.004,'hemp_light',False,4)
    for x in (cx-length*.32,cx+length*.32):
        tube(name+' binding band',[(x,cy+(radius+.008)*math.cos(i*math.tau/40),cz+(radius+.008)*math.sin(i*math.tau/40)) for i in range(40)],.007,'hemp',True)


def cloth():
    roll('Coarse cloth lower cream',0,-.18,.19,.93,.18,'cloth_cream')
    roll('Coarse cloth lower indigo',0,.18,.19,.89,.18,'cloth_indigo')
    roll('Coarse cloth upper russet',.02,0,.49,.83,.17,'grain_cloth')
    # Convex support envelope of the three rolls produces a taut triangular tie.
    circles=((- .18,.19,.18),(.18,.19,.18),(0,.49,.17))
    for x in (-.28,.28):
        pts=[]
        for i in range(80):
            a=i*math.tau/80;u=math.cos(a);v=math.sin(a)
            cy,cz,r=max(circles,key=lambda q:q[0]*u+q[1]*v+q[2])
            pts.append((x,cy+(r+.009)*u,cz+(r+.009)*v))
        tube('Cloth bale taut binding',pts,.011,'hemp',True)
    # Loose fabric selvage curls down from the top roll; an actual sheet edge.
    mesh('Unrolled cloth selvage',[(-.32,-.13,.61),(.34,-.13,.61),(.34,-.24,.53),(-.32,-.24,.53),(-.30,-.28,.43),(.31,-.28,.43)],[(0,1,2,3),(3,2,5,4)],'grain_cloth')


def silk():
    plank_crate('Silk protective open case',.99,.68,.24,1,'wood2')
    for i,mat in enumerate(('silk_jade','silk_wine','silk_oldgold','silk_ivory')):
        roll('Silk roll '+mat,0,-.225+i*.15,.25,.82,.084,mat)
    roll('Raised silk jade roll',0,.02,.41,.77,.083,'silk_jade')
    for y in (-.325,.325):
        for i in range(9):box('Silk case narrow bamboo guard',(-.44+i*.11,y,.20),(.025,.025,.27),'wood3',.004)
    tube('Silk case carry loop',[(-.19,.36,.20),(-.16,.41,.40),(.15,.41,.40),(.19,.36,.20)],.012,'hemp')


def straw(cx,cy,z,spread=.35,count=30):
    for i in range(count):
        x=cx+RNG.uniform(-spread,spread);y=cy+RNG.uniform(-spread*.7,spread*.7)
        a=RNG.random()*math.tau;ll=RNG.uniform(.07,.21)
        tube('Curled packing straw',[(x+ll*(t-.5)*math.cos(a),y+ll*(t-.5)*math.sin(a),z+.012*math.sin(t*math.pi)) for t in (0,.25,.5,.75,1)],.004,'straw',sides=4)


def vase(name,x,y,z,r,h,mat='porcelain'):
    profile=[(.44*r,0),(.76*r,.10*h),(r,.36*h),(.91*r,.61*h),(.50*r,.78*h),(.42*r,.94*h),(.49*r,h),(.40*r,h),(.34*r,.93*h),(.33*r,.83*h)]
    lathe(name,profile,mat,(x,y,z),32)
    for zz,rr in ((.62*h,.90*r),(.77*h,.51*r),(.96*h,.46*r)):
        ring(name+' cobalt band',x,y,z+zz,rr,rr,.004,'cobalt')


def porcelain():
    plank_crate('Porcelain straw crate',1.02,.76,.33,2,'wood2')
    straw(0,0,.105,.43,58)
    vase('Tall pale porcelain vase',-.25,.08,.13,.145,.57)
    vase('Celadon storage vase',.10,.14,.13,.15,.43,'celadon')
    vase('Small pale jar',.30,-.15,.13,.105,.34)
    for j in range(3):
        z=.14+j*.055
        lathe('Nested porcelain bowl '+str(j),[(.055,0),(.075,.025),(.13,.09),(.145,.115),(.132,.118),(.118,.085),(.05,.028)],'porcelain',(-.12,-.20,z),32)
        ring('Bowl cobalt rim',-.12,-.20,z+.116,.14,.14,.003,'cobalt')
    for x,y in ((-.25,.08),(.10,.14),(.30,-.15)):
        ring('Straw cushioning collar',x,y,.18,.17,.17,.010,'straw')
    for x in (-.39,.34):
        box('Porcelain crate straw divider',(x,0,.23),(.025,.65,.21),'straw',.006)


def tea():
    w=.82;d=.61;h=.62
    box('Tea chest solid body',(0,0,h/2),(w,d,h),'tea_dark',.018)
    for j in range(5):
        x=-w/2+w*(j+.5)/5
        box('Tea chest lid board',(x,0,h+.017),(w/5-.007,d+.015,.035),'wood'+str(j%3),.006)
    for x in (-w/2,w/2):
        for y in (-d/2,d/2):box('Tea chest corner rib',(x,y,h/2),(.045,.045,h+.025),'wood3',.006)
    for z in (.08,h-.08):
        for y in (-d/2-.01,d/2+.01):box('Tea chest edge batten',(0,y,z),(w+.04,.03,.045),'wood2',.005)
    for axis in ('X','Y'):rope_rectangle('Tea chest crossed rope',axis,(0,0,h/2+.015),d+.065 if axis=='X' else w+.075,h+.09,.012)
    # Raised, wordless botanical mark: two tea leaves in a shallow inset panel.
    box('Tea chest inset seal board',(0,-d/2-.025,.32),(.24,.014,.24),'wood0',.007)
    for side in (-1,1):
        points=[(0,-d/2-.037,.25),(side*.09,-d/2-.037,.34),(side*.015,-d/2-.037,.42),(-side*.018,-d/2-.037,.33)]
        mesh('Embossed tea leaf',points,[(0,1,2,3)],'tea_leaf')
        tube('Tea leaf relief vein',[(0,-d/2-.042,.26),(side*.02,-d/2-.042,.37)],.003,'wood3',sides=4)


def sugar():
    plank_crate('Open sugar shipping box',.94,.68,.28,2,'wood1')
    straw(0,0,.12,.38,20)
    for i,(x,y,h,r) in enumerate(((-.25,.06,.53,.14),(.05,.13,.44,.145),(.27,-.07,.36,.13))):
        lathe('Raw sugar cone '+str(i),[(r,0),(.98*r,.10*h),(.73*r,.45*h),(.40*r,.78*h),(.08*r,h)],'sugar_pale' if i!=1 else 'sugar',(x,y,.13),24,.045)
        ring('Cane wrap at sugar cone foot',x,y,.18,r*.98,r*.98,.008,'straw')
    for i in range(8):
        x=RNG.uniform(-.32,.28);y=RNG.uniform(-.24,-.12)
        ob=box('Unrefined sugar lump '+str(i),(x,y,.18+RNG.random()*.025),(.065,.055,.055),'sugar',.009)
        ob.rotation_euler=(RNG.random()*.5,RNG.random()*.5,RNG.random())


def salt():
    # Open woven basket and a sealed upright bag: distinct from bulging grain sacks.
    for i in range(24):
        a=i*math.tau/24
        tube('Salt basket upright',[(.36*(.82+.18*t)*math.cos(a)-.12,.26*(.82+.18*t)*math.sin(a),.05+.26*t) for t in (0,.25,.5,.75,1)],.009,'hemp')
    for k in range(9):ring('Salt basket horizontal weave',-.12,0,.05+k*.03,.36*(.82+.18*k/8),.26*(.82+.18*k/8),.008,'hemp_light')
    ball('Coarse salt mound',(-.12,0,.26),(.33,.23,.085),'salt',24,12)
    for i in range(28):
        a=RNG.random()*math.tau;r=math.sqrt(RNG.random())
        x=-.12+.29*r*math.cos(a);y=.20*r*math.sin(a);z=.31+.035*(1-r)
        ob=box('Visible salt crystal '+str(i),(x,y,z),(.027,.022,.022),'salt_crystal',.003)
        ob.rotation_euler=(RNG.random(),RNG.random(),RNG.random())
    sack('Sealed salt bag',(.29,.14,.015),.17,.52,'cloth_cream')
    box('Salt bag indigo seal',(.29,.018,.38),(.09,.014,.14),'cloth_indigo',.009,(-.1,0,0))


def spices():
    plank_crate('Spice merchant tray',.98,.73,.16,1,'wood0')
    for i,(x,y,r,h,mat) in enumerate(((-.27,.08,.15,.40,'terracotta'),(.06,.16,.145,.34,'jar_olive'),(.29,-.07,.125,.29,'jar_dark'))):
        lathe('Spice ceramic jar '+str(i),[(r*.60,0),(r*.91,.10*h),(r,.43*h),(r*.82,.77*h),(r*.58,.89*h),(r*.60,h)],mat,(x,y,.12),28)
        lathe('Cloth lid on spice jar '+str(i),[(r*.66,.98*h),(r*.65,1.04*h),(r*.45,1.09*h),(.02,1.10*h)],'grain_cloth',(x,y,.12),24,.025)
        ring('Spice jar tied neck',x,y,.12+h*.98,r*.64,r*.64,.008,'hemp')
        tube('Spice jar hanging tie',[(x+r*.6,y,.12+h),(x+r*.7,y-.025,.12+h*.72),(x+r*.58,y-.035,.12+h*.65)],.006,'hemp')
    sack('Small ochre spice bundle',(-.18,-.22,.10),.125,.25,'cloth_russet')
    sack('Small saffron cloth bundle',(.06,-.23,.10),.11,.23,'grain_cloth')
    for i in range(8):ball('Loose pepper bead',(-.37+i*.025,-.25,.15),(.012,.012,.012),'pepper',8,5)


def evaluated_bounds(objects):
    import bpy
    from mathutils import Vector
    dep=bpy.context.evaluated_depsgraph_get();points=[]
    for ob in objects:
        e=ob.evaluated_get(dep)
        points += [e.matrix_world @ Vector(c) for c in e.bound_box]
    return [[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]


def merge_for_export(good):
    import bpy
    from mathutils import Matrix
    dep=bpy.context.evaluated_depsgraph_get();duplicates=[]
    for ob in PARTS[good]:
        data=bpy.data.meshes.new_from_object(ob.evaluated_get(dep),depsgraph=dep)
        clone=bpy.data.objects.new('Export '+ob.name,data)
        bpy.context.scene.collection.objects.link(clone)
        clone.matrix_world=ob.matrix_world.copy();duplicates.append(clone)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in duplicates:ob.select_set(True)
    bpy.context.view_layer.objects.active=duplicates[0]
    bpy.ops.object.join();merged=bpy.context.object;merged.name='Cargo_'+good
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    merged['good']=good;merged['units']='metres';merged['origin']='bottom centre'
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    return merged


def export_asset(good):
    import bpy
    bounds=evaluated_bounds(PARTS[good]);size=[bounds[1][i]-bounds[0][i] for i in range(3)]
    factor=min(1,1.35/max(size));shift=[-(bounds[0][i]+bounds[1][i])/2 for i in range(2)]+[-bounds[0][2]]
    root=bpy.data.objects['Source_'+good]
    root.location=tuple(s*factor for s in shift);root.scale=(factor,)*3
    bpy.context.view_layer.update()
    merged=merge_for_export(good)
    bpy.ops.object.select_all(action='DESELECT');merged.select_set(True);bpy.context.view_layer.objects.active=merged
    target=OUT/(good+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_extras=True,export_cameras=False,export_lights=False)
    merged.data.calc_loop_triangles()
    bounds=evaluated_bounds([merged]);dims=[bounds[1][i]-bounds[0][i] for i in range(3)]
    materials=sorted({m.name for m in merged.data.materials if m})
    data={'id':good,'file':target.name,'sha256':sha(target),'bytes':target.stat().st_size,'source_component_count':len(PARTS[good]),'export_mesh_objects':1,'vertices':len(merged.data.vertices),'triangles':len(merged.data.loop_triangles),'bounds_blender_z_up_metres':bounds,'dimensions_metres':dims,'materials':materials,'origin':'bottom centre','units':'metres','source_collection':'cargo_'+good,'construction_parts':[o.name for o in PARTS[good]]}
    assert max(dims)<=1.3501 and abs(bounds[0][2])<1e-5
    bpy.data.objects.remove(merged,do_unlink=True)
    return data


def camera_at(name,location,target,ortho):
    import bpy
    from mathutils import Vector
    data=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,data);bpy.context.scene.collection.objects.link(ob)
    ob.location=location;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO';data.ortho_scale=ortho;bpy.context.scene.camera=ob
    return ob


def studio():
    import bpy
    from mathutils import Vector
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=28;scene.cycles.use_denoising=True
    scene.cycles.device='CPU';scene.render.image_settings.file_format='PNG'
    scene.render.resolution_percentage=100
    if scene.world is None:scene.world=bpy.data.worlds.new('Cargo review world')
    scene.world.color=(.32,.32,.32)
    scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.58,.61,.62,1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
    scene.view_settings.view_transform='AgX'
    material('review_ground',(.22,.235,.23),.94)
    material('review_text',(.65,.64,.55),.9)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.018))
    ground=bpy.context.object;ground.name='Review ground';ground.data.materials.append(MATS['review_ground'])
    for name,loc,power,size in (('Key',(-3,-4,8),1700,6),('Fill',(5,-1,6),1100,5),('Rim',(1,6,7),1500,5)):
        data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
        ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector((0,0,0))-ob.location).to_track_quat('-Z','Y').to_euler()


def render_reviews():
    import bpy
    from mathutils import Vector
    studio();scene=bpy.context.scene
    roots={g:bpy.data.objects['Source_'+g] for g in GOODS}
    canonical={g:roots[g].location.copy() for g in GOODS}
    for i,g in enumerate(GOODS):
        x=(i%4-1.5)*1.85;y=(i//4-1)*1.65
        roots[g].location += Vector((x,y,0))
        data=bpy.data.curves.new('Review label '+g,'FONT');data.body=g.upper();data.size=.16;data.align_x='CENTER';data.extrude=.0005
        ob=bpy.data.objects.new('Review label '+g,data);scene.collection.objects.link(ob);ob.location=(x,y-.68,.008);data.materials.append(MATS['review_text'])
    camera_at('Contact camera',(7.8,-11.5,15.8),(0,0,.14),9.45)
    scene.render.resolution_x=2800;scene.render.resolution_y=2100;scene.render.filepath=str(OUT/'review-contact.png')
    bpy.ops.render.render(write_still=True)
    # Save the useful studio arrangement, but roots still identify each local package.
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'cargo-pack-r1.blend'),compress=True)
    for good in ('porcelain','grain'):
        for g,root in roots.items():
            root.location=canonical[g]
            for ob in PARTS[g]:ob.hide_render=(g!=good)
        for ob in scene.objects:
            if ob.name.startswith('Review label '):ob.hide_render=True
        camera_at(good+' close camera',(1.65,-2.25,1.75),(0,0,.29),1.65)
        scene.render.resolution_x=1800;scene.render.resolution_y=1600;scene.render.filepath=str(OUT/('review-'+good+'.png'))
        bpy.ops.render.render(write_still=True)


def build():
    import bpy
    global CURRENT
    if (OUT/'cargo-pack-r1.blend').exists() or any((OUT/(g+'.glb')).exists() for g in GOODS):raise FileExistsError('Preserve existing cargo outputs; use a fresh revision')
    OUT.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
    palette();assets=[]
    for good in GOODS:
        collection=bpy.data.collections.new('cargo_'+good);bpy.context.scene.collection.children.link(collection)
        root=bpy.data.objects.new('Source_'+good,None);collection.objects.link(root);root['good']=good;root['units']='metres';root['canonical_origin']='bottom centre before review layout translation'
        CURRENT=root;PARTS[good]=[]
        globals()[good]()
        assets.append(export_asset(good))
        print('CARGO_EXPORTED',good,assets[-1]['triangles'],flush=True)
    manifest={'schema_version':1,'asset_pack':'cargo-pack-r1','created_utc':datetime.now(timezone.utc).isoformat(),'blender_version':bpy.app.version_string,'goods':list(GOODS),'source':'cargo-pack-r1.blend','generator':Path(__file__).relative_to(ROOT).as_posix(),'generator_sha256':sha(__file__),'provenance':'Original agent-authored Blender procedural geometry. No external texture or model references. Artist-considered creative reconstruction; not human-authored or archaeologically authenticated.','textures':[],'glb_coordinate_system':'glTF Y up, metres; origin bottom centre','source_coordinate_system':'Blender Z up, metres; source roots translated into review grid in master blend','assets':assets,'validation_scope':'Static mesh/material/export and Blender renderer. Godot animation, visibility, collisions, real cargo ledger and buoyancy require integration validation.'}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    render_reviews()
    manifest['source_sha256']=sha(OUT/'cargo-pack-r1.blend')
    manifest['review_renders']=[{'file':p.name,'sha256':sha(p),'renderer':'Blender Cycles CPU','samples':28} for p in (OUT/'review-contact.png',OUT/'review-porcelain.png',OUT/'review-grain.png')]
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print('CARGO_BUILD_COMPLETE',len(assets),flush=True)


def glb_json(path):
    data=path.read_bytes();magic,version,length=struct.unpack_from('<III',data,0)
    assert magic==0x46546C67 and version==2 and length==len(data)
    count,kind=struct.unpack_from('<II',data,12);assert kind==0x4E4F534A
    return json.loads(data[20:20+count])


def verify():
    import bpy
    manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf8'))
    source=OUT/'cargo-pack-r1.blend';before=sha(source)
    assert Path(bpy.data.filepath).resolve()==source.resolve()
    source_goods=sorted(o['good'] for o in bpy.context.scene.objects if o.name.startswith('Source_'))
    assert source_goods==sorted(GOODS)
    reopened_parts={g:sum(1 for o in bpy.context.scene.objects if o.type=='MESH' and o.get('cargo_good')==g) for g in GOODS}
    records=[]
    for item in manifest['assets']:
        g=item['id'];path=OUT/item['file'];data=glb_json(path)
        assert sha(path)==item['sha256'] and reopened_parts[g]==item['source_component_count']
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(path))
        meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];bounds=evaluated_bounds(meshes)
        triangles=0
        for ob in meshes:ob.data.calc_loop_triangles();triangles+=len(ob.data.loop_triangles)
        assert len(meshes)==1 and abs(bounds[0][2])<1e-5
        dims=[bounds[1][i]-bounds[0][i] for i in range(3)]
        assert max(dims)<=1.3501 and triangles==item['triangles']
        records.append({'id':g,'imported_meshes':len(meshes),'glb_nodes':len(data.get('nodes',[])),'glb_materials':len(data.get('materials',[])),'glb_primitives':sum(len(m['primitives']) for m in data.get('meshes',[])),'triangles':triangles,'bounds_after_import_blender':bounds,'source_parts':reopened_parts[g],'sha256':sha(path),'pass':True})
    assert before==sha(source)==manifest['source_sha256']
    result={'pass':True,'verified_utc':datetime.now(timezone.utc).isoformat(),'source_reopened':True,'source_sha256':before,'source_unchanged':True,'exact_good_ids':list(GOODS),'assets':records,'scope':'Master blend reopened and all 12 GLBs independently imported by Blender; dimensions, origin, mesh count, materials, triangles and hashes checked. No Godot acceptance claimed.'}
    (OUT/'verification.json').write_text(json.dumps(result,indent=2),encoding='utf8')
    print('CARGO_VERIFY_COMPLETE',len(records),flush=True)


def launch():
    OUT.mkdir(parents=True,exist_ok=True)
    for mode in ('build','verify'):
        cmd=['rtk','proxy',str(BLENDER),'--background']
        if mode=='verify':cmd += [str(OUT/'cargo-pack-r1.blend')]
        cmd += ['--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--'+mode]
        log=OUT/(mode+'.log')
        with log.open('xb') as stream:
            result=subprocess.run(cmd,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
        print(mode,'exit',result.returncode,'log',log,flush=True)
        if result.returncode:print(log.read_text(encoding='utf8',errors='replace')[-4000:]);return result.returncode
    return 0


if __name__=='__main__':
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    parser=argparse.ArgumentParser();parser.add_argument('--launch',action='store_true');parser.add_argument('--build',action='store_true');parser.add_argument('--verify',action='store_true');options=parser.parse_args(args)
    if options.launch:raise SystemExit(launch())
    if options.build:build()
    elif options.verify:verify()
    else:parser.error('Choose --launch, --build, or --verify')
