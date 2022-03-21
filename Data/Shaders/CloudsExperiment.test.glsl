// Copyright (c) 2022 David Gallardo and SDFEditor Project

// --- CLOUDS
// Copy this code before main in Color.frag.glsl and replace RaymarchAtlas call by RaymarchAtlasClouds
//
// Refs:
// Volume raycasting: https://www.shadertoy.com/view/lss3zr
// Cloudy Shapes: https://www.shadertoy.com/view/WdXGRj


//-----------------------------------------------------------------------------
// Maths utils
//-----------------------------------------------------------------------------
mat3 m = mat3(0.00, 0.80, 0.60,
    -0.80, 0.36, -0.48,
    -0.60, -0.48, 0.64);

float hash(float n)
{
    return fract(sin(n) * 43758.5453);
}

float noise(in vec3 x)
{
    vec3 p = floor(x);
    vec3 f = fract(x);

    f = f * f * (3.0 - 2.0 * f);

    float n = p.x + p.y * 57.0 + 113.0 * p.z;

    float res = mix(mix(mix(hash(n + 0.0), hash(n + 1.0), f.x),
        mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
        mix(mix(hash(n + 113.0), hash(n + 114.0), f.x),
            mix(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
    return res;
}

float fbm(vec3 p)
{
    float f;
    f = 0.5000 * noise(p); p = m * p * 2.02;
    f += 0.2500 * noise(p); p = m * p * 2.03;
    f += 0.1250 * noise(p);
    return f;
}

vec3 RaymarchAtlasClouds(in ray_t camRay)
{
    float totalDist = 0.0;
    float finalDist = 1000000.0f;
    int iters = 0;
    int maxIters = 300;
    //float limit = sqrt(pow(uVoxelSide.x * 0.5, 2.0) * 2.0f);
    float limit = uVoxelSide.x * 1.0;
    float limitSubVoxel = 0.02;
    vec3 color = backgroundColor.rgb;

    // See lights as background
    //color = ApplyLight(camRay.pos + camRay.dir * 1000.0f, camRay.dir, -camRay.dir, vec3(backgroundColor.rgb), -lightDir, lightAColor.rgb, 1.0, 1.0);
    //color += ApplyLight(camRay.pos + camRay.dir * 1000.0f, camRay.dir, -camRay.dir, vec3(backgroundColor.rgb), -lightDir2, lightBColor.rgb, 1.0, 1.0);


    vec3 testNormal = vec3(0, 0, 0);
    vec2 testDistance = vec2(0, 0);
    bool intersectsBox = rayboxintersect(camRay.pos, camRay.dir, vec3(uVoxelSide.x * uVolumeExtent.x * -0.5), vec3(uVoxelSide.x * uVolumeExtent.x * 0.5), testNormal, testDistance);
    float minZeroDist = clamp(testDistance.x, 0.0, abs(testDistance.x));
    vec3 enterPoint = camRay.pos + camRay.dir * minZeroDist;
    bool reenter = false;
    if (intersectsBox)
    {
        camRay.pos = enterPoint + 0.05 * camRay.dir;
        testDistance.y -= minZeroDist;

        const int nbSample = 128;
        const int nbSampleLight = 6;

        float zMax = 40.;
        float step = zMax / float(nbSample);
        float zMaxl = 10.;
        float stepl = zMaxl / float(nbSampleLight);
        //vec3 p = camRay.pos;
        float T = 1.;
        float absorption = 70.0;
        vec3 sun_direction = normalize(lightDir);

        for (int i = 0; i < nbSample && (totalDist < testDistance.y); i++)
        {
            float density = 0.02 - distToSceneLut(camRay.pos) + fbm(camRay.pos * 2.8) * 0.4;
            if (density > 0.)
            {
                float tmp = density / float(nbSample);
                T *= 1. - tmp * absorption;
                if (T <= 0.02)
                    break;


                //Light scattering
                float Tl = 1.0;
                for (int j = 0; j < nbSampleLight; j++)
                {
                    float densityLight = 0.02 - distToSceneLut(camRay.pos + normalize(sun_direction) * float(j) * stepl) + fbm(camRay.pos * 2.8) * 0.4;
                    if (densityLight > 0.)
                        Tl *= 1. - densityLight * absorption / float(nbSample);
                    if (Tl <= 0.02)
                        break;
                }

                //Add ambiant + light scattering color
                color += vec3(1.) * 50. * tmp * T + lightAColor.rgb * 80. * tmp * T * Tl;
            }
            camRay.pos += camRay.dir * step;
            totalDist = distance(camRay.pos, enterPoint);
        }

        // Debug box
        //color = mix(color, vec3(0.0, 0.5, 0.0), 0.1);
        return color;


    }

    return color;
}

// --- CLOUDS END