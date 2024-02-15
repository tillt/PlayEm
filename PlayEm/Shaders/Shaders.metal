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
#import "../WaveShaderTypes.h"
#import "../Sample/VisualPair.h"

using namespace metal;

typedef struct {
    float2 position;
} Point;

typedef struct {
    Point begin;
    Point end;
} Line;

typedef struct {
    float2 position;
} Node;

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

///
/// Instance vertex shader rendering lines.
/// FIXME: This is strictly monochrome at the moment. Completely lacks use of transparency or textures to its advantage.
///
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

    float2 pa,pb,pc,pd,pe;

    // Premultiply a bunch of things so we dont have to repeat ourselves later on.
    float2 n1_thick_ar = n1 * thickness;
    n1_thick_ar.x *= uniforms.lineAspectRatio;
    float2 n2_thick_ar = n2 * thickness;
    n2_thick_ar.x *= uniforms.lineAspectRatio;

    float2 miter_a_length_ar = miter_a * length_a;
    miter_a_length_ar.x *= uniforms.lineAspectRatio;
    float2 miter_b_length_ar = miter_b * length_b;
    miter_b_length_ar.x *= uniforms.lineAspectRatio;

    if(dot(v0, n1) > 0) {
        // Start at negative miter.
        pa = pd1 - miter_a_length_ar;
        // Proceed to positive normal.
        pb = pd1 + n1_thick_ar;
    } else {
        // Start at negative normal.
        pa = pd1 - n1_thick_ar;
        // Proceed to positive miter.
        pb = pd1 + miter_a_length_ar;
    }

    if( dot( v2, n1 ) < 0 ) {
        // Proceed to negative miter.
        pc = pd2 - miter_b_length_ar;
        // Proceed to positive normal.
        pd = pd2 + n1_thick_ar;
        // End at positive normal.
        pe = pd2 + n2_thick_ar;
    } else {
        // Proceed to negative normal.
        pc = pd2 - n1_thick_ar;
        // Proceed to positive miter.
        pd = pd2 + miter_b_length_ar;
        // End at negative normal.
        pe = pd2 - n2_thick_ar;
    }
    
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
    
    const float width = (2.0f / uniforms.frequenciesCount);
    
    const float x = -1.0f + (instance * width);
    const float space = width / 2.0f;
    const float halfwidth = width - space / 2.0f;

    //float x = -1.0f + (instance * (uniforms.frequencySpaceWidth + uniforms.frequencyLineWidth));
    float4 startPosition = matrix * float4(x+halfwidth, -1.0f, 0.0f, 1.0f);
    float4 endPosition = matrix * float4(x+halfwidth, 1.0f, 0.0f, 1.0f);

    float4 v = endPosition - startPosition;
    float2 p0 = float2(startPosition.x, startPosition.y);
    float2 v0 = float2(v.x, v.y);
    float2 v1 = halfwidth * normalize(v0) * float2x2(0.0f, -1.0f, 1.0f, 0.0f);
    v1.x *= uniforms.lineAspectRatio;
    float2 v2 = halfwidth * normalize(v1) * float2x2(0.0f, -1.0f, 1.0f, 0.0f);
    v2.x *= uniforms.lineAspectRatio;
 
    float2 pa = p0 + v1 + v2;
    float2 pb = p0 - v1 + v2;
    float2 pc = p0 + v1 + v0 - v2;
    float2 pd = p0 - v1 + v0 - v2;

    float2 position[] = {
        float2(pa.x, pa.y),
        float2(pb.x, pb.y),
        float2(pc.x, pc.y),
        float2(pd.x, pd.y),
    };

    const float amplitude = frequenciesBuffer[instance % uniforms.frequenciesCount];
    
    const float2 p = position[vid & 0x03];

    return ColorInOut{
        { p.x, p.y, 0.0f, 1.0f },
        { uniforms.fftColor.r, uniforms.fftColor.g, uniforms.fftColor.b, uniforms.fftColor.a * amplitude }
    };
}

fragment float4 frequenciesFragmentShader(ColorInOut in [[stage_in]])
{
    return in.color;
}

