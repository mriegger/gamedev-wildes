shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform sampler2DArray terrain_textures : source_color, filter_nearest_mipmap, repeat_enable;

void fragment() {
	float texture_layer = floor(UV2.x + 0.5);
	vec4 texel = texture(terrain_textures, vec3(UV, texture_layer));
	ALBEDO = texel.rgb * COLOR.rgb;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.90;
	SPECULAR = 0.18;
}
