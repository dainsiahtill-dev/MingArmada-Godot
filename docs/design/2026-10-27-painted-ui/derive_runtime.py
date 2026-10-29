"""Derive runtime PNGs only by alpha-visible bounds crop + proportional LANCZOS resize."""
from pathlib import Path
from PIL import Image
import hashlib, json
root = Path(__file__).resolve().parents[3]
manifest_path = Path(__file__).with_name("ASSETS.json")
data = json.loads(manifest_path.read_text(encoding="utf-8"))
runtime = root / "assets/ui/ming_maritime/painted/runtime"
runtime.mkdir(parents=True, exist_ok=True)
widths = {"command":768,"folio":512,"header":768,"normal":512,"selected":512,"compass":256}
caps = {"command":[90,40,90,62],"folio":[72,76,72,110],"header":[130,36,130,36],"normal":[52,14,52,14],"selected":[52,14,52,14],"compass":None}
for asset in data["assets"]:
    if asset["key"] not in widths:
        continue
    path = root / asset["path"]
    with Image.open(path) as im:
        assert im.mode == "RGBA"
        alpha = im.getchannel("A")
        visible_bbox = alpha.point(lambda a:255 if a>=16 else 0).getbbox()
        l,t,r,b = visible_bbox
        crop_box = (max(0,l-8),max(0,t-8),min(im.width,r+8),min(im.height,b+8))
        cropped = im.crop(crop_box)
        width = widths[asset["key"]]
        size = (width,round(cropped.height*width/cropped.width))
        if asset["key"]=="compass":
            assert cropped.width==cropped.height, "Compass must remain square without distortion."
        resized = cropped.resize(size,Image.Resampling.LANCZOS)
        output = runtime/path.name
        resized.save(output)
        # Audit discarded border pixels; never use threshold to modify retained alpha.
        retained = (crop_box[2]-crop_box[0])*(crop_box[3]-crop_box[1])
        orig_hist = alpha.histogram()
        cropped_hist = cropped.getchannel("A").histogram()
        discarded_nonzero = sum(orig_hist[1:])-sum(cropped_hist[1:])
        aout = resized.getchannel("A")
        runtime_record = {
            "path":output.relative_to(root).as_posix(),
            "sha256":hashlib.sha256(output.read_bytes()).hexdigest(),
            "size":list(resized.size),
            "source_sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
            "alpha_bbox_threshold_inclusive":16,
            "visible_bbox_xyxy":list(visible_bbox),
            "padding_original_pixels":8,
            "padding_clamped_to_original_canvas":True,
            "crop_box_xyxy":list(crop_box),
            "discarded_nonzero_alpha_pixels":discarded_nonzero,
            "operation":"crop retained RGBA verbatim, then proportional Pillow LANCZOS resize; no alpha/color threshold, keying, matte, painting or other edits",
            "scale":width/cropped.width,
            "alpha_min_max":list(aout.getextrema()),
            "center_rgba":list(resized.getpixel((resized.width//2,resized.height//2)))
        }
        asset["runtime"]=runtime_record
        asset["runtime"]["ninepatch_caps_ltrb_source_pixels"] = caps[asset["key"]]
        if asset["key"] in ["normal","selected"]:
            small = cropped.resize((128,round(cropped.height*128/cropped.width)),Image.Resampling.LANCZOS)
            small_output = output.with_name(output.stem+"-small.png")
            small.save(small_output)
            asset["runtime_small"] = {
                "path":small_output.relative_to(root).as_posix(),
                "size":list(small.size),
                "sha256":hashlib.sha256(small_output.read_bytes()).hexdigest(),
                "source_crop_box_xyxy":list(crop_box),
                "operation":"same raw crop, proportional LANCZOS resize only",
                "ninepatch_caps_ltrb_source_pixels":[14,5,14,5],
                "target_control_size":[100,36],
                "recommendation":"Use the small source for 100x36 controls. The 512px source safe caps sum to 104px, wider than that control."
            }
        print(json.dumps({"key":asset["key"],**runtime_record},ensure_ascii=False))
manifest_path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
