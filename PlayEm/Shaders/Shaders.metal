//
//  Shaders.metal
//  PlayEm
//
//  Created by Till Toenshoff on 09.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>

#import "../ShaderTypes.h"
#import "../ScopeShaderTypes.h"
#import "../Sample/VisualPair.h"

using namespace metal;

typedef struct {
    float2 position;
} Point;

typedef struct {
    Point begin;
    Point end;
} Line;

typedef Point Node;

typedef struct {
    float3 position [[ attribute(VertexAttributePosition) ]];
    float2 texCoord [[ attribute(VertexAttributeTexcoord) ]];
} Vertex;

typedef struct {
    float4 position [[ position ]];
    float4 color;
} ColorInOut;

// Vertex shader outputs and fragment shader inputs for texturing pipeline.
typedef struct {
    float4 position [[ position ]];
    float2 texcoord;
} TexturePipelineRasterizerData;

/// Projects provided vertices to corners of drawable texture.
vertex TexturePipelineRasterizerData projectTexture(unsigned int vertex_id [[ vertex_id ]]) {
    float4x4 renderedCoordinates = float4x4(float4(-1.0, -1.0, 0.0, 1.0),
                                            float4( 1.0, -1.0, 0.0, 1.0),
                                            float4(-1.0,  1.0, 0.0, 1.0),
                                            float4( 1.0,  1.0, 0.0, 1.0));
    float4x2 uvs = float4x2(float2(0.0, 1.0),
                            float2(1.0, 1.0),
                            float2(0.0, 0.0),
                            float2(1.0, 0.0));
    
    TexturePipelineRasterizerData outVertex;
   
    outVertex.position = renderedCoordinates[vertex_id];
    outVertex.texcoord = uvs[vertex_id];
    
    return outVertex;
}

