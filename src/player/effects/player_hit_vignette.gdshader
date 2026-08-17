shader_type canvas_item;

uniform vec4 hit_color : source_color = vec4(0.67, 0.025, 0.018, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	vec2 edge_uv = abs(centered_uv) * 2.0;
	float angle = atan(centered_uv.y, centered_uv.x);
	float irregularity = sin(angle * 5.0 + 0.7) * 0.025 + sin(angle * 9.0 - 1.2) * 0.015;
	float edge_distance = pow(pow(edge_uv.x, 4.0) + pow(edge_uv.y, 4.0), 0.25);
	float inner_edge = 0.74 + irregularity;
	float body = smoothstep(inner_edge, inner_edge + 0.24, edge_distance);
	float outline = smoothstep(inner_edge, inner_edge + 0.06, edge_distance) * (1.0 - smoothstep(inner_edge + 0.12, inner_edge + 0.28, edge_distance));
	float alpha = (body * 0.31 + outline * 0.15) * intensity;
	COLOR = vec4(hit_color.rgb, alpha * hit_color.a);
}
