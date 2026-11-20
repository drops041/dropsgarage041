// Cromado / metal polido (frisos, emblemas, retrovisor, borda da roda)
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
#include "res://scripts/shaders/reflexo.gdshaderinc"

uniform vec3 tinta : source_color = vec3(0.92);
uniform float aspereza : hint_range(0.0, 1.0) = 0.08;
uniform sampler2D textura : source_color, hint_default_white;
uniform bool usa_textura = false;

void fragment() {
	vec3 n_m = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v_m = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 t = tinta * (usa_textura ? texture(textura, UV).rgb : vec3(1.0));
	ALBEDO = t * 0.25;
	METALLIC = 1.0;
	ROUGHNESS = aspereza;
	EMISSION = amostra_reflexo(reflect(-v_m, n_m), aspereza) * t * 0.95 * forca_reflexo;
}
