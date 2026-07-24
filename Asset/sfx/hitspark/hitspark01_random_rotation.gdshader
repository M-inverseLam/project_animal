shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform sampler2D albedo_texture : source_color;
uniform vec4 tint_color : source_color = vec4(2.03982, 2.03982, 2.03982, 1.0);
uniform float uv_rotation = 0.0;


void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	float rotation_sin = sin(uv_rotation);
	float rotation_cos = cos(uv_rotation);
	vec2 rotated_uv = vec2(
		centered_uv.x * rotation_cos - centered_uv.y * rotation_sin,
		centered_uv.x * rotation_sin + centered_uv.y * rotation_cos
	) + vec2(0.5);

	vec4 albedo_sample = texture(albedo_texture, rotated_uv) * tint_color * COLOR;
	ALBEDO = albedo_sample.rgb;
	ALPHA = albedo_sample.a;
}
