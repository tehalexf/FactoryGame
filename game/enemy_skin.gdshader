// Skins one Enemy out of a texture of bone poses, so the whole swarm draws from one
// MultiMesh and the scene tree never gains a node for a Crawler (ADR 0001).
//
// This is the vertex-animation technique the ticket names, with the baked quantity changed
// from vertex positions to **skinning matrices**. `EnemyBodies` writes three RGBA texels a
// bone across and one row a frame down; `EnemyAnimator` decides which row; and the whole of
// what happens here is the four-bone linear blend that any skinned mesh does, out of
// attributes a MultiMesh can actually carry.
//
// Three things about it worth knowing before changing anything:
//
// * **The bone indices and weights arrive as CUSTOM0 and CUSTOM1, not as ARRAY_BONES.** A
//   shader can only see ARRAY_BONES through a Skeleton3D, and a MultiMesh has none — so the
//   bake moves them into ordinary vertex attributes and drops the skinning declaration, and
//   this file is the only thing that skins the mesh.
// * **The row is read with texelFetch and the sampler filters nearest.** A matrix
//   interpolated between two texels is not a matrix; a bilinear read across a bone boundary
//   would blend one bone's third row into the next bone's first.
// * **Which row comes in on INSTANCE_CUSTOM.x**, as a float carrying an integer. That is
//   the whole of the per-instance animation state: no clock, no time uniform, nothing the
//   renderer remembers — the row is arithmetic over the tick, the Enemy's spawn tick and
//   its serial, so two Runs down the same script put the same frame on the same Crawler.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// The baked skinning matrices. Not `source_color`: these are numbers, and an sRGB curve
// applied to a matrix is a character turned inside out.
uniform sampler2D pose : filter_nearest, repeat_disable;
// How many texels one bone occupies, so the fetch and `EnemyBodies.TEXELS_PER_BONE` cannot
// drift apart without somebody passing a different number.
uniform int texels_per_bone = 3;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_texture = false;
// What the pack's own colours are multiplied by. The committed skeletons are bone-white and
// this palette runs 0.055 to 0.14 albedo, so a character dropped in untinted is the
// brightest thing in frame — which is the mistake #32 found on the Walls, measured rather
// than guessed, and the reason a colour picked against a white background is a colour
// picked against the wrong thing.
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;

// There were two emission uniforms here and #49 removed them with the branch that set
// them. They painted the characters' own `Glow` material — their eye sockets — and the
// geometry is inside the skull on every committed character, so nothing ever reached the
// screen. `WorldView._skinned_mesh` carries the whole note and the measurement.

// ── What damage looks like (#70) ─────────────────────────────────────────────
//
// **The darkening was here since #38 and it is invisible, which is the finding this ticket
// turned on.** `INSTANCE_CUSTOM.y` has carried the health fraction from the day the
// characters arrived, and `ALBEDO *= mix(1.0 - wound_darkening, 1.0, health)` is a correct
// implementation of the wrong idea: these bodies are already the darkest thing in frame —
// #75 measured the median Enemy pixel at 0.021 linear against a ground at 0.046 — so taking
// another 45% off a mortally wounded Crawler moves it from *dark against dark ground* to
// *darker against dark ground*, and at thirty metres that is a silhouette either way. It is
// #42's Wall, #52's ore, #64's tool and #65's gloves a fifth time: **a value picked against
// the wrong background**, and the background here is almost black.
//
// So a wound is **light** rather than the absence of it, and the vocabulary is already in
// this world: the Siege Hulk's vent is an unshaded glow and is the one place geometry
// carries a rule (#16). A hurt Enemy is a casting cracked open with something hot inside it,
// and what decides *where* it cracks is the grime field the surface is already derived from,
// offset per Enemy by `INSTANCE_CUSTOM.z` so six Crawlers are not six copies of one Crawler.
//
// The soot stays and its job changed, exactly as the per-kind tint's did in #75: it is no
// longer asked to carry the signal, so it is halved — enough to dirty a body around the
// cracks and nowhere near enough to be the thing a player reads.
uniform float wound_darkening : hint_range(0.0, 1.0) = 0.22;

