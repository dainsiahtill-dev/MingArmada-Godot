"""Art-directed flagship rebuild; retains the existing rig/physics contract.
Run Blender --background --python this_file. Original v1/v2 assets stay intact.
"""
import bpy, bmesh, math, importlib.util, sys
from datetime import datetime, timezone
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
if '--vintage' not in sys.argv:sys.argv.append('--vintage')
spec=importlib.util.spec_from_file_location('hero_base',ROOT/'tools/blender/build_hero_fuchuan.py')
B=importlib.util.module_from_spec(spec);spec.loader.exec_module(B)
B.OUT=ROOT/'assets/models/hero_fuchuan_v3'
REVIEW_RUN=next((a.split('=',1)[1] for a in sys.argv if a.startswith('--review-run=')),datetime.now(timezone.utc).strftime('v3-%Y%m%dT%H%M%SZ'))
PANEL_AMPLITUDE=float(next((a.split('=',1)[1] for a in sys.argv if a.startswith('--panel-amplitude=')),'.025'))
assert Path(REVIEW_RUN).name==REVIEW_RUN
B.EVIDENCE=ROOT/'docs/production/hero-fuchuan-2026-10-26-art'/REVIEW_RUN
if B.EVIDENCE.exists():raise RuntimeError('Choose a fresh --review-run; preserve earlier art evidence')
B.BLEND_NAME='hero-fuchuan-v3.blend';B.ASSET='hero-fuchuan-v3'
for path in [B.OUT,B.EVIDENCE]:path.mkdir(parents=True,exist_ok=True)

def smooth_table(z):
    knots=[(-16,2.25),(-14,3.0),(-10,3.88),(-5,4.38),(0,4.5),(5,4.3),(9,3.72),(12,2.85),(14,1.85),(16,.24)]
    if z<=-16:return knots[0][1]
    if z>=16:return knots[-1][1]
    for i in range(len(knots)-1):
        a,b=knots[i],knots[i+1]
        if a[0]<=z<=b[0]:
            t=(z-a[0])/(b[0]-a[0]);h=b[0]-a[0]
            before=knots[max(0,i-1)];after=knots[min(len(knots)-1,i+2)]
            ma=(b[1]-before[1])/(b[0]-before[0]);mb=(after[1]-a[1])/(after[0]-a[0])
            return max(.12,(2*t**3-3*t*t+1)*a[1]+(t**3-2*t*t+t)*h*ma+(-2*t**3+3*t*t)*b[1]+(t**3-t*t)*h*mb)

def sheer(z):return 1.92+1.80*(max(0,z)/16)**3.2+.70*(max(0,-z)/16)**2.6
def deck_y(x,z):return sheer(z)+.10*(1-(x/max(.25,smooth_table(z)))**2)
def quarter_width(z):return smooth_table(z)*(.82+.06*max(0,min(1,(-z-7)/8)))
def quarter_y(z):return 4.38+.25*max(0,min(1,(-z-7)/8))**2
def outer_x(y,z):
    keel=-2+1.62*(abs(z)/16)**5
    t=max(0,min(1,(y-keel)/(sheer(z)-keel)))
    return .10+(smooth_table(z)-.10)*math.sin(t*math.pi/2)**.80

def shell_z(z,t):
    return z-2.3*(1-t)*max(0,(z-11)/5)**2+1.2*(1-t)*max(0,(-z-12)/4)**2

def plank_wall(name,vertices,faces,mat,parent):
    ob=B.mesh(name,vertices,faces,mat,parent)
    # Side planks keep longitudinal grain even when built from short sections.
    for polygon in ob.data.polygons:
        for loop in polygon.loop_indices:
            point=ob.data.vertices[ob.data.loops[loop].vertex_index].co
            ob.data.uv_layers.active.data[loop].uv=(point.y*.35,point.z*.35)
    return ob

def shadow_resource(ob):
    # Same parent/local coordinates as the rich component. Export the Mesh,
    # but hide it in Blender and explicitly in HeroProvider after GLTF import.
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(len(edge.link_faces)==2 for edge in bm.edges),ob.name+' is not closed'
    bm.to_mesh(ob.data);bm.free();ob.data.update()
    ob['hero_shadow_resource']=True;ob.hide_render=True;ob.display_type='WIRE'
    return ob

