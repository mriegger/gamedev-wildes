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
uniform vec4 ripple_events[8];
uniform vec4 ripple_motions[8];
uniform float ripple_duration = 1.1;
uniform float ripple_speed = 1.35;
uniform float ripple_width = 0.28;
uniform float ripple_strength = 0.55;
uniform float ripple_directionality = 0.65;

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
	vec2 ripple_normal = vec2(0.0);
	for (int index = 0; index < 8; index++) {
		vec4 event = ripple_events[index];
		if (event.w <= 0.0 || event.z >= ripple_duration) {
			continue;
		}
		vec4 motion = ripple_motions[index];
		vec2 forward = motion.xy / max(length(motion.xy), 0.001);
		vec2 right = vec2(-forward.y, forward.x);
		float directional_amount = smoothstep(0.5, 8.0, motion.z) * ripple_directionality;
		vec2 ripple_center = event.xy - forward * 0.22 * directional_amount;
		vec2 offset = vertex_uv - ripple_center;
		float lateral_offset = dot(offset, right);
		float forward_offset = dot(offset, forward);
		float stretch = 1.0 + directional_amount * 0.9;
		float distance_from_step = length(vec2(lateral_offset, forward_offset / stretch));
		vec2 normal_gradient = right * lateral_offset + forward * forward_offset / (stretch * stretch);
		vec2 direction = normal_gradient / max(length(normal_gradient), 0.001);
		float wave_radius = event.z * ripple_speed;
		float wave_distance = distance_from_step - wave_radius;
		float band = 1.0 - smoothstep(ripple_width * 0.35, ripple_width, abs(wave_distance));
		float fade_in = smoothstep(0.0, 0.1, event.z);
		float fade_out = 1.0 - smoothstep(ripple_duration * 0.58, ripple_duration, event.z);
		float wave = cos(wave_distance * 3.14159265 / ripple_width);
		float forward_ratio = dot(offset / max(length(offset), 0.001), forward);
		float wake_bias = mix(1.0, mix(1.35, 0.72, smoothstep(-0.7, 0.7, forward_ratio)), directional_amount);
		ripple_normal += direction * wave * band * fade_in * fade_out * wake_bias * ripple_strength * event.w;
	}
	n = normalize(vec3(n.xy + ripple_normal, max(n.z, 0.08)));
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
