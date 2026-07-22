shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 shadow_color: source_color = vec4(0.06, 0.06, 0.06, 0.55);

void fragment() {
    // UV centered, radial soft falloff
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv) * 2.0; // 0 center, 1 edge
    float falloff = 1.0 - smoothstep(0.0, 1.0, dist);
    falloff = pow(falloff, 1.4); // soften
    ALBEDO = shadow_color.rgb;
    ALPHA = shadow_color.a * falloff;
}
