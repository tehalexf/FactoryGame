#!/usr/bin/env python3
"""Convert purchased set-dressing props into the GLBs the game loads at runtime.

Driven by ``tools/assets/convert_props.sh``; that script is the entry point and
this file is the catalogue — which prop comes from which pack, and why.

The licence is the whole shape of this, exactly as it is for
``convert_weapons.py``'s sibling ``convert_weapons.sh``:

* the input lives in ``assets_licensed/``, gitignored, with a ``.gdignore`` so
  Godot's importer never walks it;
* **the output is gitignored too.** A converted GLB is a derivative of a
  non-redistributable asset and is exactly as forbidden as the source. The
  licence guard blocks it and that guard is correct;
* so the game loads the result **at runtime, from a path that may legitimately
  not exist**, and draws self-authored stand-ins when it does not. See
  ``game/set_dressing.gd``.

Nothing here feeds a model. Two of these licences forbid machine-learning use of
their assets outright (docs/LICENSED_ASSETS.md) and this is a JSON rewriter: it
reads glTF chunks, retints a material factor and writes the chunks back.

── What the conversion actually does ────────────────────────────────────────

**heyheythere — the pack this ticket mostly runs on.** It is on a 2 m grid with
1 unit to the metre, which is *our* grid, so its props sit on our tiles without a
scale factor or a fudge. All 213 share one 2048 atlas plus a glow map, referenced
out of each GLB by a relative URI (``../textures/atlas.png``). Shipping that
reference forward would make Godot decode a 2048 square per prop and hold forty
copies of one image in VRAM, so the images are **stripped out of every GLB** and
the two PNGs are copied once into the output directory. ``SetDressing`` builds a
single shared material from them and overrides it onto every prop, which is also
why the whole set draws in a handful of calls.

Vertex colours carry baked occlusion and are kept; the shared material multiplies
them into the albedo, which is what the pack's own Godot addon does.

**lukami-ch and shapita — the far yard only.** Both are cleaner and more modern
than the Dieselpunk palette (docs/LICENSED_ASSETS.md says so about Shapita in as
many words), so they are used where that does not show: big silhouettes out past
the buildable edge, small in frame and behind the depth fog. Their textures are
embedded (lukami) or absent (shapita, flat colours), so those files are copied
through with nothing but a retint.

**The retint** is the one artistic change. Every pack is lit and coloured to look
good on a white studio backdrop; ours is an ochre smog at late afternoon. A
multiplier on ``baseColorFactor`` darkens and desaturates toward
``dieselpunk_palette.json`` without touching the geometry or the maps — the same
move ``convert_weapons.sh`` makes on the arms, for the same reason.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import shutil
import struct
import sys

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942

# ── The catalogue ────────────────────────────────────────────────────────────
#
# `pack` names a directory under the quarantine root; `source` is the path inside
# it. The key is the id the game asks for, and it is also the file name written
# out, so `game/set_dressing.gd` and this table are the two halves of one name.

HEYHEYTHERE = "heyheythere/low-poly-industrial-facility"
LUKAMI = "lukami-ch/low-poly-industrial-pack-60"
SHAPITA = "shapita/factory-line-86-assets-v1.5"

# Ground clutter: the things that make a yard look worked in rather than mown.
# Everything here is roughly tile-sized or smaller, because it is scattered one
# per tile and a prop wider than 2 m would overhang its neighbour.
CLUTTER = [
    "pallet",
    "pallet_boxes",
    "pallet_sacks",
    "pallet_stack",
    "crate_large",
    "crate_small",
    "cardboard_heap",
    "drum_steel_blue",
    "drum_steel_red",
    "drum_steel_open",
    "drum_plastic",
    "gas_cylinder_rack",
    "ibc_tote",
    "cable_drum",
    "cable_coil",
    "tyre_stack",
    "debris_pile",
    "rubble_spread",
    "oil_spill",
    "wheelie_bin",
    "waste_skip",
    "hand_truck",
    "pallet_jack",
    "work_light_tripod",
    "tool_chest",
    "workbench",
    "shelving_steel",
    "racking_bay_loaded",
    "traffic_cone",
    "spill_kit",
]

# Runs: props placed end to end in a line rather than scattered. A pipe run along
# the ground and a catwalk over it are most of what reads as "industrial" at a
# glance, and they are the thing a flat plane has none of.
RUNS = [
    "pipe_straight",
    "pipe_elbow",
    "pipe_rack",
    "pipe_lagged",
    "pipe_riser",
    "tray_straight",
    "catwalk_straight",
    "catwalk_support",
    "railing_2m",
    "mesh_fence",
    "jersey_barrier",
    "bollard",
]

# Landmarks: tall things, placed sparsely, that give the eye somewhere to go and
# tell a player how far away the edge of the yard is.
LANDMARKS = [
    "tank_vertical",
    "tank_horizontal",
    "pressure_vessel",
    "hopper",
    "lamp_high_bay",
    "floodlight_wall",
]

CATALOGUE: dict[str, dict] = {}
for _name in CLUTTER + RUNS + LANDMARKS:
    CATALOGUE[_name] = {"pack": HEYHEYTHERE, "source": f"glb/{_name}.glb"}

# The far yard. Lukami's floodlight is a free-standing mast, which heyheythere has
# no equivalent of — its lights are all wall or ceiling fittings — and a mast is
# what a perimeter wants. Its silo and water tank, and Shapita's container and
# yard light, are skyline: they are only ever seen past the Map edge through fog.
CATALOGUE.update(
    {
        "yard_floodlight": {"pack": LUKAMI, "source": "Smooth/GLB/Floodlight.glb"},
        "yard_silo": {"pack": LUKAMI, "source": "Smooth/GLB/Storage_Silo.glb"},
        "yard_water_tank": {"pack": LUKAMI, "source": "Smooth/GLB/Water_Tank.glb"},
        "yard_container": {"pack": SHAPITA, "source": "GLB/72_Shipping_Container.glb"},
        "yard_light": {"pack": SHAPITA, "source": "GLB/75_Yard_Light.glb"},
    }
)

# How far each pack is pulled toward the Dieselpunk palette, as a multiplier on
# `baseColorFactor`. heyheythere's atlas is already grimy and wants only a stop of
# darkening; the other two are clean modern industrial and want a good deal more,
# with the blue end pulled down hardest because the sky is ochre and nothing in
# this world is cold except the fill light.
TINTS = {
    HEYHEYTHERE: [0.80, 0.76, 0.70, 1.0],
    LUKAMI: [0.70, 0.66, 0.58, 1.0],
    SHAPITA: [0.64, 0.61, 0.55, 1.0],
}

# The atlas the heyheythere props share, copied once beside them. The game builds
# one material from these and overrides it onto every prop in the pack.
SHARED_TEXTURES = {
    HEYHEYTHERE: ["textures/atlas.png", "textures/atlas_glow.png"],
}


# ── glTF surgery ─────────────────────────────────────────────────────────────


def read_glb(path: pathlib.Path) -> tuple[dict, bytes]:
    """The JSON chunk and the binary chunk of a .glb, as they are on disk."""
    data = path.read_bytes()
    magic, version, _length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise ValueError(f"{path} is not a glTF 2.0 binary")
    offset = 12
    document: dict | None = None
    binary = b""
    while offset + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        body = data[offset + 8 : offset + 8 + chunk_length]
        if chunk_type == JSON_CHUNK:
            document = json.loads(body)
        elif chunk_type == BIN_CHUNK:
            binary = body
        offset += 8 + chunk_length
    if document is None:
        raise ValueError(f"{path} carries no JSON chunk")
    return document, binary


def write_glb(path: pathlib.Path, document: dict, binary: bytes) -> None:
    """Pack a document and its buffer back into a .glb, chunks padded to four."""
    json_bytes = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)
    chunks = [(JSON_CHUNK, json_bytes)]
    if binary:
        padded = binary + b"\0" * (-len(binary) % 4)
        chunks.append((BIN_CHUNK, padded))
    total = 12 + sum(8 + len(body) for _, body in chunks)
    out = bytearray(struct.pack("<III", 0x46546C67, 2, total))
    for chunk_type, body in chunks:
        out += struct.pack("<II", len(body), chunk_type)
        out += body
    path.write_bytes(bytes(out))


def strip_images(document: dict) -> None:
    """Drop every image, texture and sampler, and every reference to one.

    The heyheythere props all wear one atlas. Carrying it inside forty GLBs would
    mean forty decodes and forty copies in VRAM of the same 2048 square, so the
    reference comes out here and `SetDressing` puts one shared material back.
    """
    for material in document.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        pbr.pop("baseColorTexture", None)
        pbr.pop("metallicRoughnessTexture", None)
        for slot in ("emissiveTexture", "normalTexture", "occlusionTexture"):
            material.pop(slot, None)
        # An emissive factor with no map behind it makes every surface glow.
        material.pop("emissiveFactor", None)
    for key in ("images", "textures", "samplers"):
        document.pop(key, None)


def retint(document: dict, tint: list[float]) -> None:
    """Multiply every material's base colour by `tint`, defaulting it to white."""
    for material in document.get("materials", []):
        pbr = material.setdefault("pbrMetallicRoughness", {})
        base = pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0])
        pbr["baseColorFactor"] = [
            round(base[channel] * tint[channel], 6) for channel in range(4)
        ]


