shader_type spatial;
render_mode specular_schlick_ggx, cull_back, blend_mix, depth_draw_always;

uniform vec4 tint_color : source_color = vec4(0.08, 0.35, 0.65, 0.88);
uniform sampler2D water_normal : hint_normal;
uniform float normal_scale = 0.048;
uniform float normal_time_scale = 0.06;
uniform vec2 normal_move_dir_a = vec2(-1.0, 0.2);
uniform vec2 normal_move_dir_b = vec2(0.2, 1.0);
uniform float refraction_test = 0.35;
uniform float refraction_offset_scale = 0.08;
uniform float roughness = 0.12;
uniform float specular = 1.0;
uniform float color_intensity = 1.0;
uniform float normal_bump_strength = 1.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

varying vec2 vertex_uv;

void vertex() {
	vertex_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv_a = vertex_uv * normal_scale + TIME * normal_move_dir_a * normal_time_scale;
	vec2 uv_b = vertex_uv * normal_scale + TIME * normal_move_dir_b * normal_time_scale;
	vec3 n_a = texture(water_normal, uv_a).xyz * 2.0 - 1.0;
	vec3 n_b = texture(water_normal, uv_b).xyz * 2.0 - 1.0;
	vec3 n = normalize(vec3((n_a.xy + n_b.xy) * normal_bump_strength, n_a.z * n_b.z));
	mat3 tbn = mat3(normalize(TANGENT), normalize(BINORMAL), normalize(NORMAL));
	vec3 world_normal = normalize(tbn * n);
	vec3 screen_col = texture(screen_texture, SCREEN_UV + world_normal.xy * refraction_offset_scale * refraction_test).rgb;
	vec3 base = mix(tint_color.rgb, screen_col, 0.3) * color_intensity;
	ALBEDO = base;
	ALPHA = tint_color.a;
	NORMAL = world_normal;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
