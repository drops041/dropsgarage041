// Reflexo do ambiente (panorama 2:1) calculado no próprio material do carro.
// Funciona no modo Compatibilidade (celular/navegador) e só nos carros: a cidade não fica brilhando.
uniform sampler2D reflexo : source_color, filter_linear_mipmap, repeat_enable, hint_default_black;
uniform float forca_reflexo = 1.0;

vec3 amostra_reflexo(vec3 r_mundo, float asp) {
	vec3 r = normalize(r_mundo);
	vec2 uv = vec2(atan(r.x, -r.z) / 6.2831853 + 0.5, acos(clamp(r.y, -1.0, 1.0)) / 3.1415927);
	float mip = asp * 7.0;   // panorama 1024x512: mip 7 já é bem borrado
	return textureLod(reflexo, uv, mip).rgb;
}

float fresnel(float f0, float nv) {
	return f0 + (1.0 - f0) * pow(1.0 - clamp(nv, 0.0, 1.0), 5.0);
}
