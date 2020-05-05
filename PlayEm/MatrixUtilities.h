//
//  MatrixUtilities.h
//  PlayEm
//
//  Created by Till Toenshoff on 25.12.21.
//  Copyright © 2021 Till Toenshoff. All rights reserved.
//

#ifndef MatrixUtilities_h
#define MatrixUtilities_h

#import <simd/simd.h>

extern matrix_float4x4 matrix_perspective_right_hand(float fovyRadians, float aspect, float nearZ, float farZ);
extern matrix_float4x4 matrix_orthographic(float left, float right, float bottom, float top, float near, float far);
extern matrix_float4x4 matrix4x4_identity(void);

extern matrix_float4x4 matrix4x4_translation(float tx, float ty, float tz);
extern matrix_float4x4 matrix4x4_scale(float sx, float sy, float sz);
extern matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis);

#endif /* MatrixUtilities_h */
