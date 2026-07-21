shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, depth_draw_opaque;

uniform vec3 base_color: source_color = vec3(0.52, 0.67, 0.40);
uniform float alpha: hint_range(0.0, 1.0) = 0.48;

void fragment() {
    ALBEDO = base_color;
    ALPHA = alpha;
}