// Fragment shader that samples a texture and outputs the sampled color.
fragment float4 drawableTextureFragmentShader(TexturePipelineRasterizerData    in      [[ stage_in ]],
                                              texture2d<float, access::sample> textureScope   [[ texture(TextureIndexScope) ]],
                                              texture2d<float, access::sample> textureCompose [[ texture(TextureIndexCompose) ]])
{
    sampler simpleSampler;
    return textureCompose.sample(simpleSampler, in.texcoord) + (textureScope.sample(simpleSampler, in.texcoord) / 5.0f);
}

// Fragment shader that samples textures and outputs the sampled color.
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

#pragma mark -= MetalWaveView

// Fragment shader that samples a texture and outputs the sampled color.
fragment float4 waveDrawableTextureFragmentShader(TexturePipelineRasterizerData    in      [[ stage_in ]],
                                                  texture2d<float, access::sample> textureWave   [[ texture(WaveTextureIndexSource) ]])
{
    constexpr sampler simpleSampler(coord::normalized,
                                    address::repeat,
                                    filter::linear);
    return textureWave.sample(simpleSampler, in.texcoord);
}


vertex ColorInOut waveTileVertexShader(const constant VisualPair* pairs [[ buffer(WaveBufferIndexVisualPairs) ]],
                                       constant WaveUniforms& uniforms  [[ buffer(WaveBufferIndexUniforms) ]],
                                       unsigned int vertex_id           [[ vertex_id ]])
{
    float4x4 matrix = uniforms.modelViewMatrix;
    
    const unsigned int instance = vertex_id / 4;
    
    const float width = 2.0f / uniforms.sampleCount;
    
    const float x = -1.0f + (instance * width);
    const float halfwidth = width / 2.0f;
  
    const float top = pairs[instance].negativeAverage - uniforms.lineWidth;
    const float bottom = pairs[instance].positiveAverage + uniforms.lineWidth;
//    const float top = -1.0;
//    const float bottom = 1.0;

    float4 startPosition = matrix * float4(x, top, 0.0f, 1.0f);
    float4 endPosition = matrix * float4(x, bottom, 0.0f, 1.0f);
    
    float4 v = endPosition - startPosition;
    float2 p0 = float2(startPosition.x, startPosition.y);
    float2 v0 = float2(v.x, v.y);
    float2 v1 = halfwidth * normalize(v0) * float2x2(0.0f, -1.0f, 1.0f, 0.0f);
    float2 v2 = halfwidth * normalize(v1) * float2x2(0.0f, -1.0f, 1.0f, 0.0f);
    
    float2 pa = p0 + v1 + v2;
    float2 pb = p0 - v1 + v2;
    float2 pc = p0 + v1 + v0 - v2;
    float2 pd = p0 - v1 + v0 - v2;
    
    float2 position[] = {
        float2(pa.x, pa.y),
        float2(pb.x, pb.y),
        float2(pc.x, pc.y),
        float2(pd.x, pd.y),
    };
    
    const float2 p = position[vertex_id & 0x03];
    
    return ColorInOut{
        { p.x, p.y, 0.0f, 1.0f },
        { uniforms.color.r, uniforms.color.g, uniforms.color.b, uniforms.color.a }
    };
}

fragment float4 waveFragmentShader(ColorInOut in [[stage_in]],
                                   constant WaveUniforms & uniforms [[ buffer(WaveBufferIndexUniforms) ]])
{
    float4 out = { uniforms.color.r, uniforms.color.g, uniforms.color.b, 1.0 };
    return out;
}

fragment float4 waveTileFragmentShader(ColorInOut in [[stage_in]],
                                       texture2d<float, access::sample> inputTexture  [[ texture(WaveTextureIndexSource) ]],
                                       constant WaveUniforms & uniforms [[ buffer(WaveBufferIndexUniforms) ]])
{
    return in.color;
}

