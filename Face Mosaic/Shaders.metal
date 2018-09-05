//
//  Shaders.metal
//  Face Mosaic
//
//  Created by Stephen H. Gerstacker on 9/2/18.
//  Copyright © 2018 Stephen H. Gerstacker. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct FaceTextureVertexIn {
    packed_float2 position;
};

struct FaceVertexUniformIn {
    packed_float2 sceneSize;
};

struct FaceVertexOut {
    float4 position [[ position ]];
    float2 texturePosition;
};


struct StandardVertexIn {
    packed_float2 position;
    packed_float2 texturePosition;
};

struct TextureVertexIn {
    packed_float2 texturePosition;
};

struct VertexUniformIn {
    float4x4 translation;
    float4x4 rotation;
    float4x4 scaling;
};

struct StandardVertexOut {
    float4 position [[position]];
    float2 texturePosition;
};

struct StandardVertexUniforms {
    int dummy;
};

vertex StandardVertexOut standard_vertex(
                                 const device StandardVertexIn *vertices [[ buffer(0) ]],
                                 const device TextureVertexIn *textureVertices [[ buffer(1) ]],
                                 const device VertexUniformIn& uniform [[ buffer(2) ]],
                                 unsigned int vid [[ vertex_id ]] ) {
    StandardVertexIn vertexIn = vertices[vid];
    TextureVertexIn textureVertexIn = textureVertices[vid];
    
    StandardVertexOut vertexOut;
    vertexOut.position = uniform.translation * uniform.scaling * uniform.rotation * float4(vertexIn.position, 0.0, 1.0);
    vertexOut.texturePosition = textureVertexIn.texturePosition;
    
    return vertexOut;
}

fragment float4 standard_fragment(
                              StandardVertexOut face_vertex [[ stage_in ]],
                              /*const device StandardVertexUniforms& uniforms, */
                              texture2d<float, access::sample> texture) {
    constexpr sampler texture_sampler (mag_filter::linear, min_filter::linear, s_address::clamp_to_edge, t_address::clamp_to_edge, r_address::clamp_to_edge);
    
    return texture.sample(texture_sampler, face_vertex.texturePosition);
}

fragment float4 target_fragment(
                                StandardVertexOut face_vertex [[ stage_in ]],
                                /*const device StandardVertexUniforms& uniforms, */
                                texture2d<float, access::sample> texture) {
    constexpr sampler texture_sampler (mag_filter::linear, min_filter::linear, s_address::clamp_to_edge, t_address::clamp_to_edge, r_address::clamp_to_edge);
    
    return texture.sample(texture_sampler, face_vertex.texturePosition).zyxw;
}