// What the inside of one of these looks like. Hot iron, near the palette's own furnace
// colours, and **emissive** — which is what survives thirty metres of depth fog and a body
// that is a silhouette, where no albedo can. The glow threshold this project renders at is
// deliberately high, so it reads as heat rather than as bloom.
uniform vec3 wound_glow : source_color = vec3(1.0, 0.36, 0.09);
uniform float wound_glow_strength = 6.0;
// Where the field has to reach before a crack opens, at full health and at none.
//
// **Two numbers rather than one fraction, and a render is why.** The first version thresholded
// against 1.0 and scaled by how hurt the body was, which is arithmetically tidy and wrong
// about this field: two octaves of value noise averaged 0.68/0.32 do not reach the ends of
// their own range, so practically nothing is above 0.79 and a Breaker at half health opened
// **nothing at all**. The band is measured against where the field actually lives.
uniform float wound_closed_at : hint_range(0.0, 1.5) = 0.82;
uniform float wound_open_at : hint_range(0.0, 1.0) = 0.58;
// How big a crack is, as a fraction of the Enemy's own height. **Six times the grime's**, and
// a render is why: read at the grime's own three-centimetre scale a dying Breaker came out as
// a speckled leopard — which is dirt-sized detail doing a wound's job, and reads as camouflage
// rather than as a body that has come apart. A crack is the size of a limb segment.
uniform float wound_metres = 0.2;
// How sharp the edge of a crack is. Measured rather than picked: the field's own distribution
// is mean 0.50 and standard deviation 0.149, so a 0.10 ramp above the threshold means a body
// at half health reaches **full** brightness over half a percent of itself and spends the
// rest of its wound in the ramp — which is a crack drawn at a tenth of its intended strength
// and rendered, in the first pass, as nothing at all.
uniform float wound_edge : hint_range(0.001, 0.5) = 0.04;

// How bright a body goes on the tick a round lands on it, and how far up its own glow colour
// that flash is pulled towards white. `INSTANCE_CUSTOM.w` carries how fresh the hit is, out
// of `CombatEvents` — a health fraction is a condition and a round landing is a change, which
// is why one rides `.y` and the other rides `.w`.
uniform float hit_flash_strength = 5.0;
uniform float hit_flash_whiteness : hint_range(0.0, 1.0) = 0.65;

// ── The custom data, all four floats of it ───────────────────────────────────
//
// `.x` is the animation row (#38), `.y` the health fraction (#38), `.z` the wound seed and
// `.w` how fresh the last hit is (#70). #38 left the last two written as zero against
// exactly this ticket and said what they were for — *"a mark that has to be in a different
// place on each one wants a per-instance offset into that field"* — and that is what `.z`
// became, to the line.
//
// **The stride stays sixteen and nothing widened**, which is why a free channel was the door
// rather than `use_colors`: turning that on takes the stride to twenty and with it
// `_write_skinned_instance`, `_stride_for` and every accessor that divides by one.

// ── Grime and relief, derived from the rest pose (#75) ───────────────────────
//
// The committed atlas is a sheet of flat swatches with a vertical gradient and nothing
// else: no pitting, no wear, no baked occlusion. `tools/assets/enemy_grade.py` puts those
// swatches in the palette's own colours and can do nothing at all about the fact that a
// Crawler's whole thigh samples one of them, so graded or not an Enemy renders as a
// *shape* with no surface inside it — which is half of what #75 was opened about.
//
// The props had an answer in hand and these characters do not: heyheythere bakes its
// ambient occlusion into `COLOR_0`, so `prop_grade.deepen_grime` had per-prop geometric
// information about where dirt collects. KayKit's six characters carry **no `COLOR_0` at
// all**, measured — `JOINTS_0, NORMAL, POSITION, TEXCOORD_0, WEIGHTS_0` and nothing more.
//
// So the grime is derived, which is exactly `ground.gdshader`'s answer to the same
// complaint about the yard: *"the ground should be slightly bumpy/textured like real
// dirt"* against an albedo-only generated set with no normal map to load. Three things are
// carried over from that file deliberately.
//
// * **It is sampled in the *rest* pose, not in world space.** The ground's noise is a
//   function of where you are standing, because the yard does not move. An Enemy does, and
//   a world-space read would make the grime swim over a walking Crawler like a projector.
//   The rest position is the one coordinate that is fixed to the body, and it costs one
//   varying — it is the pre-skin `VERTEX`, which this shader already has in hand.
// * **What is visible is the slope, not the height** — #42's three-render lesson. The knob
//   is `relief` over `grime_metres`, and a physically reasoned couple of centimetres over a
//   feature a metre across is a one-degree tilt a 23-degree sun cannot find.
// * **Each octave is turned off the one below it**, so two octaves of a square-lattice
//   noise do not put a lattice back.
//
// The rest pose is in the normalised units `EnemyBodies` bakes a body into — one unit is
// the whole Enemy, whatever `query_enemy_hit_height_metres` then scales it to — so
// `grime_metres` is a *fraction of a body* and the same number gives a Siege Hulk coarser
// pitting than a Crawler in absolute terms, which is the right way round for a thing twice
// the size.
uniform float grime_depth : hint_range(0.0, 1.0) = 0.30;
uniform float grime_metres = 0.034;
uniform float grime_step = 0.008;
// How deep the pitting is, as a fraction of the Enemy's own height — the same shape
// `ground.bump_height_metres` has, and read against `grime_metres` rather than on its own,
// because what a 23-degree sun finds is the **slope** and the slope is this over that (#42).
// 0.012 of a 1.6 m Crawler is about two centimetres of relief over three-centimetre
// features, which is a casting that has been outside.
uniform float relief : hint_range(0.0, 0.2) = 0.012;
// Where the relief stops being paid for, in metres from the eye. `ground.gdshader` fades
// its own bump out over 26 to 70 m for the same two reasons: a procedural field has no mip
// chain, so past the distance where one feature is under a pixel it stops being relief and
// starts being noise; and a Crawler at forty metres is a silhouette with a highlight on it,
// which is what a player is reading at that range anyway.
uniform float relief_fade_begin = 14.0;
uniform float relief_fade_end = 34.0;
// How far roughness is pushed either side of the material's own figure by the same field.
// A surface whose roughness is one number is a surface with one highlight on it; dirt in a
// crease is matte and a worn edge is polished, and that difference is most of what says
// "metal that has been outside" rather than "grey plastic".
uniform float roughness_spread : hint_range(0.0, 0.5) = 0.10;

