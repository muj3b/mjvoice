#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct RainbowUniforms {
    float2 resolution;
    float  time;
    float  intensity;
    float  rippleProgress;
    float  rippleStrength;
    float  rippleWidth;
    float  rippleSoftness;
};

static inline float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vertex VertexOut rainbow_vertex(uint vertexID [[vertex_id]]) {
    const float2 positions[6] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0, 1.0),  float2(1.0, -1.0), float2(1.0, 1.0)
    };
    const float2 texcoords[6] = {
        float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0),
        float2(0.0, 1.0), float2(1.0, 0.0), float2(1.0, 1.0)
    };

    VertexOut outVertex;
    outVertex.position = float4(positions[vertexID], 0.0, 1.0);
    outVertex.uv = texcoords[vertexID];
    return outVertex;
}

fragment float4 rainbow_fragment(VertexOut in [[stage_in]],
                                  constant RainbowUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.uv;

    // Distance to the nearest edge in uv space (0-0.5)
    float edgeDistance = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));

    float baseThickness = mix(0.0012, 0.008, uniforms.intensity);
    float glowThickness = baseThickness * 2.1;
    float highlightThickness = baseThickness * 0.35;
    float softness = baseThickness * 0.35;

    // Ripple band travelling from bottom to top
    float rippleMod = 0.0;
    if (uniforms.rippleProgress >= 0.0) {
        float center = clamp(uniforms.rippleProgress, 0.0, 1.0);
        float distance = uv.y - center;
        float width = max(uniforms.rippleWidth, 0.0008);
        float envelope = exp(-(distance * distance) / (2.0 * width * width));
        rippleMod = envelope * uniforms.rippleStrength;
        edgeDistance = max(edgeDistance - rippleMod * 0.6, 0.0);
        float flow = sin((uv.x + uv.y) * 18.0 + uniforms.time * 5.0) * rippleMod * 0.015;
        uv.y -= flow;
    }

    float edgeMask = smoothstep(baseThickness + softness, baseThickness, edgeDistance);
    float glowMask = smoothstep(glowThickness + softness * 2.0, glowThickness, edgeDistance);
    float highlightMask = smoothstep(highlightThickness + softness, highlightThickness, edgeDistance);

    // Animated rainbow palette
    float hue = fract(uniforms.time * 0.06 + uv.x * 0.5 + uv.y * 0.2);
    float saturation = mix(0.65, 0.92, uniforms.intensity);
    float brightness = mix(0.55, 0.95, uniforms.intensity + rippleMod * 0.4);
    float3 rainbow = hsv2rgb(float3(hue, saturation, brightness));
    float3 glowColor = rainbow * (0.35 + 0.5 * uniforms.intensity + rippleMod * 1.2);
    float3 highlightColor = float3(1.0) * (0.05 + 0.24 * uniforms.intensity + rippleMod * 0.45);

    float alpha = edgeMask * (0.38 + 0.32 * uniforms.intensity) + glowMask * 0.25;
    float3 color = rainbow * edgeMask + glowColor * glowMask + highlightColor * highlightMask;

    // Clamp alpha and color
    alpha = clamp(alpha, 0.0, 1.0);
    color = clamp(color, 0.0, 1.0);

    return float4(color, alpha);
}
