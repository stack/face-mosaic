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
    private struct CanvasUniform {
        let modelMatrix: float4x4
    }
    
    private struct CheckersVertexUniform {
        let screenSize: float2
        let dimensions: float2
    }
    
    private struct FaceUniform {
        let modelMatrix: float4x4
    }
    
    private struct FaceVertex {
        let position: float2
        let texturePosition: float2
    }
    
    // MARK: - Properties
    
    private let metalDevice: MTLDevice
    private let metalView: MTKView
    
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    private let atlasGenerator: AtlasGenerator
    private let textureLoader: TextureLoader
    
    private var faces: [RendererFace] = []
    private var facesTexture: MTLTexture?
    private var facesVertexBuffer: MTLBuffer?
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
        didSet {
            relayoutCanvasTexture = true
            rebuildCheckeredUniform = true
        }
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
    
    private var checkeredPipelineState: MTLRenderPipelineState
    private var checkeredUniformBuffer: MTLBuffer
    
    private var canvasIsDirty: Bool = true
    private var rebuildCanvasTexture: Bool = true
    private var recalculateScale: Bool = true
    private var relayoutCanvasTexture: Bool = true
    private var rebuildCheckeredUniform: Bool = true
    
    private let importQueue = DispatchQueue(label: "Renderer Import Queue")
    
    
    // MARK: - Initialization
    
    required init(metalView: MTKView) {
        // Store the core Metal data
        self.metalView = metalView
        metalDevice = metalView.device!
        
        // Build a texture loader for loading faces
        textureLoader = TextureLoader(device: metalDevice)
        
        // Build the atlas generator for compositing to one texture
        atlasGenerator = AtlasGenerator(device: metalDevice)
        
        // Build a command queue
        commandQueue = metalDevice.makeCommandQueue()!
        commandQueue.label = "Main Command Queue"
        
        // Get the default library for the shaders
        library = metalDevice.makeDefaultLibrary()!
        
        // Build the resources for the checkered background
        let checkeredPipelineDescriptor = MTLRenderPipelineDescriptor()
        checkeredPipelineDescriptor.label = "Checkered Pipeline"
        checkeredPipelineDescriptor.vertexFunction = library.makeFunction(name: "checkered_vertex")
        checkeredPipelineDescriptor.fragmentFunction = library.makeFunction(name: "checkered_fragment")
        checkeredPipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        
        checkeredPipelineState = try! metalDevice.makeRenderPipelineState(descriptor: checkeredPipelineDescriptor)
        
        checkeredUniformBuffer = metalDevice.makeBuffer(length: MemoryLayout<CheckersVertexUniform>.size, options: [])!
        
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
    
    func addFaces(faces: [Face], completionHandler: @escaping (Error?) -> Void) {
        let group = DispatchGroup()
        
        var lastError: Error? = nil
        var newFaces: [RendererFace] = []
        
        for face in faces {
            group.enter()
            
            textureLoader.load(url: face.url) { (texture, imageSize, error) in
                if let loaderError = error {
                    lastError = loaderError
                } else if let loaderTexture = texture {
                    print("Texture loaded \(face.uuid) for \(face.url)")
                    
                    loaderTexture.label = "Face \(face.uuid)"
                    
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
                    
                    var newFace = RendererFace(face: face)
                    
                    newFace.imageSize = float2(Float(imageSize.width), Float(imageSize.height))
                    newFace.textureSize = float2(Float(loaderTexture.width), Float(loaderTexture.height))
                    
                    newFace.pipelineState = try! self.metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
                    newFace.texture = loaderTexture
                    
                    newFaces.append(newFace)
                } else {
                    fatalError("Failed to get either an error or a texture, which should never happen")
                }
                
                group.leave()
            }
        }
        
        group.notify(queue: importQueue) {
            if let error = lastError {
                completionHandler(error)
                return
            }
            
            let finalFaces = self.faces + newFaces
            
            self.compositeFaces(faces: finalFaces) { (texture, buffer) in
                DispatchQueue.main.sync {
                    self.facesTexture = texture
                    self.facesVertexBuffer = buffer
                    
                    self.faces.append(contentsOf: newFaces)
                    
                    self.recalculateScale = true
                    self.canvasIsDirty = true
                }
                
                completionHandler(nil)
            }
        }
    }
    
    func compositeFaces(faces: [RendererFace], completionHandler: @escaping (_ texture: MTLTexture, _ buffer: MTLBuffer) -> Void) {
        atlasGenerator.generate(faces: faces) { (texture, buffer, error) in
            if let generatorError = error {
                print("Failed to generate the atlas: \(generatorError)")
                return
            }
            
            guard let newTexture = texture, let newBuffer = buffer else {
                print("Did not get an atlas texture of buffer")
                return
            }
            
            completionHandler(newTexture, newBuffer)
        }
    }
    
    func removeFaces(faces: [Face], completionHandler: @escaping (Error?) -> Void) {
        var finalFaces = self.faces
        for face in faces {
            finalFaces.removeAll { $0.face == face }
        }
        
        if finalFaces.isEmpty {
            DispatchQueue.main.sync {
                self.facesTexture = nil
                self.facesVertexBuffer = nil
                
                self.faces.removeAll()
                
                self.recalculateScale = true
                self.canvasIsDirty = true
            }
            
            completionHandler(nil)
        } else {
            self.compositeFaces(faces: finalFaces) { (texture, buffer) in
                DispatchQueue.main.sync {
                    self.facesTexture = texture
                    self.facesVertexBuffer = buffer
                    
                    self.faces = finalFaces
                    
                    self.recalculateScale = true
                    self.canvasIsDirty = true
                }
                
                completionHandler(nil)
            }
        }
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
            
            guard let texture = facesTexture, let buffer = facesVertexBuffer else {
                encoder.endEncoding()
                return
            }
            
            // Render each face
            for iteration in 0 ..< Int(iterations) {
                for (idx, face) in faces.enumerated() {
                    let offset = iteration * faces.count + idx
                    
                    encoder.setRenderPipelineState(face.pipelineState!)
                    encoder.setVertexBuffer(buffer, offset: idx * MemoryLayout<Float>.size * 8, index: 0)
                    encoder.setVertexBuffer(facesUniformBuffer, offset: memorySize * offset, index: 1)
                    encoder.setFragmentTexture(texture, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
            }
        }
    
        encoder.endEncoding()
    }
    
    
    // MARK: - Rendering Functions
    
    func draw(in view: MTKView) {
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
        
        // Rebuild the checked uniform if needed
        if rebuildCheckeredUniform {
            let scalingFactor: Float
            if let factor = view.window?.screen?.backingScaleFactor {
                scalingFactor = Float(factor)
            } else {
                scalingFactor = 1.0
            }
            
            var uniform = CheckersVertexUniform(
                screenSize: sceneSize,
                dimensions: float2(16.0 * scalingFactor, 16.0 * scalingFactor)
            )
            
            memcpy(checkeredUniformBuffer.contents(), &uniform, MemoryLayout<CheckersVertexUniform>.size)
            
            rebuildCheckeredUniform = false
        }
        
        // Render the canvas to the drawable
        if let renderPassDescriptor = metalView.currentRenderPassDescriptor {
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            
            encoder.setRenderPipelineState(checkeredPipelineState)
            encoder.setFragmentBuffer(checkeredUniformBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            encoder.setRenderPipelineState(canvasPipelineState)
            encoder.setVertexBuffer(canvasUniformBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(canvasTexture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            
            if let drawable = view.currentDrawable {
                commandBuffer.present(drawable)
            }
        }
        
        // Finalize the drawing
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        sceneSize = float2(Float(size.width), Float(size.height))
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
