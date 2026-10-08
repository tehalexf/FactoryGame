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

varying float health;

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

void vertex() {
	int row = int(INSTANCE_CUSTOM.x);
	health = INSTANCE_CUSTOM.y;

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
}

void fragment() {
	vec4 colour = albedo_tint;
	if (has_albedo_texture) {
		colour *= texture(albedo_texture, UV);
	}
	ALBEDO = colour.rgb * mix(1.0 - wound_darkening, 1.0, clamp(health, 0.0, 1.0));
	ALPHA = colour.a;
	METALLIC = metallic;
	ROUGHNESS = roughness;
}
