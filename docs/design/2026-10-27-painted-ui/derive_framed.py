from pathlib import Path
from PIL import Image
import hashlib,json
root=Path(__file__).resolve().parents[3]
mp=Path(__file__).with_name("FRAMED-ASSETS.json")
data=json.loads(mp.read_text(encoding="utf-8"))
for asset in data["assets"]:
    path=root/asset["path"];raw=path.read_bytes()
    with Image.open(path) as im:
        assert im.mode=="RGBA"
        a=im.getchannel("A");h=a.histogram()
        bb=a.getbbox()
        high=a.point(lambda v:255 if v>=240 else 0).getbbox()
        l,t,r,b=bb
        cb=(max(0,l-8),max(0,t-8),min(im.width,r+8),min(im.height,b+8))
        cropped=im.crop(cb);ch=cropped.getchannel("A").histogram()
        assert sum(h[1:])==sum(ch[1:]),"Must retain every nonzero-alpha pixel including full shadow."
        w=asset["runtime_width"];size=(w,round(cropped.height*w/cropped.width))
        small=cropped.resize(size,Image.Resampling.LANCZOS)
        out=path.parent/"runtime"/path.name;out.parent.mkdir(parents=True,exist_ok=True);small.save(out)
        # Read actual right-edge alpha falloff, without editing or inferring a matte.
        points=[(x,im.getpixel((x,im.height//2))) for x in range(im.width-45,im.width,3)]
        boundary_alpha=[]
        for x in range(im.width):boundary_alpha.extend([im.getpixel((x,0))[3],im.getpixel((x,im.height-1))[3]])
        for y in range(im.height):boundary_alpha.extend([im.getpixel((0,y))[3],im.getpixel((im.width-1,y))[3]])
        asset.update(size=list(im.size),sha256=hashlib.sha256(raw).hexdigest(),source_byte_identical=raw==Path(asset["generation_source"]).read_bytes(),edit_target_sha256=hashlib.sha256((root/asset["edit_target"]).read_bytes()).hexdigest())
        assert asset["source_byte_identical"] and h[0]>0
        asset["alpha"]={"range":list(a.getextrema()),"fully_transparent_pixels":h[0],"partial_alpha_pixels":sum(h[1:255]),"center_rgba":list(im.getpixel((im.width//2,im.height//2))),"nonzero_bbox_xyxy":list(bb),"alpha_ge_240_bbox_xyxy":list(high),"right_midline_rgba_witness":points,"maximum_original_canvas_edge_alpha":max(boundary_alpha),"shadow_evidence":"dark RGB outside near-opaque face exhibits graded partial alpha toward zero; right-midline samples are recorded. No background removal or alpha repair."}
        asset["runtime"]={"path":out.relative_to(root).as_posix(),"size":list(size),"sha256":hashlib.sha256(out.read_bytes()).hexdigest(),"crop_box_xyxy":list(cb),"crop_rule":"exact alpha>0 bounding box plus eight original pixels; only fully alpha-zero outside is discarded","retained_every_nonzero_alpha_pixel":True,"threshold":0,"operation":"crop alpha-zero padding only then proportional LANCZOS resize; full shadow kept","center_rgba":list(small.getpixel((small.width//2,small.height//2)))}
        print(json.dumps({"name":path.name,"raw_size":im.size,"alpha_bbox":bb,"canvas_edge_alpha_max":max(boundary_alpha),"runtime":asset["runtime"]}))
mp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
