//
//  TextureLoader.swift
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/13/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

import AppKit
import Metal

class TextureLoader {
    
    public enum Error: Swift.Error {
        case cannotLoadFile
    }
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    private let queue: DispatchQueue
    
    let mipmapped: Bool = false
    
    init(device: MTLDevice) {
        self.device = device
        commandQueue = device.makeCommandQueue()!
        
        queue = DispatchQueue(label: "Texture Loader")
    }
    
    func load(url: URL, completionHandler: @escaping (_ texture: MTLTexture?, _ imageSize: CGSize, _ error: Swift.Error?) -> Void) {
        queue.async {
            guard let image = NSImage(contentsOf: url) else {
                completionHandler(nil, .zero, Error.cannotLoadFile)
                return
            }
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            
            let width = Int(image.size.width)
            let height = Int(image.size.height)
            let dimension = width > height ? width : height
            
            let bytesPerPixel = 4
            let bytesPerRow = dimension * bytesPerPixel
            
            let context = CGContext(
                data: nil,
                width: dimension,
                height: dimension,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            
            let bounds = CGRect(x: 0, y: 0, width: dimension, height: dimension)
            context.clear(bounds)
            
            let imageSource = CGImageSourceCreateWithData(image.tiffRepresentation! as CFData, nil)!
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
            
            let drawingBounds = CGRect(x: (dimension - width) / 2, y: (dimension - height) / 2, width: width, height: height)
            context.draw(cgImage, in: drawingBounds)
            
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: dimension, height: dimension, mipmapped: self.mipmapped)
            let texture = self.device.makeTexture(descriptor: textureDescriptor)!
            texture.label = url.lastPathComponent
            
            let pixelData = context.data!
            let region = MTLRegionMake2D(0, 0, dimension, dimension)
            texture.replace(region: region, mipmapLevel: 0, withBytes: pixelData, bytesPerRow: bytesPerRow)
            
            let commandBuffer = self.commandQueue.makeCommandBuffer()!
            
            if self.mipmapped {
                let blitCommandEncoder = commandBuffer.makeBlitCommandEncoder()!
                blitCommandEncoder.generateMipmaps(for: texture)
                blitCommandEncoder.endEncoding()
            }
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            completionHandler(texture, CGSize(width: width, height: height), nil)
        }
    }
}

