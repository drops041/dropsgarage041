// Pintura do carro: cor base + segunda cor na lateral (pérola / camaleão), flocos metálicos e verniz refletindo o ambiente
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
#include "res://scripts/shaders/reflexo.gdshaderinc"

uniform vec3 cor : source_color = vec3(0.9);
uniform vec3 cor2 : source_color = vec3(0.6, 0.4, 0.9);
uniform float flip : hint_range(0.0, 1.0) = 0.0;      // quanto a 2ª cor aparece de lado
uniform float metal : hint_range(0.0, 1.0) = 0.5;
uniform float aspereza : hint_range(0.0, 1.0) = 0.25;
uniform float verniz : hint_range(0.0, 1.0) = 1.0;
uniform float flocos : hint_range(0.0, 1.0) = 0.6;

varying vec3 p_local;

void vertex() {
	p_local = VERTEX;
}

float h3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void fragment() {
	vec3 n_m = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v_m = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float nv = dot(NORMAL, VIEW);
	float lado = pow(1.0 - clamp(nv, 0.0, 1.0), 1.6);
	vec3 base = mix(cor, cor2, lado * flip);
	// flocos: pontinhos que brilham quando chegam perto (somem de longe pra não serrilhar)
	vec3 cel = floor(p_local * 900.0);
	float perto = 1.0 - smoothstep(0.0006, 0.0025, length(fwidth(p_local)));
	float floco = step(0.95, h3(cel)) * perto * flocos * metal;
	vec3 r_m = reflect(-v_m, n_m);
	vec3 amb_borrado = amostra_reflexo(r_m, clamp(aspereza * 1.6, 0.25, 1.0));
	vec3 amb_nitido = amostra_reflexo(r_m, 0.0);
	float f = fresnel(0.045, nv);
	// a luz da cena faz o difuso e o brilho das lâmpadas; o "metal" de verdade vem do reflexo (EMISSION)
	ALBEDO = base * (1.0 - metal * 0.35);
	METALLIC = metal * 0.25;
	ROUGHNESS = aspereza;
	CLEARCOAT = verniz;
	CLEARCOAT_ROUGHNESS = 0.04;
	vec3 cor_metal = amb_borrado * base * metal * (0.6 + floco * 1.2);
	vec3 brilho_verniz = amb_nitido * f * verniz;
	EMISSION = (cor_metal + brilho_verniz + amb_borrado * base * 0.05) * forca_reflexo;
}
