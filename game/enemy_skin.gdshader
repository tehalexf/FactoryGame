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

// How dark an Enemy goes as its hit points run out, as a fraction taken off its albedo at
// zero health. Carried per instance on INSTANCE_CUSTOM.y, so a Crawler a Turret has been
// working on reads as hurt without a gauge over it.
uniform float wound_darkening : hint_range(0.0, 1.0) = 0.45;

// ── What is left in the custom data, which is the next ticket's room ─────────
//
// `INSTANCE_CUSTOM` is four floats and two of them are spoken for: `.x` is the animation
// row and `.y` is the health fraction above. **`.z` and `.w` are written as zero by
// `_write_skinned_instance` and read by nothing**, so anything that wants to say something
// per Enemy has two channels already paid for — the stride is fixed at sixteen whatever
// they carry, so using them costs no bandwidth and no second buffer.
//
// Worth knowing before reaching for `use_colors` instead: turning that on widens the stride
// to twenty, which means `_write_skinned_instance`, `_stride_for` and every accessor that
// divides by it. A free channel is much the cheaper door.
//
// And one thing about *this* file that a damage ticket will meet immediately: the grime
// field below is a function of the **rest pose alone**, so it is identical on every Enemy
// of a kind. A mark that has to be in a different place on each one — scorching, a wound —
// wants a per-instance offset into that field, which is exactly what one of the two free
// channels is for: `grime_at(rest + vec3(seed))`.

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
float grime_at(vec3 at) {
	vec3 scaled = at / grime_metres;
	float coarse = value_noise(scaled);
	vec3 turned = vec3(scaled.z * 2.17 + 11.3, scaled.x * 2.17 - 7.1, scaled.y * 2.17 + 3.9);
	return clamp(coarse * 0.68 + value_noise(turned) * 0.32, 0.0, 1.0);
}

void vertex() {
	int row = int(INSTANCE_CUSTOM.x);
	health = INSTANCE_CUSTOM.y;
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

	ALBEDO = (
		colour.rgb
		* mix(1.0 - grime_depth, 1.0, dirt)
		* mix(1.0 - wound_darkening, 1.0, clamp(health, 0.0, 1.0))
	);
	ALPHA = colour.a;
	METALLIC = metallic;
	ROUGHNESS = clamp(roughness + (0.5 - dirt) * 2.0 * roughness_spread, 0.04, 1.0);

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