vertex TexturePipelineRasterizerData waveProjectTextureVertexShader(constant WaveUniforms & uniforms   [[ buffer(WaveBufferIndexUniforms) ]],
                                                                    unsigned int vertex_id [[ vertex_id ]],
                                                                    constant const float &tilePosition [[buffer(WaveTextureIndexPosition)]])
{
    float4x4 renderedCoordinates = float4x4(float4(tilePosition,                        -1.0,   0.0,    1.0),
                                            float4(tilePosition + uniforms.tileWidth,   -1.0,   0.0,    1.0),
                                            float4(tilePosition,                        1.0,    0.0,    1.0),
                                            float4(tilePosition + uniforms.tileWidth,   1.0,    0.0,    1.0));

    float4x2 uvs = float4x2(float2(0.0, 1.0),
                            float2(1.0, 1.0),
                            float2(0.0, 0.0),
                            float2(1.0, 0.0));
    
    TexturePipelineRasterizerData outVertex;
   
    outVertex.position = renderedCoordinates[vertex_id];
    outVertex.texcoord = uvs[vertex_id];
    
    return outVertex;
}


// Fragment shader that samples a texture and outputs the sampled color.
fragment float4 waveProjectTextureFragmentShader(TexturePipelineRasterizerData    in      [[ stage_in ]],
                                                 texture2d<float, access::sample> inputTexture   [[ texture(WaveTextureIndexSource) ]])
{
    sampler simpleSampler;
    return inputTexture.sample(simpleSampler, in.texcoord);
}

vertex TexturePipelineRasterizerData waveOverlayComposeTextureVertexShader(constant WaveUniforms & uniforms   [[ buffer(WaveBufferIndexUniforms) ]],
                                                                           constant const float2 &uvsMap      [[ buffer(WaveTextureIndexUVSMapping) ]],
                                                                           unsigned int vertex_id             [[ vertex_id ]])
{
    float4x4 renderedCoordinates = float4x4(float4(-1.0, -1.0, 0.0, 1.0),
                                            float4( 1.0, -1.0, 0.0, 1.0),
                                            float4(-1.0,  1.0, 0.0, 1.0),
                                            float4( 1.0,  1.0, 0.0, 1.0));

    float4x2 uvs = float4x2(float2(0.0,         uvsMap.y),
                            float2(uvsMap.x,    uvsMap.y),
                            float2(0.0,         0.0),
                            float2(uvsMap.x,    0.0));
    
    TexturePipelineRasterizerData outVertex;
   
    outVertex.position = renderedCoordinates[vertex_id];
    outVertex.texcoord = uvs[vertex_id];
    
    return outVertex;
}

fragment float4 waveOverlayComposeTextureFragmentShader(
    TexturePipelineRasterizerData in [[ stage_in ]],
    texture2d<float, access::sample> waveTexture     [[ texture(WaveTextureIndexSource) ]])
{
    constexpr sampler quadSampler(coord::normalized,
                                  address::repeat,
                                  filter::linear);

    return waveTexture.sample(quadSampler, in.texcoord);
}

vertex TexturePipelineRasterizerData waveCurrentTimeTextureVertexShader(constant WaveUniforms & uniforms   [[ buffer(WaveBufferIndexUniforms) ]],
                                                                        unsigned int vertex_id             [[ vertex_id ]])
{
    float4x4 renderedCoordinates = float4x4(float4(uniforms.currentFrameOffset, -1.0, 0.0, 1.0),
                                            float4( 1.0, -1.0, 0.0, 1.0),
                                            float4(uniforms.currentFrameOffset,  1.0, 0.0, 1.0),
                                            float4( 1.0,  1.0, 0.0, 1.0));

    float4x2 uvs = float4x2(float2(uniforms.currentFrameOffset, 1.0),
                            float2(1.0, 1.0),
                            float2(uniforms.currentFrameOffset, 0.0),
                            float2(1.0, 0.0));
    
    TexturePipelineRasterizerData outVertex;
   
    outVertex.position = renderedCoordinates[vertex_id];
    outVertex.texcoord = uvs[vertex_id];
    
    return outVertex;
}

