shader_type canvas_item;

uniform float shake_amount = 0.0;
uniform float threshold = 0.1;
uniform vec2 bounce_direction = vec2(0.0, 0.0);
uniform float bounce_amount = 0.0;
uniform float hit_flash = 0.0;

varying vec4 vertex_modulate;

void vertex() {
	// Store modulate color to pass to fragment shader
	vertex_modulate = COLOR;

	// Add shake effect
	if (shake_amount > 0.0) {
		float shake_x = cos(TIME * 50.0) * shake_amount;
		float shake_y = sin(TIME * 45.0) * shake_amount;
		VERTEX.x += shake_x;
		VERTEX.y += shake_y;
	}

	// Add bounce effect
	VERTEX += bounce_direction * bounce_amount;
}

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	vec4 flash_color = mix(tex_color, vec4(1.0, 1.0, 1.0, tex_color.a), hit_flash);
	COLOR = flash_color * vertex_modulate;
}