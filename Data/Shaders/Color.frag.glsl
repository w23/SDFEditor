#version 450

#extension GL_ARB_shader_storage_buffer_object : require

layout(location = 0) in vec2 inFragUV;
layout(location = 1) in vec3 inRayOrigin;
layout(location = 2) in vec3 inRayDirection;

layout(location = 0) out vec4 outColor;

struct stroke_t
{
    vec4 param0;    // position.xyz, blend.a
    vec4 param1;    // size.xyz, radius.x, round.w
    ivec4 id;       // shape.x, flags.y
};

layout(std430, binding = 0) buffer strokes_buffer
{
    stroke_t strokes[];
};

layout(location = 1) uniform uint uStrokesNum;

struct ray_t 
{
    vec3 pos;
    vec3 dir;
};

// polynomial smooth min
float sminCubic(float a, float b, float k)
{
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * h * k * (1.0 / 6.0);
}

// - SDFS -------------------------
float sdEllipsoid(vec3 p, vec3 r)
{
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

float sdRoundBox(vec3 p, vec3 b, float r)
{
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

float sdTorus(vec3 p, vec2 t)
{
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

float sdVerticalCapsule(vec3 p, float h, float r)
{
    p.y -= clamp(p.y, 0.0, h);
    return length(p) - r;
}

// - STROKE EVALUATION --------------
void evalStroke(in out float d, vec3 p, stroke_t stroke)
{
    float shape = d;
    vec3 position = p - stroke.param0.xyz;

    if (stroke.id.x == 0)
    {
        shape = sdEllipsoid(position, stroke.param1.xyz);
    }
    else if (stroke.id.x == 1)
    {
        float round = clamp(stroke.param1.w, 0.0, 1.0);
        float smaller = min(min(stroke.param1.x, stroke.param1.y), stroke.param1.z);
        round = mix(0.0, smaller, round);
        shape = sdRoundBox(position, stroke.param1.xyz - round, round);
    }
    else if (stroke.id.x == 2)
    {
        shape = sdTorus(position, stroke.param1.xy);
    }
    else if (stroke.id.x == 3)
    {
        shape = sdVerticalCapsule(position, stroke.param1.x, stroke.param1.y);
    }


    d = sminCubic(d, shape, stroke.param0.w);
}

//Distance to scene at point
float distToScene(vec3 p) 
{
    //float a = length(p - vec3(0.0, 0.0, -1.0)) - 0.3;
    //float b = length(p - vec3(0.35, 0.0, -1.0)) - 0.3;
    float d = 1000000.0;

    //d = sminCubic(d, length(p - vec3(0.0, 0.0, -1.0)) - 0.3, 0.2);
    //d = sminCubic(d, length(p - vec3(0.35, 0.0, -1.0)) - 0.3, 0.2);

    for (uint i = 0; i < uStrokesNum; i++)
    {
        evalStroke(d, p, strokes[i]);
    }

    return d;
}

//Estimate normal based on distToScene function
const float EPS = 0.001;
vec3 estimateNormal(vec3 p) 
{
    float xPl = distToScene(vec3(p.x + EPS, p.y, p.z));
    float xMi = distToScene(vec3(p.x - EPS, p.y, p.z));
    float yPl = distToScene(vec3(p.x, p.y + EPS, p.z));
    float yMi = distToScene(vec3(p.x, p.y - EPS, p.z));
    float zPl = distToScene(vec3(p.x, p.y, p.z + EPS));
    float zMi = distToScene(vec3(p.x, p.y, p.z - EPS));
    float xDiff = xPl - xMi;
    float yDiff = yPl - yMi;
    float zDiff = zPl - zMi;
    return normalize(vec3(xDiff, yDiff, zDiff));
}


// - TONEMAPPING -----------------------
vec3 LessThan(vec3 f, float value)
{
    return vec3(
        (f.x < value) ? 1.0f : 0.0f,
        (f.y < value) ? 1.0f : 0.0f,
        (f.z < value) ? 1.0f : 0.0f);
}

vec3 LinearToSRGB(vec3 rgb)
{
    rgb = clamp(rgb, 0.0f, 1.0f);

    return mix(
        pow(rgb, vec3(1.0f / 2.4f)) * 1.055f - 0.055f,
        rgb * 12.92f,
        LessThan(rgb, 0.0031308f)
    );
}

vec3 SRGBToLinear(vec3 rgb)
{
    rgb = clamp(rgb, 0.0f, 1.0f);

    return mix(
        pow(((rgb + 0.055f) / 1.055f), vec3(2.4f)),
        rgb / 12.92f,
        LessThan(rgb, 0.04045f)
    );
}

// -----------------------

void main()
{
    //vec3 direction = normalize(inRayDirection);
    //outColor = vec4(abs(direction.xyz), 1.0);

    
    vec2 uv = inFragUV;
    uv -= vec2(0.5);//offset, so center of screen is origin
    uv *= 2.0;
    //uv.x *= iResolution.x / iResolution.y;//scale, so there is no rectangular distortion

    ray_t camRay;
    camRay.pos = inRayOrigin;
    camRay.dir = normalize(inRayDirection);

    float totalDist = 0.0;
    float finalDist = distToScene(camRay.pos);
    int iters = 0;
    int maxIters = 50;

    vec3 color = vec3(0.0, 0.0, 0.0);

    for (iters = 0; iters < maxIters && finalDist>0.008; iters++) {
        camRay.pos += finalDist * camRay.dir;
        totalDist += finalDist;
        finalDist = distToScene(camRay.pos);
    }

    if (finalDist < 0.008)
    {
        color.r = 1.0;

        vec3 normal = estimateNormal(camRay.pos);

        vec3 lightDir = normalize(vec3(1.0, 1.0, 0.0));

        float dotSN = dot(normal, lightDir);
        dotSN = (dotSN + 1.0) * 0.5;
        dotSN = mix(0.1, 1.2, dotSN);

        //outColor = vec4(0.5 + 0.5 * normal, 1.0) * dotSN;
        outColor = vec4(0.5 + 0.5 * normal, 1.0) * dotSN;

    }

    else
    {
        outColor = vec4(0.05, 0.05, 0.1, 1.0);
    }

    outColor.rgb = LinearToSRGB(outColor.rgb);
    
    //outColor.rgb = abs(strokes[0].param0.xyz);
}
