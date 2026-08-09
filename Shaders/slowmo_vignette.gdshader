shader_type canvas_item;
// Mode overlay for the slow-mo powerups: tinted breathing vignette.
// Teal = enemy slow-mo, indigo = world slow-mo. strength animates 0..1.

uniform vec4 tint : source_color = vec4(0.0, 0.75, 0.7, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 c = UV - vec2(0.5);
	c.x *= 1.35; // wider falloff on a 16:9 frame
	float d = length(c) * 1.6;
	float v = smoothstep(0.30, 1.05, d);
	float pulse = 0.88 + 0.12 * sin(TIME * 2.6);
	COLOR = vec4(tint.rgb, strength * v * 0.55 * pulse);
}
