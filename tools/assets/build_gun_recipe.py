#!/usr/bin/env python3
"""The Build Gun's geometry and its two takes: what a tool looks like in frame.

The one held object this project authored itself. Every weapon frame arrives from
a purchased pack, so its model is a derivative of something non-redistributable
and is gitignored; this is built out of `machine_parts` and
`dieselpunk_palette.json` and nothing else, so **it is committed and every clone
has it** — which is the whole of what #64 bought over #28's two placeholder boxes.

**Reading as a tool rather than as a gun is the entire job**, and it is the same
argument `machine_recipes` makes about a Machine's silhouette one scale down. A
holster exists so that a player who pressed `B` knows they pressed it, and a
boxy body with a barrel on the front is what every weapon in the game already
is. So the form commits to three cues, none of which any firearm has:

| Cue | Why a gun cannot have it |
|---|---|
| a **flared** emitter that opens out towards the muzzle | a barrel is a tube of constant bore; nothing that fires a projectile widens at the end |
| a **stock canister down the left flank**, with a sight glass in its end | a magazine sits in line under the action; a cylinder bolted along the side, read end-on through glass, is a thing that holds material |
| a **hazard-striped collar** at the emitter throat | it is the same fitting a Machine wears at a declared port, so the tool reads as factory plant rather than as ordnance |

plus the emissive lens and rail, which are the one part of #29's placeholder worth
keeping literally.

**The rail is cyan and deliberately not the hologram's green.** CLAUDE.md recorded
#29's rail as being "in the hologram's own colour"; the code it describes used
`Color(0.35, 0.80, 1.00)`, a cool blue, and the colour matters rather than the
sentence. `HOLOGRAM_ALLOWED` is green, the hologram is on screen in every single
frame this tool is, and #52 threw away a green ore mark for exactly that reason —
three greens in one frame, where the one that is supposed to mean "click here"
has to win. A cyan rail on the tool and a green ghost on the ground are two marks
a player can tell apart.

**Axes are the camera's, not the world's.** A Machine recipe builds about the
centre of a footprint on the ground; a viewmodel is built about the **eye**,
because that is the space a converted viewmodel arrives in and
`WeaponViewmodel` applies no offset to a model it loaded. In Blender's terms,
with `export_yup=True` doing the one axis change in the pipeline:

    +X  right        -> glTF +X   right
    +Y  forward      -> glTF -Z   the way the camera looks
    +Z  up           -> glTF +Y   up

So a positive `Y` here is *away from the viewer*, which is the axis that has
already cost this project two wrong fixes (`convert_weapons.sh`, and the
`--offset` table in it). The framing is measured against the frustum by
`generate_build_gun.py` on every run and the generator refuses a model that
leaves the frame, so it cannot be argued about again.
"""

from __future__ import annotations

# `machine_parts` is imported **inside** `build` rather than here, and that is
# deliberate: it needs Blender's `bmesh`, and the declarations in this file —
# which materials are used, how long the takes are, where the grip sits — are
# exactly what `tools/assets/tests/test_build_gun.py` has to read in a clone with
# no Blender at all. A module-level import would make the geometry's *dependency*
# decide whether the *declaration* is readable.

#: The one material in this file that is not a `dieselpunk_palette.json` entry,
#: and it is a **light** rather than a surface. The palette is the surfaces of
#: interwar heavy industry — cast iron, paint over primer, soot — and it has no
#: emissive entry because no Machine emits anything. A projector lens does.
#: `tools/assets/tests/test_build_gun.py` asserts the exported file carries the
#: palette's names and this one, so a third material cannot creep in unnoticed.
EMISSIVE_MATERIAL = "ProjectorCyan"

