
#version 450

#VERSION_DEFINES

layout(push_constant, std140) uniform Pos {
	vec4 src_rect;
	vec4 dst_rect;

	float rotation_sin;
	float rotation_cos;
	vec2 eye_center;

	float k1;
	float k2;
	float upscale;
	float aspect_ratio;

	uint layer;
	bool source_is_srgb;
	bool use_debanding;
	uint target_color_space;

	float reference_multiplier;
	float output_max_value;
	uint pad1;
	uint pad2;
}
data;

layout(location = 0) in vec2 uv;

layout(location = 0) out vec4 color;

#ifdef USE_LAYER
layout(binding = 0) uniform sampler2DArray src_rt;
#else
layout(binding = 0) uniform sampler2D src_rt;
#endif


#define COLOR_SPACE_REC709_LINEAR 0
#define COLOR_SPACE_REC709_NONLINEAR_SRGB 1

vec3 srgb_to_linear(vec3 color) {
	return mix(pow((color.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), color.rgb * (1.0 / 12.92), lessThan(color.rgb, vec3(0.04045)));
}

vec3 linear_to_srgb(vec3 color) {
	const vec3 a = vec3(0.055f);
	return mix((vec3(1.0f) + a) * pow(color.rgb, vec3(1.0f / 2.4f)) - a, 12.92f * color.rgb, lessThan(color.rgb, vec3(0.0031308f)));
}






vec3 screen_space_dither(vec2 frag_coord) {
	
	
	vec3 dither = vec3(dot(vec2(171.0, 231.0), frag_coord));
	dither.rgb = fract(dither.rgb / vec3(103.0, 71.0, 97.0));

	
	
	
	return (dither.rgb - 0.5) / 255.0;
}

void main() {
#ifdef APPLY_LENS_DISTORTION
	vec2 coords = uv * 2.0 - 1.0;
	vec2 offset = coords - data.eye_center;

	
	offset.y /= data.aspect_ratio;

	
	vec2 offset_sq = offset * offset;
	float radius_sq = offset_sq.x + offset_sq.y;
	float radius_s4 = radius_sq * radius_sq;
	float distortion_scale = 1.0 + (data.k1 * radius_sq) + (data.k2 * radius_s4);
	offset *= distortion_scale;

	
	offset.y *= data.aspect_ratio;

	
	coords = offset + data.eye_center;
	coords /= data.upscale;

	
	if (coords.x < -1.0 || coords.y < -1.0 || coords.x > 1.0 || coords.y > 1.0) {
		color = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		
		coords = (coords + vec2(1.0)) / vec2(2.0);
		color = texture(src_rt, vec3(coords, data.layer));
	}
#elif defined(USE_LAYER)
	color = texture(src_rt, vec3(uv, data.layer));
#else
	color = texture(src_rt, uv);
	// crt mod: chromatic aberration, growing towards the edges.
	{
		vec2 from_centre = uv - vec2(0.5);
		vec2 shift = from_centre * dot(from_centre, from_centre) * 0.012;
		color.r = texture(src_rt, uv + shift).r;
		color.b = texture(src_rt, uv - shift).b;
	}
#endif

	// crt mod: scanlines and a vignette over the whole final image.
	{
		float scan = 0.88 + 0.12 * sin(gl_FragCoord.y * 3.14159265 / 2.0);
		vec2 v = uv * (1.0 - uv);
		float vignette = clamp(pow(v.x * v.y * 16.0, 0.22), 0.0, 1.0);
		color.rgb *= scan * vignette;
	}

	
	if (data.target_color_space == COLOR_SPACE_REC709_LINEAR) {
		if (data.source_is_srgb == true) {
			
			color.rgb = srgb_to_linear(color.rgb);
		}

		
		
		
		
		
		
		
		
		color.rgb = clamp(color.rgb, vec3(0.0), vec3(data.output_max_value));

		
		color.rgb *= data.reference_multiplier;
	} else if (data.target_color_space == COLOR_SPACE_REC709_NONLINEAR_SRGB) {
		
		
		if (data.source_is_srgb == false) {
			
			color.rgb = linear_to_srgb(color.rgb);

			
			
			
			
			
			
			if (data.use_debanding) {
				color.rgb += screen_space_dither(gl_FragCoord.xy);
			}
		}
	}
}
