//
//  Shaders.metal
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/2/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct FaceVertexUniformIn {
    float4x4 translation;
    float4x4 rotation;
    float4x4 scaling;
};

struct TargetVertexIn {
    packed_float2 position;
};

struct StandardVertexOut {
    float4 position [[position]];
    float2 texturePosition;
};

vertex StandardVertexOut face_vertex(const device FaceVertexUniformIn& uniform [[ buffer(0) ]],
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
    
    StandardVertexOut vertexOut;
    vertexOut.position = uniform.translation * uniform.scaling * uniform.rotation * vertices[vid];
    vertexOut.texturePosition = texturePositions[vid];
    
    return vertexOut;
}

fragment float4 face_fragment(StandardVertexOut face_vertex [[ stage_in ]],
                              texture2d<float, access::sample> texture)
{
    constexpr sampler texture_sampler(
                                      mag_filter::linear,
                                      min_filter::linear,
                                      s_address::clamp_to_edge,
                                      t_address::clamp_to_edge,
                                      r_address::clamp_to_edge);
    
    return texture.sample(texture_sampler, face_vertex.texturePosition).zyxw;
}


vertex StandardVertexOut target_vertex(const device TargetVertexIn* vertices [[ buffer(0) ]],
                                       ushort vid [[ vertex_id ]],
                                       ushort iid [[ instance_id ]])
{
    constexpr float2 texturePositions[4] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 1.0)
    };
    
    TargetVertexIn vertexIn = vertices[vid];
    
    StandardVertexOut vertexOut;
    vertexOut.position = float4(vertexIn.position, 0.0, 1.0);
    vertexOut.texturePosition = texturePositions[vid];
    
    return vertexOut;
}

fragment float4 target_fragment(StandardVertexOut face_vertex [[ stage_in ]],
                                texture2d<float, access::sample> texture)
{
    constexpr sampler texture_sampler (mag_filter::linear, min_filter::linear, s_address::clamp_to_edge, t_address::clamp_to_edge, r_address::clamp_to_edge);
    
    return texture.sample(texture_sampler, face_vertex.texturePosition);
}
