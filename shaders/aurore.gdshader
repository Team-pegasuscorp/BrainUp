shader_type canvas_item;

/// Soft aurora wash: base fill + two colour blobs in opposite corners,
/// masked to a rounded rectangle (radius in px, size via rect_size).

uniform vec4 c1 : source_color = vec4(0.486, 0.361, 1.0, 1.0);
uniform vec4 c2 : source_color = vec4(0.0, 0.761, 0.722, 1.0);
uniform vec4 base : source_color = vec4(0.165, 0.133, 0.459, 1.0);
uniform float radius : hint_range(0.0, 64.0) = 14.0;
uniform vec2 rect_size = vec2(200.0, 80.0);

float rounded_box_sdf(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void fragment() {
	vec2 size = max(rect_size, vec2(1.0));
	vec2 pixel = UV * size;
	vec2 half_size = size * 0.5;
	float dist = rounded_box_sdf(pixel - half_size, half_size, min(radius, min(half_size.x, half_size.y)));
	float alpha = 1.0 - smoothstep(-1.0, 1.0, dist);

	float blob1 = exp(-length((UV - vec2(0.05, 0.08)) * vec2(1.7, 2.0)) * 2.15);
	float blob2 = exp(-length((UV - vec2(0.95, 0.92)) * vec2(1.7, 2.0)) * 2.15);

	vec3 col = base.rgb;
	col = mix(col, c1.rgb, clamp(blob1 * 0.92, 0.0, 1.0));
	col = mix(col, c2.rgb, clamp(blob2 * 0.92, 0.0, 1.0));

	COLOR = vec4(col, alpha);
}
