
layout(std140, binding = 3) uniform view
{
    mat4 view_viewMatrix;
    mat4 view_projectionMatrix;
    vec4 view_resolution;
};
