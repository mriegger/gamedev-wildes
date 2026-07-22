shader_type spatial;
render_mode cull_disabled, blend_mix, diffuse_lambert, specular_disabled;

uniform vec4 water_color : source_color = vec4(0.43, 0.68, 0.78, 0.44);

void fragment() {
    ALBEDO = water_color.rgb;
    ALPHA = water_color.a;
    ROUGHNESS = 0.15;
    // Keep water slightly emissive so it's visible in shadows
    EMISSION = water_color.rgb * 0.08;
}

