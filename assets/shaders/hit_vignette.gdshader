shader_type canvas_item;

uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_opacity : hint_range(0.0, 1.0) = 0.5;
uniform vec4 vignette_rgb : source_color = vec4(0.8, 0.0, 0.0, 1.0);

void fragment() {
    // Quantize UV coordinates to create pixelation
    // Multiply by screen size to get more pixels (32 pixels across)
    vec2 uv = UV;
    uv *= 32.0;
    uv = floor(uv);
    uv /= 32.0;

    vec2 center = vec2(0.5, 0.5);
    float dist = distance(uv, center);
    float vignette = smoothstep(0.8, 0.4, dist * (1.0 + vignette_intensity));

    COLOR = vec4(vignette_rgb.rgb, (1.0 - vignette) * vignette_opacity);
}