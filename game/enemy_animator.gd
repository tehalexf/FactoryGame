## What one Enemy should be doing this frame: which baked clip, and which frame of it.
##
## One question, asked once a frame per Enemy: given what the Simulation says — the
## tick, the tick this Enemy came through its Breach, its serial, and whether it is
## biting or holding — which clip belongs on it and how far into that clip are we.
##
## **It holds no state about the Run at all**, which is one step stronger than
## `WeaponAnimator`, whose transitions have lengths and so have to be remembered.
## Nothing here is remembered: a `Facts` goes in and a `Cue` comes out, every field
## of the `Facts` is a `query_*`, and the answer is a pure function of them. That is
## what lets the whole swarm be animated out of one `MultiMesh` with no per-Enemy
## bookkeeping anywhere — there is no object per Crawler to keep the bookkeeping in
## (ADR 0001), and this is the class that makes that affordable rather than painful.
##
## **Nothing is timed by a clock and nothing is chosen at random.** The frame is
## integer arithmetic over three hashed Simulation facts, which is the audio
## director's rule (`tick % count`, cooldowns counted in ticks) and the viewmodel's
## rule (clip time computed from the tick count and seeked explicitly) applied to the
## thing a player spends the whole Run looking at. Two Runs down the same script put
## the same frame on the same Crawler.
##
## It touches no node, loads no file and knows no asset. Frame counts are told to it
## (`set_frame_counts`) by whoever baked the bodies, so the whole rule runs, and is
## tested, without a single character mesh on the machine.
class_name EnemyAnimator
extends RefCounted

## The roles a baked clip can play. A pack names its takes its own way —
## `Running_A` here, `Walking_A` there — so a role is what the game asks for and
## `EnemyBodies` is what resolves it to a clip name the library actually has. The
## same split `WeaponAnimator` makes between a role and a clip needle.
##
## Three, and deliberately only three: an Enemy in this Simulation is walking at
## something, chewing something, or standing still. There is no death clip because
## there is no corpse — `_remove_enemy` takes the entry out on the tick the hit
## points reach zero, so a dying animation would be a clip with nothing to play it
## on.
const MOVE: String = "move"
const IDLE: String = "idle"
const ATTACK: String = "attack"

## How many ticks one baked frame lasts. The bake runs at half the Simulation's rate,
## so this is 2 — which keeps the frame an exact integer division of the tick rather
## than a ratio with a rounding rule, in the spirit of everything else that counts in
## ticks here.
const TICKS_PER_FRAME: int = 2

## How far apart in the cycle two consecutively-spawned Enemies are held, in ticks.
##
## **This is the whole of "the swarm is not in visible lockstep", and it is a serial
## rather than a draw.** Six Crawlers released from one Breach on one tick share a
## spawn tick, so without this they would step in perfect unison — which reads as one
## object rather than as six. A serial is issued once and never reused (#9), so the
## offset is stable for an Enemy's whole life and identical on every client, where an
## RNG draw would have cost the Run a draw and a clock would have cost it determinism.
##
## Coprime with every plausible clip length, so successive serials spread across the cycle
## instead of landing on a few phases. Eleven rather than seven after reading a render: at
## seven, two Breakers released a tick apart were three frames into a thirty-three-frame walk
## and photographed in visibly the same pose. The Crawlers' faster run cycle spread fine
## either way, which is why the number had to come from the slowest clip rather than the
## commonest one.
const PHASE_STRIDE_TICKS: int = 11


## Everything about an Enemy that decides what it is doing. Every field is a
## Simulation query; none is a remembered copy.
class Facts extends RefCounted:
	## `query_tick`.
	var tick: int = 0
	## `query_enemy_spawn_tick`. What the stride is counted from, so an Enemy comes
	## through its Breach at the start of a stride rather than half way through one.
	var spawn_tick: int = 0
	## `query_enemy_serial`. The de-lockstepping offset, and the reason it is the
	## serial rather than the index: indices shift as Enemies die, so an index would
	## make a Crawler's gait jump every time something ahead of it in the array was
	## killed.
	var serial: int = 0
	## `query_enemy_is_attacking` — biting a Machine, a Wall, a player or the Nest,
	## or, for a Siege Hulk, shelling or stomping.
	var attacking: bool = false
	## Whether this Enemy is standing still with nothing to bite. True of a Siege
	## Hulk that has halted and is not shelling; false of everything that walks,
	## because a Crawler with a route is always walking it.
	var holding: bool = false


## What should be on screen.
class Cue extends RefCounted:
	## One of the role constants above.
	var role: String = ""
	## Which frame of that role's baked clip, counted from its first.
	var frame: int = 0


var _frames: Dictionary = {}


## How many baked frames each role's clip runs for. Told to it by whoever baked the
## bodies rather than read off a file, for the reason `WeaponAnimator` is told its
## clip lengths: a rule that needed the asset is a rule only a machine with the asset
## can check.
func set_frame_counts(frames: Dictionary) -> void:
	_frames = frames.duplicate()


## Which clip, and which frame of it.
func cue_for(facts: Facts) -> Cue:
	var cue: Cue = Cue.new()
	cue.role = _role_for(facts)
	var frames: int = int(_frames.get(cue.role, 1))
	if frames < 1:
		frames = 1
	# Counted from the tick this Enemy arrived, offset by its serial. Both halves are
	# integers, so there is nothing here to round and nothing to accumulate.
	var elapsed: int = facts.tick - facts.spawn_tick
	if elapsed < 0:
		elapsed = 0
	var phase: int = elapsed + facts.serial * PHASE_STRIDE_TICKS
	cue.frame = (phase / TICKS_PER_FRAME) % frames
	return cue


## Biting beats holding beats walking, which is the order the Simulation decides them
## in: `query_enemy_is_attacking` is a fact about contact, and holding is what is left
## of a Siege Hulk that has halted with nothing in reach.
func _role_for(facts: Facts) -> String:
	if facts.attacking:
		return ATTACK
	if facts.holding:
		return IDLE
	return MOVE
