shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D albedo_noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scroll_speed = vec2(0.0, -1.0);
uniform vec2 albedo_noise_uv_scroll_speed = vec2(0.2, -0.1);
uniform vec2 albedo_noise_tiling = vec2(2.0, 2.0);
uniform float albedo_distortion_strength : hint_range(0.0, 0.5, 0.001) = 0.025;
uniform sampler2D mask_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 mask_uv_scroll_speed = vec2(0.0, 0.0);
uniform vec2 noise_uv_scroll_speed = vec2(0.35, 0.15);
uniform vec2 noise_tiling = vec2(2.0, 2.0);
uniform float mask_distortion_strength : hint_range(0.0, 0.5, 0.001) = 0.04;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_multiplier : hint_range(0.0, 5.0, 0.01) = 1.0;
uniform float emission_multiplier : hint_range(0.0, 10.0, 0.01) = 1.0;

void fragment() {
	vec2 albedo_noise_uv = (UV * albedo_noise_tiling) + (albedo_noise_uv_scroll_speed * TIME);
	vec2 albedo_noise_offset = (texture(albedo_noise_texture, albedo_noise_uv).rg * 2.0 - 1.0) * albedo_distortion_strength;
	vec2 albedo_uv = UV + (uv_scroll_speed * TIME) + albedo_noise_offset;
	vec2 mask_noise_uv = (UV * noise_tiling) + (noise_uv_scroll_speed * TIME);
	vec2 mask_noise_offset = (texture(noise_texture, mask_noise_uv).rg * 2.0 - 1.0) * mask_distortion_strength;
	vec2 mask_uv = UV + (mask_uv_scroll_speed * TIME) + mask_noise_offset;
	vec4 albedo_sample = texture(albedo_texture, albedo_uv);
	float mask_value = texture(mask_texture, mask_uv).r;
	vec3 final_color = albedo_sample.rgb * tint_color.rgb;
	float final_alpha = albedo_sample.a * mask_value * tint_color.a * alpha_multiplier;

	ALBEDO = final_color;
	EMISSION = final_color * emission_multiplier;
	ALPHA = final_alpha;
}
