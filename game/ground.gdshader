// The ground the Factory is built on, and the 2 m grid drawn **on** it.
//
// A flat plane with a grid texture is a placeholder, and reads as one: a uniform
// sheet with the build grid as its only surface. This replaces both halves of
// that.
//
// ── The surface ──────────────────────────────────────────────────────────────
//
// Three of #20's generated maps, sampled in **world space** rather than from the
// mesh's UVs, so the texture density is a number in metres and does not change
// when the plane is made bigger. Poured concrete is the floor of the Map — the
// palette says so in as many words, and it is the one generated map deliberately
// left out of the Machine materials for exactly this. Rust and soot blend over it
// on two octaves of value noise at very different scales: a broad one that says
// which part of the yard is worn, and a tighter one that breaks up the join.
//
// The result is not a repeating sheet. That matters more than any single texture
// does: the eye finds a tile repeat in about a second, and once it has, the ground
// is a material sample rather than a place.
//
// ── Breaking the repeat, and the relief under it (#42) ───────────────────────
//
// A playtest found the repeat anyway — *"the textures don't look so tiled"* — and
// the reason was that each map was read **once, at one density, on one axis**.
// Blending three maps over noise hides where one ends and the next begins; it does
// nothing at all about the fact that each of them repeats every few metres on a
// perfect lattice, and a lattice is what the eye is actually finding.
//
// `detiled` is the fix and it is two changes in one function. Each map is read
// **twice** — once at its stated density and once turned 21 degrees off-axis and
// scaled by the golden ratio — and the two are mixed by a noise far broader than
// either. Turned and rescaled, the second read's lattice is incommensurate with the
// first's, so there is no distance at which both repeat together and no repeat for
// the eye to lock onto. Ahead of both, the sampling coordinate is **warped** by a
// slow noise, which bends the lattice itself: a straight line of repeats becomes a
// wandering one, which is the cheap half of the trick and does most of the work at
// grazing angles where the repeat is most visible.
//
// The second half of the complaint was *"the ground should be slightly bumpy/
// textured like real dirt"*, and the reason it was not is that this shader wrote
// `ALBEDO` and nothing else. However worn the picture looked, the surface was
// geometrically a sheet of glass: one normal over the whole Map, so the sun fell on
// every square metre identically and nothing cast the tiny shadow that says
// "ground". #20's generated set is albedo-only — there is no normal map to load —
// so the relief is **derived rather than textured**: `ground_height` is a
// three-octave value-noise height field in world metres, and `fragment` takes its
// gradient by four extra evaluations and bends the world normal along it.
//
// Derived rather than generated on purpose. A normal map baked off the albedo would
// be a second file to commit, to keep in step with its albedo, and to re-derive
// whenever the texture is regenerated — and it would still repeat on the same
// lattice the albedo does, which is the problem above. A world-space height field
// has no lattice, costs no bytes, and is the same arithmetic at every scale.
//
// It fades out with distance, because a two-centimetre clod is smaller than a pixel
// past about forty metres and a sub-pixel normal is not detail, it is noise.
//
// ── The grid ─────────────────────────────────────────────────────────────────
//
// The 2 m grid is load-bearing — a player builds against it — so it is drawn
// rather than textured, from the world position, with `fwidth` setting the line
// width in *pixels*. That is what keeps it a marking: one crisp pixel-wide line
// at any distance and any resolution, with no mip chain turning the far half of
// the yard into grey noise, and it fades out as the lines converge past the point
// where a player could read them anyway. Every fifth line is brighter, because
// counting to ten tiles by eye needs something to count.
//
// ── The edge of the world ────────────────────────────────────────────────────
//
// `build_extent_metres` is where the Simulation stops accepting a build. Inside
// it the ground carries the grid and the paint; outside it the markings stop and
// the surface darkens into an unpaved apron that runs on past the fence. The Map
// no longer ends at a cliff of nothing — it ends at a boundary with ground beyond
// it, which is what a yard looks like.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D concrete : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D worn : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// How many metres one tile of each map covers. Metres, not UV repeats, because
// world-space sampling makes density independent of the mesh.
uniform float concrete_metres = 3.2;
uniform float worn_metres = 2.3;
uniform float grime_metres = 5.7;

uniform vec3 concrete_tint : source_color = vec3(0.40, 0.40, 0.39);
uniform vec3 worn_tint : source_color = vec3(0.33, 0.28, 0.24);
uniform vec3 grime_tint : source_color = vec3(0.24, 0.23, 0.22);

// The build grid: its pitch in metres, how far the buildable Map reaches, and the
// colour of a marking painted on concrete.
uniform float tile_metres = 2.0;
uniform float build_extent_metres = 128.0;
uniform vec3 grid_colour : source_color = vec3(0.58, 0.57, 0.50);
uniform float grid_strength = 0.21;
uniform float grid_major_every = 5.0;
// Where the lines stop being worth drawing, in metres from the camera.
uniform float grid_fade_begin = 45.0;
uniform float grid_fade_end = 130.0;

// How much darker the unpaved ground past the Map's edge is.
uniform float apron_darkness = 0.78;

