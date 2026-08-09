// technicolor_film_view.gdshader (ViewRoot material variant: samples TEXTURE, no screen copies) — Godot 4.4 canvas_item port of RetroArch's
// "technicolor" film preset (libretro/slang-shaders: film/technicolor.slangp).
//
// Original chain (2 passes, fused here into one):
//   pass 0: reshade/shaders/LUT/LUT.slang   (color LUT, texture: cmyk-16.png)
//   pass 1: film/shaders/film_noise.slang   ("film noise" by hunterk — license: public domain)
// The two-strip Technicolor math inside film_noise.slang is credited by its
// author to aybe (github.com/aybe/RetroArch-shaders, shaders/technicolor1.cg,
// 2014, "from http://001.vade.info/").
// LUT.slang and cmyk-16.png carry no license header and the libretro
// slang-shaders repo has no top-level license — keep this attribution block
// when redistributing.
//
// Port notes:
// - Pass fusion is exact: pass 0 is a pure per-pixel color map, so it is
//   applied to each of pass 1's source taps before channel compositing.
//   (Differences vs RetroArch: no 8-bit quantization between passes, and
//   LUT.slang's `vTexCoord * 1.0001` driver-precision hack is dropped.)
// - RetroArch's default texture wrap is clamp_to_border (transparent black);
//   Godot has no border wrap, so it is emulated in the sample helpers.
// - FrameCount is reconstructed from TIME via `frame_rate` (the original is
//   frame-counted; its look assumes 60 fps).
// - The original samples the *red* offsets for the blue channel (upstream
//   bug); kept by default for faithfulness — toggle `fix_blue_offset`.
// - Added uniforms not in the original: tint, strength, use_lut, frame_rate,
//   fix_blue_offset.

shader_type canvas_item;

// This variant samples the item's own TEXTURE (the SubViewportContainer's
// game view) - built-ins are only visible inside fragment(), so the sampler
// is threaded into the helper functions as a parameter.

// ------------------------------------------- textures from the original preset
// Assign cmyk-16.png (repo: reshade/shaders/LUT/cmyk-16.png).
// Import as Lossless (NO VRAM compression) — a compressed LUT ruins the grade.
uniform sampler2D lut_tex : filter_linear, repeat_disable, hint_default_black;
uniform bool use_lut = true;
// Assign film_noise1.png (repo: film/resources/film_noise1.png).
// Transparent default: scratches become a no-op if left unassigned.
uniform sampler2D noise_tex : hint_default_transparent, filter_linear, repeat_disable;

// ------------------------------------------------------------ added controls
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 1.0; // 0 = untouched image
uniform float frame_rate = 60.0;                     // FrameCount = TIME * frame_rate
uniform bool fix_blue_offset = false;                // corrects the upstream bug

// --------------------- original #pragma parameters (defaults/ranges preserved)
uniform float jitter       : hint_range(0.0, 1.0, 1.0)  = 1.0;  // Jitter Toggle
uniform float noise_toggle : hint_range(0.0, 1.0, 1.0)  = 1.0;  // Film Scratches
uniform float hotspot      : hint_range(0.0, 1.0, 1.0)  = 1.0;  // Hotspot Toggle
uniform float vignette     : hint_range(0.0, 1.0, 1.0)  = 1.0;  // Vignette Toggle
uniform float vig_flicker  : hint_range(0.0, 1.0, 1.0)  = 1.0;  // Vignette Flicker
uniform float technicolor  : hint_range(0.0, 1.0, 0.01) = 0.5;  // Color Shift Intensity
uniform float x_off_r      : hint_range(-1.0, 1.0, 0.01) = 0.12;
uniform float y_off_r      : hint_range(-1.0, 1.0, 0.01) = 0.07;
uniform float x_off_g      : hint_range(-1.0, 1.0, 0.01) = -0.06;
uniform float y_off_g      : hint_range(-1.0, 1.0, 0.01) = -0.08;
uniform float x_off_b      : hint_range(-1.0, 1.0, 0.01) = -0.11;
uniform float y_off_b      : hint_range(-1.0, 1.0, 0.01) = 0.09;
uniform float grain_str    : hint_range(0.0, 60.0, 1.0) = 24.0; // Grain Strength
uniform float vig_amt      : hint_range(0.0, 1.0, 0.01) = 0.15; // Vignette Amount

const vec3 redfilter = vec3(1.0, 0.0, 0.0);
const vec3 bluegreenfilter = vec3(0.0, 1.0, 0.7);

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

// https://www.shadertoy.com/view/4sXSWs strength = 16.0
float film_grain(vec2 uv, float str, float timer) {
	float x = (uv.x + 4.0) * (uv.y + 4.0) * ((mod(timer, 800.0) + 10.0) * 10.0);
	return (mod((mod(x, 13.0) + 1.0) * (mod(x, 123.0) + 1.0), 0.01) - 0.005) * str;
}

// Verbatim from LUT.slang: keeps stray undefined values in a safe range
// (behavior differs per GPU vendor otherwise).
vec4 mixfix(vec4 a, vec4 b, float c) {
	return (a.z < 1.0) ? mix(a, b, c) : a;
}

