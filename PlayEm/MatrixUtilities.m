//
//  MatrixUtilities.c
//  PlayEm
//
//  Created by Till Toenshoff on 25.12.21.
//  Copyright © 2021 Till Toenshoff. All rights reserved.
//

#include "MatrixUtilities.h"

#pragma mark Matrix Math Utilities

matrix_float4x4 matrix4x4_translation(float tx, float ty, float tz)
{
    return (matrix_float4x4) {{{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {tx, ty, tz, 1}}};
}

matrix_float4x4 matrix4x4_scale(float sx, float sy, float sz)
{
    return (matrix_float4x4) {{{sx, 0.0f, 0.0f, 0.0f}, {0.0f, sy, 0.0f, 0.0f}, {0.0f, 0.0f, sz, 0.0f}, {0.0f, 0.0f, 0.0f, 1.0f}}};
}

matrix_float4x4 matrix4x4_identity(void)
{
    return matrix4x4_translation(0.0f, 0.0f, 0.0f);
}

matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis)
{
    axis = vector_normalize(axis);
    float ct = cosf(radians);
    float st = sinf(radians);
    float ci = 1 - ct;
    float x = axis.x, y = axis.y, z = axis.z;

    return (matrix_float4x4) {{{ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0},
                               {x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0},
                               {x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0},
                               {0, 0, 0, 1}}};
}

matrix_float4x4 matrix_perspective_right_hand(float fovyRadians, float aspect, float nearZ, float farZ)
{
    float ys = 1 / tanf(fovyRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);

    return (matrix_float4x4) {{{xs, 0.0f, 0.0f, 0.0f}, {0.0f, ys, 0.0f, 0.0f}, {0.0f, 0.0f, zs, -1.0f}, {0.0f, 0.0f, nearZ * zs, 0.0f}}};
}

matrix_float4x4 matrix_orthographic(float left, float right, float bottom, float top, float near, float far)
{
    return (matrix_float4x4) {{{2.0f / (right - left), 0.0f, 0.0f, 0.0f},
                               {0.0f, 2.0f / (top - bottom), 0.0f, 0.0f},
                               {0.0f, 0.0f, -2.0f / (far - near), 0.0f},
                               {(left + right) / (left - right), (top + bottom) / (bottom - top), near / (near - far), 1.0f}}};
}
