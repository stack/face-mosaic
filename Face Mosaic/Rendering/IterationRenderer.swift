//
//  IterationRenderer.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/6/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import AppKit
import GameKit
import Metal
import MetalKit

class IterationRenderer: NSObject, Renderer {
    
    private struct Face: Equatable {
        enum State {
            case new
            case loading
            case ready
            case error
        }
        
        let uuid: UUID
        
        var state: Face.State = .new
        
        var imageSize: float2 = float2(0.0, 0.0)
        var textureSize: float2 = float2(0.0, 0.0)
        var scalingMatrix: float4x4 = float4x4.identity()
        
        var pipelineState: MTLRenderPipelineState? = nil
        var texture: MTLTexture? = nil
        
        init() {
            uuid = UUID()
        }
        
        static func ==(lhs: Face, rhs: Face) -> Bool {
            return lhs.uuid == rhs.uuid
        }
    }
    
    private struct FaceUniform {
        let modelMatrix: float4x4
    }
    
    private struct CanvasUniform {
        let modelMatrix: float4x4
    }
    
    // MARK: - Properties
    
    private let metalDevice: MTLDevice
    private let metalView: MTKView
    
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    private let textureLoader: TextureLoader
    
    private var faces: [Face] = []
    private var facesUniformBuffer: MTLBuffer
    
    var backgroundColor: NSColor = .black {
        didSet { canvasIsDirty = true }
    }
    
    var canvasSize: float2 = float2(640.0, 480.0) {
        didSet { rebuildCanvasTexture = true }
    }
    
    var iterations: Int = 1 {
        didSet {
            if iterations != oldValue {
                canvasIsDirty = true
            }
        }
    }
    
    var maxRotation: Float = 0.0 {
        didSet {
            if maxRotation != oldValue {
                canvasIsDirty = true
            }
        }
    }
    
    var scale: Float = 0.5 {
        didSet {
            if scale != oldValue {
                recalculateScale = true
                canvasIsDirty = true
            }
        }
    }
    
    var sceneSize: float2 = float2(200.0, 200.0) {
        didSet { relayoutCanvasTexture = true }
    }
    
    var seedData: Data = "Seed.data".data(using: .utf8)! {
        didSet {
            if seedData != oldValue {
                canvasIsDirty = true
            }
        }
    }
    
    private var canvasPipelineState: MTLRenderPipelineState
    private var canvasTexture: MTLTexture
    private var canvasUniformBuffer: MTLBuffer
    
    private var canvasIsDirty: Bool = true
    private var rebuildCanvasTexture: Bool = true
    private var recalculateScale: Bool = true
    private var relayoutCanvasTexture: Bool = true
    
    
    // MARK: - Initialization
    
    required init(metalView: MTKView) {
        // Store the core Metal data
        self.metalView = metalView
        metalDevice = metalView.device!
        
        // Build a texture loader for loading faces
        textureLoader = TextureLoader(device: metalDevice)
        
        // Build a command queue
        commandQueue = metalDevice.makeCommandQueue()!
        commandQueue.label = "Main Command Queue"
        
        // Get the default library for the shaders
        library = metalDevice.makeDefaultLibrary()!
        
        // Build the resources for rendering the canvas to the screen
        let canvasPipelineDescriptor = MTLRenderPipelineDescriptor()
        canvasPipelineDescriptor.label = "Canvas Pipeline"
        canvasPipelineDescriptor.vertexFunction = library.makeFunction(name: "canvas_vertex")
        canvasPipelineDescriptor.fragmentFunction = library.makeFunction(name: "canvas_fragment")
        canvasPipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        canvasPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        canvasPipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        canvasPipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        canvasPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        canvasPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        canvasPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        canvasPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        canvasPipelineState = try! metalDevice.makeRenderPipelineState(descriptor: canvasPipelineDescriptor)
        
        let canvasDescriptor = IterationRenderer.canvasTextureDescriptor(format: metalView.colorPixelFormat, size: canvasSize)
        canvasTexture = metalDevice.makeTexture(descriptor: canvasDescriptor)!
        
        canvasUniformBuffer = metalDevice.makeBuffer(length: MemoryLayout<CanvasUniform>.size, options: [])!
        
        // Build a dummy buffer as a place holder for the face uniform buffer
        facesUniformBuffer = metalDevice.makeBuffer(length: 1, options: [])!
    }
    
    
    // MARK: - Face Management
    
