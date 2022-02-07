//#version 450

//#extension GL_ARB_shader_storage_buffer_object : require

layout(location = 0) in vec2 inFragUV;
layout(location = 1) in vec4 inNear;
layout(location = 2) in vec4 inFar;

layout(location = 0) out vec4 outColor;

struct ray_t
{
    vec3 pos;
    vec3 dir;
};

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


vec3 aces_tonemap(vec3 color) {
    mat3 m1 = mat3(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
    );
    mat3 m2 = mat3(
        1.60475, -0.10208, -0.00327,
        -0.53108, 1.10813, -0.07276,
        -0.07367, -0.00605, 1.07602
    );
    vec3 v = m1 * color;
    vec3 a = v * (v + 0.0245786) - 0.000090537;
    vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return pow(clamp(m2 * (a / b), 0.0, 1.0), vec3(1.0 / 2.2));
}

// -----------------------

float CalcAO(in vec3 pos, in vec3 nor)
{
    float occ = 0.0;
    float sca = 1.0, dd;
    for (int i = 0; i < 5; i++)
    {
        float hr = 0.01 + 0.29 * float(i) / 4.0;
        vec3 aopos = nor * hr + pos;
        dd = distToScene(aopos);
        occ += -(dd - hr) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 1.4 * occ, 0.0, 1.0);
}


float CalcAOLut(in vec3 pos, in vec3 nor)
{
    float occ = 0.0;
    float sca = 1.0, dd;
    for (int i = 0; i < 5; i++)
    {
        float hr = 0.01 + 0.39 * float(i) / 4.0;
        vec3 aopos = nor * hr + pos;
        dd = distToSceneLut(aopos);
        occ += -(dd - hr) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 1.6 * occ, 0.0, 1.0);
}

vec3 ApplyMaterial(vec3 pos, vec3 rayDir, vec3 normal, float ao)
{
    vec3 lightDir = normalize(vec3(1.0, 1.0, 0.0));

    float dotSN = dot(normal, lightDir);
    dotSN = (dotSN + 1.0) * 0.5;
    dotSN = mix(0.4, 1.0, dotSN);

    float dotCam = 1.0 - abs(dot(rayDir, normal));
    dotCam = pow(dotCam, 2.0);

    //vec3 color = vec3(0.5 + 0.5 * normal) * dotSN;
    //float ao = CalcAO(pos, normal);
    vec3 color = mix(vec3(0.06, 0.001, 0.001), vec3(vec3(0.15, 0.008, 0.008)), ao);// *dotSN;
    color = mix(color, vec3(0.19, 0.08, 0.08 ), dotCam);
    return color;
}

vec3 RaymarchStrokes(in ray_t camRay)
{
    float totalDist = 0.0;
    float finalDist = distToScene(camRay.pos);
    int iters = 0;
    int maxIters = 70;
    float limit = 0.02f;

    vec3 color = vec3(0.07, 0.08, 0.19) * 0.8;

    for (iters = 0; iters < maxIters && finalDist > limit; iters++)
    {
        camRay.pos += finalDist * camRay.dir;
        totalDist += finalDist;
        finalDist = distToScene(camRay.pos);
    }

    if (finalDist <= limit)
    {
        vec3 normal = estimateNormal(camRay.pos);

        color = ApplyMaterial(camRay.pos, camRay.dir, normal, CalcAO(camRay.pos, normal));
    }

    return color;
}



vec3 RaymarchLut(in ray_t camRay) // Debug only
{
    float totalDist = 0.0;
    float finalDist = distToSceneLut(camRay.pos);
    int iters = 0;
    int maxIters = 150;
    float limit = sqrt(pow(uVoxelSide.x * 0.5, 2.0) * 2.0f);
    //float limit = uVoxelSide.x * 0.5;
    vec3 color = vec3(0.07, 0.08, 0.19) * 0.8;

    for (iters = 0; iters < maxIters && finalDist > limit; iters++)
    {
        camRay.pos += finalDist * camRay.dir;
        totalDist += finalDist;
        finalDist = distToSceneLut(camRay.pos);
    }

    if (finalDist <= limit)
    {
        vec3 normal = estimateNormalLut(camRay.pos);

        color = ApplyMaterial(camRay.pos, camRay.dir, normal, CalcAOLut(camRay.pos, normal));
        //ivec3 lutcoord = WorldToLutCoord(camRay.pos);
        //color = texelFetch(uSdfLutTexture, clamp(lutcoord, ivec3(0), ivec3(uVolumeExtent.x - 1)), 0).rgb;
    }

    return color;
}

void main()
{    
    vec3 origin = inNear.xyz / inNear.w;  //ray's origin
    vec3 far3 = inFar.xyz / inFar.w;
    vec3 dir = far3 - origin;
    dir = normalize(dir);        //ray's direction

    ray_t camRay;
    camRay.pos = origin;
    camRay.dir = dir;
    
    vec3 finalColor = (uVoxelPreview.x == 1) ? RaymarchLut(camRay) : RaymarchStrokes(camRay);

    finalColor = LinearToSRGB(finalColor.rgb);
    
    {
        // Vignette
        vec2 uv2 = inFragUV * (vec2(1.0) - inFragUV.yx);   //vec2(1.0)- uv.yx; -> 1.-u.yx; Thanks FabriceNeyret !
        float vig = uv2.x * uv2.y * 13.0; // multiply with sth for intensity
        vig = pow(vig, 0.35); // change pow for modifying the extend of the  vignette
        vig = mix(0.35, 1.0, vig);
        vig = smoothstep(0.0, 0.75, vig);
        finalColor *= vig;
    }

    outColor = vec4(finalColor, 1.0f);

    //outColor.rgb = abs(strokes[0].posb.xyz);
    if (uVoxelPreview.x == 1)
    {
        vec4 sdf = texelFetch(uSdfLutTexture, ivec3(inFragUV.x * 2.0 * (16.0f / 9.0f) * uVolumeExtent.x, float(uVoxelPreview.y), inFragUV.y * 2.0 * uVolumeExtent.x), 0).rgba;
        //vec4 sdfTop = texture(uSdfLutTexture, vec3(inFragUV.x * 2.0 * (16.0f / 9.0f), inFragUV.y * 2.0 - 1.0, float(uVoxelPreview.y) / 128.0f)).rgba;
        //sdf = mix(sdfTop, sdf, step(sdf.a, 1.0f / 128.0f));
        sdf.a = (sdf.a * 2.0) - 1.0;
        sdf.a = abs(sdf.a * uVolumeExtent.x * uVoxelSide.x);
        float debugLimit = sqrt(pow(uVoxelSide.x * 0.5, 2.0) * 2.0f) * 2.5f;
        outColor.rgb = mix(finalColor, sdf.rgb, sdf.a < debugLimit ? 1.0f : 0.0f);
    }
}
