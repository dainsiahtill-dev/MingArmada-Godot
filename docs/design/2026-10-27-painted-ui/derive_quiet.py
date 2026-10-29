from pathlib import Path
from PIL import Image
import json,hashlib
root=Path(__file__).resolve().parents[3]
mp=Path(__file__).with_name("QUIET-ASSETS.json")
data=json.loads(mp.read_text(encoding="utf-8"))
for asset in data["assets"]:
    p=root/asset["path"]; raw=p.read_bytes()
    with Image.open(p) as im:
        assert im.mode=="RGBA"
        a=im.getchannel("A"); h=a.histogram()
        assert h[0]>0 and h[255]>0
        asset.update(size=list(im.size),sha256=hashlib.sha256(raw).hexdigest(),bytes=len(raw),source_byte_identical=raw==Path(asset["generation_source"]).read_bytes())
        assert asset["source_byte_identical"]
        asset["alpha"]={"min_max":list(a.getextrema()),"transparent_pixels":h[0],"partial_pixels":sum(h[1:255]),"opaque_pixels":h[255],"center_rgba":list(im.getpixel((im.width//2,im.height//2)))}
        bb=a.point(lambda v:255 if v>=16 else 0).getbbox()
        l,t,r,b=bb; cb=(max(0,l-8),max(0,t-8),min(im.width,r+8),min(im.height,b+8))
        crop=im.crop(cb); w=asset["runtime_width"]; size=(w,round(crop.height*w/crop.width))
        out=p.parent/"runtime"/p.name;out.parent.mkdir(parents=True,exist_ok=True)
        small=crop.resize(size,Image.Resampling.LANCZOS);small.save(out)
        asset["runtime"]={"path":out.relative_to(root).as_posix(),"size":list(size),"sha256":hashlib.sha256(out.read_bytes()).hexdigest(),"bbox_threshold_inclusive":16,"threshold_bbox_xyxy":list(bb),"padding_original_pixels":8,"crop_box_xyxy":list(cb),"operation":"crop + proportional LANCZOS resize only; retained alpha/colors not otherwise edited","center_rgba":list(small.getpixel((small.width//2,small.height//2))),"ninepatch_caps_ltrb_source_pixels":[8,3,8,3] if p.name.startswith("button-") else ([32,16,8,8] if p.name=="folio-panel.png" else [8,8,8,8])}
        print(json.dumps({"name":p.name,"raw_size":asset["size"],"sha256":asset["sha256"],"alpha":asset["alpha"],"runtime":asset["runtime"]}))
mp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
oldp=Path(__file__).with_name("ASSETS.json")
old=json.loads(oldp.read_text(encoding="utf-8"))
for asset in old["assets"]:
    asset["status"]="retained character focal artwork" if asset["key"]=="xufu" else "rejected ornate iteration"
oldp.write_text(json.dumps(old,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