def hull_shadow(root):
    n=20;vs=[];fs=[];levels=[0,.16,.38,.65,.85,1]
    for j in range(n+1):
        z=-16+32*j/n;keel=-2+1.62*(abs(z)/16)**5
        for side,ts in [(1,levels),(-1,list(reversed(levels)))]:
            for t in ts:
                y=keel+(sheer(z)-keel)*t
                vs.append((side*outer_x(y,z),y,shell_z(z,t)))
            if side==1:vs.append((0,deck_y(0,z),z))
    ring=13
    for j in range(n):
        for i in range(ring):
            a=j*ring+i;b=j*ring+(i+1)%ring
            fs.append((a,b,b+ring,a+ring))
    fs.extend([tuple(reversed(range(ring))),tuple(n*ring+i for i in range(ring))])
    pieces=[B.mesh('Closed shadow shell',vs,fs,'pitch',root)]
    ports=[32*(-.138+i*.092) for i in range(4)]
    breaks=sorted(set([-16+32*j/20 for j in range(21)]+[z+d for z in ports for d in [-.58,.58]]))
    for side in [-1,1]:
        for za,zb in zip(breaks,breaks[1:]):
            opening=any(abs((za+zb)/2-z)<.58 for z in ports)
            for section in (['bottom','top'] if opening else ['whole']):
                lowa,lowb=sheer(za),sheer(zb);higha,highb=lowa+.94,lowb+.94
                if section=='bottom':higha=highb=1.99
                if section=='top':lowa=lowb=2.76
                if min(higha-lowa,highb-lowb)<.015:continue
                xa,xb=side*smooth_table(za),side*smooth_table(zb);d=-side*.16
                vs=[(xa,lowa,za),(xb,lowb,zb),(xb,highb,zb),(xa,higha,za),(xa+d,lowa,za),(xb+d,lowb,zb),(xb+d,highb,zb),(xa+d,higha,za)]
                pieces.append(B.mesh('Shadow bulwark with open gunports',vs,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(3,2,6,7),(0,3,7,4),(1,5,6,2)],'pitch',root))
    shadow_resource(B.join(pieces,'shadow_hull',root))
    vs=[];fs=[];steps=12
    for j in range(steps+1):
        z=-15.7+8.85*j/steps;w=quarter_width(z);y=quarter_y(z)
        vs.extend([(-w,y,z),(w,y,z),(-w,y-.17,z),(w,y-.17,z)])
        if j:
            k=4*j;fs.extend([(k-4,k,k+1,k-3),(k-2,k+2,k,k-4),(k-3,k+1,k+3,k-1),(k-2,k-1,k+3,k+2)])
    fs.extend([(0,1,3,2),(4*steps+2,4*steps+3,4*steps+1,4*steps)])
    shadow_resource(B.mesh('shadow_deck',vs,fs,'pitch',root))

