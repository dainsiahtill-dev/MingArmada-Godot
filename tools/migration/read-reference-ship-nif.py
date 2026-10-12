"""Import actual ship buffers with the existing verified read-only NIF loader.

No PE/IDA/Unicorn analysis, no writes into the reference. -B is required by caller.
"""
from pathlib import Path
import hashlib, json, sys

reference = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
sys.path.insert(0, str(reference / "naval-study/deep/asset-details"))
from legacy_adapter import load, NifFormat

families = ["sloop1", "barque", "frigate", "ship_brigantine", "ship_merman", "treasure_galleon"]
inventory = json.loads((reference / "naval-study/deep/asset-details/source-inventory.json").read_text(encoding="utf-8"))
records = {item["name"]: item for item in inventory}
output.mkdir(parents=True, exist_ok=True)

def text(value):
    return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else str(value)

def vec(value):
    return [float(getattr(value, axis)) for axis in "xyz"]

def prop(value, ids):
    result = {"id": ids[id(value)], "type": type(value).__name__}
    if isinstance(value, NifFormat.NiMaterialProperty):
        result.update(name=text(value.name), diffuse=[float(getattr(value.diffuse_color, key)) for key in "rgb"], alpha=float(value.alpha), ambient=[float(getattr(value.ambient_color, key)) for key in "rgb"], emissive=[float(getattr(value.emissive_color, key)) for key in "rgb"], specular=[float(getattr(value.specular_color, key)) for key in "rgb"], glossiness=float(value.glossiness))
    if isinstance(value, NifFormat.NiTexturingProperty):
        result["slots"] = {}
        for slot in ["base", "dark", "detail", "gloss", "glow", "bump_map", "decal_0", "decal_1", "decal_2", "decal_3"]:
            if getattr(value, "has_" + slot + "_texture", False):
                desc = getattr(value, slot + "_texture")
                result["slots"][slot] = {"texture": text(desc.source.file_name).replace("\\", "/").split("/")[-1], "uv_set": int(desc.uv_set), "clamp_mode": int(desc.clamp_mode), "filter_mode": int(desc.filter_mode)}
        if value.has_base_texture:
            result.update(texture=text(value.base_texture.source.file_name), uv_set=int(value.base_texture.uv_set))
    if isinstance(value, NifFormat.NiAlphaProperty):
        result.update(flags=int(value.flags), threshold=int(value.threshold))
    if isinstance(value, NifFormat.NiZBufferProperty):
        result.update(flags=int(value.flags), function=int(value.function))
    if isinstance(value, NifFormat.NiStencilProperty):
        result.update(flags=int(value.flags), draw_mode=int(value.draw_mode))
    return result

for family in families:
    for profile, name in [("lowend", family + "-lowend.nif"), ("battle", family + "-battle.nif"), ("anchors", family + ".nif")]:
        record = records[name]
        source_path = reference / record["raw"]
        blob = source_path.read_bytes()
        assert hashlib.sha256(blob).hexdigest() == record["sha256"], "source provenance mismatch"
        data, consumed = load(source_path)
        assert consumed == len(blob), "incomplete existing-loader asset read"
        ids = {id(block): index for index, block in enumerate(data.blocks)}
        nodes, meshes = [], []
        def walk(node, parent=None, inherited=None, crew=False):
            if not isinstance(node, NifFormat.NiAVObject):
                return
            node_id = ids[id(node)]
            effective = dict(inherited or {})
            own = [prop(item, ids) for item in node.properties]
            for item in own:
                effective[item["type"]] = item
            crew = crew or text(node.name).startswith("D_Crew_")
            matrix = node.get_transform(relative_to=data.roots[0])
            nodes.append({"id": node_id, "parent": parent, "name": text(node.name), "type": type(node).__name__, "flags": int(node.flags), "translation": vec(node.translation), "rotation": [[float(getattr(node.rotation, f"m_{row}{column}")) for column in range(1, 4)] for row in range(1, 4)], "scale": float(node.scale), "worldOrigin": vec(NifFormat.Vector3() * matrix), "properties": own})
            if isinstance(node, NifFormat.NiGeometry) and profile != "anchors":
                geometry = node.data
                vertices = [vec(value) for value in geometry.vertices]
                triangles = [list(value) for value in geometry.get_triangles() if len(set(value)) == 3]
                world_vertices = [vec(value * matrix) for value in geometry.vertices]
                # Original rotation transforms row-vector normals; translation does not.
                world_normals = []
                for normal in geometry.normals:
                    rotated = normal * matrix.get_matrix_33()
                    world_normals.append(vec(rotated))
                sample_indices = sorted(set([0, len(vertices) // 2, len(vertices) - 1]))
                meshes.append({"node_id": node_id, "name": text(node.name), "crew": crew, "skin_instance": getattr(node, "skin_instance", None) is not None, "flags": int(node.flags), "vertices": vertices, "worldVertices": world_vertices, "normals": [vec(value) for value in geometry.normals], "worldNormals": world_normals, "triangles": triangles, "uv_sets": [[[float(value.u), float(value.v)] for value in group] for group in geometry.uv_sets], "material": effective.get("NiMaterialProperty", {}), "texture": effective.get("NiTexturingProperty", {}), "alpha": effective.get("NiAlphaProperty"), "zbuffer": effective.get("NiZBufferProperty"), "stencil": effective.get("NiStencilProperty"), "worldSamples": [{"index": index, "value": world_vertices[index]} for index in sample_indices]})
            for child in getattr(node, "children", []):
                if child is not None:
                    walk(child, node_id, effective, crew)
        for source_root in data.roots:
            walk(source_root)
        result = {"family": family, "profile": profile, "source": record, "nodes": nodes, "meshes": meshes, "scope": "Actual original buffers through the previously verified NIF loader. Static source pose, not captured game assembly."}
        (output / f"{family}-{profile}.json").write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(json.dumps({"families": len(families), "profiles": 3, "output": str(output)}))
