//
//  Renderer.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/6/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import AppKit
import Metal
import MetalKit
import simd

protocol Renderer: MTKViewDelegate {
    var seedData: Data { get set }
    var canvasSize: float2 { get set }
    var sceneSize: float2 { get set }
    
    var backgroundColor: NSColor { get set }
    var iterations: Int { get set }
    var maxRotation: Float { get set }
    var scale: Float { get set }
    
    init(metalView: MTKView)
    
    func addFace(url: URL)
    func removeFace(at index: Int)
    
    func makeImageBuffer() -> MTLBuffer
}
