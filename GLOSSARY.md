# Context

Domain glossary for the factory-defense game. Terms only — no implementation
details, no plans, no open questions. A term appears here once it is settled.

## Core entities

**Nest** — The central structure the players defend. Its destruction ends the
Run. Factory damage is survivable; Nest loss is not. Also the players' respawn
point.

**Run** — A single continuous play session on one Map, saveable and resumable,
with no fixed end. It ends when the Nest is destroyed. "Infinitely scaling":
Waves escalate without bound.

**Map** — The handcrafted terrain a Run takes place on. One Map exists. It holds
Nodes at varying Depths, Breaches, and Hives, and defines the chokepoints that
make Factory layout a defensive decision.

**Breach** — A fixed point on the Map where Enemies enter. Known in advance and
fortifiable. Mining at greater Depth opens new Breaches near the mine, so
reaching for better ore literally changes the geography of the threat.

**Hive** — An Enemy structure out on the Map that adds continuous pressure.
Destroying one reduces pressure permanently but requires leaving the Factory.
Hives are why the players carry Gear at all. Not to be confused with the Nest,
which is theirs and is defended.

**Host** — The player who owns the Factory and the Run's save file. Other
players join the Host's Run. Authoritative over all simulation state.

## Production

**Factory** — The whole player-built production network: Machines, Belts, Power,
and Turrets. It is simultaneously the production system and the
tower-defense map.

**Machine** — A discrete building that consumes inputs and produces outputs per
a Recipe. Mortal: it can be damaged and destroyed by Enemies, and repaired.

**Turret** — A Machine whose output is damage rather than an Item. It consumes
Ammunition as a Recipe input. Not a separate combat subsystem — the same
Recipe, inventory, and Belt rules apply.

**Ammunition** — The Item a Turret consumes to fire. An ordinary Item in every
respect: made by an Ammo Press from a Recipe, carried on Belts, buffered in an
input port. It is what makes defence a running production cost rather than a
one-time build, and a Turret holding none does not fire.

**Ammo Press** — The Machine that makes Ammunition. An ordinary crafter; it is
the Turret's place in the Recipe graph, not a special case.

**Repair Pylon** — A Turret-class Machine whose output is repair rather than
damage. Consumes repair material to mend nearby Machines, making Machine
mortality something the players can engineer against rather than only endure.

**Recipe** — A declarative input→output transformation with a rate. Defined as
data, never as code.

**Node** — An inexhaustible source of a raw Resource at a fixed location and
Depth. Never depletes.

**Depth** — The tier a Node sits at. Greater Depth yields more valuable
Resources, demands more Power, and raises Heat.

**Miner** — The Machine that extracts a Resource from a Node. Different Miners
reach different Depths.

**Power** — The capacity that lets Machines run. One grid, modelled as total
supply against total demand; shortfall throttles Machines rather than stopping
them. Three classes of generator feed it, each with its own fuel chain and its
own characteristic failure: **Steam** (fuel logistics can be cut), **Electric**
(generators can be destroyed), **Exotic** (deep-ore gated, continuously raises
Heat, can fail catastrophically).

**Belt** — The sole means of moving Items between Machines. Connects directly to
a Machine's input and output ports; no intermediate loading device exists.

## Combat

**Wave** — A timed assault of Enemies on the Factory and the Nest. Arrival and
size are driven by a baseline timer modified by Heat. A Wave may be called early
by the players for a reward.

**Heat** — The scalar that measures how much attention the players have drawn.
Raised by production throughput and by mining at greater Depth. Drives Wave
frequency and size. Makes scaling up a deliberate risk rather than a free gain.

**Enemy** — A hostile unit. Two tiers: a small number of full-fidelity enemies
that constitute the actual threat, and a large number of weak Chaff that
constitute the sense of a swarm.

**Chaff** — A weak, one-hit Enemy using shared movement and minimal logic.
Present for perceived scale.

**Crawler** — Chaff. Swarms toward whatever is nearest.

**Breaker** — A full-fidelity Enemy that preferentially attacks Machines rather
than players. The reason Machine mortality is felt rather than merely true.

**Siege Hulk** — A slow Enemy that bombards the Factory from beyond Turret
range. Cannot be answered by defenses; the players must go out and kill it.

**Telegraph** — The warning that precedes a Wave: klaxon, rising gauges, dust on
the horizon. Waves are never silent, and building is never disabled.

**Downed** — A player at zero health, immobilised and bleeding out, revivable by
a teammate. Failing that, they die and respawn at the Nest after a delay. Death
costs tempo, never progress or resources. Solo play has no Downed state.

**Stratagem** — A player-called intervention from outside the Map, drawn from a
stockpile of Charges. Factory output is therefore combat power: more production
directly means more Stratagems available.

**Silo** — The Machine that assembles Charges. An ordinary Machine with a
Recipe, fed by Belts, consuming Power — and destructible, so a breakthrough
threatens the players' heaviest weapons.

**Charge** — One stockpiled use of a Stratagem. Built in advance, never
instantaneous. Committing a Charge is irreversible: a Painting that is
interrupted consumes it for nothing.

**Painting** — The act of calling in a Stratagem. A player must stand at the
target and channel, exposed and unable to act. Interruption cancels the
Stratagem and wastes the Charge.

**Gear** — Player-crafted weapons and equipment, produced by the Factory and
used in first-person combat. **Modular**: a single weapon frame accepts
components (barrels, magazines, sights) made on different production lines.
Power comes from combination, not from tiers.

## Interaction

**Diegetic control** — A physical in-world mechanism (lever, crank, valve,
gauge, dial) operated directly rather than through a menu. Reserved for weighty,
infrequent, problem-solving actions. Routine high-frequency actions use menus.

## Progression

**Delivery** — The act of bringing goods to the Nest to unlock the next tier of
Machines, Gear components, and Stratagems. There is no research menu and no
science resource; progression is physical. Depth gates what is possible to
deliver at all.

## Aesthetic

**Dieselpunk** — The project's visual language. 1920s-40s heavy industry: cast
iron, welded steel, olive drab, hydraulics, grime. Not Victorian steampunk —
no brass, copper, polished wood or whimsy.

## Interaction, continued

**Build Gun** — The tool through which all construction happens. A hologram
snaps to the grid; placement and rotation are immediate. Available at all times,
including mid-Wave.

**Survey View** — A temporary raised, downward-looking camera used while
building. Exists because a Factory is illegible from eye level.
