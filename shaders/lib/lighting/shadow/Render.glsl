
#ifndef PCSS_SEARCH_SAMPLES
	#define PCSS_SEARCH_SAMPLES 8 // [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 48 64]
#endif
#ifndef PCSS_FILTER_SAMPLES
	#define PCSS_FILTER_SAMPLES 16 // [4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 48 64]
#endif
#ifndef SHADOW_FILTER_SCALE
	#define SHADOW_FILTER_SCALE 1.0 // [0.5 0.75 1.0 1.25 1.5 1.75 2.0]
#endif
#ifndef SHADOW_SOFTNESS
	#define SHADOW_SOFTNESS 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0]
#endif
#ifndef SHADOW_BIAS_PRESET
	#define SHADOW_BIAS_PRESET 1 // [0 1 2]
#endif
#ifndef SHADOW_TEMPORAL_STABILITY
	#define SHADOW_TEMPORAL_STABILITY 0.75 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#endif

//================================================================================================//

#include "Common.glsl"

vec3 WorldToShadowScreenSpace(in vec3 worldPos) {
	vec3 shadowClipPos = transMAD(shadowModelView, worldPos);
	shadowClipPos = projMAD(shadowProjection, shadowClipPos);

	return DistortShadowSpace(shadowClipPos) * 0.5 + 0.5;
}

vec3 WorldToShadowScreenSpace(in vec3 worldPos, out float distortionFactor) {
	vec3 shadowClipPos = transMAD(shadowModelView, worldPos);
	shadowClipPos = projMAD(shadowProjection, shadowClipPos);

	distortionFactor = CalcDistortionFactor(shadowClipPos.xy);
	return DistortShadowSpace(shadowClipPos, distortionFactor) * 0.5 + 0.5;
}

//================================================================================================//

uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

float BlockerSearch(in vec3 shadowScreenPos, in float dither, in float searchScale) {
	float blockerDepth = 0.0;

	vec2 searchRadius = searchScale * SHADOW_FILTER_SCALE * diagonal2(shadowProjection);

	for (uint i = 0u; i < PCSS_SEARCH_SAMPLES; ++i) {
		vec2 sampleCoord = shadowScreenPos.xy + sampleVogelDisk(i, PCSS_SEARCH_SAMPLES, dither) * searchRadius;

		float sampleDepth = texelFetch(shadowtex0, ivec2(sampleCoord * realShadowMapRes), 0).x;
		blockerDepth += saturate(shadowScreenPos.z - sampleDepth);
	}

	blockerDepth *= -5.0 / float(PCSS_SEARCH_SAMPLES);
	return blockerDepth * shadowProjectionInverse[2].z;
}



float CalculateShadowBias(in float NdotL, in float distortionFactor) {
	float slopeBias = mix(0.7, 2.0, saturate(1.0 - NdotL));
	float angleBias = mix(1.4, 0.7, saturate(worldSunVector.y * 0.5 + 0.5));

	float presetScale = 1.0;
	#if SHADOW_BIAS_PRESET == 0
		presetScale = 0.7;
	#elif SHADOW_BIAS_PRESET == 2
		presetScale = 1.35;
	#endif

	return 2.2e-8 * presetScale * (0.35 + slopeBias * angleBias) * shadowProjectionInverse[1].y * distortionFactor;
}

float StableShadowRotation(in vec3 shadowScreenPos, in float dither) {
	vec2 shadowTexel = floor(shadowScreenPos.xy * realShadowMapRes);
	float stableNoise = InterleavedGradientNoise(ivec2(shadowTexel));
	float mixedNoise = mix(dither, stableNoise, SHADOW_TEMPORAL_STABILITY);
	return mixedNoise * TAU;
}
vec3 CalculateWaterCaustics(in vec3 worldPos, in float waterDepth, in float dither) {
	vec3 surfacePos = worldPos - vec3(0.0, 1.0, 0.0);

	float caustics = 0.0;
	for (uint i = 0u; i < 16u; ++i) {
		vec3 samplePos = worldPos;
		samplePos.xz += sampleVogelDisk(i, 16, dither) * 0.15;

		vec2 sampleCoord = WorldToShadowScreenSpace(samplePos).xy;
		vec3 waveNormal = OctDecodeUnorm(texture(shadowcolor1, sampleCoord).xy);

		vec3 refractDir = refract(vec3(0.0, 1.0, 0.0), waveNormal, 1.0 / WATER_IOR);
		vec3 refractedPos = samplePos + refractDir * abs(1.0 / refractDir.y);

		caustics += saturate(1.0 - 20.0 * distance(surfacePos, refractedPos));
	}

	return -smin(-caustics, -0.1, 0.15) * saturate(exp2(-rLOG2 * waterExtinction * waterDepth));
}

