shader_type spatial;
render_mode specular_schlick_ggx, cull_back, blend_mix, depth_draw_always;

// SINGLE SOURCE OF TRUTH: res://environment/water_profile.tres
uniform vec4 tint_color;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D water_normal : hint_normal;

uniform float normal_scale;
uniform float normal_time_scale;
uniform vec2 normal_move_dir_a;
uniform vec2 normal_move_dir_b;
uniform float depth_tint_strength;
uniform float refraction_test;
uniform float refraction_offset_scale;
uniform vec3 sun_dir;
uniform vec3 sun_color;
uniform float sun_energy;
uniform float roughness;
uniform float specular;
uniform float color_intensity;
uniform float color_boost;

uniform float normal_bump_strength;
uniform float large_wave_scale;
uniform float large_wave_strength;

varying vec2 vertex_uv;

vec3 get_mixed_normals(vec3 c1, vec3 c2, float bump) {
    vec3 n1 = c1 * 2.0 - 1.0;
    vec3 n2 = c2 * 2.0 - 1.0;
    vec3 m = vec3((n1.xy + n2.xy) * bump, n1.z * n2.z);
    return normalize(m);
}

vec3 get_large_wave(vec2 uv, float scale, float strength, float t) {
    vec2 suv = uv * scale + vec2(t * 0.02, t * 0.01);
    vec3 s = texture(water_normal, suv).xyz * 2.0 - 1.0;
    s.xy *= strength;
    return normalize(vec3(s.xy, s.z));
}

vec3 get_view_position_from_uv(vec2 uv, float depth, mat4 inv_proj) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, depth, 1.0);
    vec4 view = inv_proj * ndc;
    view.xyz /= view.w;
    return view.xyz;
}

void vertex() {
    vertex_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    // Tangent space normals - scrolling, world XZ continuous
    vec2 time_vec_a = (TIME * normal_move_dir_a) * normal_time_scale;
    vec2 time_vec_b = (TIME * normal_move_dir_b) * normal_time_scale;
    vec3 normal_sample_a = texture(water_normal, vertex_uv * normal_scale + time_vec_a).xyz;
    vec3 normal_sample_b = texture(water_normal, vertex_uv * normal_scale + time_vec_b).xyz;
    vec3 mixed_normal_tangent = get_mixed_normals(normal_sample_a, normal_sample_b, normal_bump_strength);

    // Large-scale wave tilt for wide glitter coverage
    if (large_wave_strength > 0.001) {
        vec3 large = get_large_wave(vertex_uv, large_wave_scale, large_wave_strength, TIME);
        mixed_normal_tangent = normalize(vec3(mixed_normal_tangent.xy + large.xy * 0.65, mixed_normal_tangent.z * large.z));
    }

    vec3 t = normalize(TANGENT);
    vec3 b = normalize(BINORMAL);
    vec3 n = normalize(NORMAL);
    mat3 tbn = mat3(t, b, n);
    vec3 mixed_normal_view = normalize(tbn * mixed_normal_tangent);

    // Depth reconstruction for refraction
    float surface_depth_raw = FRAGCOORD.z;
    vec3 water_view_pos = get_view_position_from_uv(SCREEN_UV, surface_depth_raw, INV_PROJECTION_MATRIX);

    vec2 direct_offset = mixed_normal_tangent.xy * refraction_offset_scale;
    vec2 refracted_uv = clamp(SCREEN_UV + direct_offset * refraction_test, vec2(0.001), vec2(0.999));
    vec3 screen_col = texture(screen_texture, refracted_uv).rgb;

    float scene_depth_refracted_raw = texture(depth_texture, refracted_uv).x;
    vec3 scene_view_pos_refracted = get_view_position_from_uv(refracted_uv, scene_depth_refracted_raw, INV_PROJECTION_MATRIX);
    float water_depth_refracted = max(length(scene_view_pos_refracted - water_view_pos), 0.0);

    // Depth-based tint
    vec3 deep_tint = tint_color.rgb * 0.45;
    float depth_tint_factor = clamp(water_depth_refracted * 0.08 * depth_tint_strength * 1.8, 0.0, 1.0);
    vec3 depth_tint = mix(tint_color.rgb, deep_tint, depth_tint_factor);

    vec3 water_base = mix(depth_tint, screen_col, refraction_test * 0.35);
    vec3 final_col = water_base;
    final_col *= color_intensity;
    final_col = mix(final_col, tint_color.rgb * color_intensity, (color_boost - 1.0) * 0.35);

    float NdotV = clamp(dot(mixed_normal_view, normalize(VIEW)), 0.0, 1.0);
    float fresnel = pow(1.0 - NdotV, 2.5);
    float depth_alpha = clamp(water_depth_refracted * 0.22 + 0.38, 0.5, 0.88);
    float alpha = mix(depth_alpha, 0.92, fresnel * 0.45);
    alpha = clamp(alpha, 0.45, 0.92) * clamp(tint_color.a, 0.0, 1.0);

    ALBEDO = final_col;
    ALPHA = alpha;
    NORMAL = mixed_normal_view;
    ROUGHNESS = roughness;
    SPECULAR = specular;
    METALLIC = 0.0;
}
