// Vidro do carro: escuro por dentro, reflexo forte de lado (fresnel)
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;
#include "res://scripts/shaders/reflexo.gdshaderinc"

uniform vec3 tinta : source_color = vec3(0.04, 0.05, 0.06);
uniform float opacidade : hint_range(0.0, 1.0) = 0.62;

void fragment() {
	vec3 n_m = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v_m = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float nv = abs(dot(NORMAL, VIEW));
	float f = fresnel(0.06, nv);
	ALBEDO = tinta;
	ROUGHNESS = 0.03;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	EMISSION = amostra_reflexo(reflect(-v_m, n_m), 0.0) * (0.12 + f * 0.9) * forca_reflexo;
	ALPHA = clamp(opacidade + f * 0.5, 0.0, 0.97);
}