uniform float surface_roughness = 0.97;

// ── Breaking the repeat ──
//
// How far, in metres, the slow warp may push a sampling coordinate. Big enough that
// the lattice visibly wanders over the width of the yard, small enough that it does
// not smear the texture into streaks.
uniform float detile_warp_metres = 2.4;
// How much denser the second read of a map is than the first. The golden ratio, so
// the two lattices share no common period and never line up anywhere.
uniform float detile_scale_ratio = 1.618034;
// How far the second read is turned off-axis, in radians. 21 degrees: far enough
// that its grain runs visibly across the first's, not so far that a directional
// texture reads as two materials.
uniform float detile_turn_radians = 0.3665;

// ── The relief ──
//
// How tall the derived height field is, peak to trough, in metres.
//
// **What is visible is the slope, not the height**, which is the thing this got
// wrong first and cost three renders to find. Two centimetres of bump spread over a
// metre is a one-degree tilt and a 23-degree sun cannot find it; the same two
// centimetres over ten is twelve degrees and reads immediately. So the number that
// matters is this one *over* `bump_metres`, the first attempt set it at 0.026 and
// rendered a sheet of glass, and the value here was bracketed by looking: 0.12 is
// visibly gravel, 0.03 is invisible, 0.075 is a yard.
uniform float bump_height_metres = 0.075;
// The coarsest feature size in that field, in metres. A clod, not a bootprint — see
// above for why this is small rather than large.
uniform float bump_metres = 0.11;
// How far apart the gradient is sampled, in metres. Smaller is sharper and noisier;
// about a fifth of `bump_metres` keeps the coarse octave smooth while still letting
// the fine ones through.
uniform float bump_step_metres = 0.025;
// Where the relief stops being worth computing, in metres from the camera. Past the
// far end a clod is smaller than a pixel on a plane seen nearly edge-on, and a
// sub-pixel normal is not detail — it is a shimmer that follows the camera.
uniform float bump_fade_begin = 26.0;
uniform float bump_fade_end = 70.0;

varying vec3 world_position;


float hashed(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453123);
}


// Value noise. Cheap, smooth, and good enough for "which part of the yard is
// worn" — this is a blend weight, not a surface.
float value_noise(vec2 at) {
	vec2 cell = floor(at);
	vec2 within = fract(at);
	vec2 eased = within * within * (3.0 - 2.0 * within);
	float a = hashed(cell);
	float b = hashed(cell + vec2(1.0, 0.0));
	float c = hashed(cell + vec2(0.0, 1.0));
	float d = hashed(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, eased.x), mix(c, d, eased.x), eased.y);
}


vec2 turned_by(vec2 at, float radians) {
	float c = cos(radians);
	float s = sin(radians);
	return vec2(at.x * c - at.y * s, at.x * s + at.y * c);
}


// One map, read so that it does not repeat on a lattice.
//
// Warp the coordinate on a slow noise so the lattice bends; read the map at its own
// density; read it again turned and rescaled so the second lattice is incommensurate
// with the first; and mix the two on a noise broader than either, so most of the
// ground is one read or the other and only a wide soft band is both. See the header.
vec3 detiled(sampler2D map, vec2 at, float metres) {
	vec2 warped = at + vec2(
		value_noise(at * 0.019) - 0.5,
		value_noise(at * 0.019 + vec2(43.0, 17.0)) - 0.5
	) * detile_warp_metres;
	vec3 first = texture(map, warped / metres).rgb;
	vec3 second = texture(
		map, turned_by(warped, detile_turn_radians) / (metres * detile_scale_ratio)
	).rgb;
	// A **narrow** crossfade on purpose. Two decorrelated reads of one texture average
	// to half its variance, so a wide band would de-tile the ground by flattening it,
	// which trades one wrong answer for another. Narrow, and almost all of the yard is
	// one read at full contrast with a soft seam between.
	float which = smoothstep(0.44, 0.56, value_noise(at * 0.0091 + vec2(7.0, 61.0)));
	return mix(first, second, which);
}


