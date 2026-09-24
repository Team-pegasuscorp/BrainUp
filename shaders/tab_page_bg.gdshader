shader_type canvas_item;

// Soft diagonal wash per tab — lighter mist (top-left → bottom-right).
uniform vec4 accent : source_color = vec4(0.071, 0.769, 0.722, 1.0);
uniform vec4 deep : source_color = vec4(0.110, 0.094, 0.188, 1.0);

void fragment() {
	float t = clamp((UV.x + UV.y) * 0.5, 0.0, 1.0);
	// Lift the whole wash toward accent so the page reads clearer.
	vec3 base = mix(deep.rgb, accent.rgb, 0.22);
	vec3 top = mix(base, accent.rgb, 0.42);
	vec3 mid = mix(base, accent.rgb, 0.22);
	vec3 bot = mix(base, accent.rgb, 0.10);
	vec3 bg = mix(top, mid, smoothstep(0.0, 0.45, t));
	bg = mix(bg, bot, smoothstep(0.40, 1.0, t));
	float glow = exp(-length((UV - vec2(0.08, 0.06)) * vec2(1.5, 1.8)) * 2.4) * 0.20;
	COLOR = vec4(bg + accent.rgb * glow, 1.0);
}