vec3 PercentageCloserFilter(in vec3 shadowScreenPos, in vec3 worldPos, in float dither, in float blockerDepth) {
	const float rSteps = 1.0 / float(PCSS_FILTER_SAMPLES);

	vec2 penumbraRadius = min(atmosphereModel.sun_angular_radius * 2.0 * blockerDepth * SHADOW_SOFTNESS, 0.25) * SHADOW_FILTER_SCALE * diagonal2(shadowProjection);

	vec3 result = vec3(0.0);
	vec2 waterData = vec2(0.0);
    // float sssDepth = 0.0;

	for (uint i = 0u; i < PCSS_FILTER_SAMPLES; ++i) {
		vec2 offset = sampleVogelDisk(i, PCSS_FILTER_SAMPLES, dither) * penumbraRadius;
		vec2 sampleCoord = shadowScreenPos.xy + offset;

		float sampleDepth1 = textureLod(shadowtex1, vec3(sampleCoord, shadowScreenPos.z), 0).x;

	#ifdef COLORED_SHADOWS
		ivec2 sampleTexel = ivec2(sampleCoord * realShadowMapRes);
		float sampleDepth0 = texelFetch(shadowtex0, sampleTexel, 0).x;
        // sssDepth += saturate(shadowScreenPos.z - sampleDepth0);

		if (step(shadowScreenPos.z, sampleDepth0) != sampleDepth1) {
			float waterMask = texelFetch(shadowcolor1, sampleTexel, 0).w;
			if (waterMask > EPS) {
				waterData += vec2(sampleDepth0 - shadowScreenPos.z, 1.0);
			} else {
				result += pow4(texelFetch(shadowcolor0, sampleTexel, 0).rgb) * sampleDepth1;
			}
		} else
	#endif
		result += sampleDepth1;
	}

	result *= rSteps;
	// sssDepth *= rSteps;

	#ifdef WATER_CAUSTICS
		if (waterData.y > EPS) {
			waterData.x /= waterData.y;

			float waterDepth = waterData.x * shadowProjectionInverse[2].z * 5.0;
			vec3 caustics = CalculateWaterCaustics(worldPos, waterDepth, dither);
			result = mix(result, caustics, waterData.y * rSteps);
		}
	#endif

	// result += exp2(32.0 * shadowProjectionInverse[2].z * sssDepth) * sssAmount;

	return result;
}

vec3 CalculatePCSS(in vec3 worldPos, in vec3 normalOffset, in float NdotL, in float dither, out float blockerDepth) {
	blockerDepth = 0.0;

	float distortionFactor;
	vec3 shadowScreenPos = WorldToShadowScreenSpace(worldPos + normalOffset, distortionFactor);
	float rotation = StableShadowRotation(shadowScreenPos, dither);
	shadowScreenPos.z -= CalculateShadowBias(saturate(NdotL), distortionFactor);

	vec3 pcss = vec3(1.0);
	if (saturate(shadowScreenPos) == shadowScreenPos) {
		blockerDepth = BlockerSearch(shadowScreenPos, rotation, 0.15 * distortionFactor);

		const float minRadius = 0.008 / atmosphereModel.sun_angular_radius;
		float sharpenFactor = saturate(blockerDepth * rcp(minRadius));

		pcss = PercentageCloserFilter(shadowScreenPos, worldPos, rotation, max(blockerDepth, minRadius) * distortionFactor);
		pcss = mix(smoothstep(0.3, 0.7, pcss), pcss, sharpenFactor); // Sharpen the edges of the shadow
	}

	return pcss;
}

//================================================================================================//

float ScreenSpaceShadow(in vec3 rayPos, in vec3 viewPos, in float dither, in float sssAmount) {
	vec3 rayDir = ViewToScreenSpace(viewLightVector * abs(viewPos.z) + viewPos) - rayPos;
	rayDir *= minOf((step(0.0, rayDir) - rayPos) / rayDir);
	rayDir *= inversesqrt(sdot(rayDir.xy));

	vec3 rayStep = rayDir * (0.05 / float(SCREEN_SPACE_SHADOWS_SAMPLES));
	rayPos += (dither + 0.5) * rayStep;

	float viewDist = length(viewPos);
	float diffTolerance = 5e-4 / viewDist + abs(rayStep.z);
    float absorption = exp2(-0.125 * viewDist / sssAmount);

	float result = 1.0;

	for (uint i = 0u; i < SCREEN_SPACE_SHADOWS_SAMPLES; ++i, rayPos += rayStep) {
		if (saturate(rayPos.xy) != rayPos.xy || result < 1e-2) break;

		ivec2 sampleTexel = uvToTexel(rayPos.xy);
		float sampleDepth = loadDepth0(sampleTexel);

		#if defined DISTANT_HORIZONS
			if (sampleDepth > 1.0 - EPS) {
				sampleDepth = loadDepth0DH(sampleTexel);
				sampleDepth = ViewToScreenDepth(ScreenToViewDepthDH(sampleDepth));
			}
		#endif

		if (abs(sampleDepth - rayPos.z + diffTolerance) < diffTolerance && rayPos.z > sampleDepth) {
			result *= absorption;
		}
	}

	return result;
}