shader_type spatial;

// The running surface of a Belt: the generated trestle's own rubber deck, with steel cleats
// crossing it that travel the way its cargo does.
//
// **Why a shader and not geometry.** A Belt tile is one instance in one MultiMesh shared by
// every Belt on the Map — hundreds of tiles in a late Factory — so moving slats would be
// moving slats per tile, which is the one thing this system's data layout exists to avoid. A
// band computed in the fragment shader costs nothing per tile and nothing per frame.
//
// **Why the cleats are read in object space.** Every Belt body is modelled running along its
// own +Z and placed by a yaw (`WorldView._yaw_for_direction`), so `VERTEX` in the vertex stage
// is distance along the run whichever way the Belt points on the Map. A world-space read would
// have made a north-south line and an east-west line scroll in unrelated directions, and a UV
// read would have depended on an unwrap the mesh generator is free to change.
//
// **Nothing here is timed by a clock.** `scroll` is handed in by `WorldView._sync_belts` as a
// fraction of one cleat pitch, computed from `Simulation.query_tick()` — see the note on
// `BELT_CLEAT_PITCH_SLOTS`. Two Runs down the same script draw the same deck, and a frame that
// stepped no ticks draws what the last one did.

// The deck's own surface, carried over from the `BeltRubber` material this replaces so the
// generated look is kept rather than painted over.
uniform sampler2D deck_map : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 deck_colour : source_color = vec4(0.3, 0.3, 0.32, 1.0);
uniform vec2 deck_map_scale = vec2(1.0, 1.0);
uniform float deck_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float deck_roughness : hint_range(0.0, 1.0) = 0.85;

// The cleats. Steel rather than a darker rubber, because a dark band on a near-black deck is
// the brightness-only contrast #52 measured and threw away — and because a cleated conveyor
// really does carry steel slats. `cleat_colour` is the palette's own `WeldedSteel`.
uniform vec4 cleat_colour : source_color = vec4(0.14, 0.145, 0.15, 1.0);
uniform float cleat_pitch_metres = 0.5;
uniform float cleat_width : hint_range(0.0, 0.5) = 0.17;
uniform float cleat_roughness : hint_range(0.0, 1.0) = 0.38;

// How far along one pitch the cleats have travelled, 0 to 1. Driven by the tick.
uniform float scroll = 0.0;

varying vec3 along_the_run;

void vertex() {
	along_the_run = VERTEX;
}

void fragment() {
	vec3 deck = deck_colour.rgb * texture(deck_map, UV * deck_map_scale).rgb;

	// Subtracted rather than added, so the cleats travel toward +Z — the direction the body is
	// modelled running in and therefore the direction its Items advance.
	float phase = fract(along_the_run.z / cleat_pitch_metres - scroll);
	// Distance to the nearest cleat line, as a fraction of half a pitch, so the band is
	// symmetric and wraps without a seam.
	float to_cleat = abs(phase - 0.5) * 2.0;
	float cleat = smoothstep(1.0 - cleat_width, 1.0 - cleat_width * 0.35, to_cleat);

	ALBEDO = mix(deck, cleat_colour.rgb, cleat);
	METALLIC = mix(deck_metallic, 1.0, cleat);
	ROUGHNESS = mix(deck_roughness, cleat_roughness, cleat);
}
