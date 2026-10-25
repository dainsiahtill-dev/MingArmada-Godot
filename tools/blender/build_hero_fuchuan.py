"""Original game-art flagship. Run with Blender --background --python this_file.
All geometry is authored here. --vintage uses the recorded image_gen textures.
Input coordinates are Godot meters (Y-up, +Z bow), converted into Blender Z-up.
"""
import bpy, math, random, json, hashlib, sys, struct
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
VINTAGE = '--vintage' in sys.argv
ASSET = 'hero-fuchuan-v2' if VINTAGE else 'hero-fuchuan-v1'
OUT = ROOT / ('assets/models/hero_fuchuan_v2' if VINTAGE else 'assets/models/hero_fuchuan')
SOURCE = ROOT / 'assets/production/hero-fuchuan-blender'
EVIDENCE = ROOT / 'docs/production/hero-fuchuan-2026-10-25'
if VINTAGE: EVIDENCE = EVIDENCE / 'texture-v2'
BLEND_NAME = 'hero-fuchuan-v2.blend' if VINTAGE else 'hero-fuchuan.blend'
GENERATED = {'teak':'weathered-hull-wood','deck':'sunworn-deck-wood','canvas':'antique-hemp-sail','iron':'aged-forged-iron','iron_edge':'aged-forged-iron'}
for directory in (OUT, SOURCE, EVIDENCE): directory.mkdir(parents=True, exist_ok=True)
RNG = random.Random(1650)
LOD = 0
MATS = {}
OBJECTS = []

def point(p): return Vector((p[0], -p[2], p[1]))

def texture(name, base, cloth=False):
    if VINTAGE and name in GENERATED:
        img=bpy.data.images.load(str(ROOT/'assets/textures/hero_fuchuan_v2'/(GENERATED[name]+'.png')),check_existing=True)
        img.colorspace_settings.name='sRGB'; img.pack()
        return img
    size=256
    img=bpy.data.images.new(name,width=size,height=size)
    pixels=[]
    for y in range(size):
        for x in range(size):
            if cloth:
                shade=.94+.035*math.sin(x*math.pi)+.025*math.cos(y*2.7)+.018*math.sin(x*9+y*3)
            else:
                phase=x*.42+2*math.sin(y*.035)+.5*math.sin(y*.17+x*.03)
                shade=.88+.09*math.sin(phase)+.04*math.sin(phase*3.1)+.025*math.sin(x*8.3+y*1.9)
            pixels.extend([min(1,c*shade) for c in base]+[1])
    img.pixels=pixels
    img.filepath_raw=str(OUT/(name+'.png')); img.file_format='PNG'; img.save(); img.pack()
    return img

def material(name, color, textured=False, cloth=False, metal=0):
    mat=bpy.data.materials.new(name); mat.use_nodes=True
    bs=mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Roughness'].default_value=(.9 if cloth else .82 if not metal else .76) if VINTAGE else (.83 if not metal else .48)
    bs.inputs['Metallic'].default_value=metal
    if textured or (VINTAGE and name in GENERATED):
        tex=mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=texture(name,color,cloth)
        if VINTAGE and cloth:
            # KHR_texture_transform: albedo repeats, normalized damage UV remains.
            coords=mat.node_tree.nodes.new('ShaderNodeTexCoord')
            mapping=mat.node_tree.nodes.new('ShaderNodeMapping'); mapping.vector_type='POINT'
            mapping.inputs['Scale'].default_value=(12,18,1)
            mat.node_tree.links.new(coords.outputs['UV'],mapping.inputs['Vector'])
            mat.node_tree.links.new(mapping.outputs['Vector'],tex.inputs['Vector'])
        mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    mat.diffuse_color=(*color,1)
    mat.use_backface_culling=not cloth
    MATS[name]=mat
    return mat

def empty(name, pos=(0,0,0), parent=None):
    ob=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(ob)
    ob.location=point(pos)
    if parent: ob.parent=parent
    OBJECTS.append(ob); return ob