def hull(root):
    parts=[];n=[64,40,24][B.LOD];bands=[13,9,7][B.LOD]
    for side in [-1,1]:
        for row in range(bands):
            vertices=[];faces=[]
            for j in range(n+1):
                z=-16+32*j/n;keel=-2+1.62*(abs(z)/16)**5
                for t in [row/bands,(row+1)/bands]:
                    y=keel+(sheer(z)-keel)*t
                    vertices.append((side*outer_x(y,z),y,shell_z(z,t)))
            for j in range(n):
                f=(2*j,2*j+1,2*j+3,2*j+2);faces.append(f if side>0 else tuple(reversed(f)))
            ob=B.mesh('Faired hull strake',vertices,faces,'tarred' if row<bands*.43 else 'teak',root)
            for poly in ob.data.polygons:poly.use_smooth=True
            parts.append(ob)
            if B.LOD<2 or row%2==0:
                points=[];t=(row+1)/bands
                for j in range(n+1):
                    z=-16+32*j/n;keel=-2+1.62*(abs(z)/16)**5;y=keel+(sheer(z)-keel)*t
                    points.append((side*(outer_x(y,z)+.012),y,shell_z(z,t)))
                parts.append(B.curve('Fine caulk seam',points,.009,'pitch',root))
        # Solid upper sides are the ship's primary mass. Openings are geometry.
        ports=[32*(-.138+i*.092) for i in range(4)]
        breaks=sorted(set([-16+32*j/n for j in range(n+1)]+[z+d for z in ports for d in [-.58,.58]]))
        for za,zb in zip(breaks,breaks[1:]):
            mid=(za+zb)/2;opening=any(abs(mid-z)<.58 for z in ports)
            intervals=[('bottom',0,0),('top',0,0)] if opening else [('whole',0,0)]
            for label,_,__ in intervals:
                low_a,low_b=sheer(za),sheer(zb);high_a,high_b=low_a+.94,low_b+.94
                if label=='bottom':high_a=high_b=1.99
                if label=='top':low_a=low_b=2.76
                if min(high_a-low_a,high_b-low_b)<.015:continue
                xa,xb=side*smooth_table(za),side*smooth_table(zb)
                thick=-side*.16
                vs=[(xa,low_a,za),(xb,low_b,zb),(xb,high_b,zb),(xa,high_a,za),(xa+thick,low_a,za),(xb+thick,low_b,zb),(xb+thick,high_b,zb),(xa+thick,high_a,za)]
                fs=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(3,2,6,7),(0,3,7,4),(1,5,6,2)]
                if side>0:fs=[tuple(reversed(f)) for f in fs]
                parts.append(plank_wall('Solid gun bulwark',vs,fs,'teak',root))
        for yoffset,rad,mat in [(-.65,.075,'teak'),(-.20,.045,'vermilion'),(.95,.075,'teak')]:
            points=[(side*(smooth_table(z)+.018),sheer(z)+yoffset,z) for z in [-15.8+31.6*j/n for j in range(n+1)]]
            parts.append(B.curve('Swept rubbing wale',points,rad,mat,root))
        for z in [-14,-11,-7.6,-5.95,-2.95,0,2.95,5.95,8.8,11.5,14]:
            # Narrow rib ends visually connect the hull, wall and capping rail.
            path=[]
            for j in range(8):
                y=-.25+(sheer(z)+1.2)*j/7
                path.append((side*(outer_x(min(y,sheer(z)),z)+.045),y,z))
            if not any(abs(z-p)<.66 for p in ports):parts.append(B.curve('External frame head',path,.043,'teak',root))
        for z in ports:
            x=side*(smooth_table(z)+.025)
            for dy in [1.99,2.76]:parts.append(B.box('Gunport sill',(x,dy,z),(.20,.095,1.32),'teak',root,.016))
            for dz in [-.63,.63]:parts.append(B.box('Gunport jamb',(side*(smooth_table(z+dz)+.025),2.375,z+dz),(.20,.79,.09),'teak',root,.014))
    # Broad raked stern closure, shaped from the same shell section.
    stern=[]
    for y in [-.38,.4,1.2,2.0,sheer(-16)]:
        t=max(0,min(1,(y+.38)/(sheer(-16)+.38)));z=shell_z(-16,t)
        stern.extend([(-outer_x(y,-16),y,z),(outer_x(y,-16),y,z)])
    parts.append(B.mesh('Shaped stern transom',stern,[(i+2,i+3,i+1,i) for i in range(0,len(stern)-2,2)],'teak',root))
    stem=[(0,y,shell_z(16,max(0,min(1,(y+.38)/(sheer(16)+.38))))+.035) for y in [-.38,.3,1.25,2.4,3.48,sheer(16)+1.34]]
    parts.append(B.curve('Sculpted raised stem',stem,.145,'teak',root))
    parts.append(B.curve('Shaped keel timber',[(0,-2+1.62*(abs(z)/16)**5-.035,shell_z(z,0)) for z in [-14.5+29*j/40 for j in range(41)]],.105,'pitch',root))
    body=B.join(parts,'hull',root);body['damage_surface']='hull';body['target_rigid_shadow_caster']=True
    decks=[];strips=[44,30,18][B.LOD]
    for i in range(strips):
        x=-4.43+(i+.5)*8.86/strips;half=8.86/strips*.5-.008;vs=[];fs=[]
        for j in range(n):
            za=-15.7+31.3*j/n;zb=-15.7+31.3*(j+1)/n
            if abs(x)+half>min(smooth_table(za),smooth_table(zb))-.16:continue
            k=len(vs);vs += [(x-half,deck_y(x-half,za),za),(x+half,deck_y(x+half,za),za),(x+half,deck_y(x+half,zb),zb),(x-half,deck_y(x-half,zb),zb)]
            fs.append((k,k+3,k+2,k+1))
        if fs:decks.append(B.mesh('Narrow cambered deck plank',vs,fs,'deck',root))
    vs=[];fs=[]
    for j in range(n+1):
        z=-15.7+31.3*j/n;w=smooth_table(z)-.17
        vs.extend([(-w,sheer(z)-.035,z),(w,sheer(z)-.035,z)])
        if j:k=2*j;fs.append((k-2,k,k+1,k-1))
    decks.append(B.mesh('Continuous deck substrate',vs,fs,'pitch',root))
    # Curved-outline quarterdeck, not a rectangular box placed on the hull.
    steps=[22,16,10][B.LOD];vs=[];fs=[]
    for j in range(steps+1):
        z=-15.7+8.85*j/steps;w=quarter_width(z)
        vs.extend([(-w,quarter_y(z),z),(w,quarter_y(z),z),(-w,quarter_y(z)-.17,z),(w,quarter_y(z)-.17,z)])
        if j:
            k=4*j;fs.extend([(k-4,k,k+1,k-3),(k-2,k+2,k,k-4),(k-3,k+1,k+3,k-1)])
    decks.append(B.mesh('Swept quarterdeck',vs,fs,'deck',root))
    for side in [-1,1]:
        decks.append(B.curve('Quarterdeck edge fascia',[(side*quarter_width(z),quarter_y(z)-.12,z) for z in [-15.7+8.85*j/steps for j in range(steps+1)]],.075,'teak',root))
    deck=B.join(decks,'deck',root);deck['deck_support']=True;deck['target_rigid_shadow_caster']=True
    hull_shadow(root)
    return body

