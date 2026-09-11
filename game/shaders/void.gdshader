shader_type canvas_item;
// The Yggdrasil void: a triangular lattice of hairlines in two layers,
// pale nodes where they cross, and a starfield in depth that the ship
// flies through: stars are born near the vanishing point ahead and run
// outward, faster and brighter as they near the rim. The lattice is the
// far fabric; it slides only when the bow swings.
// The middle of the frame stays nearly clear so real windows can live
// there; the edges and the bottom, where the hull will be, are denser.
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
// The fabric slides only when the bow swings: an offset per lattice
// layer from the vanishing point's lean (far layer in its rotated space).
uniform vec2 near_off = vec2(0.0);
uniform vec2 far_off = vec2(0.0);
// Forward flight. The stars are depth slices cycling from far to near,
// projected through the vanishing point `vp`; `travel` is depth crossed
// (wraps each 1.0) and `blur` the depth a star crosses in one streak.
uniform vec2 vp = vec2(720.0, 450.0);
uniform float travel = 0.0;
uniform float blur = 0.0;
// The bow's bearing, for the warp seam. On the far side of `sweep` (px
// along the bearing from the frame's center) the star field is seed_b,
// and a plane of pale light rides the seam. A very negative sweep is none.
uniform vec2 heading = vec2(0.87, -0.48);
uniform float seed_a = 0.0;
uniform float seed_b = 0.0;
uniform float sweep = -1.0e9;
uniform float sweep_glow : hint_range(0.0, 1.0) = 0.0;

const int LAYERS = 6;
const float CELL = 150.0;
const float Z_MIN = 0.08;
const float STREAK_CAP = 0.9 * CELL;   // keeps a streak inside the 3x3 search

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

// The starfield: each depth slice is a jittered grid on the far plane;
// a pixel maps onto slice z at q = (p - vp) * z, so as z shrinks the
// grid swells on screen and its stars run outward from the vanishing
// point, near ones fast and far ones slow. A star trails a streak toward
// where it was one blur ago (nearer the vanishing point), fading to the
// tail. `gold` is 1 for the rare warm ones.
void stars(vec2 p, vec2 origin, float depth, float smear, float t, float seed, out float pin, out float halo, out float gold) {
	pin = 0.0;
	halo = 0.0;
	gold = 0.0;
	vec2 rel = p - origin;
	for (int L = 0; L < LAYERS; L++) {
		float z = fract((float(L) + 0.5) / float(LAYERS) - depth);
		if (z < Z_MIN) {
			continue;
		}
		float lseed = seed + float(L) * 19.7;
		vec2 q = rel * z;
		vec2 id = floor(q / CELL);
		float fade = smoothstep(1.0, 0.8, z) * smoothstep(Z_MIN, Z_MIN + 0.08, z);
		float near = 1.0 - z;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 n = id + vec2(float(x), float(y));
				float h = hash21(n + lseed);
				if (h < 0.58) {
					continue;
				}
				vec2 off = vec2(hash21(n + lseed + 7.1), hash21(n + lseed + 3.7));
				vec2 head = (n + off) * CELL;
				float f = z / (z + smear);
				f = max(f, 1.0 - min(STREAK_CAP / max(length(head), 1.0), 1.0));
				vec2 seg = head * f - head;
				float l2 = dot(seg, seg);
				float u = l2 > 0.0 ? clamp(dot(q - head, seg) / l2, 0.0, 1.0) : 0.0;
				float d = length(q - (head + seg * u)) / z;
				float dh = length(q - head) / z;
				float pulse = 0.7 + 0.3 * sin(t * (0.18 + 0.25 * h) + h * 6.2831);
				float k = pulse * (0.7 + 0.3 * breath) * fade * (0.3 + 0.7 * near);
				float r = 0.7 + 1.0 * near;
				float pn = (1.0 - smoothstep(r * 0.6, r + 0.9, d)) * k * (1.0 - 0.85 * u);
				float hl = (1.0 - smoothstep(0.0, 6.0 + 10.0 * near, dh)) * 0.3 * k;
				float g = step(0.92, h);
				pin += pn;
				halo += hl;
				gold = max(gold, g * (pn + hl));
			}
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

	// Far layer: wide, faint, rotated; the fabric, still unless the bow swings.
	float l2, n2;
	vec2 p2 = rot(p, PI / 6.0) + far_off;
	lattice(p2, 236.0, 1.1, l2, n2);
	dst = over(dst, vec4(line_color.rgb, l2 * lattice_alpha * 0.45 * mask));
	dst = over(dst, vec4(light_color.rgb, n2 * lattice_alpha * 1.2 * mask));

	// Near layer: the main lattice.
	float l1, n1;
	vec2 p1 = p + near_off;
	lattice(p1, 96.0, 1.0, l1, n1);
	float breathe = 0.85 + 0.15 * breath;
	dst = over(dst, vec4(line_color.rgb, l1 * lattice_alpha * mask * breathe));
	dst = over(dst, vec4(light_color.rgb, n1 * lattice_alpha * 2.2 * mask * breathe));

	// The stars. A warp seam splits the field: the stars behind the plane are new.
	float along = dot(p - res * 0.5, heading);
	float seed = along < sweep ? seed_b : seed_a;
	float pin, halo, gold;
	stars(p, vp, travel, blur, t, seed, pin, halo, gold);
	vec3 star_rgb = mix(light_color.rgb, gold_color.rgb, gold);
	float star_mask = mix(center_clear * 2.0, 1.0, max(rim, bottom));
	dst = over(dst, vec4(star_rgb, halo * 0.5 * star_mask));
	dst = over(dst, vec4(star_rgb, pin * 0.85 * star_mask));

	// The plane of light: a soft band on the seam, brightest at its core,
	// crossing the whole frame (a cutscene, so the middle is not spared,
	// only softened).
	float band = exp(-abs(along - sweep) / 26.0);
	float core = exp(-abs(along - sweep) / 3.0);
	float seam_mask = mix(0.45, 1.0, max(rim, bottom));
	dst = over(dst, vec4(light_color.rgb, band * 0.28 * sweep_glow * seam_mask));
	dst = over(dst, vec4(light_color.rgb, core * 0.8 * sweep_glow * seam_mask));

	COLOR = dst;
}
