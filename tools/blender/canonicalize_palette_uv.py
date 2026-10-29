"""Restore tiny rudder UV export drift without reserializing a GLB.

This is an explicit palette-only candidate guard, not a claim about the source
of Blender's observed float drift. It never writes the reference. Unsupported
or ambiguous layouts fail before a candidate is changed.
"""
import hashlib
import json
import math
from pathlib import Path
import struct


_MAX_UV_DELTA = 2e-8
_COMPONENT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
_VECTOR_WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def _integer(value, label, minimum=0):
    if type(value) is not int or value < minimum:
        raise ValueError(f"{label} must be an integer >= {minimum}")
    return value


def _item(items, index, label):
    index = _integer(index, label)
    if index >= len(items):
        raise ValueError(f"{label} is outside its array")
    return items[index]


def _layout_components(kind, size):
    if kind in _VECTOR_WIDTH:
        return tuple(range(0, size * _VECTOR_WIDTH[kind], size))
    if kind in ("MAT2", "MAT3", "MAT4"):
        width = int(kind[-1])
        column_stride = (width * size + 3) // 4 * 4
        return tuple(column * column_stride + row * size
                     for column in range(width) for row in range(width))
    raise ValueError("unsupported accessor type")


class _Glb:
    def __init__(self, raw):
        self.raw = raw
        if len(raw) < 12:
            raise ValueError("truncated GLB header")
        magic, version, length = struct.unpack_from("<4sII", raw)
        if magic != b"glTF" or version != 2 or length != len(raw):
            raise ValueError("expected a complete GLB 2 file")
        chunks = []
        cursor = 12
        while cursor < len(raw):
            if cursor + 8 > len(raw):
                raise ValueError("truncated GLB chunk header")
            size, kind = struct.unpack_from("<I4s", raw, cursor)
            start = cursor + 8
            end = start + size
            if size % 4 or end > len(raw):
                raise ValueError("invalid GLB chunk bounds/alignment")
            chunks.append((kind, start, end))
            cursor = end
        if not chunks or chunks[0][0] != b"JSON":
            raise ValueError("first GLB chunk must be JSON")
        if sum(kind == b"JSON" for kind, _, _ in chunks) != 1:
            raise ValueError("GLB must have one JSON chunk")
        binary = [(start, end) for kind, start, end in chunks if kind == b"BIN\0"]
        if len(binary) != 1:
            raise ValueError("GLB must have one embedded BIN chunk")
        try:
            self.doc = json.loads(raw[chunks[0][1]:chunks[0][2]].decode("utf-8"))
        except (UnicodeError, json.JSONDecodeError) as error:
            raise ValueError("invalid GLB JSON") from error
        if not isinstance(self.doc, dict):
            raise ValueError("GLB JSON root must be an object")
        buffers = self.doc.get("buffers", [])
        if len(buffers) != 1 or "uri" in buffers[0]:
            raise ValueError("only one embedded buffer is supported")
        self.bin_start, bin_end = binary[0]
        self.buffer_length = _integer(buffers[0].get("byteLength"), "buffer byteLength")
        if not 0 <= bin_end - self.bin_start - self.buffer_length <= 3:
            raise ValueError("BIN chunk does not match embedded buffer length")
        self.views = self.doc.get("bufferViews", [])
        self.accessors = self.doc.get("accessors", [])
        self.layouts = []
        self.opaque_sparse_ranges = []
        for index, accessor in enumerate(self.accessors):
            if "sparse" in accessor:
                # Unrelated original sail morph data stays opaque. Whole views
                # are protected, so no sparse decoding or interpretation occurs.
                self.opaque_sparse_ranges.extend(self.sparse_ranges(accessor))
                self.layouts.append(None)
            else:
                self.layouts.append(self.layout(index))

    def view(self, index):
        view = _item(self.views, index, "bufferView")
        if view.get("buffer") != 0:
            raise ValueError("bufferView must use the embedded buffer")
        if view.get("extensions"):
            raise ValueError("extended/compressed bufferViews are unsupported")
        offset = _integer(view.get("byteOffset", 0), "bufferView byteOffset")
        length = _integer(view.get("byteLength"), "bufferView byteLength", 1)
        if offset + length > self.buffer_length:
            raise ValueError("bufferView exceeds embedded buffer")
        return view, offset, length

    def layout(self, index, accessor=None):
        if accessor is None:
            accessor = _item(self.accessors, index, "accessor")
        if "sparse" in accessor or accessor.get("extensions"):
            raise ValueError("sparse/extended accessors are unsupported")
        view, view_offset, view_length = self.view(accessor.get("bufferView"))
        component = accessor.get("componentType")
        if component not in _COMPONENT_SIZE:
            raise ValueError("unsupported accessor componentType")
        size = _COMPONENT_SIZE[component]
        kind = accessor.get("type")
        components = _layout_components(kind, size)
        item_size = components[-1] + size
        if kind.startswith("MAT"):
            item_size = (item_size + 3) // 4 * 4
        count = _integer(accessor.get("count"), "accessor count", 1)
        offset = _integer(accessor.get("byteOffset", 0), "accessor byteOffset")
        stride = _integer(view.get("byteStride", item_size), "accessor stride", 1)
        if "byteStride" in view and (stride < 4 or stride > 252 or stride % 4):
            raise ValueError("invalid bufferView byteStride")
        if stride < item_size or stride % size or (view_offset + offset) % size:
            raise ValueError("invalid accessor component alignment/stride")
        if offset + (count - 1) * stride + item_size > view_length:
            raise ValueError("accessor exceeds bufferView")
        return {"accessor": accessor, "component": component, "kind": kind,
                "count": count, "size": size, "components": components,
                "stride": stride, "start": self.bin_start + view_offset + offset,
                "end": self.bin_start + view_offset + offset + (count - 1) * stride + item_size}

    def sparse_ranges(self, accessor):
        if accessor.get("extensions"):
            raise ValueError("extended sparse accessors are unsupported")
        component = accessor.get("componentType")
        if component not in _COMPONENT_SIZE:
            raise ValueError("unsupported sparse accessor componentType")
        size = _COMPONENT_SIZE[component]
        components = _layout_components(accessor.get("type"), size)
        item_size = components[-1] + size
        if accessor["type"].startswith("MAT"):
            item_size = (item_size + 3) // 4 * 4
        count = _integer(accessor.get("count"), "sparse accessor count", 1)
        sparse = accessor["sparse"]
        sparse_count = _integer(sparse.get("count"), "sparse count", 1)
        if sparse_count > count:
            raise ValueError("sparse count exceeds accessor count")
        ranges = []
        if "bufferView" in accessor:
            # Validate optional dense base storage without decoding sparse values.
            base = dict(accessor)
            del base["sparse"]
            self.layout(0, base)
            _, offset, length = self.view(base["bufferView"])
            ranges.append((self.bin_start + offset, self.bin_start + offset + length))
        for label in ("indices", "values"):
            part = sparse.get(label, {})
            view, offset, length = self.view(part.get("bufferView"))
            if "byteStride" in view:
                raise ValueError("sparse storage must be tightly packed")
            part_offset = _integer(part.get("byteOffset", 0), f"sparse {label} byteOffset")
            part_size = item_size
            alignment = size
            if label == "indices":
                index_component = part.get("componentType")
                if index_component not in (5121, 5123, 5125):
                    raise ValueError("unsupported sparse index componentType")
                part_size = alignment = _COMPONENT_SIZE[index_component]
            if (offset + part_offset) % alignment or part_offset + sparse_count * part_size > length:
                raise ValueError(f"sparse {label} exceeds/misaligns bufferView")
            ranges.append((self.bin_start + offset, self.bin_start + offset + length))
        return ranges

    def target_layout(self, index):
        layout = _item(self.layouts, index, "rudder accessor")
        if layout is None:
            raise ValueError("sparse rudder accessors are unsupported")
        return layout

    def packed(self, layout):
        return b"".join(self.raw[offset:offset + layout["size"]]
                        for offset in _component_offsets(layout))

    def rudder(self):
        nodes = self.doc.get("nodes", [])
        matches = [index for index, node in enumerate(nodes)
                   if node.get("name") == "rudder_blade"]
        if len(matches) != 1:
            raise ValueError("expected exactly one node named rudder_blade")
        mesh_index = nodes[matches[0]].get("mesh")
        mesh = _item(self.doc.get("meshes", []), mesh_index, "rudder mesh")
        if sum(node.get("mesh") == mesh_index for node in nodes) != 1:
            raise ValueError("rudder mesh is shared by multiple nodes")
        primitives = mesh.get("primitives", [])
        if len(primitives) != 1:
            raise ValueError("rudder mesh must have one primitive")
        primitive = primitives[0]
        if primitive.get("extensions") or primitive.get("targets"):
            raise ValueError("extended/morphing rudder primitives are unsupported")
        attributes = primitive.get("attributes", {})
        if not {"POSITION", "NORMAL", "TEXCOORD_0"}.issubset(attributes):
            raise ValueError("rudder must contain POSITION, NORMAL and TEXCOORD_0")
        layouts = {name: self.target_layout(index)
                   for name, index in attributes.items()}
        for name in ("POSITION", "NORMAL"):
            layout = layouts[name]
            if layout["component"] != 5126 or layout["kind"] != "VEC3":
                raise ValueError(f"rudder {name} must be float32 VEC3")
        uv = layouts["TEXCOORD_0"]
        if uv["component"] != 5126 or uv["kind"] != "VEC2" or uv["accessor"].get("normalized", False):
            raise ValueError("rudder TEXCOORD_0 must be unnormalized float32 VEC2")
        if any(layout["count"] != uv["count"] for layout in layouts.values()):
            raise ValueError("rudder vertex attribute counts differ")
        indices = self.target_layout(primitive.get("indices"))
        if indices["kind"] != "SCALAR" or indices["component"] not in (5121, 5123, 5125):
            raise ValueError("rudder indices must be unsigned integers")
        self.require_private_uv(attributes["TEXCOORD_0"], uv)
        return primitive, layouts, indices

    def require_private_uv(self, uv_index, uv):
        references = []
        for mesh in self.doc.get("meshes", []):
            for primitive in mesh.get("primitives", []):
                references.extend(primitive.get("attributes", {}).values())
                references.append(primitive.get("indices"))
                for target in primitive.get("targets", []):
                    references.extend(target.values())
        references.extend(skin.get("inverseBindMatrices") for skin in self.doc.get("skins", []))
        for animation in self.doc.get("animations", []):
            for sampler in animation.get("samplers", []):
                references.extend((sampler.get("input"), sampler.get("output")))
        if references.count(uv_index) != 1:
            raise ValueError("rudder UV accessor is shared")
        footprint = {byte for offset in _component_offsets(uv) for byte in range(offset, offset + 4)}
        for index, other in enumerate(self.layouts):
            if other is None or index == uv_index or other["end"] <= uv["start"] or other["start"] >= uv["end"]:
                continue
            if any(byte in footprint for offset in _component_offsets(other)
                   for byte in range(offset, offset + other["size"])):
                raise ValueError("rudder UV storage aliases another accessor")
        if any(start <= byte < end for start, end in self.opaque_sparse_ranges for byte in footprint):
            raise ValueError("rudder UV storage aliases unrelated sparse storage")
        for image in self.doc.get("images", []):
            if "bufferView" in image:
                _, offset, length = self.view(image["bufferView"])
                start = self.bin_start + offset
                if any(start <= byte < start + length for byte in footprint):
                    raise ValueError("rudder UV storage aliases an image")