def mesh(name, vertices, faces, mat='teak', parent=None):
    data=bpy.data.meshes.new(name+'_mesh'); data.from_pydata([point(p) for p in vertices],[],faces); data.update()
    ob=bpy.data.objects.new(name,data); bpy.context.collection.objects.link(ob)
    if parent: ob.parent=parent
    data.materials.append(MATS[mat]); OBJECTS.append(ob)
    uv=data.uv_layers.new(name='UVMap')
    spans=[max(v.co[a] for v in data.vertices)-min(v.co[a] for v in data.vertices) for a in range(3)]
    for polygon in data.polygons:
        normal=polygon.normal
        axis=max(range(3),key=lambda a:abs(normal[a]))
        axes=[a for a in range(3) if a!=axis]
        if VINTAGE and mat in ['teak','deck','tarred','bamboo']:
            axes.sort(key=lambda a:spans[a],reverse=True)
        for loop in polygon.loop_indices:
            p=data.vertices[data.loops[loop].vertex_index].co
            uv.data[loop].uv=(p[axes[0]]*.35,p[axes[1]]*.35)
    return ob

def box(name, center, size, mat='teak', parent=None, bevel=.035):
    x,y,z=center; a,b,c=[v/2 for v in size]
    vertices=[(x+sx*a,y+sy*b,z+sz*c) for sx,sy,sz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
    ob=mesh(name,vertices,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)],mat,parent)
    if bevel and LOD<2:
        mod=ob.modifiers.new('Soft hand-worked edges','BEVEL'); mod.width=bevel; mod.segments=2 if LOD==0 else 1
    return ob

