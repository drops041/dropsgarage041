// Foto dos projetos (quadros dos encontros): mostra a foto com as cores DELA.
// O jogo passa tudo por um filtro de cor (tonemap filmic + contraste) que clareia os tons médios; e a névoa
// deixava o preto acinzentado. Aqui a foto ignora a névoa e entra com a curva inversa do filtro (medida no jogo,
// ambiente do main.gd: filmic 0.88, contraste 1.1), aí sai na tela igual à original.
// A curva muda com o renderizador: no Compatibility a cor sai quase direto; no Forward+/Mobile o ALBEDO é linear.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
uniform float ganho = 1.0;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
// nesse renderizador a textura chega "crua" (o valor do arquivo), com ou sem source_color
uniform sampler2D foto : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
const int N = 16;
const float lut[17] = {0.0, 0.0, 0.071, 0.173, 0.267, 0.361, 0.451, 0.545, 0.624, 0.690, 0.753, 0.816, 0.867, 0.918, 0.957, 0.996, 1.0};
#else
// sem source_color: lê o valor do arquivo como ele é
uniform sampler2D foto : filter_linear_mipmap_anisotropic, repeat_disable;
const int N = 64;   // ALBEDO = i/64 até 57/64; acima disso a tela já satura em 1
const float lut[58] = {0.000, 0.110, 0.192, 0.259, 0.310, 0.357, 0.400, 0.435, 0.471, 0.502, 0.529, 0.553, 0.576, 0.600, 0.624, 0.639, 0.659, 0.678, 0.694, 0.710, 0.722, 0.737, 0.749, 0.765, 0.776, 0.788, 0.796, 0.808, 0.820, 0.827, 0.835, 0.847, 0.855, 0.863, 0.871, 0.878, 0.886, 0.894, 0.902, 0.906, 0.914, 0.918, 0.925, 0.933, 0.937, 0.941, 0.949, 0.953, 0.957, 0.965, 0.969, 0.973, 0.976, 0.980, 0.984, 0.992, 0.996, 1.000};
#endif

float inversa(float s) {
	if (s <= lut[0]) { return 0.0; }
	for (int i = 0; i < lut.length() - 1; i++) {
		if (s <= lut[i + 1]) {
			float t = (s - lut[i]) / max(lut[i + 1] - lut[i], 0.0001);
			return (float(i) + t) / float(N);
		}
	}
	return float(lut.length() - 1) / float(N);
}

void fragment() {
	vec3 v = texture(foto, UV).rgb;                  // cor da foto como ela é no arquivo
	ALBEDO = vec3(inversa(v.r), inversa(v.g), inversa(v.b)) * ganho;
}
