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

protocol Renderer: MTKViewDelegate {
    var seedData: Data { get set }
    var canvasSize: CGSize { get set }
    var sceneSize: CGSize { get set }
    
    var backgroundColor: NSColor { get set }
    var iterations: UInt { get set }
    var maxRotation: Float { get set }
    var scale: Float { get set }
    
    func addFace(url: URL)
    func removeFace(at index: Int)
}
