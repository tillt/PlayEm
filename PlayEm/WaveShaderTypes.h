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

#include "ShaderTypes.h"

typedef NS_ENUM(NSInteger, WaveBufferIndex)
{
    WaveBufferIndexVisualPairs    = 0,
    WaveBufferIndexUniforms       = 1
};

typedef NS_ENUM(NSInteger, WaveTextureIndex)
{
    WaveTextureIndexSource   = 0,
    WaveTextureIndexOverlay = 1,
    WaveTextureIndexPosition = 2,
    WaveTextureIndexUVSMapping = 3
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;

    float           lineAspectRatio;
    float           lineWidth;

    uint32_t        sampleCount;

    vector_float4   color;

    float           tileWidth;
    
    float           currentFrameOffset;
} WaveUniforms;

#endif /* WaveShaderTypes_h */
