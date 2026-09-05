// SPDX-License-Identifier: GPL-3.0-only
shader_type canvas_item;
render_mode unshaded;

uniform int mode = 0;
uniform float elapsed = 0.0;
uniform float speed = 1.0;
uniform float density = 1.0;
uniform float seed_value = 20260905.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + mod(seed_value, 65521.0)) * 43758.5453);
}

void fragment() {
	vec2 p = UV * vec2(1152.0, 648.0);
	vec3 color = vec3(0.035, 0.06, 0.095);
	float grid = step(1.0, mod(p.x, 48.0)) * step(1.0, mod(p.y, 48.0));
	color += (1.0 - grid) * 0.035;
	float t = elapsed * speed;
	if (mode == 1) {
		// A repeatable, panning procedural image; no external image loading.
		vec2 q = p + vec2(t * 24.0, t * 9.0);
		color += vec3(0.06, 0.12, 0.16) * (0.5 + 0.5 * sin(q.x * 0.014 + sin(q.y * 0.021)));
	} else if (mode == 2) {
		vec2 a = floor((p + vec2(t * 51.0, -t * 33.0)) * density / 4.0);
		vec2 b = floor((p + vec2(-t * 29.0, t * 47.0)) * density / 6.0);
		color = vec3(hash(a), hash(b), hash(a + b)) * 0.65;

	}
	COLOR = vec4(color, 1.0);
}
