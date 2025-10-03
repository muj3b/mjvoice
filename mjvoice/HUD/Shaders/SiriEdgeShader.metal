#include <metal_stdlib>
using namespace metal;

constant float kHalfPi = 1.57079632679;
constant float kTau = 6.28318530718;

struct Uniforms {
    float4 timeAudio;                // x: time, y: audio level, z: ripple time, w: ripple intensity
    float4 resolutionCornerQuality;  // x: width, y: height, z: corner radius, w: quality level (0-2)
    float4 flowWarp;                 // x,y: flow offset, z,w: warp offset
    float4 animationParams;          // x: animation state, y: ripple base, z: exposure, w: frame time EMA
};

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

inline float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

inline float hash(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);

    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));

    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float valueNoise(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);

    float n000 = hash(i);
    float n100 = hash(i + float3(1, 0, 0));
    float n010 = hash(i + float3(0, 1, 0));
    float n110 = hash(i + float3(1, 1, 0));
    float n001 = hash(i + float3(0, 0, 1));
    float n101 = hash(i + float3(1, 0, 1));
    float n011 = hash(i + float3(0, 1, 1));
    float n111 = hash(i + float3(1, 1, 1));

    float3 u = f * f * (3.0 - 2.0 * f);

    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);

    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);

    return mix(nxy0, nxy1, u.z);
}

float3 gradientColor(float t, constant Uniforms& uniforms) {
    float audioBoost = uniforms.timeAudio.y;
    float time = uniforms.timeAudio.x;

    float flowNoise = valueNoise(float3(t * 6.0 + uniforms.flowWarp.x * 0.15,
                                        t * 4.0 + uniforms.flowWarp.y * 0.1,
                                        time * 0.12));
    float scatterNoise = valueNoise(float3(t * 9.0 + uniforms.flowWarp.z * 0.2,
                                           t * 7.0 + uniforms.flowWarp.w * 0.2 + 13.37,
                                           time * 0.18));

    float offset = time * (0.06 + 0.03 * flowNoise) + scatterNoise * 0.35;
    float warpedT = fract(t + offset);

    constexpr float3 colors[8] = {
        float3(1.0, 0.85, 0.2),
        float3(0.74, 0.51, 0.95),
        float3(0.96, 0.73, 0.92),
        float3(0.55, 0.62, 1.0),
        float3(1.0, 0.4, 0.47),
        float3(1.0, 0.73, 0.44),
        float3(0.67, 0.42, 0.93),
        float3(0.4, 0.9, 0.6)
    };

    float segment = warpedT * 8.0;
    int index = int(segment);
    float blend = fract(segment);
    float3 base = mix(colors[index % 8], colors[(index + 1) % 8], smoothstep(0.0, 1.0, blend));

    float brightness = uniforms.animationParams.z;
    brightness += sin(time * 2.3 + warpedT * kTau) * 0.08;
    brightness += audioBoost * 0.4;

    return base * brightness;
}

float computePerimeter(float2 uv, constant Uniforms& uniforms) {
    float width = uniforms.resolutionCornerQuality.x;
    float height = uniforms.resolutionCornerQuality.y;
    float radius = uniforms.resolutionCornerQuality.z;
    radius = clamp(radius, 0.0f, 0.5f * min(width, height) - 1.0f);

    float straightWidth = max(width - 2.0f * radius, 0.0f);
    float straightHeight = max(height - 2.0f * radius, 0.0f);
    float arcLength = kHalfPi * radius;
    float totalPerimeter = 2.0f * (straightWidth + straightHeight) + 4.0f * arcLength;

    float2 pos = float2(uv.x * width, uv.y * height); // origin top-left
    float t = 0.0f;

    if (pos.y <= radius) {
        if (pos.x <= radius) {
            float2 center = float2(radius, radius);
            float2 local = center - pos;
            float angle = clamp(atan2(local.y, local.x), 0.0f, kHalfPi);
            t = (kHalfPi - angle) * radius;
        } else if (pos.x < width - radius) {
            t = arcLength + (pos.x - radius);
        } else {
            float2 center = float2(width - radius, radius);
            float2 local = pos - center;
            float angle = clamp(atan2(local.y, local.x), -kHalfPi, 0.0f);
            t = arcLength + straightWidth + (angle + kHalfPi) * radius;
        }
    } else if (pos.x >= width - radius) {
        if (pos.y < height - radius) {
            t = arcLength * 2.0f + straightWidth + (pos.y - radius);
        } else {
            float2 center = float2(width - radius, height - radius);
            float2 local = pos - center;
            float angle = clamp(atan2(local.y, local.x), 0.0f, kHalfPi);
            t = arcLength * 2.0f + straightWidth + straightHeight + angle * radius;
        }
    } else if (pos.y >= height - radius) {
        if (pos.x > radius) {
            t = arcLength * 3.0f + straightWidth + straightHeight + (width - radius - pos.x);
        } else {
            float2 center = float2(radius, height - radius);
            float2 local = pos - center;
            float angle = clamp(atan2(local.y, local.x), kHalfPi, kTau / 2.0f);
            t = arcLength * 3.0f + straightWidth * 2.0f + straightHeight + (angle - kHalfPi) * radius;
        }
    } else {
        t = arcLength * 4.0f + straightWidth * 2.0f + straightHeight + (height - radius - pos.y);
    }

    // start seam at bottom center to avoid visibility
    float offset = arcLength * 2.0f + straightWidth + straightHeight * 0.5f;
    return fract((t + offset) / max(totalPerimeter, 0.0001f));
}

