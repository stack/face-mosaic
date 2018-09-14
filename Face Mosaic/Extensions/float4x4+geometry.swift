//
//  float4x4+geometry.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/4/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import simd

extension float4x4 {
    
    static func identity() -> float4x4 {
        return float4x4(diagonal: float4(1.0, 1.0, 1.0, 1.0))
    }
    
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> float4x4 {
        let length = 1.0 / (right - left)
        let height = 1.0 / (top - bottom)
        let depth = 1.0 / (far - near)
        
        let p = float4(2.0 * length, 0.0,          0.0,                 0.0)
        let q = float4(0.0,          2.0 * height, 0.0,                 0.0)
        let r = float4(0.0,          0.0,          depth,               0.0)
        let s = float4(0.0,          0.0,          -1.0 * near * depth, 1.0)
        
        return float4x4(p, q, r, s)
    }
    
    static func scale(by x: Float, y: Float, z: Float) -> float4x4 {
        let p = float4(x, 0.0, 0.0,   0.0)
        let q = float4(0.0, y, 0.0,   0.0)
        let r = float4(0.0, 0.0, z,   0.0)
        let s = float4(0.0, 0.0, 0.0, 1.0)
        
        return float4x4(p, q, r, s)
    }
    
    func scaled(by x: Float, y: Float, z: Float) -> float4x4 {
        let m = float4x4.scale(by: x, y: y, z: z)
        return m * self
    }
    
    static func translate(by x: Float, y: Float, z: Float) -> float4x4 {
        let p = float4(1.0, 0.0, 0.0, 0.0)
        let q = float4(0.0, 1.0, 0.0, 0.0)
        let r = float4(0.0, 0.0, 1.0, 0.0)
        let s = float4(x,   y,   z,   1.0)
        
        return float4x4(p, q, r, s)
    }
    
    func translated(by x: Float, y: Float, z: Float) -> float4x4 {
        let m = float4x4.translate(by: x, y: y, z: z)
        return m * self
    }
    
    func zRotated(by radians: Float) -> float4x4 {
        let m = float4x4.zRotation(by: radians)
        return m * self
    }
    
    static func zRotation(by radians: Float) -> float4x4 {
        let sine = sinf(radians)
        let cosine = cosf(radians)
        
        let p = float4(cosine, sine * -1.0, 0.0, 0.0)
        let q = float4(sine,   cosine,      0.0, 0.0)
        let r = float4(0.0,    0.0,         1.0, 0.0)
        let s = float4(0.0,    0.0,         0.0, 1.0)
        
        return float4x4(p, q, r, s)
    }
}
