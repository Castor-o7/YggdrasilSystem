shader_type canvas_item;
// The Yggdrasil void: a triangular lattice of hairlines in two drifting
// layers, pale nodes where they cross, and a sparse field of motes that
// breathe. The middle of the frame stays nearly clear so real windows can
// live there; the edges and the bottom, where the hull will be, are denser.
//
// Everything is drawn with real alpha. There is no glow pass in this
// project (macOS drops its alpha), so any halo is drawn here by hand.

uniform vec2 res = vec2(1440.0, 900.0);
uniform vec4 ground : source_color = vec4(0.02, 0.027, 0.051, 1.0);
uniform float ground_alpha : hint_range(0.0, 1.0) = 1.0;
uniform vec4 line_color : source_color = vec4(0.435, 0.498, 0.659, 1.0);
uniform vec4 light_color : source_color = vec4(0.863, 0.902, 1.0, 1.0);
uniform vec4 gold_color : source_color = vec4(0.949, 0.831, 0.541, 1.0);
uniform float lattice_alpha : hint_range(0.0, 1.0) = 0.16;
uniform float center_clear : hint_range(0.0, 1.0) = 0.12;
uniform float breath : hint_range(0.0, 1.0) = 0.0;
uniform float time_offset = 0.0;
uniform float drift_speed = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec4 over(vec4 dst, vec4 src) {
	float a = src.a + dst.a * (1.0 - src.a);
	vec3 rgb = a > 0.0 ? (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / a : vec3(0.0);
	return vec4(rgb, a);
}

vec2 rot(vec2 p, float ang) {
	float c = cos(ang);
	float s = sin(ang);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Three families of hairlines sixty degrees apart. `lines` is the line
// coverage, `nodes` the coverage where all three cross.
void lattice(vec2 p, float spacing, float width, out float lines, out float nodes) {
	float acc = 0.0;
	float node = 1.0;
	for (int i = 0; i < 3; i++) {
		float ang = float(i) * PI / 3.0;
		vec2 d = vec2(cos(ang), sin(ang));
		float t = dot(p, d) / spacing;
		float f = abs(fract(t) - 0.5) * spacing;
		acc += 1.0 - smoothstep(0.0, width, f);
		node *= 1.0 - smoothstep(0.0, width * 3.2, f);
	}
	lines = clamp(acc, 0.0, 1.0);
	nodes = node;
}

// Sparse motes on a jittered grid: a hard pinpoint and a soft halo, each
// on its own slow pulse. `gold` is 1 for the rare warm ones.
void motes(vec2 p, float cell, float t, out float pin, out float halo, out float gold) {
	pin = 0.0;
	halo = 0.0;
	gold = 0.0;
	vec2 id = floor(p / cell);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 n = id + vec2(float(x), float(y));
			float h = hash21(n);
			if (h < 0.62) {
				continue;
			}
			vec2 off = vec2(hash21(n + 7.1), hash21(n + 3.7));
			vec2 center = (n + off) * cell;
			float d = length(p - center);
			float pulse = 0.55 + 0.45 * sin(t * (0.18 + 0.25 * h) + h * 6.2831);
			float k = pulse * (0.7 + 0.3 * breath);
			float pn = (1.0 - smoothstep(0.6, 1.6, d)) * k;
			float hl = (1.0 - smoothstep(0.0, 9.0 + 5.0 * h, d)) * 0.35 * k;
			float g = step(0.9, h);
			pin += pn;
			halo += hl;
			gold = max(gold, g * (pn + hl));
		}
	}
	pin = clamp(pin, 0.0, 1.0);
	halo = clamp(halo, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV * res;
	float t = TIME + time_offset;
	vec2 aspect = vec2(1.0, res.y / res.x);
	vec2 c = (UV - 0.5) * aspect * 2.0;
	// How far from the clear middle: 0 at center, 1 at the rim.
	float rim = smoothstep(0.35, 1.05, length(c));
	// The bottom band, where the hull will sit, is the brightest part.
	float bottom = smoothstep(0.62, 1.0, UV.y);
	float mask = mix(center_clear, 1.0, max(rim, bottom * 0.85));

	vec4 dst = vec4(ground.rgb, ground_alpha);

	// Far layer: wide, faint, rotated, drifting slowest.
	float l2, n2;
	vec2 p2 = rot(p + vec2(t * 0.45, -t * 0.3) * drift_speed, PI / 6.0);
	lattice(p2, 236.0, 1.1, l2, n2);
	dst = over(dst, vec4(line_color.rgb, l2 * lattice_alpha * 0.45 * mask));
	dst = over(dst, vec4(light_color.rgb, n2 * lattice_alpha * 1.2 * mask));

	// Near layer: the main lattice.
	float l1, n1;
	vec2 p1 = p + vec2(t * 1.6, -t * 0.9) * drift_speed;
	lattice(p1, 96.0, 1.0, l1, n1);
	float breathe = 0.85 + 0.15 * breath;
	dst = over(dst, vec4(line_color.rgb, l1 * lattice_alpha * mask * breathe));
	dst = over(dst, vec4(light_color.rgb, n1 * lattice_alpha * 2.2 * mask * breathe));

	// Motes, drifting with the near layer but not locked to it.
	float pin, halo, gold;
	vec2 pm = p + vec2(t * 0.9, -t * 1.4) * drift_speed;
	motes(pm, 140.0, t, pin, halo, gold);
	vec3 mote_rgb = mix(light_color.rgb, gold_color.rgb, gold);
	float mote_mask = mix(center_clear * 2.0, 1.0, max(rim, bottom));
	dst = over(dst, vec4(mote_rgb, halo * 0.5 * mote_mask));
	dst = over(dst, vec4(mote_rgb, pin * 0.85 * mote_mask));

	COLOR = dst;
}
