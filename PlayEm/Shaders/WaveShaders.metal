//
//  WaveShaders.metal
//  PlayEm
//
//  Created by Till Toenshoff on 15.03.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#include <metal_stdlib>

#include <simd/simd.h>

#import "../ShaderTypes.h"
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

