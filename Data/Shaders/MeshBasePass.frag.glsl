// Copyright (c) 2022 David Gallardo and SDFEditor Project
// main raymarching, lots of optimizations to be done here

layout(location = 1) in vec4 inNear;
layout(location = 2) in vec4 inFar;

layout(location = 0) out vec4 outColor;

//layout(location = 0) uniform mat4 uViewMatrix;
//layout(location = 1) uniform mat4 uProjectionMatrix;
//layout(location = 2) uniform mat4 uModelMatrix;
layout(location = 10) uniform sampler2D uRoughnessMap;
layout(location = 11) uniform sampler2D uDitheringMap;

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
        float hr = 0.01 + 0.23   * float(i) / 4.0;
        vec3 aopos = nor * hr + pos;
        dd = distToScene(aopos);
        occ += -(dd - hr) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 1.6 * occ, 0.0, 1.0);
}

float CalcAOAtlas(in vec3 pos, in vec3 nor)
{
    float occ = 0.0;
    float sca = 1.0, dd;
    pos += nor * 0.01; // move towards normal a bit
    for (int i = 0; i < 5; i++)
    {
        float hr = 0.01 + 0.23 * float(i) / 4.0;
        vec3 aopos = nor * hr + pos;
        dd = distToSceneAtlas(aopos);
        occ += -(dd - hr) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 1.6 * occ, 0.0, 1.0);
}

// Blend between dielectric and metallic materials.
// Note: The range of semiconductors is approx. [0.2, 0.45]
vec3 BlendMaterial(vec3 Kdiff, vec3 Kspec, vec3 Kbase, float metallic)
{
    //float scRange = clamp(0.2, 0.45, metallic);
    float scRange = metallic;
    vec3  dielectric = Kdiff + Kspec;
    vec3  metal = Kspec * Kbase;
    return mix(dielectric, metal, scRange);
}

//mostly from: http://blog.selfshadow.com/publications/s2013-shading-course/karis/s2013_pbs_epic_notes_v2.pdf
//from https://www.shadertoy.com/view/ltjBzK
vec3 ApplyLight(in vec3 pos, in vec3 rd, in vec3 n, in vec3 alb, vec3 lgt, vec3 lcol, float rough, float metallic)
{
    //const float rough = 0.3;
    float nl = dot(n, lgt);
    nl = (nl + 0.7) / 1.7; // cover more area
    nl = clamp(nl, 0.01, 1.0);
    float nv = dot(n, -rd);
    vec3 col = vec3(0.);
    //float ao = calcAO(pos, n);
    vec3 f0 = vec3(0.1);
    if (nl > 0.)
    {
        vec3 haf = normalize(lgt - rd);
        float nh = clamp(dot(n, haf), 0., 1.);
        float nv = clamp(dot(n, -rd), 0., 1.);
        float lh = clamp(dot(lgt, haf), 0., 1.);
        float a = rough * rough;
        float a2 = a * a;
        float dnm = nh * nh * (a2 - 1.) + 1.;
        float D = a2 / (3.14159 * dnm * dnm);
        float k = pow(rough + 1., 2.) / 8.; //hotness reducing
        float G = (1. / (nl * (1. - k) + k)) * (1. / (nv * (1. - k) + k));
        vec3 F = f0 + (1. - f0) * exp2((-5.55473 * lh - 6.98316) * lh);
        vec3 spec = nl * D * F * G;
        col.rgb = lcol * nl * (spec + alb * (1. - f0));
        //col.rgb = alb * ((metallic > 0.001) ? max(0.5, rough) : 0.0);
        //col.rgb += BlendMaterial(lcol*nl*alb*(1. - f0), lcol*nl*spec, alb, metallic);
    }
    //col *= shadow(pos, lgt, 0.1,2.)*0.8+0.2;

#if 1
    float bnc = clamp(dot(n, normalize(vec3(-lgt.x, 5.0, -lgt.z))) * .5 + 0.28, 0., 1.);
    col.rgb += lcol * alb * bnc * 0.1;
#endif

    //col += 0.05*alb;
    //col *= ao;
    return col;
}

// BoxMap from https://www.shadertoy.com/view/MtsGWH
// "p" point apply texture to
// "n" normal at "p"
// "k" controls the sharpness of the blending in the
//     transitions areas.
// "s" texture sampler
vec4 BoxMap(in sampler2D s, in vec3 p, in vec3 n, in float k)
{
    // project+fetch
    vec4 x = texture(s, p.yz);
    vec4 y = texture(s, p.zx);
    vec4 z = texture(s, p.xy);

    // and blend
    vec3 m = pow(abs(n), vec3(k));
    return (x * m.x + y * m.y + z * m.z) / (m.x + m.y + m.z);
}

vec3 lightDir = normalize(vec3(1.0, 1.0, 0.0));
vec3 lightDir2 = normalize(vec3(-1.0, -1.0, 0.0));