#: Linear RGB and the emission strength that goes with it. #29's own rail value.
#:
#: **The strength is low and a render is why.** At 3.0 every channel of
#: `(0.35, 0.80, 1.00)` lands above 1 after the scene's filmic tonemap and glow,
#: so the lens came out as a blown white disc with no hue in it at all — the
#: brightest thing in frame, and the one colour decision this model actually
#: makes thrown away. That is #52's finding from the other end: a colour picked
#: against the wrong background, except that here the background is the
#: *exposure* rather than the ground. At 1.1 the blue channel peaks just over 1,
#: so the lens reads as a lit cyan lamp against a palette that runs 0.055 to 0.14
#: and the hue survives.
EMISSIVE_COLOUR = (0.35, 0.80, 1.00, 1.0)
EMISSIVE_STRENGTH = 1.1

#: Where the grip sits relative to the eye, in metres: right, forward, down.
#: Right of centre because the tool is held in the right hand, and below the eye
#: because a held object that crosses the horizon hides what the player is aiming
#: at. These are the three numbers the frustum measurement is actually about, and
#: **all three were moved by looking at a render rather than by reasoning.**
#:
#: The first pair was `(0.205, 0.255, -0.255)`, which passed the frustum
#: measurement and was wrong twice over in the picture. At 25 cm the tool is close
#: enough to the eye to fill a quarter of the frame — the purchased arms sit at
#: about 50 cm and read as something held rather than something pressed against
#: the lens — and that near, 20 cm of rightward offset and 25 cm of drop throw it
#: into the **bottom-right corner, behind the hotbar**, which is the one piece of
#: furniture guaranteed to be on screen at the same time as this model: a Build
#: Gun is only ever in frame in build mode, and build mode is when the Machine
#: picker is drawn. #48's lesson in a new place — *a mark that is behind something
#: looks exactly like a mark that was never drawn* — and the frustum check could
#: never have caught it, because the hotbar is not geometry.
#:
#: So the tool sits further out, nearer the middle and higher: the emitter clears
#: the top of the hotbar and the grip runs off the bottom edge, which is where a
#: viewmodel's grip belongs. It went out **twice** — 42 cm still filled a third of
#: the frame with the hopper drum, because apparent size is the thing a frustum
#: half-angle does not report and only a picture does. At 57 cm the tool reads as
#: something held at arm's length, which is what the purchased arms read as.
GRIP = (0.150, 0.660, -0.175)

#: How the tool is held, in degrees: yaw turns the muzzle across the view, pitch
#: drops it.
#:
#: **Square to the view is the one pose that hides everything this model is for.**
#: The first version had none of this and the render showed why: a tool pointing
#: straight down the camera axis presents its *back end*, so the flared emitter
#: was a small disc 1 m away pointing away from the viewer, the hazard collar was
#: edge-on, and the hopper drum — the only cue with any width across the view —
#: was left carrying the whole silhouette on its own, which reads as a cylinder
#: and therefore as a magazine. Three cues, two of them invisible.
#:
#: The turn is **outward and small**, which took one more render to get right.
#: Turned *inward* — muzzle toward the middle of the screen — the tool shows the
#: player the inside of its own emitter, which is a disc and tells them nothing;
#: the three-quarter view that shows the flank comes free from the tool being
#: held to the **right of the eye** in the first place, so the yaw only has to
#: stop the body being exactly parallel. The nose-down is what keeps the mouth
#: off the horizon, where it would sit on top of whatever the player is aiming
#: at.
REST_YAW_DEGREES = 5.0
REST_PITCH_DEGREES = -7.0

#: How long the body runs forward of the grip, and how far the emitter extends
#: past that. The whole tool is about 46 cm nose to tail, which is a hand tool.
BODY_LENGTH = 0.30
EMITTER_LENGTH = 0.20


