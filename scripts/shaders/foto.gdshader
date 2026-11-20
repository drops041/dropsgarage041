// Foto dos projetos (quadros dos encontros): mostra a foto com as cores DELA.
// O jogo passa tudo por um filtro de cor (tonemap filmic + contraste) que clareia os tons médios; e a névoa
// deixava o preto acinzentado. Aqui a foto ignora a névoa e entra com a curva inversa do filtro (medida no jogo),
// aí sai na tela igual à original.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
uniform sampler2D foto : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float ganho = 1.0;
// o que sai na tela pra ALBEDO = 0, 1/16 ... 1 — medido no renderizador compatível com o ambiente do main.gd
// (filmic 0.88, contraste 1.1). Nesse renderizador a textura chega "crua" (o valor do arquivo), com ou sem source_color.
const float lut[17] = {0.0, 0.0, 0.071, 0.173, 0.267, 0.361, 0.451, 0.545, 0.624, 0.690, 0.753, 0.816, 0.867, 0.918, 0.957, 0.996, 1.0};

float inversa(float s) {
	if (s <= lut[0]) { return 0.0; }
	for (int i = 0; i < 16; i++) {
		if (s <= lut[i + 1]) {
			float t = (s - lut[i]) / max(lut[i + 1] - lut[i], 0.0001);
			return (float(i) + t) / 16.0;
		}
	}
	return 1.0;
}

void fragment() {
	vec3 v = texture(foto, UV).rgb;                  // cor da foto como ela é no arquivo
	ALBEDO = vec3(inversa(v.r), inversa(v.g), inversa(v.b)) * ganho;
}
