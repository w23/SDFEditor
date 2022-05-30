// Copyright (c) 2022 David Gallardo and SDFEditor Project
// 
//struct primitive_data_t
//{
//    mat4 transform;
//};
//
//layout(std430, binding = 0) readonly buffer primitive_data_buffer
//{
//    primitive_data_t primitive_data[];
//};




out gl_PerVertex
{
  vec4 gl_Position;
  float gl_PointSize;
  float gl_ClipDistance[];
};

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;

layout(location = 1) out vec4 outNear;
layout(location = 2) out vec4 outFar;
layout(location = 3) out vec3 outWorldPos;
layout(location = 4) out vec3 outNormal;

//layout(location = 0) out mat4 outViewMatrix;
//layout(location = 1) out mat4 outProjectionMatrix;
//layout(location = 2) out mat4 outModelMatrix;

//layout(location = 0) uniform mat4 uViewMatrix;
//layout(location = 1) uniform mat4 uProjectionMatrix;
layout(location = 2) uniform mat4 uModelMatrix; //TODO: should come from a buffer



void main()
{
    //vec2 clipPos = positions[gl_VertexID].xy;
    //float near = 0.1f;
    //float far = 100.0f;
    //
    //gl_Position = vec4(clipPos, 0.0, 1.0);
    //outFragUV = uvs[gl_VertexID].xy;
    //
    mat4 viewProj = view_projectionMatrix * view_viewMatrix;
    mat4 invViewProj = inverse(viewProj);
    //
    
    gl_Position = viewProj * vec4(inPosition * 3.2, 1.0);
    outWorldPos = inPosition * 3.2; // TODO model matrix
    outNormal = normalize(inNormal); //normalize(inPosition.xyz);

    outNear = invViewProj * vec4(gl_Position.xy, 0, 1);
    ////nearPos /= nearPos.w;
    outFar = invViewProj * vec4(gl_Position.xy, 1, 1);
    ////farPos /= farPos.w;
}