def build(assembly) -> None:
    """Assemble the Build Gun into `assembly`, about the eye at the origin."""
    gx, gy, gz = GRIP
    body_start = gy
    body_end = gy + BODY_LENGTH
    body_mid = (body_start + body_end) / 2.0
    axis = gz + 0.055  # the bore line, a little above the grip's top

    # Imported here rather than at module scope — see the note at the top — and
    # handed down rather than stashed in a global, so every helper's dependency
    # is in its signature.
    import machine_parts as parts

    _grip(parts, assembly, gx, gy, gz)
    _body(parts, assembly, gx, body_mid, body_start, body_end, axis)
    _canister(parts, assembly, gx, body_start, body_end, axis)
    _emitter(parts, assembly, gx, body_end, axis)
    _dial(parts, assembly, gx, body_mid, axis)
    _rail(parts, assembly, gx, body_start, body_end, axis)


def _grip(parts, assembly, gx: float, gy: float, gz: float) -> None:
    """A raked pistol grip under a short trigger guard.

    Raked rather than vertical with `prism`, because a vertical grip under a
    horizontal body is the outline of a pistol and a raked one under a drum is
    the outline of a caulking gun.
    """
    assembly.add("OliveDrab", parts.prism(
        bottom_center=(gx, gy - 0.035, gz - 0.085),
        bottom_size=(0.052, 0.062),
        top_center=(gx, gy + 0.012, gz + 0.045),
        top_size=(0.058, 0.088),
    ))
    # The guard: a flat strap forward of the grip, which is also what stops the
    # grip reading as the whole of the tool's lower outline.
    assembly.add("CastIron", parts.box(
        (0.030, 0.088, 0.016), (gx, gy + 0.062, gz - 0.028), chamfer=0.004))
    assembly.add("OiledSteel", parts.box(
        (0.016, 0.022, 0.044), (gx, gy + 0.030, gz + 0.004), chamfer=0.003))


def _body(parts, assembly, gx: float, body_mid: float,
          body_start: float, body_end: float, axis: float) -> None:
    """The painted housing, and the frame rails down its flanks.

    `OliveDrab` is the palette's stated silhouette colour and is what every
    Machine housing in the game wears, which is the point: the thing in your
    hands came out of the same works as the thing you are building with it.
    """
    length = body_end - body_start
    assembly.add("OliveDrab", parts.box(
        (0.098, length, 0.112), (gx, body_mid, axis), chamfer=0.010))
    # Two cast flanks, proud of the paint, so the body has an edge in profile
    # rather than being one flat slab of colour.
    for side in (-1, 1):
        assembly.add("CastIron", parts.box(
            (0.012, length * 0.86, 0.070),
            (gx + side * 0.055, body_mid, axis), chamfer=0.004))
    # A bolted end plate at the breech, which closes the outline off behind the
    # hopper instead of letting the body taper away into the arm.
    assembly.add("WeldedSteel", parts.box(
        (0.104, 0.022, 0.118), (gx, body_start + 0.011, axis), chamfer=0.006))


