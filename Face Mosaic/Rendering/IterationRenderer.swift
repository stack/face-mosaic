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
    
    // MARK: - Internal Structures
    
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
    private var facesUniformBuffer: MTLBuffer?
    
    private var canvasPipelineState: MTLRenderPipelineState
    private var canvasTexture: MTLTexture
    private var canvasUniformBuffer: MTLBuffer
    
    private var checkeredPipelineState: MTLRenderPipelineState
    private var checkeredUniformBuffer: MTLBuffer
    
    private let importQueue = DispatchQueue(label: "Renderer Import Queue")
    
    private var rebuildCanvasTexture: Bool = true
    private var rebuildCanvasUniformBuffer: Bool = true
    private var rebuildCheckedUniformBuffer: Bool = true
    private var rebuildFaceModelMatrices: Bool = true
    private var rebuildFaceScalingMatrices: Bool = true
    
    private var redrawFaces: Bool = true
    
    var backgroundColor: NSColor = .black {
        didSet {
            redrawFaces = true
        }
    }
    
    var canvasSize: float2 = float2(640.0, 480.0) {
        didSet {
            rebuildCanvasTexture = true
            rebuildCanvasUniformBuffer = true
            rebuildFaceScalingMatrices = true
            rebuildFaceModelMatrices = true
            redrawFaces = true
        }
    }
    
    var iterations: Int = 1 {
        didSet {
            if iterations != oldValue {
                rebuildFaceModelMatrices = true
                redrawFaces = true
            }
        }
    }
    
    var maxRotation: Float = 0.0 {
        didSet {
            if maxRotation != oldValue {
                rebuildFaceModelMatrices = true
                redrawFaces = true
            }
        }
    }
    
    var scale: Float = 0.5 {
        didSet {
            if scale != oldValue {
                rebuildFaceModelMatrices = true
                redrawFaces = true
            }
        }
    }
    
    var sceneSize: float2 = float2(200.0, 200.0) {
        didSet {
            rebuildCheckedUniformBuffer = true
            rebuildCanvasUniformBuffer = true
        }
    }
    
    var seedData: Data = "Seed.data".data(using: .utf8)! {
        didSet {
            if seedData != oldValue {
                rebuildFaceModelMatrices = true
                redrawFaces = true
            }
        }
    }
    
    
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
        
        let canvasDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: metalView.colorPixelFormat, width: Int(canvasSize.x), height: Int(canvasSize.y), mipmapped: false)
        canvasDescriptor.usage = [.renderTarget, .shaderRead]
        canvasTexture = metalDevice.makeTexture(descriptor: canvasDescriptor)!
        
        canvasUniformBuffer = metalDevice.makeBuffer(length: MemoryLayout<CanvasUniform>.size, options: [])!
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
                    
                    self.rebuildFaceScalingMatrices = true
                    self.rebuildFaceModelMatrices = true
                    self.redrawFaces = true
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
                
                self.redrawFaces = true
            }
            
            completionHandler(nil)
        } else {
            self.compositeFaces(faces: finalFaces) { (texture, buffer) in
                DispatchQueue.main.sync {
                    self.facesTexture = texture
                    self.facesVertexBuffer = buffer
                    
                    self.faces = finalFaces
                    
                    self.rebuildFaceScalingMatrices = true
                    self.rebuildFaceModelMatrices = true
                    self.redrawFaces = true
                }
                
                completionHandler(nil)
            }
        }
    }
    
    // MARK: - Rendering Functions
    
    func draw(in view: MTKView) {
        // Prepare all of the assets
        prepareBackground()
        prepareCanvas()
        prepareFaces()
        
        // Start the drawing
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Could not generate a command buffer")
            return
        }
        
        guard let renderPassDescriptor = metalView.currentRenderPassDescriptor else {
            print("No render pass descriptor could be retrieved")
            return
        }
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("Could not make a render commadn encoder")
            return
        }
        
        // Draw all of the parts
        drawBackground(encoder: encoder)
        drawFaces()
        drawCanvas(encoder: encoder)
        
        
        // Finalize the drawing
        encoder.endEncoding()
        
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        
        commandBuffer.commit()
    }
    
    private func drawBackground(encoder: MTLRenderCommandEncoder) {
        // Render a empty set of vertices to draw the triangles
        encoder.setRenderPipelineState(checkeredPipelineState)
        encoder.setFragmentBuffer(checkeredUniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    
    private func drawCanvas(encoder: MTLRenderCommandEncoder) {
        // Render the canvas to the background
        encoder.setRenderPipelineState(canvasPipelineState)
        encoder.setVertexBuffer(canvasUniformBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(canvasTexture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    
    private func drawFaces() {
        guard redrawFaces else {
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Failed to create faces command buffer")
            return
        }
        
        // Extract the background color
        var red: CGFloat = 0.0, green: CGFloat = 0.0, blue: CGFloat = 0.0, alpha: CGFloat = 0.0
        backgroundColor.usingColorSpace(.deviceRGB)!.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // Build a new render pass descriptor
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
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("Failed to build faces command encoder")
            return
        }
        
        encoder.setViewport(MTLViewport(originX: 0.0, originY: 0.0, width: Double(canvasSize.x), height: Double(canvasSize.y), znear: 0.0, zfar: 1.0))
        
        // Draw faces
        if let texture = facesTexture, let buffer = facesVertexBuffer, let uniformBuffer = facesUniformBuffer {
            for iteration in 0 ..< Int(iterations) {
                for (idx, face) in faces.enumerated() {
                    let offset = iteration * faces.count + idx
                    
                    encoder.setRenderPipelineState(face.pipelineState!)
                    encoder.setVertexBuffer(buffer, offset: idx * MemoryLayout<Float>.size * 8, index: 0)
                    encoder.setVertexBuffer(uniformBuffer, offset: MemoryLayout<FaceUniform>.size * offset, index: 1)
                    encoder.setFragmentTexture(texture, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
            }
        }
        
        // Finalize
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        redrawFaces = false
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        sceneSize = float2(Float(size.width), Float(size.height))
    }
    
    private func prepareBackground() {
        // Fill in the uniform buffer
        if rebuildCheckedUniformBuffer {
            let scalingFactor: Float
            if let factor = metalView.window?.screen?.backingScaleFactor {
                scalingFactor = Float(factor)
            } else {
                scalingFactor = 1.0
            }
        
            var uniform = CheckersVertexUniform(
                screenSize: sceneSize,
                dimensions: float2(16.0 * scalingFactor, 16.0 * scalingFactor)
            )
        
            memcpy(checkeredUniformBuffer.contents(), &uniform, MemoryLayout<CheckersVertexUniform>.size)
            
            rebuildCheckedUniformBuffer = false
        }
    }
    
    private func prepareCanvas() {
        // Make the texture
        if rebuildCanvasTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: Int(canvasSize.x), height: Int(canvasSize.y), mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
        
            guard let texture = metalDevice.makeTexture(descriptor: descriptor) else {
                print("Failed to make the canvas texture")
                return
            }
            
            canvasTexture = texture
            
            rebuildCanvasTexture = false
        }
        
        // Calculate the vertices for the canvas
        if rebuildCanvasUniformBuffer {
            let delta = sceneSize / canvasSize
            let factor = delta.min() ?? 1.0
            
            let scaledSize = canvasSize * factor
            let scaledOffset = scaledSize / sceneSize
            
            var uniform =  CanvasUniform(modelMatrix: float4x4.scale(by: scaledOffset.x, y: scaledOffset.y, z: 1.0))
            memcpy(canvasUniformBuffer.contents(), &uniform, MemoryLayout<CanvasUniform>.size)
        
            rebuildCanvasUniformBuffer = false
        }
    }
    
    func prepareFaces() {
        // Recaulcate scaling matrices
        if rebuildFaceScalingMatrices {
            for (idx, face) in faces.enumerated() {
                var newFace = face
                
                let delta = canvasSize / face.imageSize
                let factor = delta.min()!
                
                let scaledSize = face.textureSize * factor
                let normalizedOffset = (scaledSize / canvasSize)
                
                newFace.scalingMatrix = float4x4.scale(by: normalizedOffset.x, y: normalizedOffset.y, z: 1.0)
                
                faces[idx] = newFace
            }
            
            rebuildFaceScalingMatrices = false
        }
        
        // Calculate model matrices
        if rebuildFaceModelMatrices {
            if faces.count > 0 && iterations > 0 {
                let memorySize = MemoryLayout<FaceUniform>.size
                let bufferSize = memorySize * iterations * faces.count
                
                let uniformBuffer: MTLBuffer
                if let buffer = facesUniformBuffer {
                    if buffer.length != bufferSize {
                        uniformBuffer = metalDevice.makeBuffer(length: bufferSize, options: [])!
                        facesUniformBuffer = uniformBuffer
                    } else {
                        uniformBuffer = buffer
                    }
                } else {
                    uniformBuffer = metalDevice.makeBuffer(length: bufferSize, options: [])!
                    facesUniformBuffer = uniformBuffer
                }

                var contents = uniformBuffer.contents()
                
                // Build a reproducable random number generate for our calculations
                let rng = GKARC4RandomSource(seed: seedData)
                
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
            }
            
            rebuildFaceModelMatrices = false
        }
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