vec4 ApplyMaterial(vec3 pos, vec3 rayDir, vec3 normal, float ao)
{

    //float dotSN = dot(normal, lightDir);
    //dotSN = (dotSN + 1.0) * 0.5;
    //dotSN = mix(0.2, 1.0, dotSN);

    float dotCam = 1.0 - abs(dot(rayDir, normal));
    dotCam = pow(dotCam, pbr.z);

    //vec3 color = vec3(0.5 + 0.5 * normal);// *dotSN* mix(0.5, 1.0, ao);
  //  color = mix(color, vec3(0.5), dotCam);
    
    //vec3 color = vec3(0); 
    //color = mix(vec3(0.18, 0.032, 0.00), vec3(0.30, 0.090, 0.050), dotCam);
    //color = mix(vec3(0.07, 0.016, 0.018), color, ao) * dotSN;// *dotSN;
    
    vec3 color = vec3(0);
    //color = mix(surfaceColor.rgb, fresnelColor.rgb, dotCam);
   // color = mix(aoColor.rgb, color, ao) * dotSN;
    
    // Added roughness map
    float roughMap = BoxMap(uRoughnessMap, pos * 1.0, normal, 8.0).r;
    //roughMap = mix(0.2, 1.0, roughMap);
    float roughness = mix(0.0, roughMap, clamp(pbr.x, 0.0, 1.0));

    color += ApplyLight(pos, rayDir, normal, surfaceColor.rgb, lightDir, lightAColor.rgb, roughness, pbr.y);
    color += ApplyLight(pos, rayDir, normal, surfaceColor.rgb, lightDir2, lightBColor.rgb, roughness, pbr.y);
    color = mix(color, fresnelColor.rgb, dotCam);
    color = mix(aoColor.rgb, color, ao);
    color += fresnelColor.rgb * (1.0 - ao) * 0.5;

    return vec4(color, 1.0);
}