def _canister(parts, assembly, gx: float, body_start: float,
              body_end: float, axis: float) -> None:
    """The stock canister, bolted **along the left flank** with its gauge aft.

    The cue that says *this thing carries material*, and its placement is the
    most-revised decision in the file — three renders, and each one was the same
    lesson from a different angle. It began as a drum lying **athwart the top**,
    which is a fine silhouette on a Machine and a bad one in a hand: a viewmodel
    is seen from *behind*, so anything across the tool at the near end is the
    largest object in frame and hides everything beyond it. Over the body's
    middle it stood directly in front of the emitter; moved back to the breech it
    stopped hiding the emitter and started filling a third of the screen on its
    own, reading as a drum magazine — which is precisely the thing this
    silhouette exists not to be.

    What a first-person view actually shows is the **flank**, which is why every
    shipped viewmodel is long along the line of sight with its detail down the
    side. So the canister runs *with* the body instead of across it: nothing is
    occluded, the sight glass faces the player because the aft end does, and the
    outline it adds is a bulge on one side rather than a barrel in the way.
    """
    length = (body_end - body_start) * 0.72
    centre = body_start + 0.035 + length / 2.0
    side_x = gx - 0.082
    assembly.add("WeldedSteel", parts.cylinder(
        0.042, length, (side_x, centre, axis - 0.012), axis="y", segments=14))
    # End caps proud of the barrel, so it reads as a vessel rather than a tube.
    for end_y in (centre - length / 2.0, centre + length / 2.0):
        assembly.add("CastIron", parts.cylinder(
            0.047, 0.012, (side_x, end_y, axis - 0.012), axis="y", segments=14))
    # The sight glass in the aft cap: the one part of this the player reads, so
    # it goes on the end that faces them.
    assembly.add("GaugeGlass", parts.cylinder(
        0.026, 0.006, (side_x, centre - length / 2.0 - 0.010, axis - 0.012),
        axis="y", segments=12))
    # Two straps tying it to the body, which is what stops it reading as a
    # separate object floating alongside.
    for strap_y in (centre - length * 0.3, centre + length * 0.3):
        assembly.add("CastIron", parts.box(
            (0.052, 0.014, 0.028), ((side_x + gx) / 2.0, strap_y, axis - 0.012),
            chamfer=0.003))


def _emitter(parts, assembly, gx: float, body_end: float,
             axis: float) -> None:
    """The flared emitter, its hazard collar, and the lens inside the mouth.

    The flare is the cue that does the work at arm's length, and it has to be the
    **widest thing on the tool** or the canister takes the silhouette off it: 22 cm
    across the mouth against the canister's 9. A cone opening towards the view is
    unmistakably not a barrel, and it is the one shape a player sees every time
    they look down.
    """
    throat = body_end
    mouth = throat + EMITTER_LENGTH
    assembly.add("CastIron", parts.cylinder(
        0.044, EMITTER_LENGTH, (gx, (throat + mouth) / 2.0, axis),
        axis="y", segments=18, radius_top=0.112))
    # The collar is the same fitting a Machine wears at a declared port
    # (`parts.port_fitting`), in the same hazard yellow, for the same reason: it
    # is the one colour in the palette that means "goods cross here".
    assembly.add("HazardYellow", parts.annulus(
        0.058, 0.040, 0.020, (gx, throat + 0.012, axis), axis="y", segments=20))
    # Narrower than the mouth it sits in: at the emitter's own radius the lens was
    # a glowing dinner plate that *was* the silhouette rather than a detail on it.
    assembly.add(EMISSIVE_MATERIAL, parts.cylinder(
        0.070, 0.008, (gx, mouth - 0.014, axis), axis="y", segments=18))


def _dial(parts, assembly, gx: float, body_mid: float,
          axis: float) -> None:
    """One dial on the left flank: the Machine on the gun, read off the tool.

    Not a gauge cluster — `parts.gauge_cluster` is sized for a boiler and three
    11 cm bezels would be most of this body. One dial is also the truer picture:
    the Build Gun holds exactly one selection.
    """
    assembly.add("DullBrass", parts.cylinder(
        0.026, 0.012, (gx - 0.064, body_mid - 0.055, axis + 0.016),
        axis="x", segments=14))
    assembly.add("GaugeGlass", parts.cylinder(
        0.019, 0.005, (gx - 0.071, body_mid - 0.055, axis + 0.016),
        axis="x", segments=14))


def _rail(parts, assembly, gx: float, body_start: float,
          body_end: float, axis: float) -> None:
    """The emissive rail along the top of the body: #29's, kept literally.

    Thin and bright, under the hopper's shadow line, so it reads as a lit
    instrument rather than as a painted stripe. It is the part of the old
    placeholder that was genuinely good and the reason the silhouette read as a
    tool at all before the rest of this file existed.
    """
    for side in (-1, 1):
        assembly.add(EMISSIVE_MATERIAL, parts.box(
            (0.012, (body_end - body_start) * 0.78, 0.010),
            (gx + side * 0.050, (body_start + body_end) / 2.0, axis + 0.052),
            chamfer=0.002))


