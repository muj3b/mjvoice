#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float time;
    float2 resolution;
    float audioLevel;
    float rippleTime;
    float rippleIntensity;
    float animationState;
    float cornerRadius;
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

float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float3 gradientColor(float t, float time, float audioBoost) {
    float offset = time * 0.08;

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

    float noise = hash(float2(t, time * 0.1)) * 0.2;
    t = fract(t + offset + noise);

    float segment = t * 8.0;
    int index = int(segment);
    float blend = fract(segment);

    float3 colorA = colors[index % 8];
    float3 colorB = colors[(index + 1) % 8];
    float3 color = mix(colorA, colorB, smoothstep(0.0, 1.0, blend));

    float brightness = 1.0 + sin(time * 2.0 + t * 6.28318) * 0.15;
    brightness += audioBoost * 0.5;

    return color * brightness;
}

float calculateRectPerimeter(float2 uv, float2 resolution) {
    float aspect = resolution.x / max(resolution.y, 1.0);
    float2 centered = (uv - 0.5) * 2.0;
    centered.x *= aspect;

    float2 absPos = abs(centered);
    float2 edgeDist = float2(aspect, 1.0) - absPos;

    float perimeter;
    if (edgeDist.x < edgeDist.y) {
        float side = centered.x > 0 ? 1.0 : 3.0;
        float yPos = (centered.y + 1.0) * 0.5;
        if (centered.x < 0) { yPos = 1.0 - yPos; }
        perimeter = (side + yPos) * 0.25;
    } else {
        float side = centered.y > 0 ? 2.0 : 0.0;
        float xPos = (centered.x / max(aspect, 0.0001) + 1.0) * 0.5;
        if (centered.y > 0) { xPos = 1.0 - xPos; }
        perimeter = (side + xPos) * 0.25;
    }

    return fract(perimeter);
}

float2 wavyEdge(float2 uv, float time) {
    float2 distortion = float2(0.0);

    distortion.x = sin(time * 0.8 + uv.y * 12.0) * 0.004;
    distortion.x += sin(time * 1.3 + uv.y * 20.0) * 0.002;
    distortion.x += sin(time * 0.5 + uv.y * 6.0) * 0.003;

    distortion.y = sin(time * 0.8 + uv.x * 12.0) * 0.004;
    distortion.y += sin(time * 1.3 + uv.x * 20.0) * 0.002;
    distortion.y += sin(time * 0.5 + uv.x * 6.0) * 0.003;

    return distortion;
}

float2 rippleDistortion(float2 uv, constant Uniforms& uniforms) {
    float2 rippleOrigin = float2(0.5, 1.0);
    float2 toOrigin = uv - rippleOrigin;

    float2 aspectCorrect = float2(1.0, uniforms.resolution.y / max(uniforms.resolution.x, 1.0));
    float distance = length(toOrigin * aspectCorrect);

    float wave = sin(distance * 15.0 - uniforms.rippleTime * 12.0);
    wave *= exp(-distance * 4.0) * uniforms.rippleIntensity;

    float ringDist = abs(distance - uniforms.rippleTime * 0.4);
    float ring = exp(-ringDist * 25.0) * uniforms.rippleIntensity * 0.6;

    float totalRipple = (wave + ring) * 0.025;

    float2 dir = normalize(toOrigin + 0.0001);
    return dir * totalRipple;
}

float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

fragment float4 fragmentShader(
    VertexOut in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]],
    texture2d<float> backgroundTexture [[texture(0)]]
) {
    float2 uv = in.texCoord;

    float2 waveDistortion = wavyEdge(uv, uniforms.time);
    float2 distortedUV = uv + waveDistortion * uniforms.animationState;

    if (uniforms.rippleIntensity > 0.01) {
        distortedUV += rippleDistortion(uv, uniforms);
    }

    float2 centered = (distortedUV - 0.5) * uniforms.resolution;
    float2 boxSize = uniforms.resolution * 0.5 - 1.0;
    float distToEdge = fabs(sdRoundedBox(centered, boxSize, uniforms.cornerRadius));

    float baseWidth = 15.0 + uniforms.audioLevel * 30.0;
    float dynamicWidth = baseWidth;

    if (uniforms.rippleIntensity > 0.01) {
        float2 toOrigin = uv - float2(0.5, 1.0);
        float2 aspectCorrect = float2(1.0, uniforms.resolution.y / max(uniforms.resolution.x, 1.0));
        float dist = length(toOrigin * aspectCorrect);
        float localRipple = exp(-dist * 4.0) * uniforms.rippleIntensity;
        dynamicWidth += baseWidth * localRipple * 0.4;
    }

    float sharpMask = 1.0 - smoothstep(0.0, dynamicWidth * 0.35, distToEdge);
    float blurMask = 1.0 - smoothstep(0.0, dynamicWidth * 1.8, distToEdge);
    float audioGlow = (1.0 - smoothstep(0.0, dynamicWidth * 0.5, distToEdge)) * uniforms.audioLevel * 0.3;

    float combinedMask = (sharpMask + blurMask * 0.5 + audioGlow) * uniforms.animationState;

    float perimeterPos = calculateRectPerimeter(distortedUV, uniforms.resolution);

    if (uniforms.rippleIntensity > 0.01) {
        float2 toOrigin = uv - float2(0.5, 1.0);
        float dist = length(toOrigin);
        float warp = sin(dist * 18.0 - uniforms.rippleTime * 10.0);
        warp *= exp(-dist * 4.0) * uniforms.rippleIntensity * 0.25;
        perimeterPos = fract(perimeterPos + warp);
    }

    float3 glowColor = gradientColor(perimeterPos, uniforms.time, uniforms.audioLevel);

    constexpr sampler textureSampler(filter::linear, address::clamp_to_edge);
    float3 backgroundColor = backgroundTexture.sample(textureSampler, distortedUV).rgb;

    float contentMask = 1.0 - combinedMask;
    float3 finalColor = mix(glowColor, backgroundColor, contentMask);
    finalColor += glowColor * combinedMask * 0.4;

    return float4(finalColor, 1.0);
}