varying float health;
varying float wound_seed;
varying float hit_flash;
varying vec3 rest;
varying mat3 surface_basis;

// One bone's skinning matrix, out of three texels of one row.
//
// The matrix was written row-major — texel `r` holds row `r` of the 3x4 affine — so the
// basis columns are assembled across the three fetches rather than within one.
mat4 bone_matrix(int bone, int row) {
	int column = bone * texels_per_bone;
	vec4 r0 = texelFetch(pose, ivec2(column + 0, row), 0);
	vec4 r1 = texelFetch(pose, ivec2(column + 1, row), 0);
	vec4 r2 = texelFetch(pose, ivec2(column + 2, row), 0);
	return mat4(
		vec4(r0.x, r1.x, r2.x, 0.0),
		vec4(r0.y, r1.y, r2.y, 0.0),
		vec4(r0.z, r1.z, r2.z, 0.0),
		vec4(r0.w, r1.w, r2.w, 1.0)
	);
}

// Two octaves of value noise over the rest pose, the shape `ground.value_noise` has with a
// third axis. Trilinear rather than bilinear because a body is a volume: a bilinear read on
// two axes would streak the third, which on a standing figure is straight down.
float hashed(vec3 cell) {
	return fract(sin(dot(cell, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

float value_noise(vec3 at) {
	vec3 cell = floor(at);
	vec3 within = fract(at);
	vec3 eased = within * within * (3.0 - 2.0 * within);
	float a = mix(hashed(cell + vec3(0.0, 0.0, 0.0)), hashed(cell + vec3(1.0, 0.0, 0.0)), eased.x);
	float b = mix(hashed(cell + vec3(0.0, 1.0, 0.0)), hashed(cell + vec3(1.0, 1.0, 0.0)), eased.x);
	float c = mix(hashed(cell + vec3(0.0, 0.0, 1.0)), hashed(cell + vec3(1.0, 0.0, 1.0)), eased.x);
	float d = mix(hashed(cell + vec3(0.0, 1.0, 1.0)), hashed(cell + vec3(1.0, 1.0, 1.0)), eased.x);
	return mix(mix(a, b, eased.y), mix(c, d, eased.y), eased.z);
}

// 0 is a crease and 1 is a face the weather has got at. The second octave is turned off the
// first's axes, for `ground_height`'s reason: two octaves of a square lattice sharing an
// axis reinstate the lattice the rest of this is for removing.
float field_at(vec3 at, float metres) {
	vec3 scaled = at / metres;
	float coarse = value_noise(scaled);
	vec3 turned = vec3(scaled.z * 2.17 + 11.3, scaled.x * 2.17 - 7.1, scaled.y * 2.17 + 3.9);
	return clamp(coarse * 0.68 + value_noise(turned) * 0.32, 0.0, 1.0);
}


float grime_at(vec3 at) {
	return field_at(at, grime_metres);
}

void vertex() {
	int row = int(INSTANCE_CUSTOM.x);
	health = INSTANCE_CUSTOM.y;
	wound_seed = INSTANCE_CUSTOM.z;
	hit_flash = INSTANCE_CUSTOM.w;
	rest = VERTEX;

	// The weights sum to one — `EnemyBodies._influences` renormalises after dropping any
	// fifth influence — so the blended matrix is affine and the sum needs no second
	// normalisation here. A weight of zero contributes a matrix multiply and nothing else,
	// which is cheaper than the branch that would skip it.
	mat4 skin =
		bone_matrix(int(CUSTOM0.x), row) * CUSTOM1.x
		+ bone_matrix(int(CUSTOM0.y), row) * CUSTOM1.y
		+ bone_matrix(int(CUSTOM0.z), row) * CUSTOM1.z
		+ bone_matrix(int(CUSTOM0.w), row) * CUSTOM1.w;

	VERTEX = (skin * vec4(VERTEX, 1.0)).xyz;
	// The upper 3x3 without its inverse transpose, which is exact here because a bone pose
	// is a rotation and the bake's normalisation is a *uniform* scale — neither shears, so
	// neither bends a normal away from its surface. A non-uniform scale anywhere in the
	// bake would make this wrong and want the full inverse transpose.
	NORMAL = normalize(mat3(skin) * NORMAL);
	// The basis that takes a direction in the rest pose into the space `fragment` writes
	// `NORMAL` in. The skinning half is a rotation with a uniform scale, so a gradient
	// rotates by exactly the matrix a normal does and needs no inverse transpose — the same
	// argument the line above makes.
	surface_basis = MODELVIEW_NORMAL_MATRIX * mat3(skin);
}

void fragment() {
	vec4 colour = albedo_tint;
	if (has_albedo_texture) {
		colour *= texture(albedo_texture, UV);
	}

	// Four evaluations: the value, and one forward difference an axis. `ground.gdshader`
	// pays the same four for the yard's relief and for the same reason — it needs no tangent
	// frame and no UVs, and a `NORMAL_MAP` would need both. These characters have UVs, and
	// they point at a 64-pixel swatch, so a normal map through them would be a flat colour.
	float dirt = grime_at(rest);
	vec3 slope = vec3(
		grime_at(rest + vec3(grime_step, 0.0, 0.0)) - dirt,
		grime_at(rest + vec3(0.0, grime_step, 0.0)) - dirt,
		grime_at(rest + vec3(0.0, 0.0, grime_step)) - dirt
	) / grime_step;

	// Where this body has opened up. The same field the grime is read out of, offset by the
	// Enemy's own seed so the cracks are in a different place on every one of them, and
	// thresholded against how much health is gone — so damage *spreads* rather than
	// brightening, which is what makes "nearly dead" and "just hit" different pictures.
	float hurt = 1.0 - clamp(health, 0.0, 1.0);
	float seam = field_at(
		rest + vec3(wound_seed, wound_seed * 1.7, wound_seed * 2.3), wound_metres
	);
	float threshold = mix(wound_closed_at, wound_open_at, hurt);
	float opened = smoothstep(threshold, threshold + wound_edge, seam);

	ALBEDO = (
		colour.rgb
		* mix(1.0 - grime_depth, 1.0, dirt)
		* mix(1.0 - wound_darkening, 1.0, clamp(health, 0.0, 1.0))
	);
	ALPHA = colour.a;
	METALLIC = metallic;
	ROUGHNESS = clamp(roughness + (0.5 - dirt) * 2.0 * roughness_spread, 0.04, 1.0);

	// The wound itself, and the flash of a round arriving. One emission, two contributions:
	// the cracks are steady and belong to how hurt the body is, and the flash is whole-body
	// and belongs to the tick a round landed. A flash pulls its colour toward white rather
	// than being a second hue, so a body that is both hurt and freshly hit reads as one thing
	// getting brighter rather than as two marks.
	float lit = clamp(hit_flash, 0.0, 1.0);
	vec3 flash_colour = mix(wound_glow, vec3(1.0), hit_flash_whiteness);
	EMISSION = (
		wound_glow * opened * hurt * wound_glow_strength
		+ flash_colour * lit * hit_flash_strength
	);

	// Bend the normal down the slope, with the component along it taken out first so that
	// the field tilts the surface rather than inflating it.
	float near = 1.0 - smoothstep(relief_fade_begin, relief_fade_end, length(VERTEX));
	// A height field's normal, with the component along the surface normal taken out first
	// so the field tilts the surface rather than inflating it. The gradient is **not**
	// normalised: a flat patch of the field has to stay a flat patch of the body, and
	// normalising would tilt every fragment by the same amount whatever the field is doing
	// — which is what the first render of this looked like, a swarm in chrome camouflage.
	vec3 tilt = surface_basis * slope;
	NORMAL = normalize(NORMAL - relief * near * (tilt - dot(tilt, NORMAL) * NORMAL));
}