/// Instance vertex shader rendering lines.
/// FIXME: This is strictly monochrome at the moment. Completely lacks use of transparency or textures to its advantage.
vertex ColorInOut polySegmentInstanceShader(constant Node*              nodes        [[ buffer(BufferIndexScopeLines) ]],
                                            constant ScopeUniforms&     uniforms     [[ buffer(BufferIndexUniforms) ]],
                                            unsigned int                vid          [[ vertex_id ]],
                                            unsigned int                instanceId   [[ instance_id ]])
{
    float4x4 matrix = uniforms.modelViewMatrix;

    const unsigned int sampleCount = uniforms.sampleCount;
    
    // We need a three line segments for being able to draw a single line with its endings.
    // For three lines worth of data, we need four nodes.
    
    const unsigned int previousIndex = instanceId > 0 ? instanceId-1 : 0;
    const unsigned int currentIndex = instanceId;
    const unsigned int nextIndex = instanceId + 1 >= sampleCount ? sampleCount-1 : instanceId + 1;
    const unsigned int skipIndex = instanceId + 2 >= sampleCount ? sampleCount-1 : instanceId + 2;

    const constant float& thickness = uniforms.lineWidth;

    const constant float2& p0 = nodes[previousIndex].position;
    const constant float2& p1 = nodes[currentIndex].position;
    const constant float2& p2 = nodes[nextIndex].position;
    const constant float2& p3 = nodes[skipIndex].position;

    // Determine the projected coordinates.
    // TODO: This may need some redo as it may be a reason on why i have to work against aspect ratio issues in the first place.
    // Something tells me all of this can be avoided.
    const float4 pmv0 = matrix * float4(p0.x, p0.y, 0.0, 0.0);
    const float4 pmv1 = matrix * float4(p1.x, p1.y, 0.0, 0.0);
    const float4 pmv2 = matrix * float4(p2.x, p2.y, 0.0, 0.0);
    const float4 pmv3 = matrix * float4(p3.x, p3.y, 0.0, 0.0);

    const float2 pd0 = float2(pmv0[0], pmv0[1]);
    const float2 pd1 = float2(pmv1[0], pmv1[1]);
    const float2 pd2 = float2(pmv2[0], pmv2[1]);
    const float2 pd3 = float2(pmv3[0], pmv3[1]);

    // Determine the direction of each of the 3 segments (previous, current, next).
    float2 v0 = normalize(pd1 - pd0);
    float2 v1 = normalize(pd2 - pd1);
    float2 v2 = normalize(pd3 - pd2);

    // Determine the normal of each of the 3 segments (previous, current, next).
    float2 n0 = float2(-v0.y, v0.x);
    float2 n1 = float2(-v1.y, v1.x);
    float2 n2 = float2(-v2.y, v2.x);
    
    // Determine miter vectors by averaging the normals of the 2 segments.
    float2 miter_a = normalize(n0 + n1);    // miter at start of current segment
    float2 miter_b = normalize(n1 + n2);    // miter at end of current segment

    // Determine the length of the miter by projecting it onto normal and then inverse it.
    // NOTE: This miter can be extremely long and thus causes weird spikes - limitting it.
    float length_a = min(thickness / dot( miter_a, n1), thickness * 4);
    float length_b = min(thickness / dot( miter_b, n1), thickness * 4);

    // Premultiply a bunch of things so we dont have to repeat ourselves later on.
    float2 n1_thick_ar = n1 * thickness;
    n1_thick_ar.x *= uniforms.lineAspectRatio;
    float2 n2_thick_ar = n2 * thickness;
    n2_thick_ar.x *= uniforms.lineAspectRatio;

    float2 miter_a_length_ar = miter_a * length_a;
    miter_a_length_ar.x *= uniforms.lineAspectRatio;
    float2 miter_b_length_ar = miter_b * length_b;
    miter_b_length_ar.x *= uniforms.lineAspectRatio;

    
    const float2 positionLookupAB[2][2] = {
        {
            // Start at negative normal.
            pd1 - n1_thick_ar,
            // Proceed to positive miter.
            pd1 + miter_a_length_ar,
        },
        {
            // Start at negative miter.
            pd1 - miter_a_length_ar,
            // Proceed to positive normal.
            pd1 + n1_thick_ar,
        },
    };

    const int positionIndexAB = (((int)copysign(1.0, dot(v0, n1))) + 1) / 2;

    const float2 pa = positionLookupAB[positionIndexAB][0];
    const float2 pb = positionLookupAB[positionIndexAB][1];

//    float2 pa, pb;
//    if(dot(v0, n1) > 0) {
//        // Start at negative miter.
//        pa = pd1 - miter_a_length_ar;
//        // Proceed to positive normal.
//        pb = pd1 + n1_thick_ar;
//    } else {
//        // Start at negative normal.
//        pa = pd1 - n1_thick_ar;
//        // Proceed to positive miter.
//        pb = pd1 + miter_a_length_ar;
//    }

    
    const float2 positionLookupCDE[2][3] = {
        {
            // Proceed to negative miter.
            pd2 - miter_b_length_ar,
            // Proceed to positive normal.
            pd2 + n1_thick_ar,
            // End at positive normal.
            pd2 + n2_thick_ar,
        },
        {
            // Proceed to negative normal.
            pd2 - n1_thick_ar,
            // Proceed to positive miter.
            pd2 + miter_b_length_ar,
            // End at negative normal.
            pd2 - n2_thick_ar,
        },
    };

    const int positionIndexCDE = (((int)copysign(1.0, dot(v2, n1))) + 1 ) / 2;

    const float2 pc = positionLookupCDE[positionIndexCDE][0];
    const float2 pd = positionLookupCDE[positionIndexCDE][1];
    const float2 pe = positionLookupCDE[positionIndexCDE][2];

//    float2 pc, pd, pe;
//    if( dot( v2, n1 ) < 0 ) {
//        // Proceed to negative miter.
//        pc = pd2 - miter_b_length_ar;
//        // Proceed to positive normal.
//        pd = pd2 + n1_thick_ar;
//        // End at positive normal.
//        pe = pd2 + n2_thick_ar;
//    } else {
//        // Proceed to negative normal.
//        pc = pd2 - n1_thick_ar;
//        // Proceed to positive miter.
//        pd = pd2 + miter_b_length_ar;
//        // End at negative normal.
//        pe = pd2 - n2_thick_ar;
//    }
    
    const float2 position[] = {
        pa, pb, pc, pd, pe,
    };
    
    return ColorInOut {
        {   position[vid % 5].x, position[vid % 5].y, 0.0f, 1.0f    },
        uniforms.color
    };
}

fragment float4 scopeFragmentShader(ColorInOut in [[stage_in]])
{
    return in.color;
}

