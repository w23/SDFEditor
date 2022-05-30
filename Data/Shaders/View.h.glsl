
layout(std140, binding = 3) uniform view
{
    mat4 view_viewMatrix;
    mat4 view_projectionMatrix;
    vec4 view_resolution;
};

layout(std140, binding = 4) uniform global_material
{
    vec4 surfaceColor;
    vec4 fresnelColor;
    vec4 aoColor;
    vec4 backgroundColor;

    vec4 lightAColor;
    vec4 lightBColor;

    vec4 pbr; // roughness.x, metalness.y
};