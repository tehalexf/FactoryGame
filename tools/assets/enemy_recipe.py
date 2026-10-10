#!/usr/bin/env python3
"""The three Enemies, declared: an insect is a handful of proportions and a gait.

Imported inside Blender by `generate_enemies.py`. This is `machine_recipes.py`'s
arrangement pointed at the things a player spends a Run shooting at — the geometry
is **declared** here and assembled there, so changing a dimension is editing a
number in this file and re-running `generate_enemies.sh`. Never edit a `.glb`.

**Why a declaration and not a model.** #38 cast three KayKit CC0 characters onto
the three kinds because they existed and were already retargeted onto one rig; #49
made them tellable apart by size; #75 graded their atlas into the palette and gave
them metal and grime. Every one of those was the right move for the asset it had,
and the asset was still a fantasy skeleton — #75's own note says so: *"the
proportions are still a cartoon's… a Crawler's skull is a third of its height"*.
A bone-white skull is a bone-white skull however much oxide you put on its ribs.

So the bodies join the Machine meshes and the Build Gun: this project's own work,
generated from a declaration, committed, and byte-for-byte reproducible. A clone
with no purchased packs holds the real thing.

### The shape of the thing being declared

Three kinds, **one builder**, and that is the load-bearing decision rather than a
saving. All three are insects — thorax, abdomen, head, mandibles, legs — so the
difference between a Crawler and a Siege Hulk is *numbers*, which means
`tests/cases/test_enemy_silhouette.gd` is measuring a declaration a person can
edit rather than three separate piles of geometry. The three silhouettes are
separated by **leg count, how high the body is slung, and where the mass is**, and
all three of those are fields below.

### Everything here is in body heights, not metres

`game/enemy_bodies.gd` bakes a body **one metre tall with its feet on the ground**
and folds that normalisation into the bone matrices; `WorldView` then scales each
instance by `query_enemy_hit_height_metres`, so what a player shoots at is what
they can see (#49). A declaration in metres would therefore be a declaration in
units nothing uses. In body heights, `thorax_centre = 0.42` reads as *"the body is
slung at two fifths of the Enemy's height"* — which is the sentence a person
editing this file is actually trying to write. The generator scales the finished
assembly so its vertical extent is exactly 1.0, so these numbers are proportions
and the sum of them is not a constraint.

**Axes are Blender's**, as everywhere else in this pipeline: +X east, +Y north, +Z
up, metres, origin on the ground under the body's centre. The glTF exporter's
Y-up conversion sends Blender +Y to Godot -Z, and `WorldView._write_instance` maps
a body's local +Z to its facing — so **an insect is built facing -Y** and its
abdomen trails off towards +Y. That is the one axis fact in this file and it is
why `head_forward` is negative and `abdomen_*` is positive.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field


#: Frames a second every clip is authored and baked at. `EnemyBodies.FRAMES_PER_SECOND`
#: is the same number from the other side, and `EnemyAnimator.TICKS_PER_FRAME` is 2 — so a
#: frame is two ticks and the shipped cycles are 0.93 s of Run for a walk, 0.53 s for a run,
#: 1.33 s for an idle and 0.67 s for a bite.
FPS = 30


@dataclass(frozen=True)
class Leg:
    """One leg of one side, mirrored onto the other by the generator.

    Two segments and no more: a coxa out to the knee and a tibia down to the foot.
    **Two bones a leg is the budget**, because the pose texture is bones times
    frames and `EnemyBodies` bakes 23 bones today — six legs at three segments
    would be 25 bones of leg alone. It is also what an insect looks like from ten
    metres, which is the only range this matters at.

    Positions are in body heights, measured from the body's own centre on the
    ground: `along` runs with the body (negative towards the head), `out` runs
    sideways, `up` is height.
    """

    #: Where the leg leaves the thorax, along the body. Negative is towards the head.
    along: float
    #: How far out and how high the knee stands. **This is the number that makes an
    #: insect an insect**: a knee above the back is what reads as splayed rather
    #: than as a quadruped, and on the Crawler and the Hulk it is also the tallest
    #: thing in the body, so it is what the normalisation measures.
    knee_out: float
    knee_up: float
    #: Where the foot lands. `foot_along` is relative to `along`, so a positive
    #: number plants the foot behind the hip.
    foot_out: float
    foot_along: float
    #: How thick the two segments are, as a square cross-section.
    thickness: float


@dataclass(frozen=True)
class Insect:
    """One Enemy kind's whole body, as proportions of its own height."""

    #: The `EnemyKind` id this is, which is the committed `.glb`'s basename.
    kind_id: str
    #: What `enemy.<kind>_hit_height_metres` says in `content/tuning.toml`. **Not
    #: used to build anything** — the body is normalised to 1.0 — and carried only
    #: so the generator can print it and the asset suite can say which declared
    #: height each committed body is for. The Simulation remains the one authority.
    hit_height_metres: float

    # ── the thorax: where the legs hang from ────────────────────────────────────
    thorax_length: float
    thorax_width: float
    thorax_depth: float
    #: How high the thorax's centre is slung. Low is a Crawler scuttling, high is a
    #: Hulk striding over its own legs, and it is one of the three numbers the
    #: silhouette gate is really measuring.
    thorax_centre: float

    # ── the carapace: a plate over the thorax, or none ──────────────────────────
    #: A shield across the back. `0.0` is no plate at all, which is what makes a
    #: Crawler bare. On the Breaker it is the dominant mass in the silhouette.
    carapace_rise: float
    carapace_width: float
    carapace_length: float

    # ── the abdomen: where the mass trails off to ──────────────────────────────
    abdomen_length: float
    abdomen_width: float
    abdomen_depth: float
    #: How much higher the abdomen's far end sits than its root. Negative tucks it
    #: under, positive cocks it up — the Hulk's raised tail, which is where the
    #: weak point lives.
    abdomen_rise: float
    #: How much narrower the far end is than the root, as a fraction.
    abdomen_taper: float
    #: How many segments the abdomen is built in. Three reads as segmented at ten
    #: metres and costs nine faces; more is detail nobody can see.
    abdomen_segments: int

    # ── the head and the mandibles: no face, a bite ────────────────────────────
    head_length: float
    head_width: float
    head_depth: float
    #: How far in front of the thorax the head sits (negative is forward) and how
    #: far below its centre.
    head_forward: float
    head_drop: float
    mandible_length: float
    mandible_spread: float
    mandible_thickness: float

    legs: tuple[Leg, ...]

    #: Palette material per part. Names index `dieselpunk_palette.json`, so the
    #: colour of an Enemy is the colour of a Machine — one declaration, and nothing
    #: here invents a hue. See `world_view._enemy_surface` for why the *material
    #: model* (metallic, roughness) is per kind rather than per entry: chitin is a
    #: glossy dielectric and the palette has no such entry.
    materials: dict = field(default_factory=dict)

    #: Whether this kind carries a weak point at the end of its tail.
    #:
    #: **Where** it is, is not declared: `generate_enemies.vent_offset` derives it
    #: from the abdomen's own numbers and exports it as a marker node, which
    #: `EnemyBodies` reads back and `WorldView` places the glowing panel at. So the
    #: opening and the tail it is an opening in cannot come apart when somebody
    #: edits `abdomen_rise` — the arrangement a Machine's `Port_*` markers already
    #: have, and the literal content of "modelled in body heights with its offset
    #: in the mesh".
    has_vent: bool = False

    def material(self, part: str) -> str:
        return self.materials.get(part, "CastIron")