vertex ColorInOut frequenciesVertexShader(constant ScopeUniforms& uniforms          [[ buffer(BufferIndexUniforms) ]],
                                          const constant float*   frequenciesBuffer [[ buffer(BufferIndexFrequencies) ]],
                                          unsigned int            vid               [[ vertex_id ]])
{
    float4x4 matrix = uniforms.modelViewMatrix;

    const unsigned int instance = vid / 4;
    
    const float width = uniforms.frequencySpaceWidth + uniforms.frequencyLineWidth;
    
    const float x = -1.0f + (instance * width);
    const float halfFFTBarWidth = uniforms.frequencyLineWidth / 2.0;

    // Top
    const float4 startPosition = matrix * float4(x + halfFFTBarWidth,
                                                 -1.0f,
                                                 0.0f,
                                                 1.0f);
    // Bottom
    const float4 endPosition = matrix * float4(x + halfFFTBarWidth,
                                               1.0f,
                                               0.0f,
                                               1.0f);

    const float4 v = endPosition - startPosition;
    const float2 p0 = float2(startPosition.x, startPosition.y);
    // Top center node.
    const float2 v0 = float2(v.x, v.y);
    // Top left node.
    const float2 v1 = halfFFTBarWidth * normalize(v0) * float2x2(0.0f, -1.0f, 1.0f, 0.0f);
    // Top right node.
    const float2 v2 = halfFFTBarWidth * normalize(v1) * float2x2(0.0f, -1.0f, 1.0f, 0.0f);

    const float2 pa = p0 + v1 + v2;
    const float2 pb = p0 - v1 + v2;
    const float2 pc = p0 + v1 + v0 - v2;
    const float2 pd = p0 - v1 + v0 - v2;

    const float2 position[4] = {
        float2(pa.x, pa.y),
        float2(pb.x, pb.y),
        float2(pc.x, pc.y),
        float2(pd.x, pd.y),
    };

    const float amplitude = frequenciesBuffer[instance % uniforms.frequenciesCount];
    const float4 color = uniforms.fftColor;

    const float4 colorLoookup[] = {
        float4(color.r * amplitude,
               color.g * amplitude,
               color.b * amplitude,
               color.a * amplitude),
        float4(color.r, color.g, color.b, color.a * amplitude),
    };

    //const int amplitudeIndex = ((int)floor(amplitude / 0.01f)) % 2;
    const int amplitudeIndex = 0;
    
    const float4 c = colorLoookup[amplitudeIndex];
    const float2 p = position[vid & 0x03];

    return ColorInOut{
        { p.x, p.y, 0.0f, 1.0f },
        { c.r, c.g, c.b, c.a }
    };
}

fragment float4 frequenciesFragmentShader(ColorInOut in [[stage_in]])
{
    return in.color;
}

/// Fragment shader that samples a texture and outputs the sampled color.
fragment float4 drawableTextureFragmentShader(TexturePipelineRasterizerData    in      [[ stage_in ]],
                                              texture2d<float, access::sample> textureScope   [[ texture(TextureIndexScope) ]],
                                              texture2d<float, access::sample> textureCompose [[ texture(TextureIndexCompose) ]])
{
    sampler simpleSampler;
    return textureCompose.sample(simpleSampler, in.texcoord) + (textureScope.sample(simpleSampler, in.texcoord) / 5.0f);
}

/// Fragment shader that samples textures and outputs the sampled color.
fragment float4 composeFragmentShader(TexturePipelineRasterizerData    in           [[ stage_in ]],
                                      texture2d<float, access::sample> textureScope [[ texture(TextureIndexScope) ]],
                                      texture2d<float, access::sample> textureLast  [[ texture(TextureIndexLast) ]],
                                      constant ScopeUniforms&          uniforms     [[ buffer(BufferIndexUniforms) ]])
{
    constexpr sampler quadSampler;

    float4 textureColorScope = textureScope.sample(quadSampler, in.texcoord);
 
    float4 transformed = float4(in.texcoord.x - 0.5, in.texcoord.y - 0.5, 0.0, 0.0) * uniforms.feedback.matrix;

    float4 textureColorLast = textureLast.sample(quadSampler, float2(transformed.x + 0.5, transformed.y + 0.5));

    float4 lastResult = textureColorLast * uniforms.feedback.colorFactor;

    return fmin(textureColorScope + lastResult, 1.0f);
}


typedef struct
{
    float mixturePercent;
} DissolveBlendUniform;

fragment float4 dissolveBlendFragment(
    TexturePipelineRasterizerData in [[ stage_in ]],
    texture2d<float, access::sample> inputTexture  [[ texture(0) ]],
    texture2d<float, access::sample> inputTexture2  [[ texture(1) ]],
    constant DissolveBlendUniform& uniform [[ buffer(1) ]])
{
    constexpr sampler quadSampler;
    float4 textureColor = inputTexture.sample(quadSampler, in.texcoord);
    constexpr sampler quadSampler2;
    float4 textureColor2 = inputTexture2.sample(quadSampler2, in.texcoord);

    return mix(textureColor, textureColor2, uniform.mixturePercent);
}