// How high the dirt stands at a point, in the 0..1 the gradient is taken of.
//
// Three octaves — clods, grit, and the fine tooth that catches a raking sun —
// weighted so the coarsest dominates, because an even mix reads as sandpaper rather
// than as ground.
//
// **Each octave is turned off the one below it.** `value_noise` is built on a square
// lattice, so three octaves sharing an axis would lay their corners on top of each
// other and the relief would acquire exactly the grid this file is otherwise trying
// to break. The turns are not round numbers for the same reason the de-tiler's
// scale ratio is not.
float ground_height(vec2 at) {
	vec2 scaled = at / bump_metres;
	return (
		value_noise(scaled) * 0.58
		+ value_noise(turned_by(scaled, 0.71) * 2.9 + vec2(13.0, 29.0)) * 0.28
		+ value_noise(turned_by(scaled, 1.93) * 8.3 + vec2(67.0, 3.0)) * 0.14
	);
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


// One axis-aligned family of lines through the world, antialiased to a constant
// width in pixels. `fwidth` is how far the coordinate moves across one pixel, so
// dividing by it turns "distance from a line in metres" into "distance in pixels"
// and the line stays one pixel wide however far away it is.
float line_mask(vec2 across, float pitch) {
	vec2 scaled = across / pitch;
	vec2 distance_to_line = abs(fract(scaled - 0.5) - 0.5);
	vec2 pixels = distance_to_line / max(fwidth(scaled), vec2(0.00001));
	return 1.0 - min(min(pixels.x, pixels.y), 1.0);
}


void fragment() {
	vec2 at = world_position.xz;

	vec3 base = detiled(concrete, at, concrete_metres) * concrete_tint;
	vec3 rusted = detiled(worn, at, worn_metres) * worn_tint;
	vec3 sooted = detiled(grime, at, grime_metres) * grime_tint;

	// Broad: which quarter of the yard is bare ground rather than slab.
	float wear = value_noise(at * 0.011);
	// Tight: breaks the join so the blend is a stain rather than a contour line.
	wear = clamp(wear + (value_noise(at * 0.071) - 0.5) * 0.35, 0.0, 1.0);
	vec3 surface = mix(base, rusted, smoothstep(0.52, 0.88, wear));

	// Soot pools in its own places, and a good deal more sparsely.
	float soot = smoothstep(0.62, 0.92, value_noise(at * 0.027 + vec2(37.0, 11.0)));
	surface = mix(surface, sooted, soot * 0.7);

	// A slow swing in brightness at a scale bigger than anything a player walks
	// across in a second, so the plane never reads as one flat value.
	surface *= mix(0.80, 1.16, value_noise(at * 0.0043));

	float inside = step(abs(at.x), build_extent_metres) * step(abs(at.y), build_extent_metres);

	float distance_out = length(world_position - CAMERA_POSITION_WORLD);
	float legible = 1.0 - smoothstep(grid_fade_begin, grid_fade_end, distance_out);
	float minor = line_mask(at, tile_metres);
	float major = line_mask(at, tile_metres * grid_major_every);
	// **Paint wears off.** The markings are multiplied by the same noise that decides
	// which part of the yard is slab and which is bare ground, so the grid is strong on
	// clean concrete, faint over a worn patch and gone under the soot. That is the one
	// change that stops it reading as graph paper: a line of uniform strength everywhere
	// is a grid *overlay*, and a line that the ground eats into is a marking.
	// Two scales again: the broad wear says which half of the yard was ever painted,
	// and a tighter one scuffs individual metres of it, which is what a player walking
	// along a line actually sees.
	float scuff = value_noise(at * 0.09 + vec2(5.0, 91.0));
	float paint = clamp(1.0 - wear * 1.35, 0.0, 1.0)
		* (1.0 - soot * 0.85)
		* smoothstep(0.18, 0.62, scuff);
	float grid = clamp(minor * 0.34 + major, 0.0, 1.0) * legible * inside * grid_strength * paint;

	// Painted on, not cut in: the marking lightens the surface it sits on rather
	// than replacing it, so the concrete's own grain still shows through a line.
	surface = mix(surface, grid_colour, grid);
	// Past the Map's edge the ground is unpaved: darker, and desaturated towards the
	// smog rather than merely dimmed, so the boundary does not read as a hard red band.
	float grey = dot(surface, vec3(0.3, 0.59, 0.11));
	surface = mix(mix(vec3(grey), surface, 0.55) * apron_darkness, surface, inside);

	ALBEDO = surface;

	// **The relief.** `ground_height` has no analytic derivative, so the gradient is
	// four extra evaluations a fragment and a central difference. The result bends the
	// *world* normal and only then goes to view space, which is why this needs no
	// tangent frame and no UVs — a `NORMAL_MAP` would need both, and the plane has
	// neither. Faded out with distance for the reason in the header.
	float relief = 1.0 - smoothstep(bump_fade_begin, bump_fade_end, distance_out);
	if (relief > 0.002) {
		float step_metres = bump_step_metres;
		float east = ground_height(at + vec2(step_metres, 0.0));
		float west = ground_height(at - vec2(step_metres, 0.0));
		float north = ground_height(at + vec2(0.0, step_metres));
		float south = ground_height(at - vec2(0.0, step_metres));
		// Bare ground is rougher than slab, so the clods stand up where the concrete
		// has worn through and lie flat where it has not. Same `wear` the albedo uses,
		// so what you see bumpy is what you see worn.
		float relief_gain = bump_height_metres * relief * mix(0.45, 1.0, wear);
		vec2 slope = vec2(east - west, north - south) * relief_gain / (2.0 * step_metres);
		vec3 bumped = normalize(vec3(-slope.x, 1.0, -slope.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
	}

	// Dirt scatters and slab does not, so roughness follows the wear rather than
	// sitting at one number. It is also the cheapest remaining de-tiler: a uniform
	// roughness makes a whole plane catch the sun identically, which reads as one
	// surface however many textures are blended into it.
	ROUGHNESS = clamp(surface_roughness * mix(0.88, 1.0, wear) + soot * 0.03, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.12;
}
