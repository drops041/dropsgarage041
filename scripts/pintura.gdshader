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
// (fase 2) desgaste: carro velho. 0 = novo. Cada peça pode ter o seu (semente muda o desenho)
uniform float ferrugem : hint_range(0.0, 1.0) = 0.0;
uniform float sujeira : hint_range(0.0, 1.0) = 0.0;
uniform float amassado : hint_range(0.0, 1.0) = 0.0;
uniform vec3 semente = vec3(0.0);
// (visual 2, padrão CSR) PBR de verdade: o motor faz o reflexo (céu HDR do estúdio / sonda da rua) com fresnel,
// verniz por cima e oclusão. Ligado por carro (carros.json "visual": 2); os outros seguem no modo antigo.
uniform bool pbr = false;

varying vec3 p_local;

float h3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// ruído suave 3D (valor) e fbm: manchas de ferrugem, sujeira e amassados
float ruido(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		s += a * ruido(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

// amassado: "buracos" suaves espalhados (0 = liso, 1 = fundo do amassado)
float campo_amassado(vec3 p) {
	return smoothstep(0.46, 0.68, fbm(p * 1.9 + semente * 3.7));
}

void vertex() {
	p_local = VERTEX;
	if (amassado > 0.001) {
		VERTEX -= NORMAL * campo_amassado(VERTEX) * amassado * 0.045;   // até 4,5 cm pra dentro
	}
}

void fragment() {
	// amassado: entorta a normal (a luz mostra o amassado mesmo onde a malha é pouco detalhada)
	if (amassado > 0.001) {
		float h = campo_amassado(p_local) * amassado;
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		if (abs(det) > 1e-9) {
			vec3 grad = (dFdx(h) * r1 + dFdy(h) * r2) / det;
			NORMAL = normalize(NORMAL - grad * 0.22);
		}
	}
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
	// (fase 2) desgaste: ferrugem (mais embaixo e nas bordas das manchas), sujeira (embaixo) e tinta desbotada
	float baixo = 1.0 - clamp((p_local.y - 0.15) / 0.9, 0.0, 1.0);
	float m_fer = 0.0;
	float m_suj = 0.0;
	vec3 cor_fer = vec3(0.0);
	if (ferrugem > 0.001) {
		float n = fbm(p_local * 5.5 + semente);
		float alvo = n * 0.75 + baixo * 0.45;
		float lim = 1.32 - ferrugem * 0.55;          // ferrugem 0,7 -> só as manchas mais fortes, quase sempre embaixo
		m_fer = smoothstep(lim, lim + 0.04, alvo);
		float borda = smoothstep(lim - 0.08, lim, alvo) - m_fer;   // tinta estufada em volta
		cor_fer = mix(vec3(0.20, 0.07, 0.025), vec3(0.52, 0.21, 0.06), fbm(p_local * 23.0 + semente));
		base = mix(base, base * 0.55 + vec3(0.12, 0.05, 0.0), clamp(borda, 0.0, 1.0) * 0.8);
	}
	if (sujeira > 0.001) {
		float n = fbm(p_local * 2.6 + semente * 1.3 + vec3(5.0));
		m_suj = clamp(sujeira * (0.35 + 0.65 * baixo) * smoothstep(0.25, 0.75, n + baixo * 0.3), 0.0, 0.85);
		base = mix(base, base * 0.75 + vec3(0.05), sujeira * 0.45);   // tinta queimada de sol
	}
	vec3 suj_cor = vec3(0.30, 0.26, 0.20);
	float lisa = (1.0 - m_fer) * (1.0 - m_suj);   // onde a tinta ainda está boa (brilho, verniz e reflexo)
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	if (pbr) {
		// tinta: base colorida (metálica de verdade) + verniz liso por cima. Sem brilho próprio (EMISSION):
		// quem reflete é o ambiente, então embaixo do carro e nas frestas fica escuro como na vida real.
		// flocos: cada pontinho é um "espelhinho" (mais metálico e mais liso) -> brilha quando pega luz
		vec3 celf = floor(p_local * 1400.0);
		float fl = h3(celf);
		float brilho_floco = smoothstep(0.82, 1.0, fl) * perto * flocos * metal;
		vec3 alb2 = base * (1.0 - metal * 0.2);
		alb2 = mix(alb2, suj_cor, m_suj);
		alb2 = mix(alb2, cor_fer, m_fer);
		ALBEDO = alb2;
		// cor clara (branco, prata pérola) é pouco metálica de verdade: o metal escurece a base e deixa cinza
		float lum = dot(base, vec3(0.299, 0.587, 0.114));
		METALLIC = clamp(metal * mix(0.85, 0.22, smoothstep(0.35, 0.85, lum)) + brilho_floco * 0.6, 0.0, 1.0) * lisa;
		ROUGHNESS = mix(clamp(mix(0.42, 0.24, metal) + aspereza * 0.3 - brilho_floco * 0.25, 0.08, 1.0), 0.92, 1.0 - lisa);
		SPECULAR = 0.5;
		CLEARCOAT = verniz * lisa * (1.0 - sujeira * 0.6);
		CLEARCOAT_ROUGHNESS = clamp(0.02 + aspereza * 0.15 + sujeira * 0.3, 0.0, 1.0);
		EMISSION = vec3(0.0);
	} else {
#endif
	// a luz da cena faz o difuso e o brilho das lâmpadas; o "metal" de verdade vem do reflexo (EMISSION)
	vec3 alb = base * (1.0 - metal * 0.35);
	alb = mix(alb, suj_cor, m_suj);
	alb = mix(alb, cor_fer, m_fer);
	ALBEDO = alb;
	METALLIC = metal * 0.25 * lisa;
	ROUGHNESS = mix(aspereza, 0.92, 1.0 - lisa);
	CLEARCOAT = verniz * lisa * (1.0 - sujeira * 0.6);
	CLEARCOAT_ROUGHNESS = 0.04 + sujeira * 0.3;
	vec3 cor_metal = amb_borrado * base * metal * (0.6 + floco * 1.2);
	vec3 brilho_verniz = amb_nitido * f * verniz * (1.0 - sujeira * 0.7);
	EMISSION = (cor_metal + brilho_verniz + amb_borrado * base * 0.05) * forca_reflexo * lisa;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	}
#endif
}
