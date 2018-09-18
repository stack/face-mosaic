//
//  RendererFace.swift
//  RendererFace Mosaic
//
//  Created by Stephen H. Gerstacker on 9/16/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import Foundation
import Metal
import simd

struct RendererFace: Equatable {
    let face: Face
    
    var imageSize: float2 = float2(0.0, 0.0)
    var textureSize: float2 = float2(0.0, 0.0)
    var scalingMatrix: float4x4 = float4x4.identity()
    
    var pipelineState: MTLRenderPipelineState? = nil
    var texture: MTLTexture? = nil
    
    init(face: Face) {
        self.face = face
    }
    
    static func ==(lhs: RendererFace, rhs: RendererFace) -> Bool {
        return lhs.face == rhs.face
    }
}
