#!/usr/bin/env python3
"""The palette as surfaces: which generated texture each material wears, and how
big it is on the Machine.

`dieselpunk_palette.json` already owned the *numbers* of every Machine material.
This module is the one place that turns those numbers into something that
shades — in three different runtimes, from the same declaration:

* **The generator** (`generate_machines.py`) builds them flat, colour only. The
  shipped `.glb` carries geometry, UVs and a material *name*; it embeds no
  images. Eight 1024x1024 textures inside each of eleven meshes would be 130 MB
  of duplicated PNG in a git repository, which is not a trade worth making when
  the engine can share one copy.
* **Godot** gets a `StandardMaterial3D` per palette entry under
  `assets/machines/materials/`, wired to the Machine mesh by the `_subresources`
  material override in each `.glb.import`. One material, eleven Machines, one
  copy of each texture on disk and in VRAM.
* **The contact-sheet renderer** builds the same thing as Blender nodes, so the
  committed render is a picture of what the engine shows and not of a lookalike.

**UVs are in metres.** The generator box-projects every face at world scale, so
one UV unit is one metre everywhere, on every part of every Machine. A material's
`texture_scale_m` is then the only thing that decides texture density, it is
declared once, and a Machine that grows does not stretch its surface. That is
what "UVs that suit a procedural body" means here: no unwrapping, no per-part
layout to maintain, and no seam to hand-place.

    python3 tools/assets/machine_materials.py            # what it would write
    python3 tools/assets/machine_materials.py --write     # write it
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PALETTE_JSON = HERE / "dieselpunk_palette.json"

MATERIAL_DIR = REPO / "assets" / "machines" / "materials"
MACHINE_DIR = REPO / "assets" / "machines"
TEXTURE_DIR = REPO / "assets" / "generated" / "textures"

#: Godot resource path of the material for a palette entry.
GODOT_MATERIAL_DIR = "res://assets/machines/materials"
GODOT_TEXTURE_DIR = "res://assets/generated/textures"

#: The name of the one UV layer every Machine mesh carries. One layer, because
#: there is one thing to look up with it.
UV_LAYER = "UVMap"


def load() -> list[dict]:
    """The palette, in declaration order. Order is the generator's material order
    and therefore part of what makes the exported bytes reproducible."""
    return json.loads(PALETTE_JSON.read_text())["materials"]


def texture_path(entry: dict) -> Path | None:
    """Where the generated texture for a material lives, or None.

    A few palette entries wear no texture on purpose: a gauge bezel is 11 cm
    across and a glass face is 7 cm, so at any distance a player sees them from
    they are a coloured dot. Giving them a 1024x1024 map would cost VRAM to
    render nothing.
    """
    name = entry.get("texture")
    return None if not name else TEXTURE_DIR / f"{name}.png"


def texture_tint(entry: dict) -> tuple[float, float, float]:
    """What a material's texture is multiplied by. White unless declared.

    The generated set was made one map per surface, so a textured material's
    colour comes out of its texture and multiplying by `base_color` as well would
    square an already dark value and turn every Machine back into the black box
    this ticket is about. The exception is a material the set has no map the
    colour of — hazard striping is yellow and the nearest surface generated is
    grey tread plate — and that exception is declared, per material, in the
    palette.
    """
    tint = entry.get("texture_tint")
    return (1.0, 1.0, 1.0) if tint is None else tuple(tint[:3])


def missing_textures() -> list[str]:
    """Textures the palette names that `assets/generated/textures/` does not have."""
    return sorted({entry["texture"] for entry in load()
                   if entry.get("texture") and not texture_path(entry).exists()})


# ---------------------------------------------------------------------------
# Godot
# ---------------------------------------------------------------------------

def _texture_uid(entry: dict) -> str:
    """The `uid://` of a generated texture, read out of its `.import` sidecar.

    Godot writes a resource reference by uid and keeps the path only as a
    fallback, so a `.tres` that cites the path alone is rewritten the first time
    the editor opens it — which would make these generated files churn. Reading
    the uid the importer already assigned keeps them stable.
    """
    sidecar = texture_path(entry).with_suffix(".png.import")
    match = re.search(r'^uid="(uid://[^"]+)"', sidecar.read_text(), re.M)
    if match is None:
        raise RuntimeError(f"{sidecar}: no uid= line; let Godot import it first")
    return match.group(1)


def godot_resource(entry: dict) -> str:
    """One `StandardMaterial3D` as a `.tres`, hand-written rather than saved.

    Written as text because the alternative is driving the editor to produce a
    file nobody can review: this way the diff of a palette change is the palette
    change.
    """
    colour = entry["base_color"]
    path = texture_path(entry)
    load_steps = 2 if path else 1
    lines = [f'[gd_resource type="StandardMaterial3D" load_steps={load_steps} format=3]',
             ""]
    if path:
        lines += [f'[ext_resource type="Texture2D" uid="{_texture_uid(entry)}" '
                  f'path="{GODOT_TEXTURE_DIR}/{path.name}" id="1_albedo"]',
                  ""]
    lines += ["[resource]",
              f'resource_name = "{entry["name"]}"']
    if path:
        tint = texture_tint(entry)
        lines += [f"albedo_color = Color({tint[0]:g}, {tint[1]:g}, {tint[2]:g}, 1)",
                  'albedo_texture = ExtResource("1_albedo")',
                  # Linear mipmap filtering with anisotropy: these are tiled
                  # world-scale textures on surfaces seen at a grazing angle
                  # across a Factory, which is exactly the case point filtering
                  # turns into a shimmering mess.
                  "texture_filter = 5",
                  "uv1_scale = Vector3(%(s)g, %(s)g, %(s)g)"
                  % {"s": 1.0 / entry["texture_scale_m"]}]
    else:
        lines += [f"albedo_color = Color({colour[0]:g}, {colour[1]:g}, "
                  f"{colour[2]:g}, {colour[3]:g})"]
    lines += [f"metallic = {entry['metallic']:g}",
              "metallic_specular = 0.5",
              f"roughness = {entry['roughness']:g}",
              ""]
    return "\n".join(lines)


def godot_material_path(entry: dict) -> str:
    return f"{GODOT_MATERIAL_DIR}/{entry['name']}.tres"


def subresources_line(entry_names: list[str]) -> str:
    """The `_subresources=` line that points a `.glb.import` at the shared
    materials, in the form Godot's importer writes it.

    This is the mechanism that applies a texture to a Machine mesh. The glTF
    material is identity only — a name — and the engine substitutes the real
    surface for it on import, which is why eleven Machines can share one copy of
    eight textures.
    """
    materials = ", ".join(
        '"%s": {\n"use_external/enabled": true,\n"use_external/path": "%s"\n}'
        % (name, f"{GODOT_MATERIAL_DIR}/{name}.tres")
        for name in entry_names)
    return '_subresources={\n"materials": {\n%s\n}\n}' % materials


#: One `"Name": { ... }` entry inside a `_subresources` materials dictionary.
_MATERIAL_ENTRY = re.compile(
    r'"(?P<name>[A-Za-z0-9_]+)":\s*\{(?P<body>[^{}]*)\}', re.S)


def declared_overrides(text: str) -> dict[str, str]:
    """Which palette material each `.glb.import` sends to which resource.

    Parsed rather than compared as text, because **Godot normalises this block
    when it imports**: it sorts the names and adds a `use_external/fallback_path`
    beside every material the mesh actually uses. A byte comparison would call a
    correctly wired Machine wrong, and re-running the writer would undo the
    engine's own normalisation on every import — a diff that never settles.
    """
    span = _subresources_span(text)
    if span is None:
        return {}
    start, end = span
    found: dict[str, str] = {}
    for match in _MATERIAL_ENTRY.finditer(text[start:end]):
        body = match.group("body")
        enabled = re.search(r'"use_external/enabled":\s*(\w+)', body)
        path = re.search(r'"use_external/path":\s*"([^"]+)"', body)
        if enabled and enabled.group(1) == "true" and path:
            found[match.group("name")] = path.group(1)
    return found


def _subresources_span(text: str) -> tuple[int, int] | None:
    """Where the `_subresources=` value starts and ends, by brace balance."""
    match = re.search(r"^_subresources=", text, re.M)
    if match is None:
        return None
    open_brace = text.index("{", match.start())
    depth = 0
    for index in range(open_brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return (match.start(), index + 1)
    raise RuntimeError("unbalanced _subresources= value")


def patch_import_sidecar(text: str, entry_names: list[str]) -> str:
    """Point a `.glb.import` at the shared materials, if it does not already.

    Rewritten in place rather than regenerated, because the file also carries the
    resource uid and the import hash that Godot owns — throwing those away would
    change every Machine's uid and break every scene that referenced one. And
    left alone outright when the wiring is already right, so that an import pass
    and a `--write` do not fight over the formatting.
    """
    wanted = {name: f"{GODOT_MATERIAL_DIR}/{name}.tres" for name in entry_names}
    current = declared_overrides(text)
    if all(current.get(name) == path for name, path in wanted.items()):
        return text
    span = _subresources_span(text)
    if span is None:
        raise RuntimeError("no _subresources= line to replace")
    start, end = span
    return text[:start] + subresources_line(entry_names) + text[end:]


# ---------------------------------------------------------------------------
# Blender
# ---------------------------------------------------------------------------

def build_blender_materials(textured: bool = False) -> dict:
    """The palette as Blender materials, keyed by name. Imports bpy on demand.

    `textured=False` is what the generator exports: a Principled BSDF with the
    palette's own numbers and no image node anywhere, so the `.glb` carries no
    texture and comes out byte-identical on every run. `textured=True` wires the
    generated PNGs through a UV scale that matches `uv1_scale` on the Godot side,
    which is what the contact sheet is rendered with.
    """
    import bpy  # type: ignore

    built: dict = {}
    for entry in load():
        material = bpy.data.materials.new(entry["name"])
        # New materials arrive node-backed in Blender 4.x and later, and
        # `use_nodes` is slated for removal in 6.0, so it is not set here.
        tree = material.node_tree
        principled = tree.nodes["Principled BSDF"]
        principled.inputs["Base Color"].default_value = tuple(entry["base_color"])
        principled.inputs["Metallic"].default_value = entry["metallic"]
        principled.inputs["Roughness"].default_value = entry["roughness"]
        path = texture_path(entry) if textured else None
        if path is not None and path.exists():
            image = tree.nodes.new("ShaderNodeTexImage")
            image.image = bpy.data.images.load(str(path), check_existing=True)
            image.location = (-700, 200)
            mapping = tree.nodes.new("ShaderNodeMapping")
            scale = 1.0 / entry["texture_scale_m"]
            mapping.inputs["Scale"].default_value = (scale, scale, scale)
            mapping.location = (-900, 200)
            coords = tree.nodes.new("ShaderNodeUVMap")
            coords.uv_map = UV_LAYER
            coords.location = (-1100, 200)
            tint = tree.nodes.new("ShaderNodeMixRGB")
            tint.blend_type = 'MULTIPLY'
            tint.inputs["Fac"].default_value = 1.0
            tint.inputs["Color2"].default_value = texture_tint(entry) + (1.0,)
            tint.location = (-400, 200)
            tree.links.new(coords.outputs["UV"], mapping.inputs["Vector"])
            tree.links.new(mapping.outputs["Vector"], image.inputs["Vector"])
            tree.links.new(image.outputs["Color"], tint.inputs["Color1"])
            tree.links.new(tint.outputs["Color"], principled.inputs["Base Color"])
        built[entry["name"]] = material
    return built


# ---------------------------------------------------------------------------
# Writing the Godot side
# ---------------------------------------------------------------------------

def write(dry_run: bool = True) -> list[str]:
    """Write every material resource and point every Machine import at them."""
    entries = load()
    names = [e["name"] for e in entries]
    touched: list[str] = []
    for entry in entries:
        destination = MATERIAL_DIR / f"{entry['name']}.tres"
        body = godot_resource(entry)
        if destination.exists() and destination.read_text() == body:
            continue
        touched.append(str(destination.relative_to(REPO)))
        if not dry_run:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(body)
    for sidecar in sorted(MACHINE_DIR.glob("*.glb.import")):
        text = sidecar.read_text()
        patched = patch_import_sidecar(text, names)
        if patched == text:
            continue
        touched.append(str(sidecar.relative_to(REPO)))
        if not dry_run:
            sidecar.write_text(patched)
    return touched


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--write", action="store_true",
                        help="write the files instead of listing what would change")
    args = parser.parse_args(argv)
    absent = missing_textures()
    if absent:
        raise SystemExit(
            f"error: dieselpunk_palette.json names textures that are not in "
            f"assets/generated/textures: {', '.join(absent)}")
    touched = write(dry_run=not args.write)
    verb = "wrote" if args.write else "would change"
    if not touched:
        print("every material resource and import sidecar is already in sync")
    for path in touched:
        print(f"  {verb} {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