def _component_offsets(layout):
    for vertex in range(layout["count"]):
        start = layout["start"] + vertex * layout["stride"]
        for offset in layout["components"]:
            yield start + offset


def _same_geometry(reference, candidate, reference_layout, candidate_layout, label):
    keys = ("component", "kind", "count")
    if any(reference_layout[key] != candidate_layout[key] for key in keys):
        raise ValueError(f"rudder {label} schema/count differs")
    if reference.packed(reference_layout) != candidate.packed(candidate_layout):
        raise ValueError(f"rudder {label} bytes/order differ")


def canonicalize_rudder_uv(reference: Path, candidate: Path) -> dict:
    """Restore only rudder_blade TEXCOORD_0 float bytes within 2e-8 drift.

    Both paths must be separate existing GLB 2 files. Geometry and vertex order
    must already match exactly. Every UV component is checked, and ambiguous,
    sparse rudder, compressed, shared or out-of-bounds storage is rejected.
    Unrelated sparse accessors remain opaque and their whole bufferViews are
    checked for overlap with the rudder UV footprint. Validation
    failures raise ValueError before any write. Return SHA-256 evidence and
    changed component/vertex counts. Identical UVs cause no file write.
    """
    reference = Path(reference)
    candidate = Path(candidate)
    if reference.resolve() == candidate.resolve() or reference.samefile(candidate):
        raise ValueError("reference and candidate must be separate files")
    baseline = _Glb(reference.read_bytes())
    exported = _Glb(candidate.read_bytes())
    reference_primitive, reference_attributes, reference_indices = baseline.rudder()
    candidate_primitive, candidate_attributes, candidate_indices = exported.rudder()
    if reference_attributes.keys() != candidate_attributes.keys():
        raise ValueError("rudder vertex attribute sets differ")
    if reference_primitive.get("mode", 4) != candidate_primitive.get("mode", 4):
        raise ValueError("rudder primitive modes differ")
    for name in ("POSITION", "NORMAL"):
        _same_geometry(baseline, exported, reference_attributes[name], candidate_attributes[name], name)
    _same_geometry(baseline, exported, reference_indices, candidate_indices, "indices")
    reference_uv = reference_attributes["TEXCOORD_0"]
    candidate_uv = candidate_attributes["TEXCOORD_0"]
    if reference_uv["count"] != candidate_uv["count"]:
        raise ValueError("rudder UV vertex counts differ")
    changed_vertices = set()
    patches = []
    maximum_delta = 0.0
    for component, (source, destination) in enumerate(zip(_component_offsets(reference_uv),
                                                       _component_offsets(candidate_uv))):
        original = baseline.raw[source:source + 4]
        current = exported.raw[destination:destination + 4]
        original_float = struct.unpack("<f", original)[0]
        current_float = struct.unpack("<f", current)[0]
        if not math.isfinite(original_float) or not math.isfinite(current_float):
            raise ValueError("rudder UV contains a non-finite component")
        delta = abs(original_float - current_float)
        maximum_delta = max(maximum_delta, delta)
        if delta > _MAX_UV_DELTA:
            raise ValueError(f"rudder UV component {component} delta {delta!r} exceeds 2e-8")
        if original != current:
            patches.append((destination, original))
            changed_vertices.add(component // 2)
    result = bytearray(exported.raw)
    for offset, original in patches:
        result[offset:offset + 4] = original
    before_sha = hashlib.sha256(exported.raw).hexdigest()
    after_sha = hashlib.sha256(result).hexdigest()
    if patches:
        # Recheck before writing: a concurrently replaced export must not be overwritten.
        if candidate.read_bytes() != exported.raw:
            raise ValueError("candidate changed during UV validation")
        candidate.write_bytes(result)
        if candidate.read_bytes() != result:
            raise OSError("candidate write verification failed")
    return {"node": "rudder_blade", "changed_components": len(patches),
            "changed_vertices": len(changed_vertices), "max_abs_delta": maximum_delta,
            "candidate_sha256_before": before_sha, "candidate_sha256_after": after_sha,
            "reference_sha256": hashlib.sha256(baseline.raw).hexdigest(),
            "byte_length": len(result), "no_op": not patches}
