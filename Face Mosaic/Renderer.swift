//
//  Renderer.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/2/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import Cocoa
import Metal
import MetalKit

class Renderer: NSObject, MTKViewDelegate {
    fileprivate struct Face {
        fileprivate enum State {
            case new
            case loading
            case ready
            case error
        }
        
        let url: URL
        
        var state: Face.State
        var texture: MTLTexture?
        var vertices: [StandardVertex]
        var vertexBuffer: MTLBuffer?
    }
    
    fileprivate struct StandardVertex {
        let x, y: Float
        let s, t: Float
        
        var floatBuffer: [Float] {
            return [x, y, s, t]
        }
    }
    
    private let metalDevice: MTLDevice
    private let metalView: MTKView
    
    private var targetPipelineState: MTLRenderPipelineState
    private var targetTexture: MTLTexture? = nil
    private var targetVertexBuffer: MTLBuffer
    
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let textureLoader: MTKTextureLoader
    
    private var faces: [Face] = []
    
    var targetBackgroundColor: NSColor = .black {
        didSet {
            targetTextureNeedsRendered = true
        }
    }
    
    var targetTextureSize: CGSize = CGSize(width: 640.0, height: 480.0) {
        didSet {
            targetTextureNeedsRebuilt = true
            sceneNeedsLayedOut = true
        }
    }
    
    var sceneSize:  CGSize = CGSize.zero {
        didSet {
            sceneNeedsLayedOut = true
        }
    }
    
    var targetTextureNeedsRebuilt: Bool = true
    var targetTextureNeedsRendered: Bool = true
    var sceneNeedsLayedOut: Bool = true
    
    init(metalView: MTKView) {
        // Store the Metal core objects
        self.metalView = metalView
        metalDevice = metalView.device!
        
        // Load the shaders in to a pipeline
        let defaultLibrary = metalDevice.makeDefaultLibrary()!
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.label = "Main Pipeline"
        pipelineStateDescriptor.vertexFunction = defaultLibrary.makeFunction(name: "standard_vertex")
        pipelineStateDescriptor.fragmentFunction = defaultLibrary.makeFunction(name: "standard_fragment")
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        pipelineState = try! metalDevice.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        
        let targetPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        targetPipelineStateDescriptor.label = "Target Pipeline"
        targetPipelineStateDescriptor.vertexFunction = defaultLibrary.makeFunction(name: "standard_vertex")
        targetPipelineStateDescriptor.fragmentFunction = defaultLibrary.makeFunction(name: "target_fragment")
        targetPipelineStateDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        targetPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
        targetPipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = .add
        targetPipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = .add
        targetPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        targetPipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        targetPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        targetPipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        targetPipelineState = try! metalDevice.makeRenderPipelineState(descriptor: targetPipelineStateDescriptor)
        
        // Build the command queue
        commandQueue = metalDevice.makeCommandQueue()!
        commandQueue.label = "Main Command Queue"
        
        // Build a vertex buffer for the target
        let vertices = [
            StandardVertex(x: -1.0, y:  1.0, s: 0.0, t: 0.0),
            StandardVertex(x:  1.0, y:  1.0, s: 1.0, t: 0.0),
            StandardVertex(x: -1.0, y: -1.0, s: 0.0, t: 1.0),
            StandardVertex(x:  1.0, y: -1.0, s: 1.0, t: 1.0),
        ]
        
        let verticesData = vertices.reduce([]) { $0 + $1.floatBuffer }
        targetVertexBuffer = metalDevice.makeBuffer(bytes: verticesData, length: MemoryLayout<Float>.size * verticesData.count, options: [])!
        
        // Build a texture loader
        textureLoader = MTKTextureLoader(device: metalDevice)
    }
    
    // MARK: - Face Management
    
    func addFace(url: URL) {
        let face = Face(
            url: url,
            state: .new,
            texture: nil,
            vertices: [
                StandardVertex(x: -1.0, y:  1.0, s: 0.0, t: 0.0),
                StandardVertex(x:  1.0, y:  1.0, s: 1.0, t: 0.0),
                StandardVertex(x: -1.0, y: -1.0, s: 0.0, t: 1.0),
                StandardVertex(x:  1.0, y: -1.0, s: 1.0, t: 1.0)
            ],
            vertexBuffer: nil
        )
        
        faces.append(face)
    }
    
    func removeFace(at index: Int) {
        faces.remove(at: index)
        targetTextureNeedsRendered = true
    }
    