// Verbatim port of LUT.slang's fragment math (pass 0 of the preset).
// Layout of cmyk-16.png: 256x16 strip = 16 blocks of 16x16
// (blue selects the block along x, red is x within the block, green is y).
vec4 lut_grade(vec4 img_color) {
	vec2 lut_size = vec2(textureSize(lut_tex, 0));
	float red   = (img_color.r * (lut_size.y - 1.0) + 0.4999) / (lut_size.y * lut_size.y);
	float green = (img_color.g * (lut_size.y - 1.0) + 0.4999) / lut_size.y;
	float blue1 = (floor(img_color.b * (lut_size.y - 1.0)) / lut_size.y) + red;
	float blue2 = (ceil(img_color.b * (lut_size.y - 1.0)) / lut_size.y) + red;
	float mixer = clamp(max((img_color.b - blue1) / (blue2 - blue1), 0.0), 0.0, 32.0);
	vec4 color1 = texture(lut_tex, vec2(blue1, green));
	vec4 color2 = texture(lut_tex, vec2(blue2, green));
	return mixfix(color1, color2, mixer);
}

// RetroArch samples with clamp_to_border (black) by default; emulate it so
// the y-jitter shows the authentic black sliver at the frame edge.
vec4 sample_screen_raw(sampler2D tex, vec2 uv) {
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	return texture(tex, uv);
}

// One source tap of the fused chain: screen -> LUT (pass 0) -> pass 1 input.
vec3 graded_tap(sampler2D tex, vec2 uv) {
	vec4 c = sample_screen_raw(tex, uv);
	return use_lut ? lut_grade(c).rgb : c.rgb;
}

// Border-emulated scratch-texture tap (alpha 0 outside = no scratch).
vec4 sample_noise(vec2 uv) {
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return vec4(0.0);
	}
	return texture(noise_tex, uv);
}

void fragment() {
	// -- clock: reconstruct RetroArch's global timer -------------------------
	float frame_count = floor(TIME * frame_rate);
	float time_f = mod(frame_count, 4268.0);

	vec2 uv = UV; // SubViewportContainer variant: use UV here instead

	// -- vertex-stage math of film_noise.slang. Done per-pixel here; it is
	//    linear in UV / constant per frame, so results are identical (the
	//    original only moved it to the vertex stage for performance). --------
	vec2 center_coord = uv - 0.5;
	center_coord.y += 0.003 * hash(sin(mod(time_f, 403.0))) * jitter;

	float hash_num1 = sin(hash(mod(time_f, 147.0)));
	float hash_num2 = hash(cos(mod(time_f, 292.0)));
	float hash_num3 = cos(hash(mod(time_f, 361.0)));
	float frame_hash = hash(time_f);

	vec2 noise_coord;
	noise_coord.x = (hash_num1 > 0.15) ? uv.x : 1.0 - uv.x;
	noise_coord.y = ((hash_num1 + hash_num2 - 0.5) > 0.66) ? uv.y : 1.0 - uv.y;

	// -- fragment stage of film_noise.slang ---------------------------------
	vec2 middle = center_coord;
	float len = length(middle) / 1.25;
	float vig = smoothstep(0.0, 1.0 - vig_amt, len);

	vec4 film_noise1 = sample_noise(noise_coord.xx + (hash_num1 + hash_num3 - 0.85));
	vec4 film_noise2 = sample_noise(noise_coord.xy + (hash_num1 + hash_num2 - 0.85));

	// Deconvergence. The original uses the RED offsets for the blue channel
	// (upstream bug in film_noise.slang) — kept unless fix_blue_offset is on.
	vec2 red_coord = (center_coord + 0.01 * vec2(x_off_r, y_off_r)) + 0.5;
	vec3 red_light = graded_tap(TEXTURE, red_coord);
	vec2 green_coord = (center_coord + 0.01 * vec2(x_off_g, y_off_g)) + 0.5;
	vec3 green_light = graded_tap(TEXTURE, green_coord);
	vec2 blue_off = fix_blue_offset ? vec2(x_off_b, y_off_b) : vec2(x_off_r, y_off_r);
	vec2 blue_coord = (center_coord + 0.01 * blue_off) + 0.5;
	vec3 blue_light = graded_tap(TEXTURE, blue_coord);

	vec3 film = vec3(red_light.r, green_light.g, blue_light.b);

	// Two-strip Technicolor process, from aybe's technicolor1.cg.
	vec3 redrecord = film * redfilter;
	vec3 bluegreenrecord = film * bluegreenfilter;
	vec3 rednegative = vec3(redrecord.r);
	vec3 bluegreennegative = vec3((bluegreenrecord.g + bluegreenrecord.b) / 2.0);
	vec3 redoutput = rednegative * redfilter;
	vec3 bluegreenoutput = bluegreennegative * bluegreenfilter;
	vec3 result = redoutput + bluegreenoutput;
	film = mix(film, result, vec3(technicolor));

	// Film grain.
	film += film_grain(uv, grain_str, time_f / 10.0);

	// Vignette + hotspot; size varies pseudo-randomly per frame.
	float vig_mod = 1.0 + 0.1 * hash_num3 * vig_flicker;
	film *= mix(1.0, 1.0 - vig, vignette * vig_mod); // vignette
	film += ((1.0 - vig) * 0.2) * hotspot * vig_mod; // hotspot

	// Scratch overlay on ~2% of frames.
	if (frame_hash > 0.99 && noise_toggle > 0.5) {
		film = mix(film, film_noise1.rgb, film_noise1.a);
	} else if (frame_hash < 0.01 && noise_toggle > 0.5) {
		film = mix(film, film_noise2.rgb, film_noise2.a);
	}

	// -- added: per-mode recolor + fade against the untouched image ---------
	vec3 effect = film * tint.rgb;
	vec3 clean = sample_screen_raw(TEXTURE, uv).rgb;
	COLOR = vec4(mix(clean, effect, strength), 1.0);
}
