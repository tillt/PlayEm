//
//  ShaderTypes.h
//  PlayEm
//
//  Created by Till Toenshoff on 09.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

typedef NS_ENUM(NSInteger, VertexAttribute)
{
    VertexAttributePosition = 0,
    VertexAttributeTexcoord = 1
};

typedef struct
{
    vector_float2 begin;
    vector_float2 end;
} ShaderLine;

typedef struct
{
    vector_float2 position;
} PolyNode;

typedef struct
{
    vector_float2 position;
    vector_float2 texcoord;
} AAPLTextureVertex;

typedef struct Feedback_t
{
    matrix_float4x4 matrix;
    vector_float4   colorFactor;
} Feedback;

#endif /* ShaderTypes_h */
