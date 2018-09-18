//
//  IterationShaders.metal
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/7/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct CanvasVertexUniform {
    float4x4 modelMatrix;
};

struct CanvasVertexOut {
    float4 position [[position]];
    float2 texturePosition;
};

vertex CanvasVertexOut canvas_vertex(const device CanvasVertexUniform& uniform [[ buffer(0) ]],
                                     ushort vid [[ vertex_id ]])
{
    constexpr float2 positions[4] = {
        float2(-1.0,  1.0),
        float2( 1.0,  1.0),
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
    };
    
    constexpr float2 texturePositions[4] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 1.0)
    };
    
    CanvasVertexOut vertexOut;
    vertexOut.position = uniform.modelMatrix * float4(positions[vid], 0.0, 1.0);
    vertexOut.texturePosition = texturePositions[vid];
    
    return vertexOut;
}

fragment half4 canvas_fragment(CanvasVertexOut canvasVertex [[ stage_in ]],
                                texture2d<float, access::sample> texture [[texture(0)]])
{
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);
    
    return (half4)texture.sample(textureSampler, canvasVertex.texturePosition);
}

struct CheckeredVertexUniform {
    float2 screenSize;
    float2 dimensions;
};

struct CheckeredVertexOut {
    float4 position [[ position ]];
    float2 spacePosition;
};

vertex CheckeredVertexOut checkered_vertex(unsigned int vid [[ vertex_id ]])
{
    constexpr float2 spacePositions[4] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 1.0)
    };
    
    constexpr float2 positions[4] = {
        float2(-1.0, 1.0),
        float2( 1.0, 1.0),
        float2(-1.0, -1.0),
        float2( 1.0, -1.0)
    };
    
    CheckeredVertexOut vertexOut;
    vertexOut.position = float4(positions[vid], 0.0, 1.0);
    vertexOut.spacePosition = spacePositions[vid];
    
    return vertexOut;
}

fragment half4 checkered_fragment(CheckeredVertexOut vertexData [[ stage_in ]],
                                 const device CheckeredVertexUniform& uniform)
{
    float2 pixelPosition = uniform.screenSize * vertexData.spacePosition;
    
    float2 blockPosition = floor(pixelPosition) / uniform.dimensions;
    int2 clippedBlockPosition = (int2)blockPosition;
    
    bool xEven = clippedBlockPosition.x % 2 == 0;
    bool yEven = clippedBlockPosition.y % 2 == 0;
    
    constexpr half4 gray = half4(0.84, 0.84, 0.84, 1.0);
    constexpr half4 white = half4(1.0, 1.0, 1.0, 1.0);
    
    if (xEven) {
        if (yEven) {
            return white;
        } else {
            return gray;
        }
    } else {
        if (yEven) {
            return gray;
        } else {
            return white;
        }
    }
}

struct FaceVertexIn {
    packed_float2 texturePosition;
};

struct FaceVertexOut {
    float4 position [[position]];
    float2 texturePosition;
};

struct FaceUniform {
    float4x4 model;
};

vertex FaceVertexOut face_instance_vertex(const device FaceVertexIn* vertices [[ buffer(0) ]],
                                          const device FaceUniform& uniform [[ buffer(1) ]],
                                          ushort vid [[ vertex_id ]])
{
    constexpr float2 positions[4] = {
        float2(-1.0, 1.0),
        float2( 1.0, 1.0),
        float2(-1.0, -1.0),
        float2( 1.0, -1.0)
    };
    
    FaceVertexIn vertexIn = vertices[vid];
    
    FaceVertexOut vertexOut;
    vertexOut.position = uniform.model * float4(positions[vid], 0.0, 1.0);
    vertexOut.texturePosition = vertexIn.texturePosition;
    
    return vertexOut;
}

fragment half4 face_instance_fragment(FaceVertexOut faceVertex [[stage_in]],
                                       texture2d<half, access::sample> texture [[ texture(0) ]])
{
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     mip_filter::nearest);
    
    return texture.sample(textureSampler, faceVertex.texturePosition);
}
