shader_type spatial;
render_mode cull_disabled, unshaded;

varying vec3 v_world_normal;
varying vec3 v_world_pos;

uniform vec3 haze_color: source_color = vec3(0.75, 0.87, 0.94);
uniform float world_size: hint_range(10, 500) = 200.0;

void vertex() {
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float top = clamp(v_world_normal.y, 0.0, 1.0);
    float crisp_shade = mix(0.82, 1.0, top); // one shade deeper sides
    vec3 base = COLOR.rgb * 1.28;
    base = clamp(base, vec3(0.0), vec3(1.0));
    vec3 albedo = base * crisp_shade;
    
    // edge haze only at very border, not playable interior
    vec2 center = vec2(world_size * 0.5);
    float dist_center = length(v_world_pos.xz - center);
    float half = world_size * 0.5;
    float h = smoothstep(half * 0.92, half * 1.08, dist_center);
    albedo = mix(albedo, haze_color, h * 0.38);
    
    ALBEDO = albedo;
}