def fittings(root):
    details=[];rails=[];cabin=[];lids=[];n=[32,24,16][B.LOD]
    for side in [-1,1]:
        # Low dark rails sit on a substantial wall, with shaped corner posts.
        for j in range(n+1):
            z=-15.7+31.4*j/n;x=side*(smooth_table(z)-.06);y=sheer(z)+.94
            rails.append(B.tube('Bulwark stanchion',(x,y-.08,z),(x,y+.39,z),.052,'teak',root,8))
            if B.LOD==0:rails.append(B.tube('Stanchion cap',(x,y+.39,z),(x,y+.43,z),.068,'teak',root,8))
        for height,rad in [(1.1,.032),(1.34,.052)]:
            rails.append(B.curve('Dark upper handrail',[(side*(smooth_table(z)-.06),sheer(z)+height,z) for z in [-15.7+31.4*j/n for j in range(n+1)]],rad,'teak',root))
        # Cabin sides follow the narrowing stern and disappear under its deck.
        for j in range(20):
            za=-15.6+6.5*j/20;zb=-15.6+6.5*(j+1)/20
            xa=side*(quarter_width(za)-.11);xb=side*(quarter_width(zb)-.11)
            cabin.append(plank_wall('Tapered stern side',[(xa,sheer(za),za),(xb,sheer(zb),zb),(xb,quarter_y(zb)-.15,zb),(xa,quarter_y(za)-.15,za)],[(3,2,1,0)] if side>0 else [(0,1,2,3)],'teak',root))
        for z in [-14.4,-12.9,-11.4,-9.9]:
            x=side*(quarter_width(z)-.095);y=3.66
            details.append(B.box('Recessed dark stern window',(x,y,z),(.025,.58,.70),'pitch',root,.01))
            for dz in [-.36,.36]:details.append(B.box('Window side frame',(x+side*.025,y,z+dz),(.055,.67,.055),'teak',root,.012))
            for dy in [-.32,.32]:details.append(B.box('Window cross frame',(x+side*.03,y+dy,z),(.06,.06,.77),'teak',root,.01))
            for k in [-2,-1,0,1,2]:details.append(B.box('Fine lattice upright',(x+side*.035,y,z+k*.12),(.03,.58,.024),'bamboo',root,.004))
            for dy in [-.16,0,.16]:details.append(B.box('Fine lattice cross',(x+side*.04,y+dy,z),(.03,.023,.69),'bamboo',root,.004))
        for j in range(10):
            z=-15.6+8.7*j/9;x=side*(quarter_width(z)-.04);y=quarter_y(z)
            rails.append(B.tube('Quarterdeck post',(x,y,z),(x,y+.76,z),.055,'teak',root,8))
        for h,rad in [(.30,.035),(.76,.055)]:rails.append(B.curve('Curved quarter rail',[(side*(quarter_width(z)-.04),quarter_y(z)+h,z) for z in [-15.6+8.7*j/20 for j in range(21)]],rad,'teak',root))
        for z in [32*(-.138+i*.092) for i in range(4)]:
            x=side*(smooth_table(z)+.04);y=2.82
            shutter=B.mesh('Open gunport shutter',[(x,y,z-.57),(x,y,z+.57),(x+side*.65,y+.32,z+.57),(x+side*.65,y+.32,z-.57)],[(0,1,2,3)],'teak',root)
            solid=shutter.modifiers.new('Shutter thickness','SOLIDIFY');solid.thickness=.055;lids.append(shutter)
            for dz in [-.34,.34]:lids.append(B.curve('Shutter iron strap',[(x+side*.02,y+.02,z+dz),(x+side*.63,y+.34,z+dz)],.025,'iron',root))
    for label,z,depth in [('Stern forward bulkhead',-9.08,.12),('Raked stern rear',-15.65,.16)]:
        bottom=sheer(z)-.06;top=quarter_y(z)-.12
        cabin.append(B.box(label,(0,(bottom+top)/2,z),(quarter_width(z)*2-.2,top-bottom,depth),'teak',root,.035))
    castle=B.join(cabin,'sterncastle',root);castle['deck_obstacle']=True
    door_y=sheer(-9.08)+.85
    details.append(B.box('Cabin recessed doorway',(0,door_y,-9.0),(.90,1.55,.025),'pitch',root,.015))
    for x in [-.49,.49]:details.append(B.box('Door jamb',(x,door_y,-8.97),(.075,1.67,.08),'teak',root,.012))
    details.append(B.box('Door lintel',(0,door_y+.82,-8.97),(1.05,.10,.08),'teak',root,.016))
    # Understated paneling organizes the cabin instead of bright random rods.
    for side in [-1,1]:
        details.append(B.curve('Stern red frieze',[(side*(quarter_width(z)-.08),4.17,z) for z in [-15.5+6.3*j/20 for j in range(21)]],.032,'vermilion',root))
        for z in [-15.5,-13.7,-12.2,-10.7,-9.1]:details.append(B.tube('Cabin corner stile',(side*(quarter_width(z)-.07),2.8,z),(side*(quarter_width(z)-.07),4.25,z),.045,'teak',root,6))
    # A pair of real stair flights join the two deck levels.
    for side in [-1,1]:
        x=side*2.72;start_z=-4.75;end_z=-7.08;y0=deck_y(x,start_z);y1=quarter_y(end_z)
        for k in range(9):
            t=(k+1)/9;z=start_z+(end_z-start_z)*t;y=y0+(y1-y0)*t
            details.append(B.box('Carved stair tread',(x,y-.06,z),(.78,.12,.32),'deck',root,.025))
        for dx in [-.41,.41]:
            details.append(B.tube('Stair carriage',(x+dx,y0-.06,start_z+.1),(x+dx,y1-.03,end_z-.1),.063,'teak',root,8))
            details.append(B.tube('Stair hand rope',(x+dx,y0+.72,start_z),(x+dx,y1+.72,end_z),.027,'hemp',root,6))
    for z in [-3.2,5.8]:
        y=deck_y(0,z);hatch=B.box('cargo_hold_%s'%z,(0,y+.14,z),(1.45,.28,1.85),'teak',root,.04);hatch['deck_obstacle']=True
        for i in range(8):details.append(B.box('Recessed hatch grid',((i-3.5)*.16,y+.29,z),(.055,.045,1.62),'teak',root,.009))
        for j in range(9):details.append(B.box('Recessed hatch cross',(0,y+.28,z+(j-4)*.18),(1.31,.035,.045),'bamboo',root,.007))
    # Purposeful deck hardware: bitts, mast partners, belaying rails and tackle.
    for z in [10,.6,-10.7]:
        y=quarter_y(z) if z<-7 else deck_y(0,z)
        details.append(B.box('Mast partner collar',(0,y+.08,z),(.92,.16,.85),'teak',root,.04))
        for side in [-1,1]:
            details.append(B.tube('Partner iron bolt',(side*.34,y+.16,z-.27),(side*.34,y+.21,z-.27),.04,'iron',root,8))
    for side in [-1,1]:
        x=side*2.4;z=9.8;y=deck_y(x,z)
        for dz in [-.55,.55]:details.append(B.box('Mooring bitt',(x,y+.42,z+dz),(.24,.84,.24),'teak',root,.025))
        details.append(B.tube('Bitt crossbar',(x,y+.63,z-.85),(x,y+.63,z+.85),.085,'teak',root,8))
        if B.LOD<2:
            for j in range(5):details.append(B.tube('Belaying pin',(side*2.1,y+.50,2+j*.28),(side*2.1,y+.92,2+j*.28),.028,'bamboo',root,6))
        ax=side*(smooth_table(12.4)-.35);ay=sheer(12.4)
        details.append(B.tube('Anchor cathead',(side*(smooth_table(12)-.3),ay+.55,12),(ax+side*.85,ay+.75,12.8),.105,'teak',root,8))
        details.append(B.tube('Anchor shank',(ax,.8,12.6),(ax,2.7,12.6),.065,'iron',root,10))
        details.append(B.tube('Anchor wood stock',(ax-.55,2.4,12.6),(ax+.55,2.4,12.6),.095,'teak',root,8))
        for dx in [-.6,.6]:details.append(B.curve('Forged anchor arm',[(ax,.8,12.6),(ax+dx*.65,.77,12.6),(ax+dx,1.22,12.6)],.075,'iron',root))
        pts=[(side*1.6+(.12+.007*i)*math.cos(i*.38),deck_y(side*1.6,10.8)+.025,10.8+(.12+.007*i)*math.sin(i*.38)) for i in range(70 if B.LOD==0 else 35)]
        details.append(B.curve('Working rope coil',pts,.018,'hemp',root))
    cy=deck_y(0,12.4)
    details.append(B.tube('Capstan foot',(0,cy,12.4),(0,cy+.15,12.4),.46,'teak',root,14))
    details.append(B.tube('Tapered capstan',(0,cy+.15,12.4),(0,cy+.79,12.4),.28,'teak',root,14,radius_b=.36))
    for a in [0,math.pi/2]:details.append(B.tube('Capstan handspike',(-1.1*math.cos(a),cy+.72,12.4-1.1*math.sin(a)),(1.1*math.cos(a),cy+.72,12.4+1.1*math.sin(a)),.047,'teak',root,8))
    B.join(rails,'bulwark_rails',root);B.join(details,'deck_fittings',root);B.join(lids,'gunport_lids',root)
    rudder=B.empty('rudder_pivot',(0,1.9,-15.6),root)
    blade=B.mesh('rudder_blade',[(-.12,-3.25,-.12),(.12,-3.25,-.12),(.12,-3.0,-1.8),(-.12,-3.0,-1.8),(-.12,.8,.1),(.12,.8,.1),(.12,.70,-1.5),(-.12,.70,-1.5)],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)],'teak',rudder)
    B.tube('rudder_stock',(0,-2.6,0),(0,3.65,0),.14,'teak',rudder,12,radius_b=.11)
    B.curve('tiller_beam',[(0,3.65,0),(0,3.68,2.0),(0,3.58,5.8),(0,3.65,8.25)],.105,'teak',rudder)
    B.tube('tiller_grip',(-.42,3.65,8.25),(.42,3.65,8.25),.045,'teak',rudder,8)
    for y in [-1.8,-.2,.65]:B.box('Rudder gudgeon',(0,y,-.75),(.28,.10,1.55),'iron',rudder,.014)