# ───────────────────────────────────────────────────────────────────────────────
# The gaits
# ───────────────────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Clip:
    """One named cycle, as a length and a function from phase to a pose.

    A pose is `{bone_name: (rx, ry, rz)}` in radians, local to the bone's rest, and
    anything the pose does not mention keeps its rest — which is the same rule
    `EnemyBodies._pose` applies to a sparse clip from the other end.

    **The cycle is sampled rather than keyframed by hand.** Eight keys over a
    24-frame walk is what an animator would author and it is also eight numbers a
    person editing a leg length would have to re-derive; a function of phase
    follows the declaration for free. The generator plants a key on every frame and
    sets linear interpolation, so what Godot imports is exactly what is written
    here and the bake samples it without an interpolation to argue about.
    """

    #: The role `EnemyAnimator` asks for, or a name a recipe maps a role onto.
    name: str
    #: How many frames, at `FPS`. The cycle's own speed: a Crawler's `run` is short
    #: because Chaff has to read as *coming*, and a Breaker's `walk` is long because
    #: #34 made it march the lane a player defended.
    frames: int


#: Every body carries all four, and every one of them is read by some kind: the
#: Crawler moves on `run` and the other two march on `walk`. A clip nothing names
#: would be the asset-pipeline version of a tuning key nothing reads.
CLIPS: tuple[Clip, ...] = (
    Clip("walk", 28),
    Clip("run", 16),
    Clip("idle", 40),
    Clip("attack", 20),
)


