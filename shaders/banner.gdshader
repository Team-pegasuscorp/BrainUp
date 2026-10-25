shader_type canvas_item;

// Player banner in one draw call: horizontal gradient (2-3 stops), a light pattern
// and rounded corners. Replaces hundreds of draw_circle / draw_line per banner.
// Pattern ids: 0 none, 1 stripes, 2 dots, 3 waves, 4 chevrons, 5 stars.

uniform vec4 color_a : source_color = vec4(0.17, 0.14, 0.31, 1.0);
uniform vec4 color_b : source_color = vec4(0.29, 0.18, 0.48, 1.0);
uniform vec4 color_c : source_color = vec4(0.29, 0.18, 0.48, 1.0);
uniform int stops = 2;
uniform int pattern = 0;
uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float radius = 18.0;
uniform float pattern_alpha = 0.16;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float band(float d, float half_width) {
	return 1.0 - smoothstep(half_width - 0.6, half_width + 0.6, d);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = local;
	float t = clamp(p.x / max(rect_size.x, 1.0), 0.0, 1.0);
	vec4 col;
	if (stops >= 3) {
		col = t < 0.5 ? mix(color_a, color_b, t * 2.0) : mix(color_b, color_c, t * 2.0 - 1.0);
	} else {
		col = mix(color_a, color_b, t);
	}

	float ink = 0.0;
	if (pattern == 1) {
		// 45° lines every 28 px horizontally, 9 px thick.
		float u = p.x + p.y;
		float d = abs(mod(u + 14.0, 28.0) - 14.0) * 0.70710678;
		ink = band(d, 4.5) * pattern_alpha;
	} else if (pattern == 2) {
		// Staggered dots, r = 3, 22 px apart, rows every 17.6 px.
		float row = floor((p.y - 11.0) / 17.6 + 0.5);
		float cy = 11.0 + row * 17.6;
		float off = mod(row, 2.0) < 0.5 ? 5.5 : 16.5;
		float cx = off + floor((p.x - off) / 22.0 + 0.5) * 22.0;
		ink = band(length(p - vec2(cx, cy)), 3.0) * pattern_alpha;
	} else if (pattern == 3) {
		// Sine waves every 20 px, 3 px thick.
		float y = p.y - 12.0 - sin(p.x / 22.0) * 6.0;
		float d = abs(mod(y + 10.0, 20.0) - 10.0);
		ink = band(d, 1.5) * pattern_alpha;
	} else if (pattern == 4) {
		// Zigzags (18 px legs, 10 px tall) every 22 px, 3 px thick.
		float f = 10.0 * (1.0 - abs(mod(p.x, 36.0) / 18.0 - 1.0));
		float y = p.y - 10.0 - f;
		float d = abs(mod(y + 11.0, 22.0) - 11.0) * 0.874;
		ink = band(d, 1.5) * pattern_alpha;
	} else if (pattern == 5) {
		// About one star per 900 px², fixed by position: the same sky every time.
		vec2 cell = floor(p / 30.0);
		vec2 centre = (cell + vec2(hash(cell), hash(cell + 17.0))) * 30.0;
		float r = mix(0.8, 2.4, hash(cell + 41.0));
		ink = band(length(p - centre), r) * mix(0.25, 0.8, hash(cell + 73.0));
	}
	col.rgb = mix(col.rgb, vec3(1.0), ink);

	// Rounded-rectangle mask (signed distance), antialiased.
	vec2 half_size = rect_size * 0.5;
	float r = min(radius, min(half_size.x, half_size.y));
	vec2 q = abs(p - half_size) - half_size + r;
	float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
	col.a *= 1.0 - smoothstep(-0.5, 0.5, sd);
	// COLOR carries the node modulate (rows dim their banner to stay readable).
	COLOR = col * COLOR;
}
