"""Which tuning values get a slider, and between what.

A slider is right for a **feel** value: one you find by dragging it while the
Run is in front of you, where the useful range is known and the exact number is
not. A number box is right for everything else — a hit point total, a Heat rate,
a capacity — where the interesting edits are not small nudges and a range would
be a guess that quietly fenced the tuner in.

So this table is only the first kind, and it is the one piece of metadata in the
whole dashboard that the tuning file does not already carry. It carries no
*descriptions*: what a value does is the file's own comment, always, because a
second description is one that drifts.

Two rules make the table safe to leave behind:

- **A key that is not in it gets a number box.** So a key added to
  `content/tuning.toml` tomorrow is editable today, and this file going stale
  costs a slider rather than correctness.
- **Every bound is inside what `Definitions` accepts**, so dragging a slider to
  either stop cannot produce a definition set the game refuses. `bob_stride`
  bottoms out above zero because it is a divisor; `field_of_view` stays inside
  0–180; `frontal_armour_percent` stops at 99 rather than 100.
  `tests/test_controls.py` asserts the first half of that, and the deep check in
  `definitions_check` is what enforces the second half at the moment of writing.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Range:
    minimum: float
    maximum: float
    step: float


## `section.key` → the slider's stops. Grouped as the file groups them.
SLIDERS: dict[str, Range] = {
    # ── The body ──────────────────────────────────────────────────────────────
    "player.walk_speed_metres_per_second": Range(0.5, 12, 0.1),
    "player.sprint_speed_multiplier": Range(1, 3, 0.05),
    "player.walk_acceleration_metres_per_second_squared": Range(1, 80, 1),
    "player.walk_deceleration_metres_per_second_squared": Range(1, 80, 1),
    "player.air_acceleration_metres_per_second_squared": Range(0, 40, 0.5),
    "player.air_deceleration_metres_per_second_squared": Range(0, 40, 0.5),
    "player.jump_height_metres": Range(0, 3, 0.05),
    "player.gravity_metres_per_second_squared": Range(5, 60, 0.5),
    "player.land_settle_seconds": Range(0, 1, 0.01),
    "player.land_settle_acceleration_percent": Range(0, 100, 5),
    "player.sprint_ramp_seconds": Range(0, 2, 0.05),
    # ── The camera's response ─────────────────────────────────────────────────
    "player.bob_vertical_metres": Range(0, 0.08, 0.001),
    "player.bob_lateral_metres": Range(0, 0.08, 0.001),
    # A divisor, so it stops above zero rather than at it.
    "player.bob_stride_metres": Range(0.5, 8, 0.1),
    "player.bob_sprint_multiplier": Range(0, 3, 0.05),
    "player.land_dip_metres": Range(0, 0.2, 0.005),
    "player.land_dip_seconds": Range(0, 1, 0.01),
    # Also a divisor.
    "player.land_dip_reference_speed_metres_per_second": Range(1, 20, 0.5),
    "player.lean_roll_degrees_per_metre_per_second": Range(0, 1, 0.01),
    "player.lean_pitch_degrees_per_metre_per_second": Range(0, 1, 0.01),
    # Inside 0–180, which is what the loader insists on.
    "player.field_of_view_degrees": Range(60, 120, 1),
    "player.sprint_field_of_view_add_degrees": Range(0, 30, 1),
    "player.holster_seconds": Range(0, 1, 0.05),
    "player.look_sensitivity_turns_per_1000_pixels": Range(0.02, 1, 0.01),
    "player.eye_height_metres": Range(1, 2, 0.01),
    # ── First-person combat ───────────────────────────────────────────────────
    "gear.enemy_hit_radius_metres": Range(0.2, 3, 0.05),
    "gear.enemy_hit_height_metres": Range(0.5, 4, 0.05),
    "gear.view_kick_degrees_per_shot": Range(0, 3, 0.05),
    "gear.view_kick_recover_seconds": Range(0.05, 3, 0.05),
    # ── Survey View ───────────────────────────────────────────────────────────
    # Has to stay above eye level, which tops out at 2 m.
    "survey.height_metres": Range(5, 60, 1),
    "survey.transition_seconds": Range(0, 2, 0.05),
    "survey.pitch_degrees": Range(0, 89, 1),
    # ── Reaches: how close you stand to do a thing ────────────────────────────
    "wrench.reach_metres": Range(1, 10, 0.5),
    "nest.delivery_reach_metres": Range(1, 15, 0.5),
    "silo.load_reach_metres": Range(1, 10, 0.5),
    "enemy.player_bite_reach_metres": Range(0.5, 5, 0.1),
    # ── The rhythm of a Wave ──────────────────────────────────────────────────
    "wave.telegraph_seconds": Range(1, 60, 1),
    "wave.spawn_interval_seconds": Range(0.1, 5, 0.1),
    # ── How the Enemies move and bite ─────────────────────────────────────────
    "enemy.crawler_speed_metres_per_second": Range(0.5, 10, 0.25),
    "enemy.breaker_speed_metres_per_second": Range(0.5, 10, 0.25),
    "enemy.crawler_attack_interval_seconds": Range(0.25, 5, 0.25),
    "enemy.breaker_attack_interval_seconds": Range(0.25, 5, 0.25),
    # ── The boss fight, which is all feel ─────────────────────────────────────
    "siege_hulk.speed_metres_per_second": Range(0.25, 5, 0.25),
    "siege_hulk.range_metres": Range(20, 120, 1),
    "siege_hulk.shell_interval_seconds": Range(1, 20, 0.5),
    "siege_hulk.shell_flight_seconds": Range(0.5, 10, 0.5),
    "siege_hulk.shell_blast_radius_metres": Range(1, 20, 0.5),
    # Stops at 99: a Hulk that shrugged off everything would be unkillable.
    "siege_hulk.frontal_armour_percent": Range(0, 99, 1),
    "siege_hulk.hit_radius_metres": Range(0.5, 5, 0.1),
    "siege_hulk.hit_height_metres": Range(1, 8, 0.1),
    "hive.hit_radius_metres": Range(0.5, 6, 0.1),
    "hive.hit_height_metres": Range(1, 10, 0.1),
}


def slider_for(key: str) -> Range | None:
    return SLIDERS.get(key)