def tripod_phase(pair: int, side: int) -> float:
    """Where in the cycle this leg's step falls, as a fraction of it.

    **A tripod gait, which is most of what makes these read as insects rather than
    as dogs.** A six-legged insect carries its weight on front-left, middle-right
    and rear-left while the other three swing, so a leg's phase is decided by its
    pair index *and its side together* — which is why this takes both. Get it from
    the pair alone and both sides step in unison, which is a pace and reads as a
    pantomime horse.

    With two pairs it degenerates to a diagonal trot, which is what a four-legged
    body does, so the Breaker needs no case of its own.
    """
    return 0.5 * float((pair + side) % 2)


def leg_pose(phase: float, reach: float, lift: float) -> tuple[float, float]:
    """One leg's coxa and tibia angles at a phase of its own step, in radians.

    Two thirds of the cycle is the stance — the foot planted, the body carried past
    it — and one third is the swing, the foot lifted and thrown forward. That ratio
    is what a walk is; an even split reads as paddling.
    """
    stance = 2.0 / 3.0
    if phase < stance:
        # Planted: the hip rotates back through its range at a constant rate, which
        # is the body moving over a foot that is not moving.
        swept = phase / stance
        return (reach * (0.5 - swept), 0.0)
    # Swinging: forward and up, and back down at the end of it.
    swept = (phase - stance) / (1.0 - stance)
    return (
        reach * (-0.5 + swept),
        -lift * math.sin(math.pi * swept),
    )


def pose_at(insect: Insect, clip: str, phase: float) -> dict:
    """The whole body's pose at a phase of one clip, as bone-local Euler angles.

    One function for all four clips and all three kinds, because the difference
    between a walk and a run is amplitude and the difference between a Crawler and
    a Hulk is which legs exist. Reading it as four `if`s over a shared leg cycle is
    what keeps a gait change from being a per-kind edit.
    """
    out: dict = {}
    legs = len(insect.legs)

    if clip in ("walk", "run"):
        running = clip == "run"
        reach = 0.52 if running else 0.34
        lift = 0.46 if running else 0.30
        for leg in range(legs):
            for index, (side, sign) in enumerate((("L", 1.0), ("R", -1.0))):
                at = (phase + tripod_phase(leg, index)) % 1.0
                hip, knee = leg_pose(at, reach, lift)
                out[f"Leg{leg}{side}Coxa"] = (hip, 0.0, sign * knee * 0.35)
                out[f"Leg{leg}{side}Tibia"] = (-knee * 1.6, 0.0, 0.0)
        # The body rides the gait: a bob at twice the step rate, because a tripod
        # plants twice a cycle, and a roll at the step rate as the tripods swap.
        bob = 0.030 if running else 0.016
        out["Thorax"] = (
            math.sin(4.0 * math.pi * phase) * bob,
            math.sin(2.0 * math.pi * phase) * bob * 1.8,
            0.0,
        )
        # The abdomen lags the thorax, which is the whole of what "a heavy back
        # end" looks like in motion.
        out["Abdomen"] = (math.sin(4.0 * math.pi * phase - 0.9) * bob * 1.4, 0.0, 0.0)
        out["Head"] = (math.sin(4.0 * math.pi * phase + 0.4) * bob * 0.8, 0.0, 0.0)
        snap = 0.10 if running else 0.05
        out["MandibleL"] = (0.0, 0.0, math.sin(2.0 * math.pi * phase) * snap)
        out["MandibleR"] = (0.0, 0.0, -math.sin(2.0 * math.pi * phase) * snap)
        return out

    if clip == "idle":
        # Breathing, and the mandibles working. Deliberately small: an Enemy
        # standing still is an Enemy a player is deciding about, and a big idle
        # reads as a creature doing something.
        breathe = math.sin(2.0 * math.pi * phase)
        out["Thorax"] = (breathe * 0.010, 0.0, 0.0)
        out["Abdomen"] = (breathe * 0.034, 0.0, 0.0)
        out["AbdomenTip"] = (breathe * 0.028, 0.0, 0.0)
        out["Head"] = (breathe * -0.016, 0.0, 0.0)
        chew = math.sin(6.0 * math.pi * phase)
        out["MandibleL"] = (0.0, 0.0, 0.10 + chew * 0.10)
        out["MandibleR"] = (0.0, 0.0, -0.10 - chew * 0.10)
        for leg in range(legs):
            for side, sign in (("L", 1.0), ("R", -1.0)):
                out[f"Leg{leg}{side}Coxa"] = (0.0, 0.0, sign * breathe * 0.02)
        return out

    if clip == "attack":
        # Rear up, then throw the mandibles forward and down. One beat, because the
        # Simulation's bite is one event and a two-beat animation would be a claim
        # about a rhythm the Simulation does not have.
        wind = math.sin(math.pi * min(phase / 0.4, 1.0)) if phase < 0.4 else 0.0
        strike = math.sin(math.pi * (phase - 0.4) / 0.6) if phase >= 0.4 else 0.0
        out["Thorax"] = (-0.30 * wind + 0.18 * strike, 0.0, 0.0)
        out["Abdomen"] = (0.24 * wind - 0.10 * strike, 0.0, 0.0)
        out["Head"] = (-0.34 * wind + 0.46 * strike, 0.0, 0.0)
        spread = 0.46 * wind
        close = 0.40 * strike
        out["MandibleL"] = (0.0, 0.0, spread - close)
        out["MandibleR"] = (0.0, 0.0, -spread + close)
        for leg in range(legs):
            front = 1.0 if insect.legs[leg].along < 0.0 else -0.4
            for side, sign in (("L", 1.0), ("R", -1.0)):
                out[f"Leg{leg}{side}Coxa"] = (-0.30 * wind * front, 0.0, sign * 0.06 * wind)
                out[f"Leg{leg}{side}Tibia"] = (0.34 * wind * front, 0.0, 0.0)
        return out

    return out


