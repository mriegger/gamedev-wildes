shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 shadow_color: source_color = vec4(0.06, 0.06, 0.06, 0.55);

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv) * 2.0;
    float falloff = 1.0 - smoothstep(0.0, 1.0, dist);
    falloff = pow(falloff, 1.4);
    ALBEDO = shadow_color.rgb;
    ALPHA = shadow_color.a * falloff;
}