    func addFace(url: URL) {
        textureLoader.load(url: url) { (texture, imageSize, error) in
            var face = Face()
            
            if let newTexture = texture {
                print("Texture loaded \(face.uuid) for \(url)")
                
                newTexture.label = "Face \(face.uuid)"
                
                // Build the resources for rendering faces to the canvas
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.label = "Face \(face.uuid) Pipeline"
                pipelineDescriptor.vertexFunction = self.library.makeFunction(name: "face_instance_vertex")
                pipelineDescriptor.fragmentFunction = self.library.makeFunction(name: "face_instance_fragment")
                pipelineDescriptor.colorAttachments[0].pixelFormat = self.canvasTexture.pixelFormat
                pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
                pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
                pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
                pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
                pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                
                face.imageSize = float2(Float(imageSize.width), Float(imageSize.height))
                face.textureSize = float2(Float(newTexture.width), Float(newTexture.height))
                
                face.pipelineState = try! self.metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
                face.texture = newTexture
                
                face.state = .ready
            } else if let _ = error {
                print("Failed to load the texture for \(url)")
                face.state = .error
            } else {
                print("Got neither a texture nor an error")
                face.state = .error
            }
            
            DispatchQueue.main.sync {
                self.faces.append(face)
                
                self.recalculateScale = true
                self.canvasIsDirty = true
            }
        }
    }
    
    func removeFace(at index: Int) {
        faces.remove(at: index)
        self.canvasIsDirty = true
    }
    
    // MARK: - Canvas Management
    
    private static func canvasTextureDescriptor(format: MTLPixelFormat, size: float2) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.width = Int(size.x)
        descriptor.height = Int(size.y)
        descriptor.pixelFormat = format
        descriptor.usage = [.renderTarget, .shaderRead]
        
