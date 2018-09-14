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
                                     min_filter::linear,
                                     s_address::clamp_to_edge,
                                     t_address::clamp_to_edge,
                                     r_address::clamp_to_edge);
    
    return (half4)texture.sample(textureSampler, canvasVertex.texturePosition);
}

struct FaceVertexIn {
    packed_float2 position;
};

struct FaceVertexOut {
    float4 position [[position]];
    float2 texturePosition;
};

struct FaceUniform {
    float4x4 model;
};

vertex FaceVertexOut face_instance_vertex(const device FaceUniform& uniform [[ buffer(0) ]],
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
    
    FaceVertexOut vertexOut;
    vertexOut.position = uniform.model * float4(positions[vid], 0.0, 1.0);
    vertexOut.texturePosition = texturePositions[vid];
    
    return vertexOut;
}

fragment half4 face_instance_fragment(FaceVertexOut faceVertex [[stage_in]],
                                       texture2d<half, access::sample> texture [[ texture(0) ]])
{
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     s_address::clamp_to_edge,
                                     t_address::clamp_to_edge,
                                     r_address::clamp_to_edge);
    
    return texture.sample(textureSampler, faceVertex.texturePosition);
}