fragment float4 waveCurrentTimeTextureFragmentShader(
    TexturePipelineRasterizerData in [[ stage_in ]],
    texture2d<float, access::sample> waveTexture     [[ texture(WaveTextureIndexSource) ]])
{
    constexpr sampler quadSampler(coord::normalized,
                                  address::repeat,
                                  filter::linear);

    float4 color = waveTexture.sample(quadSampler, in.texcoord);
    float gray = 0.21 * color[0] + 0.71 * color[1] + 0.07 * color[3];
    return float4(gray, gray, gray, color[3]);
}

/*
CGContextSetLineWidth(context, 7.0f);
CGContextSetStrokeColorWithColor(context, [[self.color colorWithAlphaComponent:0.40f] CGColor]);

CGFloat mid = floor(layer.bounds.size.height / 2.0);

for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
    CGFloat top = (mid + ((data[sampleIndex].negativeAverage * layer.bounds.size.height) / 2.0)) - 2.0;
    CGFloat bottom = (mid + ((data[sampleIndex].positiveAverage * layer.bounds.size.height) / 2.0)) + 2.0;

    CGContextMoveToPoint(context, sampleIndex, top);
    CGContextAddLineToPoint(context, sampleIndex, bottom);
    CGContextStrokePath(context);
}

CGContextSetLineWidth(context, 1.5);
CGContextSetStrokeColorWithColor(context, self.color.CGColor);

for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
    CGFloat top = (mid + ((data[sampleIndex].negativeAverage * layer.bounds.size.height) / 2.0)) - 1.0;
    CGFloat bottom = (mid + ((data[sampleIndex].positiveAverage * layer.bounds.size.height) / 2.0)) + 1.0;

    CGContextMoveToPoint(context, sampleIndex, top);
    CGContextAddLineToPoint(context, sampleIndex, bottom);
    CGContextStrokePath(context);
}
 */

/*
 
 
vertex ColorInOut waveVertexShader(constant WaveUniforms&  uniforms          [[ buffer(WaveBufferIndexUniforms) ]],
                                   const constant float*   samplesBuffer     [[ buffer(WaveBufferIndexVisualPairs) ]],
                                   unsigned int            vid               [[ vertex_id ]])
{
    float4x4 matrix = uniforms.modelViewMatrix;

    const unsigned int instance = vid / 4;
    
    const float width = (2.0f / uniforms.sampleCount);
    const float top = samplesBuffer[instance % uniforms.sampleCount];
    const float bottom = samplesBuffer[instance % uniforms.sampleCount];

    const float x = -1.0f + (instance * width);
    const float space = width / 2.0f;
    const float halfwidth = width - space / 2.0f;

    //float x = -1.0f + (instance * (uniforms.frequencySpaceWidth + uniforms.frequencyLineWidth));
    float4 startPosition = matrix * float4(x+halfwidth, -1.0f, 0.0f, 1.0f);
    float4 endPosition = matrix * float4(x+halfwidth, 1.0f, 0.0f, 1.0f);

    float4 v = endPosition - startPosition;
    float2 p0 = float2(startPosition.x, startPosition.y);
    float2 v0 = float2(v.x, v.y);
    float2 v1 = halfwidth * normalize(v0) * float2x2(0.0f, -1.0f, 1.0f, 0.0f);
    v1.x *= uniforms.lineAspectRatio;
    float2 v2 = halfwidth * normalize(v1) * float2x2(0.0f, -1.0f, 1.0f, 0.0f);
    v2.x *= uniforms.lineAspectRatio;
 
    float2 pa = p0 + v1 + v2;
    float2 pb = p0 - v1 + v2;
    float2 pc = p0 + v1 + v0 - v2;
    float2 pd = p0 - v1 + v0 - v2;

    float2 position[] = {
        float2(pa.x, pa.y),
        float2(pb.x, pb.y),
        float2(pc.x, pc.y),
        float2(pd.x, pd.y),
    };

   
    const float2 p = position[vid & 0x03];
     return ColorInOut{
         { p.x, p.y, 0.0f, 1.0f },
         { uniforms.color.r, uniforms.color.g, uniforms.color.b, uniforms.color.a * amplitude }
     };
}
*/
