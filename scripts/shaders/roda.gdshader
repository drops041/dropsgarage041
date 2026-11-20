// Tinta de roda: liga leve pintada (prata, grafite, cores) ou fosca (branco/preto fosco).
// Tem luz de verdade (não é espelho) + um pouco do reflexo do ambiente. Os dois lados aparecem
// (alguns aros vieram com faces viradas pra dentro e ficavam "furados").
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
#include "res://scripts/shaders/reflexo.gdshaderinc"

uniform vec3 tinta : source_color = vec3(0.79, 0.8, 0.82);
uniform float metal : hint_range(0.0, 1.0) = 0.7;
uniform float aspereza : hint_range(0.0, 1.0) = 0.3;
uniform float brilho : hint_range(0.0, 1.0) = 0.45;   // quanto do reflexo do ambiente aparece
// aros com raios desenhados numa textura (ex.: BBS trançada): recorte + relevo
uniform bool usa_mascara = false;
uniform sampler2D mascara : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D relevo : hint_normal, filter_linear_mipmap_anisotropic;

void fragment() {
	if (usa_mascara) {
		ALPHA = texture(mascara, UV).a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
		NORMAL_MAP = texture(relevo, UV).rgb;
	}
	vec3 n_m = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v_m = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	ALBEDO = tinta * (1.0 - 0.35 * metal);
	METALLIC = metal;
	ROUGHNESS = aspereza;
	vec3 f0 = mix(vec3(0.04), tinta, metal);
	float nv = clamp(dot(n_m, v_m), 0.0, 1.0);
	vec3 esp = f0 + (vec3(1.0) - f0) * pow(1.0 - nv, 5.0);
	EMISSION = amostra_reflexo(reflect(-v_m, n_m), aspereza) * esp * brilho * forca_reflexo;
}
