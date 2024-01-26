//
//  WaveShaderTypes.m
//  PlayEm
//
//  Created by Till Toenshoff on 21.01.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef WaveShaderTypes_h
#define WaveShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

typedef NS_ENUM(NSInteger, BufferIndex)
{
    BufferIndexScopeLines  = 0,
    BufferIndexUniforms    = 1,
    BufferIndexFrequencies = 2,
    BufferIndexFeedback    = 3
};

typedef NS_ENUM(NSInteger, TextureIndex)
{
    TextureIndexWave = 0,
    TextureIndexLast = 1,
    TextureIndexCompose = 2
};

typedef struct
{
    matrix_float4x4 matrix;
    vector_float4   colorFactor;
} Feedback;

typedef struct
{
    vector_float2   screenSize;
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;
    float           lineAspectRatio;
    float           lineWidth;
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
} Uniforms;

typedef struct
{
    vector_float2   screenSize;
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;
    float           lineAspectRatio;
    float           lineWidth;
    uint32_t        sampleCount;
    vector_float4   color;
} WaveUniforms;

#endif /* WaveShaderTypes_h */