float2 wavyEdge(float2 uv, constant Uniforms& uniforms) {
    float quality = uniforms.resolutionCornerQuality.w;
    float qNorm = clamp(quality / 2.0f, 0.0f, 1.0f);

    float scaleBase = mix(10.0f, 26.0f, qNorm);
    float amplitude = mix(0.0012f, 0.0048f, qNorm) * uniforms.animationParams.x;

    float2 flow = uniforms.flowWarp.xy;
    float2 warp = uniforms.flowWarp.zw;

    float n1 = valueNoise(uv * scaleBase + flow);
    float n2 = valueNoise(uv * (scaleBase * 1.7f) + warp);
    float n3 = valueNoise(float3(uv * (scaleBase * 0.6f), uniforms.timeAudio.x * 0.2f));

    float2 distortion = float2(n1 - 0.5f + (n3 - 0.5f) * 0.6f,
                               n2 - 0.5f + (n3 - 0.5f) * 0.4f) * amplitude;

    return distortion;
}

float2 rippleDistortion(float2 uv, constant Uniforms& uniforms) {
    float2 rippleOrigin = float2(0.5, 1.0);
    float2 aspect = float2(1.0, uniforms.resolutionCornerQuality.y / max(uniforms.resolutionCornerQuality.x, 1.0));
    float2 toOrigin = uv - rippleOrigin;
    float distance = length(toOrigin * aspect) + 1e-5f;

    float kBase = 18.0f;
    float k = kBase / (1.0f + distance * 3.0f);
    float gravity = 9.80665f;
    float omega = sqrt(gravity * k);
    float phase = k * distance - omega * uniforms.timeAudio.z;
    float mainWave = sin(phase);
    float secondary = sin(k * 0.6f * distance - omega * 0.8f * uniforms.timeAudio.z + 0.7f);

    float attenuation = exp(-distance * 3.5f);
    float combined = (mainWave + secondary * 0.5f) * attenuation * uniforms.timeAudio.w;

    float rippleStrength = 0.024f + uniforms.animationParams.y * 0.015f;
    return normalize(toOrigin) * combined * rippleStrength;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]], constant Uniforms& uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord;

    float2 distortedUV = uv + wavyEdge(uv, uniforms);

    if (uniforms.timeAudio.w > 0.001f) {
        distortedUV += rippleDistortion(uv, uniforms);
    }

    float2 centered = distortedUV - 0.5f;
    centered *= uniforms.resolutionCornerQuality.xy;

    float2 halfSize = uniforms.resolutionCornerQuality.xy * 0.5f - 1.0f;
    float radius = uniforms.resolutionCornerQuality.z;

    float2 q = abs(centered) - halfSize + radius;
    float distToEdge = min(max(q.x, q.y), 0.0f) + length(max(q, 0.0f)) - radius;
    distToEdge = fabs(distToEdge);

    float quality = uniforms.resolutionCornerQuality.w;
    float qNorm = clamp(quality / 2.0f, 0.0f, 1.0f);

    float baseWidth = mix(14.0f, 38.0f, uniforms.timeAudio.y);
    baseWidth *= mix(0.9f, 1.2f, qNorm);

    if (uniforms.timeAudio.w > 0.001f) {
        float2 toOrigin = uv - float2(0.5, 1.0);
        float dist = length(toOrigin);
        float localRipple = exp(-dist * 5.0f) * uniforms.timeAudio.w;
        baseWidth += 14.0f * localRipple;
    }

    float sharpMask = 1.0f - smoothstep(0.0f, baseWidth * 0.38f, distToEdge);
    float blurMask = 1.0f - smoothstep(0.0f, baseWidth * 1.9f, distToEdge);
    float audioBloom = (1.0f - smoothstep(0.0f, baseWidth * 0.6f, distToEdge)) * uniforms.timeAudio.y * 0.35f;

    float combinedMask = (sharpMask + blurMask * 0.45f + audioBloom) * uniforms.animationParams.x;
    combinedMask = clamp(combinedMask, 0.0f, 1.0f);

    float perimeter = computePerimeter(distortedUV, uniforms);
    float3 glow = gradientColor(perimeter, uniforms);

    float hdrScale = uniforms.animationParams.z;
    float3 color = glow * hdrScale;

    return float4(color, combinedMask);
}
