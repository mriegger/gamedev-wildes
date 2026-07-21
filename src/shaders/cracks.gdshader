shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, depth_draw_opaque;

uniform float progress: hint_range(0.0, 1.0) = 0.0;
uniform vec4 crack_color: source_color = vec4(0.08, 0.08, 0.08, 1.0);

varying vec3 v_local_pos;
varying vec3 v_world_normal;

void vertex() {
    v_local_pos = VERTEX;
    v_world_normal = NORMAL;
}

float seg(vec2 a, vec2 b, vec2 p, float w) {
    vec2 ap = p - a;
    vec2 ab = b - a;
    float t = clamp(dot(ap, ab) / max(dot(ab, ab), 0.001), 0.0, 1.0);
    vec2 c = a + ab * t;
    float d = length(p - c);
    return 1.0 - smoothstep(0.0, w, d);
}

void fragment() {
    vec2 uv;
    if (abs(v_world_normal.y) > 0.5) {
        uv = v_local_pos.xz;
    } else if (abs(v_world_normal.x) > 0.5) {
        uv = v_local_pos.zy;
    } else {
        uv = v_local_pos.xy;
    }
    uv *= 2.0;
    
    float c = 0.0;
    c += seg(vec2(-0.7,-0.7), vec2(0.7,0.7), uv, 0.045) * smoothstep(0.1, 0.35, progress);
    c += seg(vec2(-0.7,0.7), vec2(0.7,-0.7), uv, 0.04) * smoothstep(0.3, 0.55, progress);
    c += seg(vec2(0.0,-0.8), vec2(0.3,0.25), uv, 0.032) * smoothstep(0.45, 0.70, progress);
    c += seg(vec2(-0.6,0.0), vec2(0.2,0.6), uv, 0.03) * smoothstep(0.6, 0.85, progress);
    
    if (c < 0.05) {
        discard;
    }
    ALBEDO = crack_color.rgb;
    ALPHA = c * crack_color.a * clamp(progress, 0.0, 1.0);
}
