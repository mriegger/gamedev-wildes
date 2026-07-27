shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

varying vec3 v_world_normal;
varying vec3 v_world_pos;

uniform vec3 haze_color: source_color = vec3(0.75, 0.87, 0.94);
uniform float world_size: hint_range(10, 500) = 200.0;

void vertex() {
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    // AO and drop-shadows baked into COLOR.rgb (0.58..1.0)
    // FIX blown out: was *1.22 + 0.72-1.0 top -> white clamp washed. Now 0.88 * 0.60-0.85 keeps saturation.
    float top = clamp(v_world_normal.y, 0.0, 1.0);
    float crisp_shade = mix(0.60, 0.85, top);
    vec3 base = COLOR.rgb * 0.88;
    base = clamp(base, vec3(0.0), vec3(1.0));
    vec3 albedo = base * crisp_shade;

    // border haze - reduced from 0.38 to avoid washout at edges
    vec2 center = vec2(world_size * 0.5);
    float dist_center = length(v_world_pos.xz - center);
    float half = world_size * 0.5;
    float h = smoothstep(half * 0.92, half * 1.08, dist_center);
    albedo = mix(albedo, haze_color, h * 0.18);

    ALBEDO = albedo;
    ROUGHNESS = 0.96;
    // lambert_wrap gives light to backfaces, so away sides are darker but not black
    // real-time shadows from Sun still apply via shadow map, softened by blur
}
