shader_type canvas_item;
// A branch of the tree: one Line2D per application, all on this one
// material. Across the line (UV.y) it draws the hairline core, a soft
// wide stroke when the branch is out of focus, and a halo that grows with
// the CPU the app burns. Along it (UV.x, root 0 to bud 1) runs the sap: a
// bead of light that only exists while the app is working, faster and
// brighter the harder it works, so at rest the tree is still.
// Everything with real alpha; no glow pass (macOS drops it).

uniform vec4 frame_color : source_color = vec4(0.435, 0.498, 0.659, 1.0);
uniform vec4 light_color : source_color = vec4(0.863, 0.902, 1.0, 1.0);
uniform vec4 gold_color : source_color = vec4(0.949, 0.831, 0.541, 1.0);
uniform float breath : hint_range(0.0, 1.0) = 0.0;
uniform float headroom = 1.0;      // Palette.headroom; the sap alone spends it
uniform float surge = -1.0;        // the warp: a bead at this place on every bough, none below 0
uniform float hair = 1.0;          // Palette.hair: hairline width on a plain screen
uniform float lift = 0.0;          // Palette.lift: 0 on the Mac, 1 on a plain 1080p screen

instance uniform float heat : hint_range(0.0, 1.0) = 0.0;     // CPU, 0..1
instance uniform float life : hint_range(0.0, 1.0) = 1.0;     // 1 alive, GHOST withered
instance uniform float near : hint_range(0.0, 1.0) = 0.5;     // depth: 0 far, 1 near
instance uniform float active : hint_range(0.0, 1.0) = 0.0;   // frontmost app
instance uniform float hidden : hint_range(0.0, 1.0) = 0.0;   // hidden as an app
instance uniform float px_width = 14.0;                        // the Line2D's width, px
instance uniform float sap = 0.0;                              // the bead's place along the branch, 0..1

void fragment() {
	float h = heat;
	float lf = life;
	float nr = near;
	float act = active;
	float hid = hidden;
	float W = px_width;
	float sp = sap;

	float breathe = 0.85 + 0.15 * breath;
	float across = abs(UV.y - 0.5) * W;   // px from the centreline

	// The colour and alpha the drawn tree used, exactly.
	vec3 col = mix(mix(frame_color.rgb, light_color.rgb, 0.4 * h), gold_color.rgb, 0.5 * h * h);
	float alpha = mix(mix(0.16, 0.3, lift), 0.5, h) * lf * breathe;
	alpha *= mix(1.0, 0.55, hid);
	alpha = max(alpha, act * 0.42 * breathe);
	float depth = mix(mix(0.5, 0.65, lift), 1.1, nr);
	alpha = min(1.0, alpha * depth);

	// Core hairline: 0.7 px far, 1.5 px near, one pixel of feather.
	float cw = mix(0.7, 1.5, nr) * hair;
	float core = clamp(cw * 0.5 + 0.5 - across, 0.0, 1.0);
	// Out of focus: a soft wide stroke under the line.
	float soft = (1.0 - smoothstep(0.0, 2.0 * hair, across)) * 0.3 * max(0.0, 1.0 - 2.0 * nr);
	// Heat: a halo that falls off softly, wider and brighter as the app works.
	float hw = mix(1.5, 4.0, nr) * (0.5 + 0.5 * h) * hair;
	float halo = exp(-across / hw) * 0.35 * h;
	// Lifted: a glow under every bough, not only a working one, wider and
	// brighter with heat and focus, gone before the strip's edge. Its own
	// weight, not the hairline's alpha: a far branch glows faintly still.
	// It rises out of the root: where the boughs meet, their glows would
	// pool into one pale fan and outshine the bud.
	float gw = mix(2.5, 4.5, nr) + 5.0 * h + 1.5 * act;
	float edge = 1.0 - smoothstep(0.55, 1.0, across / (0.5 * W));
	float glow = lift * exp(-across * across / (gw * gw)) * edge
		* (0.12 + 0.7 * h + 0.12 * act) * lf * mix(1.0, 0.55, hid) * depth * breathe
		* smoothstep(0.0, 0.25, UV.x) * (1.0 - smoothstep(0.94, 1.0, UV.x));

	// Sap. Only while the app works: a bead running from the root toward
	// the bud, brighter with heat; the tree walks it (Branch.sap) so a
	// change of pace never moves it.
	float d = UV.x - sp;
	float bead = exp(-d * d * 400.0) * step(0.08, h) * smoothstep(0.08, 0.3, h);
	float flow = bead * (1.0 - smoothstep(0.0, 2.0 + 2.0 * h, across)) * 0.9 * lf;

	float sg = 0.0;
	if (surge >= 0.0) {
		float ds = UV.x - surge;
		sg = exp(-ds * ds * 60.0) * (1.0 - smoothstep(0.0, 3.0, across)) * lf;
	}
	float a = min(1.0, (core + soft + halo) * alpha + glow + flow + sg);
	vec3 rgb = mix(col, light_color.rgb, min(1.0, flow * 0.7 + sg)) * mix(1.0, headroom, max(flow, sg));
	COLOR = vec4(rgb, a);
}