def tube(name, a, b, radius, mat='teak', parent=None, sides=None, radius_b=None):
    sides=sides or [12,8,6][LOD]; a=Vector(a); b=Vector(b); direction=(b-a).normalized()
    helper=Vector((0,1,0)) if abs(direction.y)<.9 else Vector((1,0,0))
    u=direction.cross(helper).normalized(); v=direction.cross(u).normalized()
    vertices=[]
    for p,r in [(a,radius),(b,radius if radius_b is None else radius_b)]:
        for i in range(sides): vertices.append(p+(u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides))*r)
    faces=[tuple(reversed(range(sides))),tuple(range(sides,2*sides))]
    faces += [(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
    ob=mesh(name,vertices,faces,mat,parent)
    for poly in ob.data.polygons:
        if len(poly.vertices)==4: poly.use_smooth=True
    return ob

def curve(name, points, radius=.035, mat='hemp', parent=None):
    data=bpy.data.curves.new(name,'CURVE'); data.dimensions='3D'; data.resolution_u=1
    data.bevel_depth=radius; data.bevel_resolution=1 if LOD==0 else 0
    spline=data.splines.new('POLY'); spline.points.add(len(points)-1)
    for p,co in zip(spline.points,points): p.co=(*point(co),1)
    ob=bpy.data.objects.new(name,data); bpy.context.collection.objects.link(ob); ob.data.materials.append(MATS[mat])
    if parent: ob.parent=parent
    OBJECTS.append(ob); return ob

def join(objects,name,parent=None):
    objects=[o for o in objects if o.type in {'MESH','CURVE'}]
    if not objects: return None
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects: ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.convert(target='MESH'); bpy.ops.object.join()
    ob=bpy.context.object; ob.name=name
    # Component geometry is already in its parent's local coordinates. All
    # source parts in a component share that parent and identity object pose.
    if parent: ob.parent=parent
    return ob

def half_width(z):
    stations=[(-16,.95),(-14,2.8),(-11,3.75),(-7,4.25),(0,4.5),(7,3.9),(11,2.7),(14,1.25),(16,.12)]
    for i in range(len(stations)-1):
        a,wa=stations[i]; b,wb=stations[i+1]
        if a<=z<=b: return wa+(wb-wa)*(z-a)/(b-a)
    return .1

def deck_height(z): return 1.9+.65*(max(0,z)/16)**3+.6*(max(0,-z)/16)**3

def hull(root):
    parts=[]; count=[40,28,18][LOD]; bands=[9,7,5][LOD]
    for side in [-1,1]:
        for row in range(bands):
            t0=row/bands; t1=(row+1)/bands
            vs=[]; fs=[]
            for j in range(count+1):
                z=-16+32*j/count; w=half_width(z); keel=-2+1.65*(abs(z)/16)**5
                for t in [t0,t1]:
                    y=keel+(deck_height(z)-keel)*t
                    x=side*(.16+(w-.16)*math.sin(t*math.pi/2)**.82)
                    vs.append((x,y,z))
            for j in range(count):
                f=(j*2,j*2+1,j*2+3,j*2+2)
                fs.append(f if side>0 else tuple(reversed(f)))
            parts.append(mesh('Hull strake %d %d'%(side,row),vs,fs,'tarred' if row<bands*.42 else 'teak',root))
            # Thin caulking lines and raised wales make the hull read at sea.
            if LOD<2 or row%2==0:
                path=[]
                for j in range(count+1):
                    z=-16+32*j/count; keel=-2+1.65*(abs(z)/16)**5
                    path.append((side*(.17+(half_width(z)-.16)*math.sin(t1*math.pi/2)**.82),keel+(deck_height(z)-keel)*t1,z))
                parts.append(curve('Caulking',path,.016,'pitch',root))
        for h,rad,mat in [(.12,.1,'vermilion'),(1.15,.1,'ochre')]:
            path=[(side*(half_width(-15+30*j/count)+.035),h+max(0,abs(-15+30*j/count)-10)*.1,-15+30*j/count) for j in range(count+1)]
            parts.append(curve('Hull wale',path,rad,mat,root))
    # Solid transoms and keel, separately readable from the planking.
    parts.append(box('Stern transom',(0,.5,-15.8),(1.9,3.5,.25),'teak',root))
    parts.append(tube('Keel',(0,-1.95,-13.5),(0,-1.95,12.0),.15,'pitch',root,8))
    result=join(parts,'hull',root); result['damage_surface']='hull'; result['target_rigid_shadow_caster']=True
    deckparts=[]
    # Long planks following the ship envelope, with actual narrow caulk gaps.
    strips=[30,22,14][LOD]
    for i in range(strips):
        x=-4.4+(i+.5)*8.8/strips; width=8.8/strips-.025
        vertices=[]; faces=[]
        for j in range(count):
            za=-15.5+31*j/count; zb=-15.5+31*(j+1)/count
            if abs(x)+width/2>min(half_width(za),half_width(zb))-.08: continue
            k=len(vertices); vertices += [(x-width/2,deck_height(za),za),(x+width/2,deck_height(za),za),(x+width/2,deck_height(zb),zb),(x-width/2,deck_height(zb),zb)]
            faces.append((k,k+3,k+2,k+1))
        if faces: deckparts.append(mesh('Deck plank',vertices,faces,'deck',root))
    # A thin continuous underdeck closes plank gaps for foot support.
    vs=[]; fs=[]
    for j in range(count+1):
        z=-15.5+31*j/count; w=half_width(z)-.08
        vs += [(-w,deck_height(z)-.035,z),(w,deck_height(z)-.035,z)]
        if j: k=j*2; fs.append((k-2,k,k+1,k-1))
    deckparts.append(mesh('Deck underlay',vs,fs,'pitch',root))
    # Raised stern command deck; open forward edge provides a readable helm.
    deckparts.append(box('Stern upper deck',(0,4.28,-10.5),(5.7,.22,7.6),'deck',root))
    deck=join(deckparts,'deck',root); deck['deck_support']=True; deck['target_rigid_shadow_caster']=True
    return result

def fittings(root):
    static=[]; rail=[]
    for side in [-1,1]:
        n=[24,18,12][LOD]
        for i in range(n+1):
            z=-14.8+29.6*i/n; y=deck_height(z); x=side*(half_width(z)-.08)
            rail.append(tube('Rail post',(x,y,z),(x,y+.92,z),.065,'teak',root,6))
        for h in [.35,.92]:
            rail.append(curve('Gunwale rail',[(side*(half_width(z)-.08),deck_height(z)+h,z) for z in [-14.8+29.6*i/n for i in range(n+1)]],.07,'ochre' if h>.5 else 'teak',root))
    # Cabin occupies the underside of the upper deck; actors stand above it.
    cabin=box('sterncastle',(0,3.05,-11.8),(5.4,2.05,4.6),'teak',root,.08); cabin['deck_obstacle']=True
    for side in [-1,1]:
        for z in [-13.0,-11.6,-10.2]:
            static.append(box('Cabin dark window',(side*2.72,3.3,z),(.05,.7,.76),'pitch',root))
            for k in [-.24,0,.24]: static.append(box('Window lattice',(side*2.77,3.3,z+k),(.06,.73,.04),'ochre',root,.008))
        static.append(tube('Upper rail',(side*2.83,5.1,-14.2),(side*2.83,5.1,-6.8),.07,'ochre',root))
        for z in [-14,-12.5,-11,-9.5,-8,-6.9]: static.append(tube('Upper rail post',(side*2.83,4.4,z),(side*2.83,5.1,z),.055,'teak',root,6))
    static.append(tube('Stern rail',(-2.85,5.1,-14.2),(2.85,5.1,-14.2),.07,'ochre',root))
    # Twin ladders leave the helm/tiller centre line clear.
    for side in [-1,1]:
        x=side*2.15
        for k in range(8): static.append(box('Stern stair',(x,2.0+k*.31,-5.0-k*.24),(.9,.12,.33),'deck',root))
        for dx in [-.48,.48]: static.append(tube('Stair stringer',(x+dx,1.94,-4.9),(x+dx,4.4,-6.85),.065,'teak',root,6))
    for z in [-3.2,5.8]:
        hatch=box('cargo_hold_%s'%z,(0,2.09,z),(1.65,.3,2.0),'teak',root); hatch['deck_obstacle']=True
        for i in range(7): static.append(box('Hatch grating',((i-3)*.22,2.27,z),(.11,.055,1.85),'ochre',root,.01))
    static.append(tube('Capstan drum',(0,2.1,12.3),(0,2.7,12.3),.38,'teak',root))
    static.append(tube('Capstan bar',(-1.3,2.66,12.3),(1.3,2.66,12.3),.065,'ochre',root))
    for side in [-1,1]:
        x=side*2.0
        static.append(tube('Anchor shank',(x,.9,12.7),(x,2.5,12.7),.07,'iron',root))
        static.append(tube('Anchor stock',(x-.65,2.2,12.7),(x+.65,2.2,12.7),.09,'teak',root))
        for dx in [-.55,.55]: static.append(tube('Anchor fluke',(x,.9,12.7),(x+dx,1.25,12.7),.08,'iron',root))
        pts=[(side*1.8+(.22+.014*i)*math.cos(i*.33),2.0+.004*i,9.2+(.22+.014*i)*math.sin(i*.33)) for i in range(85 if LOD==0 else 45)]
        static.append(curve('Coiled working line',pts,.025,'hemp',root))
    join(rail,'bulwark_rails',root); join(static,'deck_fittings',root)
    rudder=empty('rudder_pivot',(0,1.9,-15.6),root)
    blade=mesh('rudder_blade',[(-.13,-3.25,-.15),(.13,-3.25,-.15),(.13,-3.25,-2.0),(-.13,-3.25,-2.0),(-.13,.8,.1),(.13,.8,.1),(.13,.8,-1.7),(-.13,.8,-1.7)],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)],'teak',rudder)
    tube('rudder_stock',(0,-2.6,0),(0,3.65,0),.16,'teak',rudder)
    tube('tiller_beam',(0,3.65,0),(0,3.65,8.25),.14,'teak',rudder,radius_b=.08)
    tube('tiller_grip',(-.5,3.65,8.25),(.5,3.65,8.25),.055,'ochre',rudder)
    for y in [-1.8,-.2,.65]: box('Rudder iron strap',(0,y,-.9),(.29,.12,1.9),'iron',rudder,.01)

