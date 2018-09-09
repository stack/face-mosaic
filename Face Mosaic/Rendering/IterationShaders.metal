//
//  IterationShaders.metal
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/7/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct CanvasVertexIn {
    packed_float2 position;
};

struct CanvasVertexOut {
    float4 position [[position]];
    float2 texturePosition;
};

vertex CanvasVertexOut canvas_vertex(const device CanvasVertexIn* vertices [[ buffer(0) ]],
                                     ushort vid [[ vertex_id ]])
{
    constexpr float2 texturePositions[4] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 1.0)
    };
    
    CanvasVertexIn vertexIn = vertices[vid];
    
    CanvasVertexOut vertexOut;
    vertexOut.position = float4(vertexIn.position, 0.0, 1.0);
    vertexOut.texturePosition = texturePositions[vid];
    
    return vertexOut;
}

fragment float4 canvas_fragment(CanvasVertexOut canvasVertex [[ stage_in ]],
                                texture2d<float, access::sample> texture [[texture(0)]])
{
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     s_address::clamp_to_edge,
                                     t_address::clamp_to_edge,
                                     r_address::clamp_to_edge);
    
    return texture.sample(textureSampler, canvasVertex.texturePosition);
}

struct FaceVertexOut {
    float4 position [[position]];
    float2 texturePosition;
};

struct FaceUniform {
    float4x4 translation;
    float4x4 rotation;
    float4x4 scaling;
};

vertex FaceVertexOut face_instance_vertex(const device FaceUniform& uniform[[ buffer(0) ]],
                                          ushort vid [[ vertex_id ]],
                                          ushort iid [[ instance_id ]])
{
    constexpr float4 vertices[4] = {
        float4(-1.0,  1.0, 0.0, 1.0),
        float4( 1.0,  1.0, 0.0, 1.0),
        float4(-1.0, -1.0, 0.0, 1.0),
        float4( 1.0, -1.0, 0.0, 1.0),
    };
    
    constexpr float2 texturePositions[4] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 1.0)
    };
    
    FaceVertexOut vertexOut;
    vertexOut.position = uniform.translation * uniform.rotation * uniform.scaling * vertices[vid];
    vertexOut.texturePosition = texturePositions[vid];
    
    return vertexOut;
}

fragment float4 face_instance_fragment(FaceVertexOut faceVertex [[stage_in]],
                                       texture2d<float, access::sample> texture [[ texture(0) ]])
{
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     s_address::clamp_to_edge,
                                     t_address::clamp_to_edge,
                                     r_address::clamp_to_edge);
    
    return texture.sample(textureSampler, faceVertex.texturePosition);
}
