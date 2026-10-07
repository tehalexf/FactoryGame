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

	vec3 base = texture(concrete, at / concrete_metres).rgb * concrete_tint;
	vec3 rusted = texture(worn, at / worn_metres).rgb * worn_tint;
	vec3 sooted = texture(grime, at / grime_metres).rgb * grime_tint;

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
	ROUGHNESS = surface_roughness;
	METALLIC = 0.0;
	SPECULAR = 0.12;
}
