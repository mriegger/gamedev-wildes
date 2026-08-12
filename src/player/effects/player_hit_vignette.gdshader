shader_type canvas_item;

uniform vec4 hit_color : source_color = vec4(0.67, 0.025, 0.018, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	vec2 vignette_uv = centered_uv * vec2(0.86, 1.12);
	float angle = atan(vignette_uv.y, vignette_uv.x);
	float irregularity = sin(angle * 5.0 + 0.7) * 0.018 + sin(angle * 9.0 - 1.2) * 0.011;
	float radius = length(vignette_uv);
	float inner_edge = 0.3 + irregularity;
	float body = smoothstep(inner_edge, inner_edge + 0.18, radius);
	float outline = smoothstep(inner_edge, inner_edge + 0.05, radius) * (1.0 - smoothstep(inner_edge + 0.14, inner_edge + 0.24, radius));
	float alpha = (body * 0.31 + outline * 0.15) * intensity;
	COLOR = vec4(hit_color.rgb, alpha * hit_color.a);
}