def sail(parent,index,height,width,base):
    pieces=[]; rows=[14,12,10][LOD]; cols=[10,8,6][LOD]
    vertices=[]; faces=[]
    for row in range(rows+1):
        v=row/rows; breadth=width*(1-.19*v)
        for col in range(cols+1):
            u=col/cols
            z=-breadth*.72+breadth*u
            y=base+height*v+.12*height*u*v
            x=.10*math.sin(math.pi*u)*math.sin(math.pi*v)
            vertices.append((x,y,z))
    for row in range(rows):
        for col in range(cols):
            a=row*(cols+1)+col; faces.append((a,a+1,a+cols+2,a+cols+1))
    cloth=mesh('Cloth panels',vertices,faces,'canvas',parent)
    # Cloth tears use a clamped 0..1 damage map, independently of meters.
    # The procedural weave is itself repeatable inside this normalized panel.
    for polygon in cloth.data.polygons:
        for loop_index in polygon.loop_indices:
            vertex=cloth.data.loops[loop_index].vertex_index
            cloth.data.uv_layers.active.data[loop_index].uv=(vertex%(cols+1)/cols,vertex//(cols+1)/rows)
    for polygon in cloth.data.polygons: polygon.use_smooth=True
    pieces.append(cloth)
    for row in range(9):
        v=row/8; breadth=width*(1-.19*v)
        pieces.append(tube('Bamboo batten',(.04,base+height*v,-breadth*.72),(.04,base+height*v+height*.12*v,breadth*.28),.047 if row not in [0,8] else .075,'bamboo',parent,sides=6))
    for u in [0,.25,.5,.75,1]:
        pts=[]
        for row in range(9):
            v=row/8; breadth=width*(1-.19*v)
            pts.append((.012,base+height*v+height*.12*u*v,-breadth*.72+breadth*u))
        pieces.append(curve('Sail panel seam',pts,.012,'canvas_seam',parent))
    # Sheets follow the battens during reefing; fixed endpoints in a separate
    # mesh would leave lines hanging in the air above a reefed sail.
    for row in [1,3,5,7]:
        v=row/8; breadth=width*(1-.19*v)
        pieces.append(curve('Batten sheet',[(.12,base+height*v,-breadth*.72),(.18,base-.2,-width*.35)],.022,'hemp',parent))
    ob=join(pieces,'sail_%d'%index,parent)
    ob.shape_key_add(name='Basis'); furl=ob.shape_key_add(name='furl'); inflate=ob.shape_key_add(name='inflate')
    # Blender 5.4's API creates active keys at value 1; authored rest must
    # explicitly be full sail, otherwise the exported default is reefed.
    furl.value=0.0; inflate.value=0.0
    for i,vert in enumerate(ob.data.vertices):
        x,negative_z,y=vert.co; z=-negative_z
        v=max(0,min(1,(y-base)/(height*1.12))); u=max(0,min(1,(z+width*.72)/width))
        furl.data[i].co.z=base+(y-base)*.035
        inflate.data[i].co.x=x+width*.055*math.sin(math.pi*v)*math.sin(math.pi*u)
    ob['damage_surface']='sail'
    return ob

def rig(root):
    for index,z,top,width,base in [(0,9.0,15.9,8.0,3.4),(1,.6,23.1,11.7,3.5),(2,-9.0,15.0,6.4,5.5)]:
        mast=empty('mast_%d'%index,(0,0,z),root); mast['sail_trim_origin']=0.0
        timber=tube('mast_timber_%d'%index,(0,deck_height(z),0),(0,top,0),.23 if index==1 else .17,'teak',mast,radius_b=.10)
        timber['deck_obstacle']=True; timber['target_rigid_shadow_caster']=True
        sail(mast,index,top-base-1.1,width,base)
        tube('Mast cap',(0,top-.15,0),(0,top+.23,0),.14,'ochre',mast)
        # Stays authored as separately named geometry for damage attachments.
        stays=[]
        for side in [-1,1]:
            for dz in [-1.2,1.2]:
                stays.append(curve('Standing shroud',[(side*(half_width(z+dz)-.25),deck_height(z+dz)+.1,z+dz),(side*.12,top*.78,z)],.028,'hemp',root))
        standing=join(stays,'rigging_%d'%index,root); standing['mast_index']=index
        if index==1:
            flag=mesh('flag_ming',[(0,top-.1,0),(0,top-.1,-3.1),(.1,top-1.05,-2.7),(0,top-1.05,0)],[(0,1,2,3)],'vermilion',mast)
            flag['source_fixed_attachment']=False

def cannon_geometry(parent):
    parts=[]; sides=[18,12,8][LOD]
    # External art only: closed dark muzzle disk, no functional internals.
    profile=[(-.9,.13),(-.76,.22),(-.5,.22),(.2,.18),(.68,.15),(.9,.20),(1.08,.20)]
    vs=[]; fs=[]
    for z,r in profile:
        for i in range(sides): vs.append((r*math.cos(math.tau*i/sides),r*math.sin(math.tau*i/sides),z))
    for j in range(len(profile)-1):
        for i in range(sides):
            a=j*sides+i; b=j*sides+(i+1)%sides; fs.append((a,b,b+sides,a+sides))
    fs.append(tuple(reversed(range(sides))))
    parts.append(mesh('Cast barrel',vs,fs,'iron',parent))
    for z,r in [(-.72,.24),(-.4,.235),(.35,.19),(.84,.22)]: parts.append(tube('Barrel band',(0,0,z-.025),(0,0,z+.025),r,'iron_edge',parent,sides))
    parts.append(tube('Muzzle dark recess',(0,0,1.015),(0,0,1.022),.15,'pitch',parent,sides))
    parts.append(tube('Trunnions',(-.36,0,-.25),(.36,0,-.25),.075,'iron',parent,sides))
    return parts

def guns(root):
    for side,sgn in [('port',1),('starboard',-1)]:
        for index in range(4):
            z=32*(-.138+index*.092); curve_factor=(1-(z/16)**2)**.64
            muzzle=9*.435*curve_factor+.87
            group=empty('cannon_%s_%02d'%(side,index),(sgn*(muzzle-1.08),2.2,z),root)
            group.rotation_euler.z=sgn*math.pi/2
            barrel=empty('barrel_%s_%02d'%(side,index),(0,0,0),group)
            join(cannon_geometry(barrel),'gun_tube_%s_%d'%(side,index),barrel)
            carriage=[]
            carriage.append(box('Carriage bed',(0,-.3,-.25),(.8,.14,1.3),'teak',group))
            for x in [-.37,.37]:
                carriage.append(box('Carriage cheek',(x,-.16,-.28),(.11,.32,1.1),'teak',group))
                for z0 in [-.65,.2]: carriage.append(tube('Wooden truck',(x-.09,-.42,z0),(x+.09,-.42,z0),.18,'pitch',group,10))
            join(carriage,'gun_carriage_%s_%d'%(side,index),group)
            empty('socket_smoke_%s_%02d'%(side,index),(0,0,1.08),group)

def setup_materials():
    material('teak',(.43,.25,.12),True)
    material('deck',(.65,.46,.25),True)
    material('tarred',(.14,.13,.11),True)
    material('canvas',(.79,.64,.40),True,True)
    material('canvas_seam',(.48,.36,.22))
    material('ochre',(.65,.43,.17)); material('vermilion',(.39,.075,.035))
    material('pitch',(.065,.052,.037)); material('bamboo',(.38,.26,.12))
    material('hemp',(.47,.37,.23)); material('iron',(.095,.11,.12),metal=.65)
    material('iron_edge',(.17,.19,.19),metal=.6)

def build(lod):
    global LOD,OBJECTS
    LOD=lod; OBJECTS=[]
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    root=empty('HeroFuchuan'); root['authored_asset']=ASSET; root['meters_per_unit']=1.0
    hull(root); fittings(root); rig(root); guns(root)
    empty('water_bow',(0,0,15.4),root); empty('water_wake',(0,0,-15.6),root)
    empty('helm_grip',(0,5.55,-7.35),root)
    empty('crew_helm',(0,4.4,-8.05),root)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in bpy.context.scene.objects:
        if ob.type in {'MESH','CURVE','EMPTY'}: ob.select_set(True)
    path=OUT/('fuchuan-lod%d.glb'%lod)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_extras=True,export_yup=True,export_animations=False,export_morph=True)
    return root,path

