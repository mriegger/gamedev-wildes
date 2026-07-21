shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, depth_draw_opaque;

uniform vec4 edge_color: source_color = vec4(1.0, 0.92, 0.1, 1.0);
uniform float edge_width: hint_range(0.005, 0.2) = 0.038;
uniform float half_size: hint_range(0.4, 0.7) = 0.5125;

varying vec3 local_pos;

void vertex() {
    local_pos = VERTEX;
}

void fragment() {
    // Wireframe: show only where at least two axes are near half_size (edge)
    vec3 a = abs(local_pos);
    vec3 d = vec3(half_size) - a; // distance to face border, positive outside?
    // Actually a <= half_size inside. d = half - a, small near border
    float near_x = step(d.x, edge_width);
    float near_y = step(d.y, edge_width);
    float near_z = step(d.z, edge_width);

    float is_edge = 0.0;
    is_edge = max(is_edge, near_x * near_y);
    is_edge = max(is_edge, near_x * near_z);
    is_edge = max(is_edge, near_y * near_z);

    if (is_edge < 0.5) {
        discard;
    }

    ALBEDO = edge_color.rgb;
    ALPHA = edge_color.a;
}
