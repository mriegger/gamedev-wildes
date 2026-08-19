shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2DArray foliage_textures : source_color, filter_nearest_mipmap, repeat_disable;

void vertex() {
    NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
    float texture_layer = floor(UV2.x + 0.5);
    vec4 texel = texture(foliage_textures, vec3(UV, texture_layer));
    ALBEDO = texel.rgb;
    ALPHA = texel.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
    ROUGHNESS = 0.90;
    SPECULAR = 0.18;
}