def preview(root):
    # Render actual authored scene; source assets remain independent of stage.
    scene=bpy.context.scene
    scene.render.engine='CYCLES'; scene.cycles.samples=32
    scene.render.resolution_x=1600; scene.render.resolution_y=1200; scene.render.resolution_percentage=100
    if scene.world is None: scene.world=bpy.data.worlds.new('Studio world')
    scene.world.use_nodes=True
    scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.28,.34,.42,1)
    scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.5
    floor=box('Studio ground',(0,-2.4,0),(200,.1,200),'pitch',None,0)
    def area(name,pos,power,size):
        data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size
        ob=bpy.data.objects.new(name,data); scene.collection.objects.link(ob); ob.location=point(pos)
        ob.rotation_euler=(point((0,8,0))-ob.location).to_track_quat('-Z','Y').to_euler()
    area('Warm key',(15,32,15),6500,18); area('Sky fill',(-16,24,4),4500,20); area('Rim',(6,26,-23),7000,15)
    data=bpy.data.cameras.new('Review camera'); camera=bpy.data.objects.new('Review camera',data); scene.collection.objects.link(camera)
    camera.location=point((34,22,39)); camera.rotation_euler=(point((0,8,0))-camera.location).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO'; data.ortho_scale=48; scene.camera=camera
    scene.view_settings.view_transform='AgX'
    scene.render.filepath=str(EVIDENCE/'blender-hero.png'); bpy.ops.render.render(write_still=True)

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True); setup_materials(); entries=[]
    for lod in [2,1,0]:
        root,path=build(lod)
        binary=path.read_bytes(); size=struct.unpack_from('<I',binary,12)[0]; gltf=json.loads(binary[20:20+size])
        triangles=sum(gltf['accessors'][primitive['indices']]['count']//3 for item in gltf['meshes'] for primitive in item['primitives'])
        entries.append({'lod':lod,'path':path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(binary).hexdigest(),'bytes':path.stat().st_size,'objects':len(bpy.context.scene.objects),'triangles':triangles,'triangleCountSource':'exported GLB index accessors, after modifiers'})
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/BLEND_NAME))
    manifest={'asset':ASSET,'tool':bpy.app.version_string,'seed':1650,'basis':'Godot Y-up, +Z bow, meters; Blender source Z-up -Y bow','nominalPhysics':{'length':32,'beam':9,'draft':2,'gunsPerSide':4},'provenance':'Original bpy-authored geometry; four built-in image_gen base-color images and retained procedural tar finish' if VINTAGE else 'Original bpy-authored geometry and procedural texture pixels; no extracted model input','historicalStatus':'Period-informed game interpretation; not certified historical reconstruction','lods':sorted(entries,key=lambda x:x['lod']),'source':str((SOURCE/BLEND_NAME).relative_to(ROOT)).replace('\\','/')}
    if VINTAGE:manifest['textureProvenance']='assets/textures/hero_fuchuan_v2/provenance.json'
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    preview(root)
    print('HERO_FUCHUAN_BUILD_OK '+json.dumps(entries))

if __name__=='__main__': main()
