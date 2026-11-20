// (visual 2) Lente colorida de lanterna / pisca / ré: vidro grosso com as "bolhas" ópticas por dentro.
// As bolhas ficam um pouco pra dentro da superfície (paralaxe): mexendo a câmera elas andam diferente da lente,
// parece que tem profundidade — sem malha extra e sem textura (leve no celular).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
#include "res://scripts/shaders/reflexo.gdshaderinc"

uniform vec3 cor : source_color = vec3(0.75, 0.02, 0.03);       // cor do vidro
uniform vec3 cor_luz : source_color = vec3(1.0, 0.06, 0.04);    // cor da luz acesa
uniform float aceso : hint_range(0.0, 3.0) = 0.35;              // lanterna (posição) ligada
uniform float freio : hint_range(0.0, 1.0) = 0.0;               // pisando no freio
uniform float claro : hint_range(0.0, 1.0) = 0.0;               // 1 = lente clara (ré): aparece o cromado de trás
uniform float celula = 125.0;                                    // bolhas por metro
uniform float fundo = 0.014;                                    // quanto as bolhas ficam pra dentro (m)

varying vec3 p_l;
varying vec3 cam_l;
varying vec3 n_l;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	p_l = VERTEX * s;
	cam_l = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz * s;
	n_l = NORMAL;
}

void fragment() {
	vec3 n = normalize(n_l);
	vec3 dv = normalize(p_l - cam_l);
	vec3 q = p_l + dv * (fundo / max(abs(dot(dv, n)), 0.3));
	vec3 an = abs(n);
	vec2 uv = an.z >= max(an.x, an.y) ? q.xy : (an.x >= an.y ? q.zy : q.xz);
	uv *= celula;
	uv.x += step(1.0, mod(floor(uv.y), 2.0)) * 0.5;   // fileiras desencontradas (colmeia)
	float d = length(fract(uv) - 0.5);
	float bolha = smoothstep(0.5, 0.1, d);
	float bf = bolha * 0.55;   // as bolhas só insinuam (de perto); de longe a lente fica lisa
	float luz = aceso + freio * 2.6;
	vec3 vidro = cor * (0.26 + 0.3 * bf);
	ALBEDO = mix(vidro, vec3(0.62 + 0.25 * bf), claro);
	METALLIC = claro * 0.7;
	ROUGHNESS = mix(0.05, 0.1, bf);
	SPECULAR = 0.6;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.02;
	EMISSION = cor_luz * luz * (0.55 + 0.6 * bf);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 n_m = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v_m = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	EMISSION += amostra_reflexo(reflect(-v_m, n_m), 0.05) * fresnel(0.05, abs(dot(NORMAL, VIEW))) * forca_reflexo;
#endif
}
