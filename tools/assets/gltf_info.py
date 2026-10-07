#!/usr/bin/env python3
"""Report what a glTF 2.0 file actually contains, using only the standard library.

A deliberately dumb reader: it parses the JSON chunk of a `.glb` (or a `.gltf`)
and answers the questions the asset pipeline cares about — how many skeleton
roots, how many images, which animations, how big the thing is, which bone names
are present. It knows nothing about Blender, so it can be trusted to check
Blender's output.

    python3 tools/assets/gltf_info.py path/to/model.glb
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def read_gltf_json(path: str | Path) -> dict:
    """The glTF JSON document, whether the file is .gltf or binary .glb."""
    data = Path(path).read_bytes()
    if len(data) >= 4 and struct.unpack_from("<I", data, 0)[0] == GLB_MAGIC:
        _, _, total = struct.unpack_from("<III", data, 0)
        offset = 12
        while offset < min(total, len(data)):
            length, kind = struct.unpack_from("<II", data, offset)
            body = data[offset + 8: offset + 8 + length]
            if kind == CHUNK_JSON:
                return json.loads(body.decode("utf-8"))
            offset += 8 + length + (-length % 4)
        raise ValueError(f"{path}: no JSON chunk in glb")
    return json.loads(data.decode("utf-8"))


#: glTF component types that can index a triangle list.
_INDEX_FORMAT = {5121: "B", 5123: "H", 5125: "I"}


def read_glb(path: str | Path) -> tuple[dict, bytes]:
    """The JSON document *and* the binary buffer of a `.glb`.

    `read_gltf_json` answers questions about the declaration; this one is for the
    questions only the vertex data can answer — what the silhouette is, whether
    the UVs are the size they claim to be. Still standard library only, so it
    stays a trustworthy second opinion on Blender's output.
    """
    data = Path(path).read_bytes()
    if struct.unpack_from("<I", data, 0)[0] != GLB_MAGIC:
        raise ValueError(f"{path}: not a binary glTF")
    _, _, total = struct.unpack_from("<III", data, 0)
    doc: dict | None = None
    binary = b""
    offset = 12
    while offset < min(total, len(data)):
        length, kind = struct.unpack_from("<II", data, offset)
        body = data[offset + 8: offset + 8 + length]
        if kind == CHUNK_JSON:
            doc = json.loads(body.decode("utf-8"))
        elif kind == CHUNK_BIN:
            binary = bytes(body)
        offset += 8 + length + (-length % 4)
    if doc is None:
        raise ValueError(f"{path}: no JSON chunk")
    return doc, binary


def _read_vectors(doc: dict, binary: bytes, index: int, components: int) -> list[tuple]:
    accessor = doc["accessors"][index]
    view = doc["bufferViews"][accessor["bufferView"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", 0) or components * 4
    layout = f"<{components}f"
    return [struct.unpack_from(layout, binary, start + i * stride)
            for i in range(accessor["count"])]


def mesh_primitives(path: str | Path) -> list[dict]:
    """Every triangle-list primitive as plain lists: positions, UVs, indices.

    One dict per primitive with `mesh` (the mesh's name), `positions`, `uvs`
    (empty when the primitive carries none) and `indices`.
    """
    doc, binary = read_glb(path)
    out: list[dict] = []
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            attributes = prim.get("attributes", {})
            if prim.get("mode", 4) != 4 or "POSITION" not in attributes:
                continue
            positions = _read_vectors(doc, binary, attributes["POSITION"], 3)
            uvs = (_read_vectors(doc, binary, attributes["TEXCOORD_0"], 2)
                   if "TEXCOORD_0" in attributes else [])
            if "indices" in prim:
                accessor = doc["accessors"][prim["indices"]]
                code = _INDEX_FORMAT[accessor["componentType"]]
                view = doc["bufferViews"][accessor["bufferView"]]
                start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
                indices = list(struct.unpack_from(
                    f"<{accessor['count']}{code}", binary, start))
            else:
                indices = list(range(len(positions)))
            out.append({"mesh": mesh.get("name", ""), "positions": positions,
                        "uvs": uvs, "indices": indices})
    return out


def _child_nodes(doc: dict) -> set[int]:
    children = set()
    for node in doc.get("nodes", []):
        children.update(node.get("children", []))
    return children


def skeleton_roots(doc: dict) -> list[str]:
    """Names of joint nodes that have no joint parent — the rig's root bones.

    More than one is the classic FBX breakage: Godot and most retargeting tools
    expect a single root.
    """
    joints: set[int] = set()
    for skin in doc.get("skins", []):
        joints.update(skin.get("joints", []))
    parent_of: dict[int, int] = {}
    for index, node in enumerate(doc.get("nodes", [])):
        for child in node.get("children", []):
            parent_of[child] = index
    nodes = doc.get("nodes", [])
    roots = [j for j in sorted(joints) if parent_of.get(j) not in joints]
    return [nodes[j].get("name", f"node{j}") for j in roots]


def bone_names(doc: dict) -> list[str]:
    joints: set[int] = set()
    for skin in doc.get("skins", []):
        joints.update(skin.get("joints", []))
    nodes = doc.get("nodes", [])
    return [nodes[j].get("name", f"node{j}") for j in sorted(joints)]


def scene_roots(doc: dict) -> list[str]:
    scene = doc.get("scenes", [{}])[doc.get("scene", 0)] if doc.get("scenes") else {}
    nodes = doc.get("nodes", [])
    return [nodes[i].get("name", f"node{i}") for i in scene.get("nodes", [])]


def animation_names(doc: dict) -> list[str]:
    return [a.get("name", "") for a in doc.get("animations", [])]


def animation_targets(doc: dict) -> set[str]:
    """Names of the nodes any animation channel drives."""
    nodes = doc.get("nodes", [])
    targets = set()
    for animation in doc.get("animations", []):
        for channel in animation.get("channels", []):
            node = channel.get("target", {}).get("node")
            if node is not None:
                targets.add(nodes[node].get("name", f"node{node}"))
    return targets


def image_count(doc: dict) -> int:
    return len(doc.get("images", []))


def material_names(doc: dict) -> list[str]:
    return [m.get("name", "") for m in doc.get("materials", [])]


def uv_layer_count(doc: dict) -> int:
    """Highest number of TEXCOORD sets on any mesh primitive."""
    highest = 0
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            sets = sum(1 for k in prim.get("attributes", {}) if k.startswith("TEXCOORD_"))
            highest = max(highest, sets)
    return highest


def position_extents(doc: dict) -> tuple[list[float], list[float]]:
    """Min and max POSITION across every mesh, from accessor bounds."""
    accessors = doc.get("accessors", [])
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            index = prim.get("attributes", {}).get("POSITION")
            if index is None:
                continue
            acc = accessors[index]
            for axis in range(3):
                lo[axis] = min(lo[axis], acc["min"][axis])
                hi[axis] = max(hi[axis], acc["max"][axis])
    return lo, hi


def node_transform_is_identity(doc: dict, name: str) -> bool:
    for node in doc.get("nodes", []):
        if node.get("name") == name:
            if "matrix" in node:
                identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
                return all(abs(a - b) < 1e-5 for a, b in zip(node["matrix"], identity))
            rot = node.get("rotation", [0, 0, 0, 1])
            scale = node.get("scale", [1, 1, 1])
            trans = node.get("translation", [0, 0, 0])
            return (all(abs(v) < 1e-5 for v in rot[:3]) and abs(abs(rot[3]) - 1) < 1e-5
                    and all(abs(s - 1) < 1e-4 for s in scale)
                    and all(abs(t) < 1e-5 for t in trans))
    raise KeyError(f"no node named {name!r}")


def summary(path: str | Path) -> dict:
    doc = read_gltf_json(path)
    lo, hi = position_extents(doc)
    size = [round(h - l, 4) for l, h in zip(lo, hi)] if lo[0] != float("inf") else None
    return {
        "file": str(path),
        "generator": doc.get("asset", {}).get("generator"),
        "version": doc.get("asset", {}).get("version"),
        "scene_roots": scene_roots(doc),
        "skeleton_roots": skeleton_roots(doc),
        "bone_count": len(bone_names(doc)),
        "bones": bone_names(doc),
        "animations": animation_names(doc),
        "animation_targets": sorted(animation_targets(doc)),
        "materials": material_names(doc),
        "images": image_count(doc),
        "uv_layers": uv_layer_count(doc),
        "mesh_extents_xyz": size,
        "height_y": size[1] if size else None,
    }


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        print(json.dumps(summary(arg), indent=2))