    // MARK: - Texture Target Rendering
    
    private func buildTargetTexture() {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type2D
        textureDescriptor.width = Int(targetTextureSize.width)
        textureDescriptor.height = Int(targetTextureSize.height)
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        
        targetTexture = metalDevice.makeTexture(descriptor: textureDescriptor)!
    }
    
    private func buildTargetTextureVertexBuffer() {
        let vertices = [
            StandardVertex(x: -1.0, y:  1.0, s: 0.0, t: 0.0),
            StandardVertex(x:  1.0, y:  1.0, s: 1.0, t: 0.0),
            StandardVertex(x: -1.0, y: -1.0, s: 0.0, t: 1.0),
            StandardVertex(x:  1.0, y: -1.0, s: 1.0, t: 1.0),
        ]
        
        let verticesData = vertices.reduce([]) { $0 + $1.floatBuffer }
        targetVertexBuffer = metalDevice.makeBuffer(bytes: verticesData, length: MemoryLayout<Float>.size * verticesData.count, options: [])!
    }
    
    private func renderFaces(commandBuffer: MTLCommandBuffer) {
        guard let target = targetTexture else {
            fatalError("Attempted to render faces without a target")
        }
        
        for face in faces {
            guard let texture = face.texture, let vertexBuffer = face.vertexBuffer else {
                continue
            }
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = target
            renderPassDescriptor.colorAttachments[0].loadAction = .load
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            encoder.setRenderPipelineState(targetPipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }
    }
    
    private func renderTargetTexture(commandBuffer: MTLCommandBuffer) {
        guard let texture = targetTexture else {
            fatalError("Attempted to render target texture without a texture")
        }
        
        // Build a render pass descriptor
        var red: CGFloat = 0.0, green: CGFloat = 0.0, blue: CGFloat = 0.0, alpha: CGFloat = 0.0
        targetBackgroundColor.usingColorSpace(.deviceRGB)!.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        // Clear the texture
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        encoder.endEncoding()
        
        // Render the faces
        renderFaces(commandBuffer: commandBuffer)
    }
    
    // MARK: - Protocols
    
    // MARK: <MTKViewDelegate>
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        sceneSize = size
    }
    
    func draw(in view: MTKView) {
        // Get the next drawable
        guard let drawable = view.currentDrawable else {
            return
        }
        
        // Rebuild the target texture if needed
        if (targetTextureNeedsRebuilt) {
            buildTargetTexture()
            targetTextureNeedsRendered = true
            targetTextureNeedsRebuilt = false
        }
        
        // Start loading images that may be missing
        for idx in 0 ..< faces.count {
            var face = faces[idx]
            
            if face.vertexBuffer == nil {
                let data: [Float] = face.vertices.reduce([]) { $0 + $1.floatBuffer }
                face.vertexBuffer = metalDevice.makeBuffer(bytes: data, length: MemoryLayout<Float>.size * data.count, options: [])
            }
            
            if face.texture == nil {
                face.state = .loading
                
                let options: [MTKTextureLoader.Option:Any] = [
                    .SRGB: false
                ]
                
                textureLoader.newTexture(URL: face.url, options: options) { (texture, error) in
                    guard self.faces.count > idx else {
                        print("Face may not longer exist")
                        return
                    }
                    
                    var face = self.faces[0]
                    
                    if let loadingError = error {
                        print("Failed to load the texture from \(face.url): \(loadingError)")
                        face.state = .error
                    } else if let newTexture = texture {
                        face.texture = newTexture
                        face.state = .ready
                        self.targetTextureNeedsRendered = true
                    } else {
                        print("Got neither an error nor a texture from the texture loader")
                        face.state = .error
                    }
                    
                    self.faces[idx] = face
                }
            }
            
            faces[idx] = face
        }
        
        // Build the command buffer
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        // Render the texture if needed
        if (targetTextureNeedsRendered) {
            renderTargetTexture(commandBuffer: commandBuffer)
            targetTextureNeedsRendered = false
        }
        
        // Build a render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        // Render the scene
        if let texture = targetTexture {
            let targetEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            targetEncoder.setRenderPipelineState(pipelineState)
            targetEncoder.setVertexBuffer(targetVertexBuffer, offset: 0, index: 0)
            targetEncoder.setFragmentTexture(texture, index: 0)
            targetEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            targetEncoder.endEncoding()
        } else {
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
