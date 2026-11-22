// (v41) plástico do alargador do para-lama (ex.: G5 Cross): no modelo a lataria do para-lama fica uns
// milímetros/centímetros pra fora do plástico em alguns pontos e "rasga" ele de branco. Aqui o plástico
// é desenhado um pouco mais perto da câmera (só na profundidade: na tela fica no mesmo lugar), então
// ele sempre ganha da lataria que está colada nele. E é fosco (plástico texturizado): o modelo tem as faces
// retas e, brilhante, cada face refletia a luz da oficina de um jeito (manchas brancas e pretas).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 cor : source_color = vec4(0.035, 0.036, 0.04, 1.0);
uniform sampler2D textura : source_color, hint_default_white;
uniform float aspereza = 0.86;
uniform float metal = 0.0;
uniform float puxa = 0.03;   // metros na direção da câmera

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = length(v.xyz);
	v.xyz *= max(dist - puxa, 0.05) / dist;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	ALBEDO = cor.rgb * texture(textura, UV).rgb;
	ROUGHNESS = aspereza;
	METALLIC = metal;
	SPECULAR = 0.18;
}
