# DEEP FOUNDRY — settled design

Vocabulary is defined in [../CONTEXT.md](../CONTEXT.md) and capitalised here.
This document records *what was decided*. Architecture rationale lives in
[adr/](adr/).

## The pitch

A dieselpunk first-person factory-defense game for 1-4 players. You build a
production line on one handcrafted Map, and that line is your armament: Belts
feed Turrets, components assemble into modular Gear, and the Silo fires only
what it was loaded with in advance.

## The keystone loop

Production *is* combat power. Not thematically — mechanically:

- Turrets are Machines whose output is damage. They consume Ammunition as a
  Recipe input, so defending costs continuous production, not a one-time build.
- Stratagems come from Charges the Silo assembled from Belt-fed inputs. More
  production means more artillery, full stop.
- Gear is modular, so a longer barrel is a new machining line.

And the counter-pressure: **Heat**. Throughput raises it. Mining at Depth raises
it. Heat drives how fast and how large Waves arrive. So scaling up is
simultaneously how you get strong and how you get hunted. Every new smelter is
a bet — which is the thing pure sandbox factory games never make you feel.

## Shape of a Run

One Map, endless, saveable, resumable. Waves arrive on a timer modified by Heat,
always preceded by a Telegraph, never while building is disabled. Players may
pull a lever to call a Wave early for a reward.

The Run ends when the Nest is destroyed. Players dying costs tempo only —
Downed, revivable, else respawn at the Nest. Nothing is lost but time.

Progression is physical: carry goods to the Nest to unlock the next tier.
No research menu, no science resource. Depth gates what is possible to deliver.

Enemies enter at fixed, fortifiable Breaches. Deep mining opens new Breaches
near the mine. Hives out on the Map add continuous pressure and can be destroyed
— which is the reason to leave the base and the reason Gear exists at all.

## Milestone 1 content

Caps, not aspirations. Everything is data-driven, so all of it extends by adding
a definition file rather than touching systems.

- **Machines (8):** Miner · Smelter · Press · Assembler · Steam Boiler ·
  Generator · Ammo Press · Silo. Plus Nest, Belt, Wall.
- **Turrets (3):** MG Turret · Cannon Turret · Repair Pylon
- **Weapons (3):** Pneumatic Wrench (melee, also repairs) · Bolt Rifle ·
  Drum Autocannon
- **Stratagems (3):** Artillery Barrage · Supply Drop · Sentry Drop
- **Enemies (2 + boss):** Crawler (Chaff) · Breaker (hunts Machines) ·
  Siege Hulk (boss; outranges Turrets, so it must be answered on foot)

The Siege Hulk is deliberate: it forces the first-person combat pillar to
justify itself early, while that is still cheap to discover.

## Rules fixed early because they are expensive to change

- **2 m grid**, machines 2x2 to 4x4 tiles. Player is 1.8 m. Belts 1 tile.
  4 m storey height reserved for if vertical building is ever enabled.
- **Flat building only** for now, but the grid is `Vector3i` internally so
  discrete floors can be switched on without a rewrite.
- **Belts are the only logistics primitive.** Belts connect directly to Machine
  ports — no inserters. No fluids: water for Steam is an adjacency check.
- **One Power grid**, total supply vs demand, shortfall *throttles* Machines
  rather than stopping them. Three generator classes feed it (Steam, Electric,
  Exotic) with distinct fuel chains and distinct failure modes.
- **Nodes never deplete.** No forced base relocation; a 40-hour Nest stays
  meaningful. Depth tiers gate value instead.
- **Build Gun plus Survey View.** A raised downward camera while building,
  because a Factory is illegible from eye level.

## Enemy scale

Target ~100 on screen, via tiering: ~15 full-fidelity Enemies that are the
actual threat, ~85 Chaff that are the *sense* of threat — one-hit, shared
flowfield movement, GPU-instanced animation, three states.

Phased deliberately: **M1 ships 20 enemies on the final architecture; the Chaff
tier switches on in M2.** The architecture is what is expensive to retrofit, not
the count. If the loop is not fun at 20, it will not be fun at 100.

Flowfield over per-agent A* is not a close call here: it is O(map) once per
destination amortised across every agent, and every Enemy converges on one
target. Enemies are never nodes — idiomatic Godot nodes cap out around 150-250.

## Diegetic controls

Physical because they are weighty, infrequent, and problem-solving: Silo loading
(irreversible shell and charge selection) · Painting · Boiler startup and
pressure relief · Delivery intake at the Nest · the call-Wave-early lever.

Menus for everything done hundreds of times: Recipe selection, Belt routing,
Gear assembly, inventory.

The line between satisfying friction and tedium is *problem-solving vs
transcription*. IRON NEST's most-praised quality is its sound design and its
most-cited criticism is "plunk in figures here, enter the results there" — with
the developer publicly agreeing that was fair. Each diegetic control therefore
needs its hero sound before it ships. Audio is load-bearing here, not polish.

## Milestone order

1. Deterministic fixed-point sim core, headless, tested. No rendering.
2. Grid, Belts, 3 Machines, Power. Placeholder cubes.
3. First-person controller, Build Gun, Survey View.
4. Nest, 1 Turret, 1 Enemy, Waves on a timer.
5. Heat, Depth, Delivery progression.
6. Art pass: Blender machines, AI textures.
7. Gear and combat: 3 weapons, Breaker, Siege Hulk.
8. Silo, Stratagems, Painting.
9. Save/load.
10. 4-player lockstep co-op.

**M1 is done at step 9, single-player:** a playable 20-minute loop where you
scale a factory, fight Waves, call in artillery, and save.

Co-op is last on purpose. Lockstep determinism is validated by replaying inputs
— a single-player test. Prove determinism solo and co-op becomes transport
plumbing rather than an architectural change.

## Scope discipline

The genre is the most content-hungry in games and the comparables are sobering.
Satisfactory: ~30 people, ~7 years. FOUNDRY: 10 full-time staff, Unity as a
renderer over a custom C++ deterministic sim. **Techtonica — first-person 4-player
co-op factory, the closest analogue — ran out of money and halted development.**

The response is thin pillars, hard caps, and data-driven everything, so breadth
is additive later instead of structural now.

## Deliberately not in M1

Fluids · inserters · drones · trains · vertical building · procedural maps ·
blueprints · controller support · dedicated servers · image-to-3D asset
generation · tiered Gear.
