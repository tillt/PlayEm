//
//  ScopeShaderTypes.h
//  PlayEm
//
//  Created by Till Toenshoff on 09.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef ScopeShaderTypes_h
#define ScopeShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

#include "ShaderTypes.h"

typedef NS_ENUM(NSInteger, BufferIndex)
{
    BufferIndexScopeLines  = 0,
    BufferIndexUniforms    = 1,
    BufferIndexFrequencies = 2,
    BufferIndexFeedback    = 3,
};

typedef NS_ENUM(NSInteger, TextureIndex)
{
    TextureIndexFirst       = 0,
    TextureIndexFrequencies = 1,
    TextureIndexLast        = 2,
    TextureIndexCompose     = 3,
};

typedef struct
{
    vector_float2   screenSize;
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;
    float           lineAspectRatio;
    float           lineWidth;
    float           miterLimit;
    float           frequencyLineWidth;
    float           frequencySpaceWidth;
    uint32_t        sampleCount;
    uint32_t        frequenciesCount;
    vector_float4   color;
    vector_float4   fftColor;
    uint32_t        sampleStepping;
    uint32_t        frequencyStepping;
    //matrix_float4x4 feedbackMatrix;
    //vector_float4   feedbackColorFactor;
    Feedback        feedback;
} ScopeUniforms;

#endif /* ScopeShaderTypes_h */