# ───────────────────────────────────────────────────────────────────────────────
# The three kinds
# ───────────────────────────────────────────────────────────────────────────────
#
# **The three silhouettes are separated here, by three things and not by detail.**
# `tests/cases/test_enemy_silhouette.gd` fails if any two converge below 0.50, and
# the risk the ticket named is real: three insects are far more alike than a
# skeleton, a knight and a golem were. What separates them:
#
# * **leg count** — six, four, six, with the Breaker's four thick and the Hulk's
#   six long. A four-legged body has gaps a six-legged one fills, which is most of
#   the front-view difference.
# * **how high the body is slung** — 0.40, 0.52, 0.66 of the Enemy's height. A
#   Crawler scuttles under its own knees, a Hulk strides over them.
# * **where the mass is** — the Crawler's is spread down a long thin body, the
#   Breaker's is a shield at the front, the Hulk's is a raised tail at the back.
#
# None of those is detailing and none of them is a texture, which is the lesson
# #38's glowing eyes and #49's resizing both paid for.


def crawler() -> Insect:
    """Chaff: low, long, bare and six-legged. The one a player sees most of.

    It is the **sense** of threat rather than the threat, so it is the only kind
    with no carapace plate at all — bare segmented chitin, nothing to shoot
    *around*. Its body is slung lowest of the three and its knees are the tallest
    thing on it, which is what makes a front-on Crawler read as a star of legs
    with very little in the middle.
    """
    legs = tuple(
        Leg(
            along=along,
            knee_out=0.34,
            knee_up=0.95,
            foot_out=0.50,
            foot_along=0.10,
            thickness=0.075,
        )
        for along in (-0.19, 0.02, 0.23)
    )
    return Insect(
        kind_id="crawler",
        hit_height_metres=1.6,
        thorax_length=0.52,
        thorax_width=0.40,
        thorax_depth=0.34,
        thorax_centre=0.42,
        carapace_rise=0.0,
        carapace_width=0.0,
        carapace_length=0.0,
        abdomen_length=0.52,
        abdomen_width=0.40,
        abdomen_depth=0.38,
        abdomen_rise=0.10,
        abdomen_taper=0.50,
        abdomen_segments=3,
        head_length=0.26,
        head_width=0.26,
        head_depth=0.22,
        head_forward=-0.05,
        head_drop=-0.14,
        mandible_length=0.22,
        mandible_spread=0.110,
        mandible_thickness=0.050,
        legs=legs,
        # **`OxideRed` is the abdomen and nothing else, and a render is why.** The first
        # version wore it on the thorax and the head too, and at thirty metres a Chaff
        # swarm read as a band of hazard tape: the entry's own `base_color` is
        # (0.13, 0.035, 0.022), which is nearly four to one red against green, and a
        # Machine only ever wears it as an accent. Restricted to the abdomen it is a
        # second cue beside height — the oxide tail against the iron thorax and legs —
        # which is the thing #75 wanted from it and could not get out of a tint.
        materials={
            "thorax": "CastIron",
            "abdomen": "OxideRed",
            "head": "CastIron",
            "joint": "Soot",
            "leg": "CastIron",
            "mandible": "DullBrass",
        },
    )


