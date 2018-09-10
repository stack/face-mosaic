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
        
        var width: Float = 0.0
        var height: Float = 0.0
        
        var pipelineState: MTLRenderPipelineState? = nil
        var texture: MTLTexture? = nil
        var vertexBuffer: MTLBuffer? = nil
        
        init() {
            uuid = UUID()
        }
        
        static func ==(lhs: Face, rhs: Face) -> Bool {
            return lhs.uuid == rhs.uuid
        }
    }
    
    private struct FaceVertex {
        let position: float2
    }
    
    private struct FaceUniform {
        let translationMatrix: float4x4
        let rotationMatrix: float4x4
    }
    
    private struct CanvasVertex {
        let position: float2
    }
    
    // MARK: - Properties
    
    private let metalDevice: MTLDevice
    private let metalView: MTKView
    
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private let textureLoader: MTKTextureLoader
    
    private var faces: [Face] = []
    private var facesUniformBuffer: MTLBuffer
    
    var backgroundColor: NSColor = .black {
        didSet { canvasIsDirty = true }
    }
    
    var canvasSize: CGSize = CGSize(width: 640.0, height: 480.0) {
        didSet { rebuildCanvasTexture = true }
    }
    
    var iterations: UInt = 1 {
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
    
    var sceneSize: CGSize = CGSize(width: 200.0, height: 200.0) {
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
    private var canvasVertexBuffer: MTLBuffer
    
    private var canvasIsDirty: Bool = true
    private var rebuildCanvasTexture: Bool = true
    private var recalculateScale: Bool = true
    private var relayoutCanvasTexture: Bool = true
    
    private let importQueue = DispatchQueue(label: "Renderer Import")
    
    
    // MARK: - Initialization
    
    required init(metalView: MTKView) {
        // Store the core Metal data
        self.metalView = metalView
        metalDevice = metalView.device!
        
        // Build a texture loader for loading faces
        textureLoader = MTKTextureLoader(device: metalDevice)
        
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
        
        canvasVertexBuffer = metalDevice.makeBuffer(length: MemoryLayout<CanvasVertex>.size * 4, options: [])!
        
        // Build a dummy buffer as a place holder for the face uniform buffer
        facesUniformBuffer = metalDevice.makeBuffer(length: 1, options: [])!
    }
    
    
    // MARK: - Face Management
    
    func addFace(data: [UInt8], width: Int, height: Int, completionHandler: @escaping () -> Void) {
        importQueue.async {
            var face = Face()
        
            print("Loading texture from data as \(face.uuid)")
        
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: true)
            let texture = self.metalDevice.makeTexture(descriptor: descriptor)!
        
            let region = MTLRegionMake2D(0, 0, width, height)
            texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: width * 4)
        
            // Build the resources for rendering faces to the canvas
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.label = "Face \(face.uuid) Pipeline"
            pipelineDescriptor.vertexFunction = self.library.makeFunction(name: "face_instance_vertex")
            pipelineDescriptor.fragmentFunction = self.library.makeFunction(name: "face_instance_fragment")
            pipelineDescriptor.colorAttachments[0].pixelFormat = texture.pixelFormat
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            var vertices: [FaceVertex] = [
                FaceVertex(position: float2(-1.0,  1.0)),
                FaceVertex(position: float2( 1.0,  1.0)),
                FaceVertex(position: float2(-1.0, -1.0)),
                FaceVertex(position: float2( 1.0, -1.0))
            ]
        
            face.pipelineState = try! self.metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
            face.texture = texture
            face.vertexBuffer = self.metalDevice.makeBuffer(bytes: &vertices, length: MemoryLayout<FaceVertex>.size * vertices.count, options: [])
            
            face.state = .ready
        
            self.faces.append(face)
        
            self.recalculateScale = true
            self.canvasIsDirty = true
            
            completionHandler()
        }
    }
    
    func addFace(url: URL) {
        // Build the initial face and inject it
        let face = Face()
        faces.append(face)
        
        print("Loading texture for \(url) as \(face.uuid)")
        
        // Start the loading process
        let options: [MTKTextureLoader.Option:Any] = [
            .generateMipmaps : true,
            .SRGB: true
        ]
        textureLoader.newTexture(URL: url, options: options) { (texture, error) in
            // Find the matching face
            guard let index = self.faces.index(of: face) else {
                print("Could not find a matching face after a texture load")
                return
            }
            
            var updatedFace = self.faces[index]
            
            // Handle the error or texture
            if let loadError = error {
                print("Error loading texture \(updatedFace.uuid): \(loadError)")
                updatedFace.state = .error
            } else if let newTexture = texture {
                print("Texture loaded for \(updatedFace.uuid)")
                print("Texture: \(newTexture)")
                
                // Build the resources for rendering faces to the canvas
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.label = "Face \(updatedFace.uuid) Pipeline"
                pipelineDescriptor.vertexFunction = self.library.makeFunction(name: "face_instance_vertex")
                pipelineDescriptor.fragmentFunction = self.library.makeFunction(name: "face_instance_fragment")
                pipelineDescriptor.colorAttachments[0].pixelFormat = newTexture.pixelFormat
                pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
                pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
                pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
                pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
                pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                
                var vertices: [FaceVertex] = [
                    FaceVertex(position: float2(-1.0,  1.0)),
                    FaceVertex(position: float2( 1.0,  1.0)),
                    FaceVertex(position: float2(-1.0, -1.0)),
                    FaceVertex(position: float2( 1.0, -1.0))
                ]
                
                updatedFace.pipelineState = try! self.metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
                updatedFace.texture = newTexture
                updatedFace.vertexBuffer = self.metalDevice.makeBuffer(bytes: &vertices, length: MemoryLayout<FaceVertex>.size * vertices.count, options: [])
                
                updatedFace.state = .ready
            } else {
                print("Texture loader returned neither a texture not an error")
                updatedFace.state = .error
            }
            
            self.faces[index] = updatedFace
            
            self.recalculateScale = true
            self.canvasIsDirty = true
        }
    }
    
    func removeFace(at index: Int) {
        faces.remove(at: index)
        self.canvasIsDirty = true
    }
    
    // MARK: - Canvas Management
    
    private static func canvasTextureDescriptor(format: MTLPixelFormat, size: CGSize) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.width = Int(size.width)
        descriptor.height = Int(size.height)
        descriptor.pixelFormat = format
        descriptor.usage = [.renderTarget, .shaderRead]
        
        return descriptor
    }
    
    private static func canvasVertices(canvasSize: CGSize, sceneSize: CGSize) -> [CanvasVertex] {
        let scene = float2(Float(sceneSize.width), Float(sceneSize.height))
        let canvas = float2(Float(canvasSize.width), Float(canvasSize.height))
        
        let delta = scene / canvas
        let scaleFactor = delta.min()!
        
        let scaledSize = canvas * scaleFactor
        let scaledOffset = (scene - scaledSize) / 2.0
        
        let leftBottomOffset = (scaledOffset / scene) * 2.0 - float2(1.0)
        let rightTopOffset = ((scene - scaledOffset) / scene) * 2.0 - float2(1.0)
        
        return [
            CanvasVertex(position: float2(leftBottomOffset[0], rightTopOffset[1])),
            CanvasVertex(position: float2(rightTopOffset[0],   rightTopOffset[1])),
            CanvasVertex(position: float2(leftBottomOffset[0], leftBottomOffset[1])),
            CanvasVertex(position: float2(rightTopOffset[0],   leftBottomOffset[1]))
        ]
    }
    
    private func calculateScalingMatrices() {
        for (idx, face) in faces.enumerated() {
            if face.state != .ready {
                continue
            }
            
            let newFace = face
            let texture = newFace.texture!
            
            let sceneSize = float2(Float(canvasSize.width), Float(canvasSize.height))
            let textureSize = float2(Float(texture.width), Float(texture.height))
            let availableSize = sceneSize * scale
            
            let delta = availableSize / textureSize
            let factor = delta.min()!
            
            let scaledSize = textureSize * factor
            let normalizedOffset = (scaledSize / sceneSize)
            
            var vertices: [FaceVertex] = [
                FaceVertex(position: float2(normalizedOffset[0] * -1.0, normalizedOffset[1])),
                FaceVertex(position: float2(normalizedOffset[0],        normalizedOffset[1])),
                FaceVertex(position: float2(normalizedOffset[0] * -1.0, normalizedOffset[1] * -1.0)),
                FaceVertex(position: float2(normalizedOffset[0],        normalizedOffset[1] * -1.0)),
            ]
            
            let buffer = newFace.vertexBuffer!
            memcpy(buffer.contents(), &vertices, MemoryLayout<FaceVertex>.size * vertices.count)
            
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
            let bufferSize = memorySize * Int(iterations) * faces.count
            
            if facesUniformBuffer.length != bufferSize {
                facesUniformBuffer = metalDevice.makeBuffer(length: bufferSize, options: [])!
            }
            
            var contents = facesUniformBuffer.contents()
            
            for _ in 0 ..< iterations {
                for _ in faces {
                    let translateX = rng.nextUniform() * 2.0 - 1.0
                    let translateY = rng.nextUniform() * 2.0 - 1.0
                    let translationMatrix = float4x4(translationBy: float3(translateX, translateY, 0))
                    
                    let rotation = rng.nextUniform() * maxRotation
                    let rotationMultiplier: Float = rng.nextInt(upperBound: 2) == 0 ? -1.0 : 1.0
                    let rotationMatrix = float4x4(rotationAbout: float3(0.0, 0.0, 1.0), by: Float.pi * 2.0 * (rotation * rotationMultiplier))
                    
                    var uniform = FaceUniform(
                        translationMatrix: translationMatrix,
                        rotationMatrix: rotationMatrix
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
                    
                    let offset = iteration * faces.count + idx
                    
                    encoder.setRenderPipelineState(face.pipelineState!)
                    encoder.setVertexBuffer(face.vertexBuffer!, offset: 0, index: 0)
                    encoder.setVertexBuffer(facesUniformBuffer, offset: memorySize * offset, index: 1)
                    encoder.setFragmentTexture(face.texture!, index: 0)
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
            let vertices = IterationRenderer.canvasVertices(canvasSize: canvasSize, sceneSize: sceneSize)
            memcpy(canvasVertexBuffer.contents(), vertices, MemoryLayout<CanvasVertex>.size * vertices.count)
            
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
        sceneSize = size
    }
    
    private func renderCanvas(to texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        encoder.setRenderPipelineState(canvasPipelineState)
        encoder.setVertexBuffer(canvasVertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(canvasTexture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
    
    // MARK: - Export Functions
    
    func makeImageBuffer() -> MTLBuffer {
        let imagesBytesPerRow = Int(canvasSize.width) * 4
        let imageByteCount = imagesBytesPerRow * Int(canvasSize.height)
        let imageBuffer = metalDevice.makeBuffer(length: imageByteCount, options: [])!
        
        let commandQueue = metalDevice.makeCommandQueue()!
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeBlitCommandEncoder()!
        
        encoder.copy(
            from: canvasTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: Int(canvasSize.width), height: Int(canvasSize.height), depth: 1),
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
