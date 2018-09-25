//
//  AtlasGenerator.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/16/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import Foundation
import Metal
import simd

class AtlasGenerator {
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    let mipmapped: Bool = false
    
    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
    }
    
    func generate(faces: [RendererFace], completionHandler: @escaping (_ texture: MTLTexture?, _ buffer: MTLBuffer?, _ error: Error?) -> Void) {
        // Determine the group size
        let floatCount = Float(faces.count)
        let root = Int(floatCount.squareRoot())
        let groupSize = (root * root == faces.count) ? root : root + 1
        
        // Split the faces in to groups
        let groups = faces.chunked(into: groupSize)
        
        // Determine the max width for the texture
        let maxWidth = groups.reduce(0.0) { (sum, slice) -> Float in
            let width = slice.reduce(0.0) { $0 + $1.textureSize.x }
            return Swift.max(sum, width)
        }
        
        // Determine the max height for each row
        let maxHeights = groups.map {
            return $0.reduce(0.0) { return Swift.max($0, $1.textureSize.y) }
        }
        
        // Determine the total max height
        let maxHeight = maxHeights.reduce(0.0) { $0 + $1 }
        
        // Generate the texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: Int(maxWidth), height: Int(maxHeight), mipmapped: mipmapped)
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            completionHandler(nil, nil, RenderingError.textureGeneration)
            return
        }
        
        // Clear the texture
        let bytes: [UInt8] = [UInt8](repeating: 0, count: Int(maxWidth * maxHeight) * 4)
        let region = MTLRegionMake2D(0, 0, Int(maxWidth), Int(maxHeight))
        texture.replace(region: region, mipmapLevel: 0, withBytes: bytes, bytesPerRow: Int(maxWidth) * 4)
        
        // Calculate pixel layouts for each face
        var currentX: Float = 0.0
        var currentY: Float = 0.0
        var pixelLayout: [float4] = []
        
        for (groupIdx, group) in groups.enumerated() {
            for face in group {
                let bounds = float4(x: currentX, y: currentY, z: currentX + face.textureSize.x, w: currentY + face.textureSize.y)
                pixelLayout.append(bounds)
                
                currentX += face.textureSize.x
            }
            
            currentY += maxHeights[groupIdx]
            currentX = 0.0
        }
        
        // Blit the individual textures in to the parent texture
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        let encoder = commandBuffer.makeBlitCommandEncoder()!
        
        for (faceIdx, face) in faces.enumerated() {
            let layout = pixelLayout[faceIdx]
            
            encoder.copy(
                from: face.texture!,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: Int(face.textureSize.x), height: Int(face.textureSize.y), depth: 1),
                to: texture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: Int(layout.x), y: Int(layout.y), z: 0)
            )
        }
        
        // Generate mipmaps
        if mipmapped {
            encoder.generateMipmaps(for: texture)
        }
        
        // Normalize the layout
        let divisor = float4(x: maxWidth, y: maxHeight, z: maxWidth, w: maxHeight)
        let normalizedLayout = pixelLayout.map { $0 / divisor }
        
        // Make the normalized output the texture coordinates
        var textureVertices: [Float] = []
        for layout in normalizedLayout {
            textureVertices.append(contentsOf: [layout.x, layout.y]) // Left / Top
            textureVertices.append(contentsOf: [layout.z, layout.y]) // Right / Top
            textureVertices.append(contentsOf: [layout.x, layout.w]) // Left / Bottom
            textureVertices.append(contentsOf: [layout.z, layout.w]) // Right / Bottom
        }
        
        let buffer = device.makeBuffer(bytes: textureVertices, length: MemoryLayout<Float>.size * textureVertices.count, options: [])!
        
        // Commit and wait for the blit
        encoder.endEncoding()
        
        commandBuffer.addCompletedHandler {_ in
            completionHandler(texture, buffer, nil)
        }
        
        commandBuffer.commit()
    }
}
