shader_type canvas_item;

uniform float speed = 0.03;
uniform float scale = 7.0;               // HIGH SCALE works here
uniform float warp_strength = 0.18;      // flow distortion
uniform float glow_strength = 1.4;
uniform float vignette_strength = 1.35;

uniform float detail_strength = 0.12;    // subtle small detail layer
uniform float dithering = 0.02;          // kills banding (increase if needed)

uniform vec4 col_dark : source_color = vec4(0.02, 0.04, 0.10, 1.0);
uniform vec4 col_mid  : source_color = vec4(0.06, 0.18, 0.35, 1.0);
uniform vec4 col_glow : source_color = vec4(0.16, 0.52, 0.82, 1.0);


// ---------- helpers ----------
vec2 rotate(vec2 p, float a) {
    float s = sin(a);
    float c = cos(a);
    return vec2(c*p.x - s*p.y, s*p.x + c*p.y);
}

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// smoother noise (quintic interpolation)
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0); // quintic smootherstep
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// rotated FBM to avoid grid / blocks
float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;

    for (int i = 0; i < 7; i++) {
        v += a * noise(p);
        p = rotate(p * 2.0, 0.65);
        a *= 0.5;
    }
    return v;
}

// screen-space grain (for debanding)
float grain(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}


// ---------- main ----------
void fragment() {
    vec2 uv = UV;
    vec2 center = vec2(0.5);

    float t = TIME * speed;

    // -------- warp field (large motion)
    float w1 = fbm(uv * scale + vec2(t, -t * 0.7));
    float w2 = fbm(rotate(uv, 1.2) * scale * 1.3 + vec2(-t * 0.6, t * 1.1));

    vec2 warped_uv = uv + (vec2(w1, w2) - 0.5) * warp_strength;

    // -------- main noise (big shapes)
    float n1 = fbm(warped_uv * scale * 1.2);
    float n2 = fbm(rotate(warped_uv, 1.7) * scale * 1.8 + vec2(t * 0.3, -t * 0.4));
    float n = mix(n1, n2, 0.5);

    // -------- micro detail layer (kills flatness + helps banding)
    float fine = fbm(warped_uv * scale * 8.0 + vec2(t * 0.8, t * 0.6));
    n = mix(n, fine, detail_strength);

    // -------- radial glow like your original
    float dist = distance(uv, center);
    float glow = pow(1.0 - dist, 2.6) * glow_strength;

    // -------- color blend
    vec4 col = mix(col_dark, col_mid, n);
    col = mix(col, col_glow, glow);

    // -------- vignette
    float vignette = pow(dist, vignette_strength);
    col.rgb *= (1.0 - vignette * 0.9);

    // -------- proper dithering / grain (pixel space)
    vec2 px = FRAGCOORD.xy;
    float g = grain(px + TIME * 60.0);       // animated grain
    g = (g - 0.5) * dithering;
    col.rgb += g;

    COLOR = col;
}