# ---------------------------------------------------------------------------
# The two takes
# ---------------------------------------------------------------------------
#
# `Draw` and `PutAway` are first-class roles in `WeaponAnimator` and a swap times
# itself off the clip lengths of whatever model is on screen, so a Build Gun with
# no takes would snap into frame while every weapon swings into it.
#
# **There is also an `Idle`, and it is one key at rest rather than a breath.** The
# first version of this file shipped only the two takes and argued for it: a held
# tool does not breathe, and the sway is already driven off `query_player_velocity`
# so a clip would double it. Both halves of that are still true and the conclusion
# was wrong, for a reason only a render found. `WeaponViewmodel._play` resolves the
# role, falls back to the **idle** when the model has no clip for it, and *returns
# without seeking* when there is no idle either — which leaves the
# `AnimationPlayer` parked wherever the last clip left it. With
# `player.holster_seconds` at 0.06 the opening `Draw` is over in three or four
# ticks, so the model froze at `Draw` time zero: **the stowed pose**, half a metre
# under the bottom of the frame. It loaded, both takes resolved, `has_model` was
# true, the frustum measurement passed, and there was nothing in the player's
# hands. Every purchased weapon ships an `Idle`, which is why nothing had ever
# met this.
#
# So the idle is the declaration of *what this looks like when nothing is
# happening* — the thing the role fallback actually needs — and holding it to a
# single key is what keeps the original argument: nothing moves that the sway is
# not already moving.
#
# All three takes are the **whole tool** moving, keyframed on the root object rather
# than on a rig. There are no bones in this model and there is nothing for them to
# do: a hand tool coming up into frame is a rigid body on an arc.

#: How long each take runs, in seconds. Shorter than `WeaponAnimator`'s own
#: `DEFAULT_SECONDS` fallback and well inside `player.holster_seconds`' ceiling,
#: because #35 measured a player waiting seven tenths of a second for a swap and
#: calling it broken.
TAKE_SECONDS = 0.22

#: Where the tool starts a `Draw` from and ends a `PutAway` at, relative to where
#: it rests: down and rolled out of frame. Below the frustum's lower edge at the
#: grip's distance, so the swap genuinely begins off screen.
#: **It grew when the tool moved out, and the generator is what said so.** The
#: first pair was a 0.34 m drop, which cleared the frame while the tool sat 25 cm
#: from the eye and did not once `GRIP` pushed it out to 42 cm — the same drop
#: subtends a smaller angle further away, so the stowed pose came back *into*
#: shot and a `Draw` would have read as the tool sliding about rather than coming
#: up. The refusal named it on the next run, which is the whole argument for
#: measuring the stow as well as the rest pose.
STOWED_OFFSET = (0.0, -0.060, -0.58)
STOWED_ROLL_DEGREES = -42.0

#: The takes, as `(name, frames)` where each frame is
#: `(fraction through the take, offset, roll in degrees)`. Three keys apiece: a
#: tool is thrown up and settles, which is one overshoot, and an overshoot is the
#: whole difference between a swap with a hand in it and a cut.
TAKES = (
    ("Idle", (
        (0.00, (0.0, 0.0, 0.0), 0.0),
        (1.00, (0.0, 0.0, 0.0), 0.0),
    )),
    ("Draw", (
        (0.00, STOWED_OFFSET, STOWED_ROLL_DEGREES),
        (0.70, (0.0, 0.012, 0.022), 4.0),
        (1.00, (0.0, 0.0, 0.0), 0.0),
    )),
    ("PutAway", (
        (0.00, (0.0, 0.0, 0.0), 0.0),
        (0.22, (0.0, 0.016, 0.028), 5.0),
        (1.00, STOWED_OFFSET, STOWED_ROLL_DEGREES),
    )),
)