def bounds_of(document: dict) -> tuple[list[float], list[float]]:
    """The model's axis-aligned bounds, out of the POSITION accessors' own min/max.

    Read rather than assumed: the packs disagree about origins — a high-bay light
    hangs below its pivot, a roof truss bears on its own zero — so where a prop
    sits relative to the ground is a fact to be measured, and `SetDressing` uses
    it to put a prop's feet on the floor instead of its origin.
    """
    accessors = document.get("accessors", [])
    low = [float("inf")] * 3
    high = [float("-inf")] * 3
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            index = primitive.get("attributes", {}).get("POSITION")
            if index is None:
                continue
            accessor = accessors[index]
            for axis in range(3):
                low[axis] = min(low[axis], float(accessor["min"][axis]))
                high[axis] = max(high[axis], float(accessor["max"][axis]))
    if low[0] == float("inf"):
        return [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]
    return [round(v, 4) for v in low], [round(v, 4) for v in high]


def convert(licensed_root: pathlib.Path, out_dir: pathlib.Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, dict] = {}
    copied_textures: set[str] = set()
    missing_packs: set[str] = set()

    for prop_id, entry in CATALOGUE.items():
        pack = entry["pack"]
        source = licensed_root / pack / entry["source"]
        if not source.exists():
            missing_packs.add(pack)
            continue
        document, binary = read_glb(source)
        if pack in SHARED_TEXTURES:
            strip_images(document)
        retint(document, TINTS[pack])
        low, high = bounds_of(document)
        write_glb(out_dir / f"{prop_id}.glb", document, binary)
        manifest[prop_id] = {"pack": pack, "source": entry["source"], "min": low, "max": high}

        for relative in SHARED_TEXTURES.get(pack, []):
            name = pathlib.Path(relative).name
            if name not in copied_textures:
                shutil.copyfile(licensed_root / pack / relative, out_dir / name)
                copied_textures.add(name)

    for pack in sorted(missing_packs):
        print(f"note: {licensed_root / pack} is absent; its props keep their stand-ins.",
              file=sys.stderr)

    # The manifest is how the game knows what it got without stat-ing the
    # directory, and it is the only committed-shaped record of a conversion that
    # may never be committed. It is written even when empty, so "the script ran
    # and the packs were not there" is distinguishable from "the script never ran".
    (out_dir / "props.json").write_text(
        json.dumps({"props": manifest}, indent=1, sort_keys=True) + "\n"
    )
    return len(manifest)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--licensed-root", required=True, type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    arguments = parser.parse_args()
    written = convert(arguments.licensed_root, arguments.out)
    print(f"wrote {written} prop(s) to {arguments.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
