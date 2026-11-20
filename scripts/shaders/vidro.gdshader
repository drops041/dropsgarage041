// Vidro do carro: escuro por dentro, reflexo forte de lado (fresnel)
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;
#include "res://scripts/shaders/reflexo.gdshaderinc"

uniform vec3 tinta : source_color = vec3(0.04, 0.05, 0.06);
uniform float opacidade : hint_range(0.0, 1.0) = 0.62;
uniform bool pbr = false;   // (visual 2) reflexo do próprio motor (estúdio/céu), sem o panorama falso

void fragment() {
	vec3 n_m = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v_m = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float nv = abs(dot(NORMAL, VIEW));
	float f = fresnel(0.06, nv);
	ALBEDO = tinta;
	ROUGHNESS = 0.03;
	METALLIC = 0.0;
	SPECULAR = 0.8;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	if (pbr) {
		// vidro de verdade: quase preto, a cor que aparece é o reflexo (mais forte de lado);
		// o interior aparece de frente (película leve)
		ROUGHNESS = 0.0;
		SPECULAR = 0.5;
		EMISSION = vec3(0.0);
		ALPHA = clamp(opacidade * 0.9 + f * 0.6, 0.0, 0.97);
	} else {
#endif
	EMISSION = amostra_reflexo(reflect(-v_m, n_m), 0.0) * (0.12 + f * 0.9) * forca_reflexo;
	ALPHA = clamp(opacidade + f * 0.5, 0.0, 0.97);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	}
#endif
}