def breaker() -> Insect:
    """The threat: four heavy legs under a shield, head down, mass at the front.

    A Hive Guard rather than a scavenger. Everything about it says *a wall coming
    down the lane*: four legs instead of six so the gaps read, a carapace plate
    that is the tallest and widest thing on the body, a short tucked abdomen so
    the mass is forward, and a head carried low in front of it.

    #49 gave a Breaker its own 2.2 m because a Crawler and a Breaker were the same
    dark silhouette past twelve metres; that height is untouched here and the form
    is now doing the work beside it.
    """
    legs = tuple(
        Leg(
            along=along,
            knee_out=0.32,
            knee_up=0.78,
            foot_out=0.48,
            foot_along=0.12,
            thickness=0.125,
        )
        for along in (-0.15, 0.19)
    )
    return Insect(
        kind_id="breaker",
        hit_height_metres=2.2,
        thorax_length=0.46,
        thorax_width=0.54,
        thorax_depth=0.42,
        thorax_centre=0.50,
        carapace_rise=0.92,
        carapace_width=0.72,
        carapace_length=0.56,
        abdomen_length=0.34,
        abdomen_width=0.48,
        abdomen_depth=0.38,
        abdomen_rise=-0.06,
        abdomen_taper=0.35,
        abdomen_segments=2,
        head_length=0.30,
        head_width=0.34,
        head_depth=0.28,
        head_forward=-0.06,
        head_drop=-0.20,
        mandible_length=0.28,
        mandible_spread=0.180,
        mandible_thickness=0.085,
        legs=legs,
        materials={
            "thorax": "CastIron",
            "abdomen": "CastIron",
            "head": "CastIron",
            "carapace": "WeldedSteel",
            "joint": "Soot",
            "leg": "CastIron",
            "mandible": "DullBrass",
        },
    )


def siege_hulk() -> Insect:
    """The boss: slung high on six long legs, with a raised tail and the vent in it.

    **The vent is the only place geometry carries a rule in this project**, and an
    insect abdomen is a better home for it than a golem's back was. `_armoured`
    shrugs off 85% of a hit landing on the front and nothing on the back, and
    nothing anywhere says so in words — so the weak point has to be a thing a
    player finds by walking round. On the golem it was a grille bolted to a
    shoulder blade; here the tail *cocks up and away from the body* and the opening
    is at the end of it, which is the one part of the silhouette a player cannot
    mistake for armour and the one part they can only see from behind.

    `vent_godot` is exported as a marker node and read back by `EnemyBodies`, so
    the glowing panel `WorldView` draws and the abdomen it is an opening in cannot
    come apart. It is where the tail's rear face actually ends up, computed below
    rather than written down twice.
    """
    legs = tuple(
        Leg(
            along=along,
            knee_out=0.42,
            knee_up=1.00,
            foot_out=0.66,
            foot_along=0.14,
            thickness=0.095,
        )
        for along in (-0.18, 0.03, 0.24)
    )
    return Insect(
        kind_id="siege_hulk",
        hit_height_metres=3.2,
        thorax_length=0.46,
        thorax_width=0.46,
        thorax_depth=0.40,
        thorax_centre=0.62,
        carapace_rise=0.82,
        carapace_width=0.52,
        carapace_length=0.48,
        abdomen_length=0.64,
        abdomen_width=0.42,
        abdomen_depth=0.40,
        abdomen_rise=0.22,
        abdomen_taper=0.35,
        abdomen_segments=3,
        head_length=0.32,
        head_width=0.32,
        head_depth=0.28,
        head_forward=-0.06,
        head_drop=-0.18,
        mandible_length=0.30,
        mandible_spread=0.140,
        mandible_thickness=0.075,
        legs=legs,
        materials={
            "thorax": "CastIron",
            "abdomen": "OxideRed",
            "head": "CastIron",
            "carapace": "CastIron",
            "joint": "Soot",
            "leg": "CastIron",
            "mandible": "DullBrass",
        },
        has_vent=True,
    )


#: Every kind with a body, in the order the generator walks them. A kind absent
#: from here has no `.glb` and draws the procedural carapace, which is an ordinary
#: state and not a warning — the rule a Machine with no generated body obeys.
KINDS: tuple[Insect, ...] = (crawler(), breaker(), siege_hulk())


def by_id(kind_id: str) -> Insect:
    for insect in KINDS:
        if insect.kind_id == kind_id:
            return insect
    raise KeyError(f"no Enemy recipe for {kind_id!r}")


def kind_ids() -> list[str]:
    return [insect.kind_id for insect in KINDS]