vec4 RaymarchStrokes(in ray_t camRay)
{
    float totalDist = 0.0;
    float finalDist = distToScene(camRay.pos);
    int iters = 0;
    int maxIters = 70;
    float limit = 0.02f;

    vec4 color = vec4(0.0);

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

vec2 opMinV2(in vec2 a, in vec2 b) { return (abs(a.x) < abs(b.x)) ? a : b; }

vec4 RaymarchAtlas(in ray_t camRay)
{
    float totalDist = 0.0;
    float finalDist = 1000000.0f;
    int iters = 0;
    int maxIters = 300;
    //float limit = sqrt(pow(uVoxelSide.x * 0.5, 2.0) * 2.0f);
    float limit = uVoxelSide.x * 1.0;
    float limitSubVoxel = 0.02;
    vec4 color = vec4(0.0f);//backgroundColor.rgb;

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
        camRay.pos = enterPoint;
        testDistance.y -= minZeroDist;
        
        finalDist = distToSceneLut(camRay.pos);

        for (iters = 0; iters < maxIters && ((finalDist > limit || reenter) && totalDist < testDistance.y); iters++)
        {
            reenter = false;
            camRay.pos += finalDist * camRay.dir;
            totalDist = distance(camRay.pos, enterPoint);
            finalDist = distToSceneLut(camRay.pos);

            if (finalDist <= limit && totalDist < testDistance.y)
            {
                // this should be done inside the raymarching loop
                // when finalDist < limit ...
                // fetch the atlas cell coords for camRay.pos
                // do a box intersection to know the distance with edges and calculate 4 points along the ray inside the box
                // convert the four points to voxel coords and ensure edge ones are at least + 0.5 of the border (clamp offset?)
                // sample the four points in this atlas cell along the ray
                // TODO: use quadratic regresion to 
                // if smalles distance is < threshold ( 0.02? ) is a hit, if is too negative < -threshold, is a it at the smallest t
                // if not, move to the next box ...
                // reset some values to avoid raymarch loop stop
                // continue raymarching

                vec3 tn = vec3(0, 0, 0);
                vec2 td = vec2(0, 0);
                vec3 bmin = (floor(camRay.pos * uVoxelSide.y)) * uVoxelSide.x;
                vec3 bmax = bmin + uVoxelSide.x;
                if (rayboxintersect(camRay.pos, camRay.dir, bmin, bmax, tn, td))
                {
                    ivec3 lutcoord = WorldToLutCoord(camRay.pos);
                    vec4 fetchedIndex = texelFetch(uSdfLutTexture, clamp(lutcoord, ivec3(0), ivec3(uVolumeExtent.x - 1)), 0).rgba;

                    vec2 minDist = vec2(1.0, 0.0);

                    float maxDist = td.y;
                    if (ivec3(fetchedIndex.rgb + 0.5) != ivec3(1))
                    {
                        uint slot = NormCoordToIndex(fetchedIndex.rgb);
                        ivec3 cellCoord = GetCellCoordFromIndex(slot, ATLAS_SLOTS) * 8;

                        // Pick four points along the ray to get the closest distance.
                        // TODO: IMPROVE: current implementation still has artifacts and require a lot of iterations
                        //float At = td.x + 0.0001; // exact offset to avoid filtering with adjadcent Atlas cubes
                        //float Bt = td.y * 0.0;
                        //float Ct = td.y * 0.1;
                        //float Dt = td.y * 0.2;

                        float diff = td.y - max(0.0, td.x);
                        float At = td.x + 0.0001; 
                        float Bt = td.y * 0.0;
                        float Ct = td.y * 0.15;
                        float Dt = td.y * 0.25;
                        maxDist = Dt;

                        vec3 Ap = camRay.pos + At * camRay.dir;
                        vec3 Bp = camRay.pos + Bt * camRay.dir;
                        vec3 Cp = camRay.pos + Ct * camRay.dir;
                        vec3 Dp = camRay.pos + Dt * camRay.dir;

                        vec3 offsetA = vec3(fract(Ap * uVoxelSide.y) * 8.0);
                        vec3 offsetB = vec3(fract(Bp * uVoxelSide.y) * 8.0);
                        vec3 offsetC = vec3(fract(Cp * uVoxelSide.y) * 8.0);
                        vec3 offsetD = vec3(fract(Dp * uVoxelSide.y) * 8.0);

                        offsetA = clamp(offsetA, 0.5f, 7.5f);
                        offsetB = clamp(offsetB, 0.5f, 7.5f);
                        offsetC = clamp(offsetC, 0.5f, 7.5f);
                        offsetD = clamp(offsetD, 0.5f, 7.5f);

                        vec2 A = vec2(sampleAtlasDist((cellCoord + offsetA) / vec3(ATLAS_SIZE)).r, At);
                        vec2 B = vec2(sampleAtlasDist((cellCoord + offsetB) / vec3(ATLAS_SIZE)).r, Bt);
                        vec2 C = vec2(sampleAtlasDist((cellCoord + offsetC) / vec3(ATLAS_SIZE)).r, Ct);
                        vec2 D = vec2(sampleAtlasDist((cellCoord + offsetD) / vec3(ATLAS_SIZE)).r, Dt);
                        
                        // this is wrong, I'm losing the option of being betweein A and B or C and D
                        minDist = opMinV2(opMinV2(A, B), opMinV2(C, D));

                        //minDist = B;


                        // surface found along the ray samples
                        if (minDist.x < limitSubVoxel)
                        {
                            // if it isn't too deep
                            if (minDist.x > -limitSubVoxel)
                            {
                                camRay.pos = camRay.pos + minDist.y * camRay.dir;
                                finalDist = minDist.x;

                                // recalculate totalDist
                                totalDist = distance(camRay.pos, enterPoint);
                            }
                            else
                            {
                                // minimum distance is too deep, just keep it in the initial position.
                                finalDist = 0.0f;
                            }
                        }
                        else
                        {
                            //we are too far away, advance until the farthest distance and continue raymarching
                            reenter = true;
                            finalDist = maxDist + 0.005; // td.y + 0.0001;
                        }
                    }
                    else
                    {
                        reenter = true;
                        finalDist = maxDist + 0.005; // td.y + 0.0001;
                    }
                }
            }
        }

        if (finalDist < limitSubVoxel)
        {
            vec3 normal = estimateNormalAtlas(camRay.pos);
            color = ApplyMaterial(camRay.pos, camRay.dir, normal, CalcAOAtlas(camRay.pos, normal));
        }

        // Debug box
        //color = mix(color, vec3(0.0, 0.5, 0.0), 0.1);
    }

    return color;
}

void main()
{    
    vec2 clipPos = (gl_FragCoord.xy / view_resolution.xy) * 2.0 - 1.0;

    mat4 viewProj = view_projectionMatrix * view_viewMatrix;
    mat4 invViewProj = inverse(viewProj);

    vec4 near = invViewProj * vec4(clipPos.xy, 0, 1);
    vec4 far = invViewProj * vec4(clipPos.xy, 1, 1);

    vec3 origin = near.xyz / near.w;  //ray's origin
    vec3 far3 = far.xyz / far.w;
    vec3 dir = far3 - origin;
    dir = normalize(dir);        //ray's direction

    ray_t camRay;
    camRay.pos = origin;
    camRay.dir = dir;
    
    vec4 finalColor = (uVoxelPreview.x == 1) ? RaymarchAtlas(camRay) : RaymarchStrokes(camRay);
    //finalColor.rgb = vec3(0.0, 1.0, 0.0) * finalColor.a;

    //vec4 finalColor = vec4(dir * 0.5 + 0.5, 0.2);

    finalColor.rgb = LinearToSRGB(finalColor.rgb);

    finalColor.rgba += vec4(0.0, 0.1, 0.0, 0.1) * (1.0 - finalColor.a);

   
    
    // Fix color banding with dithering: https://www.anisopteragames.com/how-to-fix-color-banding-with-dithering/
    finalColor += texture2D(uDitheringMap, gl_FragCoord.xy / 8.0).r / 32.0 - (1.0 / 128.0);

   outColor = finalColor;
   //outColor = vec4(vec3(1.0, 0.0, 0.0), 1.0f);
}
