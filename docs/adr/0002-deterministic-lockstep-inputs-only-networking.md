# 2. Deterministic lockstep with inputs-only networking

Date: 2026-10-06

## Status

Accepted

## Context

4-player co-op over a factory simulation with thousands of moving Items. The
naive approach — replicate entity state — is bandwidth-hostile in exactly the
way this genre is worst at.

The two reference points are unusually clear-cut:

- **Factorio** replicates **only Input Actions** — movement, build intents,
  selections. World state never crosses the wire. Every client simulates every
  tick bit-identically; any divergence is a desync whose only recovery is
  reconnect and a full map re-download. A speculative "Latency State" applies the
  local player's own actions immediately so input feels instant despite lockstep.
  **Belt Items therefore cost zero bandwidth** — they are derived state,
  recomputed identically everywhere, not replicated state.
- **Satisfactory** uses standard Unreal actor replication and has years of public
  conveyor-desync history: Belts stuck rendering as holograms, Items correct on
  host and wrong on client, reconnect-to-fix workflows. Coffee Stain shipped a
  dedicated "Conveyor Networking Rework" patch rather than changing the
  architecture, with ~30 people on the team.
- **FOUNDRY** also uses deterministic lockstep: full world sync on join, then
  inputs only.

No factory game was found that successfully replicates per-item Belt state via
engine replication at scale. The two titles with the fewest multiplayer
complaints both use lockstep; the one using engine replication does not.

## Decision

**Deterministic lockstep, inputs-only on the wire.** Full world state transfers
once on join; thereafter only Input Actions are exchanged. Host is a player
(peer-to-peer listen server), 4 players maximum, drop-in. The Host owns the save.

Local actions apply immediately against a speculative state and reconcile on
confirmation, following Factorio's latency-hiding model.

## Consequences

**Good.** Belt Items — the single largest entity population — are free to
network. Bandwidth scales with player count and intent frequency, not world
size, so a 40-hour megabase networks no worse than a fresh save. Godot's thin
high-level replication API becomes irrelevant, since lockstep barely uses it,
which removes the strongest argument against Godot for multiplayer. Dedicated
servers are unnecessary. And determinism is testable *in single-player* by
replaying recorded inputs, which is why co-op sits last in the milestone order
while costing almost nothing to prepare for.

**Bad.** Determinism becomes a correctness requirement across the entire
simulation rather than a networking concern — any float, any iteration over an
unordered collection, any use of wall-clock time or unseeded randomness is a
latent desync. This demands the fixed-point arithmetic from ADR 0001 and
permanent discipline. Desync recovery is brutal: full state resync. Joining a
large save costs a full world transfer. The simulation cannot be allowed to
diverge per-client for cosmetic reasons, so visual-only effects must be kept
strictly outside the simulation boundary.

**Mitigation.** A determinism test harness exists from the first milestone, not
retrofitted: record inputs, replay, assert the state hash is identical. This
catches divergence the day it is introduced rather than during a co-op session
months later.
