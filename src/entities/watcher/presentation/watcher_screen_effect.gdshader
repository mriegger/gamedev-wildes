shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform vec2 aperture_center = vec2(0.5, 0.5);
uniform vec2 pixel_to_ground_x = vec2(0.05, 0.0);
uniform vec2 pixel_to_ground_z = vec2(0.0, 0.05);
uniform float aperture_radius_world_units = 2.5;
uniform float aperture_feather_world_units = 0.5;
uniform float shake_power = 0.01;
uniform float shake_rate : hint_range(0.0, 1.0) = 1.0;
uniform float shake_speed = 5.0;
uniform float shake_block_size = 30.5;
uniform float noise_amount : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float noise_speed : hint_range(0.1, 5.0, 0.1) = 1.0;

float random(float seed) {
	return fract(543.2543 * sin(dot(vec2(seed, seed), vec2(3525.46, -54.3415))));
}

float noise_random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	float enable_shift = float(random(trunc(TIME * shake_speed)) < shake_rate);
	float glitch_strength = enable_shift * intensity;
	vec2 half_texel = vec2(0.5) / viewport_size;
	vec2 fixed_uv = SCREEN_UV;
	fixed_uv.x += (
		random((trunc(SCREEN_UV.y * shake_block_size) / shake_block_size) - TIME) - 0.5
	) * shake_power * glitch_strength;
	fixed_uv = clamp(fixed_uv, half_texel, vec2(1.0) - half_texel);
	vec3 center_color = textureLod(screen_texture, fixed_uv, 0.0).rgb;
	vec3 luminance_weights = vec3(0.2126, 0.7152, 0.0722);
	vec3 grayscale_color = vec3(dot(center_color, luminance_weights));
	vec2 aperture_delta_pixels = (fixed_uv - aperture_center) * viewport_size;
	vec2 ground_delta = vec2(
		dot(pixel_to_ground_x, aperture_delta_pixels),
		dot(pixel_to_ground_z, aperture_delta_pixels)
	);
	float aperture_distance_world_units = length(ground_delta);
	float aperture = 1.0 - smoothstep(
		aperture_radius_world_units,
		aperture_radius_world_units + aperture_feather_world_units,
		aperture_distance_world_units
	);
	float visibility = mix(0.025, 1.0, aperture);
	vec3 original_color = textureLod(screen_texture, clamp(SCREEN_UV, half_texel, vec2(1.0) - half_texel), 0.0).rgb;
	vec3 affected_color = grayscale_color * visibility;
	vec3 composited_color = mix(original_color, affected_color, intensity);
	vec2 noise_pixel = floor(UV * viewport_size);
	float noise_frame = mod(floor(TIME * noise_speed * 24.0), 4093.0);
	vec2 noise_seed = noise_pixel + vec2(noise_frame * 0.754877666, noise_frame * 0.569840296);
	float noise_value = noise_random(noise_seed);
	float centered_noise = noise_value - 0.5;
	float dark_biased_noise = min(centered_noise, 0.0) + max(centered_noise, 0.0) * 0.35;
	composited_color += vec3(dark_biased_noise * noise_amount * intensity);
	COLOR = vec4(clamp(composited_color, vec3(0.0), vec3(1.0)), 1.0);
}
