# 1. Godot as a renderer, with a custom fixed-point simulation outside the node tree

Date: 2026-10-06

## Status

Accepted

## Context

A first-person co-op factory-defense game needs three things simultaneously: a
simulation of thousands of Belt Items and Machines, roughly a hundred Enemies,
and first-person combat — in 4-player multiplayer, authored almost entirely by
an AI agent with the human in a playtest-and-direct role.

Engine candidates were Godot 4.6, Unity 6.3 LTS, and Unreal 5.7.

Relevant evidence:

- **FOUNDRY** (Channel 3 Entertainment, 10 full-time staff) runs Unity purely as
  a presentation layer over a custom C++ simulation library, originally a C#/C++
  hybrid and later fully rewritten to C++ for megabase scale. Their reported
  performance profile is ~90% CPU-bound at endgame, dominated by the belt system
  and the items on it. This is a 10-person team shipping the exact shape we want.
- **Godot has no ECS and its nodes are heavy.** Community reports put idiomatic
  `CharacterBody3D` agents at roughly 150-250 before frame times collapse, while
  `MultiMeshInstance3D` reaches 1,000+ — but MultiMesh is rendering only, with no
  collision, navigation or physics.
- **Scene formats differ in kind, not degree.** Godot's `.tscn`/`.tres`/`.gd` are
  human-readable text. Unity's YAML is GUID-dense and unresolvable without
  crawling the asset database. Unreal's `.uasset` is binary and Blueprints are
  binary node graphs an LLM cannot read or write at all.
- **Linux support**: Godot is first-class native with Wayland support; Unity's
  Linux editor is officially supported but second-class; Unreal generally wants a
  source build on Linux and is a standing friction tax. Development is on WSL2.
- **Unreal has the best first-person animation tooling** by a clear margin —
  Motion Matching, Control Rig, and FPS heritage in its character movement.

## Decision

Use **Godot 4.6 as a renderer and input layer only.** All game logic — grid,
Belts, Machines, Power, Heat, Enemy movement — lives in a custom data-oriented
simulation that never touches the node tree. Enemies and Items are entries in
arrays, drawn via MultiMesh, not nodes.

The simulation uses **fixed-point integer arithmetic throughout.** Start in
GDScript; port hot loops to C++ via GDExtension when profiling demands it.

## Consequences

**Good.** Engine-as-renderer makes Godot's missing ECS irrelevant — a custom
data-oriented sim was required in any engine, so the one differentiator that
favoured Unity stops applying. Text scene formats mean an agent can author
content directly without the human operating an editor, which is the decisive
property given how this project is built. Native Linux keeps development on WSL2
where the CUDA toolchain and the rest of the user's environment already live.
Fixed-point arithmetic is the precondition for the lockstep networking in
ADR 0002, and is very expensive to retrofit — floats diverge across machines and
lockstep desyncs on any divergence.

**Bad.** Godot has the weakest first-person animation tooling of the three, and
that taxes the project's highest-risk pillar: combat feel. Mitigated by buying
animation assets and hand-building the first-person weapon layer, but not
eliminated. Fixed-point maths is more awkward to write than floats and needs
care at every boundary with Godot's float-based APIs. Bypassing the node tree
means forgoing Godot's built-in collision, navigation and animation for Enemies
— all of that becomes ours to own.

**Reversal cost.** Very high. This shapes every system. The trigger that would
have justified Unreal instead is combat feel being the single highest priority
above all else; that was considered and explicitly ranked below shippability
and AI-authorability.