        return descriptor
    }
    
    private static func canvasVertices(canvasSize: float2, sceneSize: float2) -> CanvasUniform {
        let delta = sceneSize / canvasSize
        let factor = delta.min() ?? 1.0
        
        let scaledSize = canvasSize * factor
        let scaledOffset = scaledSize / sceneSize
        
        return CanvasUniform(modelMatrix: float4x4.scale(by: scaledOffset.x, y: scaledOffset.y, z: 1.0))
    }
    
    private func calculateScalingMatrices() {
        for (idx, face) in faces.enumerated() {
            if face.state != .ready {
                continue
            }
            
            var newFace = face
            
            let delta = canvasSize / face.imageSize
            let factor = delta.min()!
            
            let scaledSize = face.textureSize * factor
            let normalizedOffset = (scaledSize / canvasSize)
            
            newFace.scalingMatrix = float4x4.scale(by: normalizedOffset.x, y: normalizedOffset.y, z: 1.0)
            
            faces[idx] = newFace
        }
    }
    
    private func renderFacesToCanvas(commandBuffer: MTLCommandBuffer) {
        // Extract the background color
        var red: CGFloat = 0.0, green: CGFloat = 0.0, blue: CGFloat = 0.0, alpha: CGFloat = 0.0
        backgroundColor.usingColorSpace(.deviceRGB)!.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = canvasTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        encoder.setViewport(MTLViewport(originX: 0.0, originY: 0.0, width: Double(canvasSize.x), height: Double(canvasSize.y), znear: 0.0, zfar: 1.0))
        
        // Fill in any missing scaling matrices
        if recalculateScale {
            calculateScalingMatrices()
            recalculateScale = false
        }
        
        // Build a reproducable random number generate for our calculations
        let rng = GKARC4RandomSource(seed: seedData)
        
        // Build all of the uniforms for each iteration of each face
        if faces.count > 0 && iterations > 0 {
            let memorySize = MemoryLayout<FaceUniform>.size
            let bufferSize = memorySize * iterations * faces.count
            
            if facesUniformBuffer.length != bufferSize {
                facesUniformBuffer = metalDevice.makeBuffer(length: bufferSize, options: [])!
            }
            
            var contents = facesUniformBuffer.contents()
            
            for _ in 0 ..< iterations {
                for face in faces {
                    var matrix = float4x4.identity()
                    
                    matrix = matrix.scaled(by: scale, y: scale, z: 1.0)
                    
                    let rotation = rng.nextUniform() * maxRotation
                    let rotationMultiplier: Float = rng.nextInt(upperBound: 2) == 0 ? -1.0 : 1.0
                    matrix = matrix.zRotated(by: .pi * 2.0 * (rotation * rotationMultiplier))
                    
                    matrix = face.scalingMatrix * matrix
                    
                    let translateX = rng.nextUniform() * 2.0 - 1.0
                    let translateY = rng.nextUniform() * 2.0 - 1.0
                    matrix = matrix.translated(by: translateX, y: translateY, z: 0.0)
                    
                    var uniform = FaceUniform(
                        modelMatrix: matrix
                    )
                    
                    memcpy(contents, &uniform, memorySize)
                    contents += memorySize
                }
            }
            
            // Render each face
            for iteration in 0 ..< Int(iterations) {
                for (idx, face) in faces.enumerated() {
                    guard face.state == .ready else {
                        continue
                    }
                    
                    guard let texture = face.texture else {
                        continue
                    }
                    
                    let offset = iteration * faces.count + idx
                    
                    encoder.setRenderPipelineState(face.pipelineState!)
                    encoder.setVertexBuffer(facesUniformBuffer, offset: memorySize * offset, index: 0)
                    encoder.setFragmentTexture(texture, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
            }
        }
    
        encoder.endEncoding()
    }
    
    
    // MARK: - Rendering Functions
    
    func draw(in view: MTKView) {
        // Ensure we have somewhere to draw to
        guard let drawable = view.currentDrawable else {
            return
        }
        
        // Rebuild the canvas if needed
        if rebuildCanvasTexture {
            let descriptor = IterationRenderer.canvasTextureDescriptor(format: metalView.colorPixelFormat, size: canvasSize)
            canvasTexture = metalDevice.makeTexture(descriptor: descriptor)!
            
            relayoutCanvasTexture = true
            recalculateScale = true
            canvasIsDirty = true
            
            rebuildCanvasTexture = false
        }
        
        // Re-layout the canvas if needed
        if relayoutCanvasTexture {
            var uniform = IterationRenderer.canvasVertices(canvasSize: canvasSize, sceneSize: sceneSize)
            memcpy(canvasUniformBuffer.contents(), &uniform, MemoryLayout<CanvasUniform>.size)
            
            relayoutCanvasTexture = false
        }
        
        // Build a new command buffer
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        // Render the canvas if needed
        if canvasIsDirty {
            renderFacesToCanvas(commandBuffer: commandBuffer)
            canvasIsDirty = false
        }
        
        // Render the canvas to the drawable
        renderCanvas(to: drawable.texture, commandBuffer: commandBuffer)
        
        // Finalize the drawing
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        sceneSize = float2(Float(size.width), Float(size.height))
    }
    
    private func renderCanvas(to texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        encoder.setRenderPipelineState(canvasPipelineState)
        encoder.setVertexBuffer(canvasUniformBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(canvasTexture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
    
    // MARK: - Export Functions
    
    func makeImageBuffer() -> MTLBuffer {
        let imagesBytesPerRow = Int(canvasSize.x) * 4
        let imageByteCount = imagesBytesPerRow * Int(canvasSize.y)
        let imageBuffer = metalDevice.makeBuffer(length: imageByteCount, options: [])!
        
        let commandQueue = metalDevice.makeCommandQueue()!
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeBlitCommandEncoder()!
        
        encoder.copy(
            from: canvasTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: Int(canvasSize.x), height: Int(canvasSize.y), depth: 1),
            to: imageBuffer,
            destinationOffset: 0,
            destinationBytesPerRow: imagesBytesPerRow,
            destinationBytesPerImage: 0
        )
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return imageBuffer
    }
}
