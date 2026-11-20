// (visual 2) Lente de fora do farol/lanterna: policarbonato transparente, quase sem cor, com reflexo forte de lado.
// Embaixo dela aparecem a parábola cromada e a máscara (peças de verdade do modelo).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
#include "res://scripts/shaders/reflexo.gdshaderinc"

uniform vec3 tinta : source_color = vec3(1.0);
uniform float opacidade : hint_range(0.0, 1.0) = 0.05;

void fragment() {
	float nv = abs(dot(NORMAL, VIEW));
	float f = fresnel(0.04, nv);
	ALBEDO = tinta;
	METALLIC = 0.0;
	ROUGHNESS = 0.02;
	SPECULAR = 0.75;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 n_m = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v_m = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	EMISSION = amostra_reflexo(reflect(-v_m, n_m), 0.0) * (0.15 + f) * forca_reflexo;
#endif
	ALPHA = clamp(opacidade + f * 0.75, 0.0, 0.95);
}
