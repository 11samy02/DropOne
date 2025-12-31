shader_type canvas_item;

uniform bool highlight_enabled = false;

uniform vec4 glow_color : source_color = vec4(0.0, 0.9, 1.0, 1.0); // neon cyan
uniform float glow_strength : hint_range(0.0, 4.0) = 1.6;
uniform float glow_size : hint_range(0.0, 12.0) = 6.0;

uniform float pulse_speed : hint_range(0.0, 10.0) = 4.0;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Standard output wenn nicht aktiv
	vec4 base = tex;

	// Puls (0.65..1.0)
	float pulse = 0.8 + pulse_amount * sin(TIME * pulse_speed);

	// Pixel-Size (funktioniert für UI)
	vec2 px = TEXTURE_PIXEL_SIZE * glow_size;

	// Glow Mask (wir schauen um den Pixel herum)
	float a = tex.a;

	float outline = 0.0;
	outline += texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
	outline += texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
	outline += texture(TEXTURE, UV + vec2(0.0, px.y)).a;
	outline += texture(TEXTURE, UV + vec2(0.0, -px.y)).a;

	outline += texture(TEXTURE, UV + vec2(px.x, px.y)).a;
	outline += texture(TEXTURE, UV + vec2(-px.x, px.y)).a;
	outline += texture(TEXTURE, UV + vec2(px.x, -px.y)).a;
	outline += texture(TEXTURE, UV + vec2(-px.x, -px.y)).a;

	// Outline soll nur dort sein wo aktuell transparent ist aber daneben nicht
	outline = clamp(outline - a, 0.0, 1.0);

	// Glow-Farbe berechnen
	vec4 glow = vec4(glow_color.rgb, outline * glow_strength * pulse);

	// Mix abhängig von highlight_enabled
	COLOR = mix(base, base + glow, float(highlight_enabled));
}