def sail_surface(u,v,height,width,base):
    breadth=width*(1+.10*math.sin(math.pi*v)-.40*v**2)
    shift=-width*.045*v*v
    z=breadth*(u-.70)+shift
    y=base+height*v+height*.15*(1-u)*v**2.2
    # C1-continuous gentle billow avoids a repeated hard crease at each batten.
    panel=math.sin(math.pi*((v*8)%1))**2
    x=.32+(.30*math.sin(math.pi*v)+PANEL_AMPLITUDE*panel)*math.sin(math.pi*u)
    return x,y,z

def sail(parent,index,height,width,base):
    pieces=[];rows=[32,24,16][B.LOD];cols=[18,12,8][B.LOD];vs=[];fs=[]
    for row in range(rows+1):
        for col in range(cols+1):vs.append(sail_surface(col/cols,row/rows,height,width,base))
    for row in range(rows):
        for col in range(cols):a=row*(cols+1)+col;fs.append((a,a+1,a+cols+2,a+cols+1))
    cloth=B.mesh('Tensioned canvas panels',vs,fs,'canvas',parent)
    for poly in cloth.data.polygons:
        poly.use_smooth=True
        for loop in poly.loop_indices:
            i=cloth.data.loops[loop].vertex_index;cloth.data.uv_layers.active.data[loop].uv=(i%(cols+1)/cols,i//(cols+1)/rows)
    pieces.append(cloth)
    for row in range(9):
        v=row/8;points=[]
        for col in range(cols+1):
            x,y,z=sail_surface(col/cols,v,height,width,base);points.append((x+.044,y,z))
        pieces.append(B.curve('Curved bamboo batten',points,.035 if row not in [0,8] else .065,'bamboo',parent))
    for column in [0,cols//4,cols//2,3*cols//4,cols]:
        u=column/cols
        pieces.append(B.curve('Canvas lacing seam',[(sail_surface(u,j/rows,height,width,base)[0]+.018,*sail_surface(u,j/rows,height,width,base)[1:]) for j in range(rows+1)],.006,'canvas_seam',parent))
    for row in [1,3,5,7]:
        p=sail_surface(0,row/8,height,width,base)
        pieces.append(B.curve('Batten sheet',[(p[0]+.08,p[1],p[2]),(.13,base-.18,-width*.30)],.017,'hemp',parent))
    # Broad cloth repairs add medium-scale history without enlarging the weave.
    pu=.13+.11*index;pv=.22+.08*index;patch=[];patch_faces=[];pn=6 if B.LOD==0 else 4
    for r in range(pn+1):
        for c in range(pn+1):
            u=pu+.17*c/pn;v=pv+.125*r/pn;x,y,z=sail_surface(u,v,height,width,base);patch.append((x+.026,y,z))
    for r in range(pn):
        for c in range(pn):a=r*(pn+1)+c;patch_faces.append((a,a+1,a+pn+2,a+pn+1))
    patch_ob=B.mesh('Restrained sailcloth repair',patch,patch_faces,'canvas',parent)
    for polygon in patch_ob.data.polygons:
        polygon.use_smooth=True
        for loop in polygon.loop_indices:
            i=patch_ob.data.loops[loop].vertex_index;patch_ob.data.uv_layers.active.data[loop].uv=(pu+.17*(i%(pn+1))/pn,pv+.125*(i//(pn+1))/pn)
    pieces.append(patch_ob)
    for row in [0,2,4,6,8]:
        v=row/8;breadth=width*(1+.10*math.sin(math.pi*v)-.40*v*v);u=.70+width*.045*v*v/breadth
        x,y,z=sail_surface(u,v,height,width,base)
        pieces.append(B.curve('Mast to batten lashing',[(x+.06,y-.045,.11),(-.20,y-.045,.11),(-.20,y+.055,-.11),(x+.06,y+.055,-.11),(x+.06,y-.045,.11)],.015,'hemp',parent))
    ob=B.join(pieces,'sail_%d'%index,parent)
    uv_by_vertex={}
    canvas_indices={slot for slot,material in enumerate(ob.data.materials) if material.name=='canvas'}
    for polygon in ob.data.polygons:
        if polygon.material_index in canvas_indices:
            for loop in polygon.loop_indices:uv_by_vertex[ob.data.loops[loop].vertex_index]=ob.data.uv_layers.active.data[loop].uv.copy()
    age=ob.data.color_attributes.new(name='SailAge',type='FLOAT_COLOR',domain='POINT')
    for i,color in enumerate(age.data):
        if i not in uv_by_vertex:color.color=(1,1,1,1);continue
        u,v=uv_by_vertex[i];sector=min(3,int(u*4));panel=min(7,int(v*8))
        variation=.5+.5*math.sin(sector*8.31+panel*3.73+index*4.0)
        edge=max(math.exp(-u/.025),math.exp(-(1-u)/.025),math.exp(-v/.035),math.exp(-(1-v)/.035))
        shade=.97-.11*variation-.12*edge
        if pu+.004<u<pu+.166 and pv+.004<v<pv+.121:shade-=.12
        color.color=(shade,shade*.985,shade*.955,1)
    ob.shape_key_add(name='Basis');furl=ob.shape_key_add(name='furl');inflate=ob.shape_key_add(name='inflate');furl.value=0;inflate.value=0
    # Invert the authored fan parameterization for all merged cloth/rig points.
    # Reefing compresses the common vertical coordinate, including batten radii.
    for i,vertex in enumerate(ob.data.vertices):
        x,nz,y=vertex.co;z=-nz;v=max(0,min(1,(y-base)/(height*1.12)))
        for _ in range(12):
            breadth=width*(1+.10*math.sin(math.pi*v)-.40*v*v);u=max(0,min(1,(z+width*.045*v*v)/breadth+.70))
            v=max(0,min(1,(y-base)/height-.15*(1-u)*v**2.2))
        furl.data[i].co.z=base+(y-base)*.038
        furl.data[i].co.x=.32+(x-.32)*.2
        # Negative inflation reduces belly without extrapolating through mast.
        inflate.data[i].co.x=x+(width*.019*math.sin(math.pi*v)*math.sin(math.pi*u) if x>.25 else 0)
    ob['damage_surface']='sail';ob['shape_design']='curved fan surface with common batten parameterization'
    return ob

def rig(root):
    for index,z,top,width,base,height in [(0,10,17.2,7.7,4.6,10.3),(1,.6,24.3,12.0,4.05,17.0),(2,-10.7,16.3,6.8,5.35,9.0)]:
        mast=B.empty('mast_%d'%index,(0,0,z),root);mast['sail_trim_origin']=0.0
        timbers=[B.tube('Tapered mast',(0,sheer(z),0),(0,top,0),.24 if index==1 else .18,'teak',mast,16 if B.LOD==0 else 10,radius_b=.085)]
        for y in [sheer(z)+.5,base-.1,top*.47,top*.70,top*.88]:
            for dy in [-.045,.015,.075]:timbers.append(B.tube('Mast rope binding',(0,y+dy-.013,0),(0,y+dy+.013,0),(.245 if index==1 else .185)*(1-y/top*.40),'hemp',mast,12))
        timber=B.join(timbers,'mast_timber_%d'%index,mast);timber['deck_obstacle']=True;timber['target_rigid_shadow_caster']=True
        shadow_resource(B.tube('shadow_mast_timber_%d'%index,(0,sheer(z),0),(0,top,0),.24 if index==1 else .18,'pitch',mast,10,radius_b=.085))
        sail(mast,index,height,width,base)
        B.tube('Mast finial',(0,top-.1,0),(0,top+.22,0),.105,'teak',mast,10)
        stays=[]
        for side in [-1,1]:
            for dz in [-1.05,1.05]:
                x=side*(smooth_table(z+dz)-.24);y=sheer(z+dz)+1.02
                stays.append(B.curve('Standing shroud',[(x,y,z+dz),(side*.10,top*.82,z)],.022,'hemp',root))
                if B.LOD<2:
                    stays.append(B.tube('Deadeye block',(x,y+.06,z+dz),(x,y+.25,z+dz),.085,'teak',root,8))
                    stays.append(B.tube('Chainplate',(x,y-.40,z+dz),(x,y+.02,z+dz),.028,'iron',root,6))
        standing=B.join(stays,'rigging_%d'%index,root);standing['mast_index']=index
        if index==1:
            flag=B.mesh('flag_ming',[(0,top-.05,0),(.06,top-.12,-2.8),(.16,top-.43,-2.15),(.08,top-.91,-3.05),(0,top-.86,0)],[(0,1,2,3,4)],'vermilion',mast)
            flag['source_fixed_attachment']=False

def cannon_geometry(parent):
    parts=[];sides=[24,16,10][B.LOD]
    profile=[(-.88,.11),(-.75,.205),(-.48,.205),(.20,.16),(.73,.14),(.91,.185),(1.08,.185)]
    vs=[];fs=[]
    for z,r in profile:
        cy=.16*(1-z/1.08)
        for i in range(sides):vs.append((r*math.cos(math.tau*i/sides),cy+r*math.sin(math.tau*i/sides),z))
    for j in range(len(profile)-1):
        for i in range(sides):a=j*sides+i;b=j*sides+(i+1)%sides;fs.append((a,b,b+sides,a+sides))
    fs.append(tuple(reversed(range(sides))));barrel=B.mesh('Contoured iron cannon',vs,fs,'iron',parent)
    for poly in barrel.data.polygons:poly.use_smooth=len(poly.vertices)==4
    parts.append(barrel)
    for z,r in [(-.71,.225),(-.40,.22),(.38,.177),(.87,.205)]:
        cy=.16*(1-z/1.08);parts.append(B.tube('Cast reinforcing ring',(0,cy,z-.023),(0,cy,z+.023),r,'iron_edge',parent,sides))
    parts.append(B.tube('Dark bore recess',(0,.009,1.015),(0,.008,1.025),.139,'pitch',parent,sides))
    parts.append(B.tube('Cannon trunnions',(-.34,.20,-.25),(.34,.20,-.25),.07,'iron',parent,12))
    return parts

def guns(root):
    for side,sgn in [('port',1),('starboard',-1)]:
        for i in range(4):
            z=32*(-.138+i*.092);muzzle=9*.435*(1-(z/16)**2)**.64+.87
            group=B.empty('cannon_%s_%02d'%(side,i),(sgn*(muzzle-1.08),2.2,z),root);group.rotation_euler.z=sgn*math.pi/2
            barrel=B.empty('barrel_%s_%02d'%(side,i),(0,0,0),group)
            B.join(cannon_geometry(barrel),'gun_tube_%s_%d'%(side,i),barrel)
            parts=[B.box('Low carriage bed',(0,-.13,-.26),(.72,.13,1.14),'teak',group,.025)]
            for x in [-.32,.32]:
                parts.append(B.box('Shaped carriage cheek',(x,.025,-.32),(.10,.28,.92),'teak',group,.025))
                for zz in [-.66,.14]:
                    parts.append(B.tube('Small wooden truck',(x-.075,-.15,zz),(x+.075,-.15,zz),.095,'teak',group,12))
                    parts.append(B.tube('Wheel axle pin',(x-.09,-.15,zz),(x+.09,-.15,zz),.026,'iron',group,8))
            parts.append(B.curve('Breeching line',[(-.54,-.02,-.1),(-.48,.10,-.79),(0,.12,-.92),(.48,.10,-.79),(.54,-.02,-.1)],.025,'hemp',group))
            B.join(parts,'gun_carriage_%s_%d'%(side,i),group)
            B.empty('socket_smoke_%s_%02d'%(side,i),(0,0,1.08),group)

original_setup=B.setup_materials
def setup_materials():
    original_setup()
    mat=B.MATS['canvas'];tree=mat.node_tree;bs=tree.nodes.get('Principled BSDF')
    tex=next(node for node in tree.nodes if node.type=='TEX_IMAGE')
    color=tree.nodes.new('ShaderNodeVertexColor');color.layer_name='SailAge'
    multiply=tree.nodes.new('ShaderNodeMix');multiply.data_type='RGBA';multiply.blend_type='MULTIPLY';multiply.inputs[0].default_value=1.0
    tree.links.new(tex.outputs['Color'],multiply.inputs[6]);tree.links.new(color.outputs['Color'],multiply.inputs[7]);tree.links.new(multiply.outputs[2],bs.inputs['Base Color'])
    for name,color in {'bamboo':(.25,.15,.075),'hemp':(.34,.26,.17),'ochre':(.32,.23,.11),'vermilion':(.32,.055,.032),'canvas_seam':(.48,.41,.30)}.items():
        mat=B.MATS[name];mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(*color,1);mat.diffuse_color=(*color,1)

original_preview=B.preview
def preview(root):
    if '--export-only' in sys.argv:return
    original_preview(root)
    scene=bpy.context.scene;camera=scene.camera
    for name,position,target,scale in [('side-profile',(55,13,0),(0,10,0),43),('stern-quarter',(-31,19,-36),(0,8,0),43),('deck-detail',(14,12,-14),(0,3,-4),21)]:
        camera.location=B.point(position);camera.rotation_euler=(B.point(target)-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=scale
        scene.cycles.samples=24;scene.render.filepath=str(B.EVIDENCE/(name+'.png'));bpy.ops.render.render(write_still=True)

B.half_width=smooth_table;B.deck_height=sheer;B.hull=hull;B.fittings=fittings;B.sail=sail;B.rig=rig;B.guns=guns;B.setup_materials=setup_materials;B.preview=preview
if __name__=='__main__':B.main()
