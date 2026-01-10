shader_type canvas_item;

uniform float radius : hint_range(0.0, 0.5) = 0.48;
uniform vec2 center = vec2(0.5, 0.5);
uniform float softness : hint_range(0.0, 0.1) = 0.01;

/* Bereich oben, der NICHT geclippt wird */
uniform float breakout_y : hint_range(0.0, 1.0) = 0.35;

/* Zoom: 1.0 = normal, 1.2 = näher, 0.8 = weiter weg */
uniform float texture_scale : hint_range(0.5, 2.0) = 1.0;

/* Verschiebung der Textur (für Positionieren) */
uniform vec2 texture_offset = vec2(0.0, 0.0);

void fragment() {

    // UV zoomen um die Mitte (0.5,0.5)
    vec2 uv = (UV - vec2(0.5)) / texture_scale + vec2(0.5) + texture_offset;

    vec4 tex = texture(TEXTURE, uv);

    // Circle mask
    float dist = distance(UV, center);
    float circle_mask = smoothstep(radius, radius - softness, dist);

    // breakout mask (oben = 1, unten = 0)
    float breakout_mask = step(UV.y, breakout_y);

    float final_mask = mix(circle_mask, 1.0, breakout_mask);

    COLOR = tex * final_mask;
}
