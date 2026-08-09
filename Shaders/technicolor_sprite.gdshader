// technicolor_sprite.gdshader — per-sprite variant of the technicolor film
// grade for the slow-mo powerup: applied by SlowMo to the sprites of slowed
// entities only ("the slowed are trapped in old film"). Keeps the color soul
// of RetroArch's film/technicolor preset (LUT grade + aybe's two-strip
// process + grain) and deliberately drops the screen-space effects
// (vignette/jitter/deconvergence) that don't survive per-sprite UV space.
// Lineage/attribution: see technicolor_film_view.gdshader.

shader_type canvas_item;

uniform sampler2D lut_tex : filter_linear, repeat_disable, hint_default_black;
uniform bool use_lut = true;
uniform float technicolor : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float grain_str : hint_range(0.0, 60.0, 1.0) = 12.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float frame_rate = 60.0;

const vec3 redfilter = vec3(1.0, 0.0, 0.0);
const vec3 bluegreenfilter = vec3(0.0, 1.0, 0.7);

vec4 mixfix(vec4 a, vec4 b, float c) {
	return (a.z < 1.0) ? mix(a, b, c) : a;
}

vec4 lut_grade(sampler2D lt, vec4 img_color) {
	vec2 lut_size = vec2(textureSize(lt, 0));
	float red   = (img_color.r * (lut_size.y - 1.0) + 0.4999) / (lut_size.y * lut_size.y);
	float green = (img_color.g * (lut_size.y - 1.0) + 0.4999) / lut_size.y;
	float blue1 = (floor(img_color.b * (lut_size.y - 1.0)) / lut_size.y) + red;
	float blue2 = (ceil(img_color.b * (lut_size.y - 1.0)) / lut_size.y) + red;
	float mixer = clamp(max((img_color.b - blue1) / (blue2 - blue1), 0.0), 0.0, 32.0);
	vec4 color1 = texture(lt, vec2(blue1, green));
	vec4 color2 = texture(lt, vec2(blue2, green));
	return mixfix(color1, color2, mixer);
}

float film_grain(vec2 uv, float str, float timer) {
	float x = (uv.x + 4.0) * (uv.y + 4.0) * ((mod(timer, 800.0) + 10.0) * 10.0);
	return (mod((mod(x, 13.0) + 1.0) * (mod(x, 123.0) + 1.0), 0.01) - 0.005) * str;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float frame_count = floor(TIME * frame_rate);
	float time_f = mod(frame_count, 4268.0);

	vec3 c = use_lut ? lut_grade(lut_tex, tex).rgb : tex.rgb;

	// two-strip Technicolor (aybe's technicolor1.cg math)
	vec3 redrecord = c * redfilter;
	vec3 bluegreenrecord = c * bluegreenfilter;
	vec3 result = vec3(redrecord.r) * redfilter
		+ vec3((bluegreenrecord.g + bluegreenrecord.b) / 2.0) * bluegreenfilter;
	c = mix(c, result, vec3(technicolor));

	// grain keyed to SCREEN position so it reads as one film layer across
	// every slowed sprite, not per-sprite confetti
	c += film_grain(SCREEN_UV, grain_str, time_f / 10.0);

	c *= tint.rgb;
	// preserve alpha and modulate (enemy flash effects keep working)
	COLOR = vec4(mix(tex.rgb, c, strength), tex.a) * COLOR;
}
