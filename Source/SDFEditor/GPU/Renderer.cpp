// Copyright (c) 2022 David Gallardo and SDFEditor Project

#include "Renderer.h"
#include <ThirdParty/glad/glad.h>
#include <GLFW/glfw3.h>

#include "SDFEditor/Utils/FileIO.h"
#include "SDFEditor/Tool/Scene.h"

#include <sbx/Core/Log.h>
#include <sbx/Texture/TextureUtils.h>

#include "glm/glm.hpp"
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

namespace EUniformLoc
{
    enum Type
    {
        uRoughnessMap = 10,
        uDitheringMap = 11,

        uStrokesNum = 20,
        uMaxSlotsCount = 21,
        uVoxelSide = 22,
        uVolumeExtent = 23,

        uSdfLutTexture = 30,
        uSdfAtlasTexture = 31,

        // Debug
        uVoxelPreview = 40,
    };
};

namespace ETexBinding
{
    enum Type
    {
        uSdfLut = 1,
        uSdfAtlas = 2,
        uRoughnessMap = 3,
        uDitheringMap = 4,
    };
}

namespace EBlockBinding
{
    enum Type
    {
        strokes_buffer = 0,
        slot_list_buffer = 1,
        slot_count_buffer = 2,
        view = 3,
        global_material = 4,
    };
};

#define VOXEL_EXTENT (0.05f)
#define LUT_RES (128)
//#define 

void CRenderer::Init()
{
    //glDisable(GL_FRAMEBUFFER_SRGB);

    // OpenGL setup
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    glFrontFace(GL_CCW);

    int workGroupSizes[3] = { 0 };
    glGetIntegeri_v(GL_MAX_COMPUTE_WORK_GROUP_SIZE, 0, &workGroupSizes[0]);
    glGetIntegeri_v(GL_MAX_COMPUTE_WORK_GROUP_SIZE, 1, &workGroupSizes[1]);
    glGetIntegeri_v(GL_MAX_COMPUTE_WORK_GROUP_SIZE, 2, &workGroupSizes[2]);
    int workGroupCounts[3] = { 0 };
    glGetIntegeri_v(GL_MAX_COMPUTE_WORK_GROUP_COUNT, 0, &workGroupCounts[0]);
    glGetIntegeri_v(GL_MAX_COMPUTE_WORK_GROUP_COUNT, 1, &workGroupCounts[1]);
    glGetIntegeri_v(GL_MAX_COMPUTE_WORK_GROUP_COUNT, 2, &workGroupCounts[2]);

    SBX_LOG("GL_MAX_COMPUTE_WORK_GROUP_SIZE: (%d, %d, %d)", workGroupSizes[0], workGroupSizes[1], workGroupSizes[2]);
    SBX_LOG("GL_MAX_COMPUTE_WORK_GROUP_COUNT: (%d, %d, %d)", workGroupCounts[0], workGroupCounts[1], workGroupCounts[2]);

    // dummy VAO
    glGenVertexArrays(1, &mDummyVAO);

    // Strokes buffer
    mStrokesBuffer = std::make_shared<CGPUBufferObject>(EGPUBufferBindTarget::SHADER_BUFFER_STORAGE);
    mStrokesBuffer->SetData(nullptr, 16 * sizeof(stroke_t), EGPUBufferFlags::DYNAMIC_STORAGE);
    mStrokesBuffer->BindShaderStorage(EBlockBinding::strokes_buffer);

    // SDF Lut texture
    TGPUTextureConfig lSdfLutConfig;
    lSdfLutConfig.mTarget = ETexTarget::TEXTURE_3D;
    lSdfLutConfig.mExtentX = LUT_RES;
    lSdfLutConfig.mExtentY = LUT_RES;
    lSdfLutConfig.mSlices = LUT_RES;
    lSdfLutConfig.mFormat = ETexFormat::RGBA8;
    lSdfLutConfig.mMinFilter = ETexFilter::LINEAR;
    lSdfLutConfig.mMagFilter = ETexFilter::LINEAR;
    lSdfLutConfig.mWrapS = ETexWrap::CLAMP_TO_EDGE;
    lSdfLutConfig.mWrapT = ETexWrap::CLAMP_TO_EDGE;
    lSdfLutConfig.mWrapR = ETexWrap::CLAMP_TO_EDGE;
    lSdfLutConfig.mMips = 1;
    mSdfLut = std::make_shared<CGPUTexture>(lSdfLutConfig);

    // SDF Atlas buffer
    TGPUTextureConfig lSdfAtlasConfig;
    lSdfAtlasConfig.mTarget = ETexTarget::TEXTURE_3D;
    lSdfAtlasConfig.mExtentX = 1024;
    lSdfAtlasConfig.mExtentY = 1024;
    lSdfAtlasConfig.mSlices = 256;
    lSdfAtlasConfig.mFormat = ETexFormat::R8;
    lSdfAtlasConfig.mMinFilter = ETexFilter::LINEAR;
    lSdfAtlasConfig.mMagFilter = ETexFilter::LINEAR;
    lSdfAtlasConfig.mWrapS = ETexWrap::CLAMP_TO_EDGE;
    lSdfAtlasConfig.mWrapT = ETexWrap::CLAMP_TO_EDGE;
    lSdfAtlasConfig.mWrapR = ETexWrap::CLAMP_TO_EDGE;
    lSdfAtlasConfig.mMips = 1;
    mSdfAtlas = std::make_shared<CGPUTexture>(lSdfAtlasConfig);

    // Slot list buffer
    mSlotListBuffer = std::make_shared<CGPUBufferObject>(EGPUBufferBindTarget::SHADER_BUFFER_STORAGE);
    size_t lListSize = size_t(lSdfLutConfig.mExtentX) * 
                       size_t(lSdfLutConfig.mExtentY) * 
                       size_t(lSdfLutConfig.mSlices) * 
                       sizeof(uint32_t);
    mSlotListBuffer->SetData(nullptr, lListSize, EGPUBufferFlags::DYNAMIC_STORAGE);
    mSlotListBuffer->BindShaderStorage(EBlockBinding::slot_list_buffer);

    // Atomic Counter buffer
    mSlotCounterBuffer = std::make_shared<CGPUBufferObject>(EGPUBufferBindTarget::SHADER_BUFFER_STORAGE);
    mSlotCounterBuffer->SetData(nullptr, sizeof(uint32_t) * 3, EGPUBufferFlags::DYNAMIC_STORAGE);
    mSlotCounterBuffer->BindShaderStorage(EBlockBinding::slot_count_buffer);

    // View Buffer
    mViewBuffer = std::make_shared<CGPUBufferObject>(EGPUBufferBindTarget::UNIFORM_BUFFER);
    mViewBuffer->SetData(nullptr, sizeof(TViewData), EGPUBufferFlags::DYNAMIC_STORAGE);
    mViewBuffer->BindUniformBuffer(EBlockBinding::view);

    // Material Buffer
    mMaterialBuffer = std::make_shared<CGPUBufferObject>(EGPUBufferBindTarget::UNIFORM_BUFFER);
    mMaterialBuffer->SetData(nullptr, sizeof(TGlobalMaterialBufferData), EGPUBufferFlags::DYNAMIC_STORAGE);
    mMaterialBuffer->BindUniformBuffer(EBlockBinding::global_material);


    // Default 8x8 white roughness texture in case nothing is specified in shading settings.
    /*uint8_t* lTempTex8x8 = (uint8_t*)::malloc(8*8);
    for (int i = 0; i < 8 * 8; ++i)
    {
        lTempTex8x8[i] = 0xFF;
    }
    SetRoughnessMap(8, 8, lTempTex8x8);
    ::free(lTempTex8x8);
    */
    
    // TODO: make this selectable in shading settings
    sbx::TTexture lRoughMap;
    sbx::texutil::LoadFromFile("./Textures/roughness.png", lRoughMap, true);
    SetRoughnessMap(lRoughMap.mWidth, lRoughMap.mHeight, lRoughMap.AsR8Buffer());
    

    // Bayer dithering
	// https://www.anisopteragames.com/how-to-fix-color-banding-with-dithering/
    {
        static const char lBayerDitheringPattern[] = {
        0, 32,  8, 40,  2, 34, 10, 42,   /* 8x8 Bayer ordered dithering  */
        48, 16, 56, 24, 50, 18, 58, 26,  /* pattern.  Each input pixel   */
        12, 44,  4, 36, 14, 46,  6, 38,  /* is scaled to the 0..63 range */
        60, 28, 52, 20, 62, 30, 54, 22,  /* before looking in this table */
        3, 35, 11, 43,  1, 33,  9, 41,   /* to determine the action.     */
        51, 19, 59, 27, 49, 17, 57, 25,
        15, 47,  7, 39, 13, 45,  5, 37,
        63, 31, 55, 23, 61, 29, 53, 21 };
        
        TGPUTextureConfig lBayerDitheringTexConfig;
        lBayerDitheringTexConfig.mTarget = ETexTarget::TEXTURE_2D;
        lBayerDitheringTexConfig.mExtentX = 8;
        lBayerDitheringTexConfig.mExtentY = 8;
        lBayerDitheringTexConfig.mSlices = 1;
        lBayerDitheringTexConfig.mFormat = ETexFormat::R8;
        lBayerDitheringTexConfig.mMinFilter = ETexFilter::LINEAR;
        lBayerDitheringTexConfig.mMagFilter = ETexFilter::LINEAR;
        lBayerDitheringTexConfig.mWrapS = ETexWrap::REPEAT;
        lBayerDitheringTexConfig.mWrapT = ETexWrap::REPEAT;
        lBayerDitheringTexConfig.mMips = 1 + uint32_t(glm::floor(glm::log2(glm::max(float(8), float(8)))));
        mDitheringMap = std::make_shared<CGPUTexture>(lBayerDitheringTexConfig);
        mDitheringMap->UpdateData(lBayerDitheringPattern);

    }

    // Box Geometry
    std::vector<SVertex> lVertices =
    {
        {glm::vec3(-1.0f, -1.0f, -1.0f)},
        {glm::vec3(-1.0f, +1.0f, -1.0f)},
        {glm::vec3(+1.0f, +1.0f, -1.0f)},
        {glm::vec3(+1.0f, -1.0f, -1.0f)},
        {glm::vec3(-1.0f, -1.0f, +1.0f)},
        {glm::vec3(-1.0f, +1.0f, +1.0f)},
        {glm::vec3(+1.0f, +1.0f, +1.0f)},
        {glm::vec3(+1.0f, -1.0f, +1.0f)}
    };

    std::vector <std::uint16_t> lIndices = 
    {
        // front face
        0, 1, 2,
        0, 2, 3,
        // back face
        4, 6, 5,
        4, 7, 6,
        // left face
        4, 5, 1,
        4, 1, 0,
        // right face
        3, 2, 6,
        3, 6, 7,
        // top face
        1, 5, 6,
        1, 6, 2,
        // bottom face
        4, 0, 3,
        4, 3, 7
    };

    mBoxGeometry = std::make_shared<CGPUGeometry>();
    mBoxGeometry->SetData(lVertices.data(), lVertices.size() * sizeof(SVertex),
        lIndices.data(), lIndices.size() * sizeof(std::uint16_t));
}

void CRenderer::Shutdown()
{
    glDeleteVertexArrays(1, &mDummyVAO);
}

void CRenderer::SetRoughnessMap(uint32_t aWidth, uint32_t aHeight, void* aData)
{
    TGPUTextureConfig lRoughnessTexConfig;
    lRoughnessTexConfig.mTarget = ETexTarget::TEXTURE_2D;
    lRoughnessTexConfig.mExtentX = aWidth;
    lRoughnessTexConfig.mExtentY = aHeight;
    lRoughnessTexConfig.mSlices = 1;
    lRoughnessTexConfig.mFormat = ETexFormat::R8;
    lRoughnessTexConfig.mMinFilter = ETexFilter::LINEAR;
    lRoughnessTexConfig.mMagFilter = ETexFilter::LINEAR;
    lRoughnessTexConfig.mWrapS = ETexWrap::REPEAT;
    lRoughnessTexConfig.mWrapT = ETexWrap::REPEAT;
    lRoughnessTexConfig.mMips = 1 + uint32_t(glm::floor(glm::log2(glm::max(float(aWidth), float(aHeight)))));
    mRoughnessMap = std::make_shared<CGPUTexture>(lRoughnessTexConfig);
    mRoughnessMap->UpdateData(aData);
}

void CRenderer::ReloadShaders()
{
    SBX_LOG("Loading shaders...");

    // Shared SDF code
    CShaderCodeRef lSdfCommonCode = std::make_shared<std::vector<char>>(std::move(ReadFile("./Shaders/SdfCommon.h.glsl")));
    
    // Compute lut shader program
    {
        CShaderCodeRef lComputeLutCode = std::make_shared<std::vector<char>>(std::move(ReadFile("./Shaders/ComputeSdfLut.comp.glsl")));
        mComputeLutProgram = std::make_shared<CGPUShaderProgram>(CShaderCodeRefList{ lSdfCommonCode, lComputeLutCode }, EShaderSourceType::COMPUTE_SHADER, "ComputeLut");
        mComputeLutPipeline = std::make_shared<CGPUShaderPipeline>(std::vector<CGPUShaderProgramRef>{ mComputeLutProgram });
    }

    // Compute atlas shader program
    {
        CShaderCodeRef lComputeAtlasCode = std::make_shared<std::vector<char>>(std::move(ReadFile("./Shaders/ComputeSdfAtlas.comp.glsl")));
        mComputeAtlasProgram = std::make_shared<CGPUShaderProgram>(CShaderCodeRefList{ lSdfCommonCode, lComputeAtlasCode }, EShaderSourceType::COMPUTE_SHADER, "ComputeAtlas");
        mComputeAtlasPipeline = std::make_shared<CGPUShaderPipeline>(std::vector<CGPUShaderProgramRef>{ mComputeAtlasProgram });
    }

    // Draw on screen shader program
    {
        CShaderCodeRef lScreenQuadVSCode = std::make_shared<std::vector<char>>(std::move(ReadFile("./Shaders/FullScreenTrinagle.vert.glsl")));
        CShaderCodeRef lColorFSCode = std::make_shared<std::vector<char>>(std::move(ReadFile("./Shaders/Color.frag.glsl")));
        mFullscreenVertexProgram = std::make_shared<CGPUShaderProgram>(CShaderCodeRefList{ lScreenQuadVSCode }, EShaderSourceType::VERTEX_SHADER, "ScreenQuadVS");
        mColorFragmentProgram = std::make_shared<CGPUShaderProgram>(CShaderCodeRefList{ lSdfCommonCode, lColorFSCode }, EShaderSourceType::FRAGMENT_SHADER, "BaseFragmentFS");
        std::vector<CGPUShaderProgramRef> lPrograms = { mFullscreenVertexProgram, mColorFragmentProgram };
        mScreenQuadPipeline = std::make_shared<CGPUShaderPipeline>(lPrograms);

        glProgramUniform1i(mColorFragmentProgram->GetHandler(), EUniformLoc::uRoughnessMap, ETexBinding::uRoughnessMap);
        glProgramUniform1i(mColorFragmentProgram->GetHandler(), EUniformLoc::uDitheringMap, ETexBinding::uDitheringMap);
    }

    // Draw mesh program
    {
        CShaderCodeRef lMeshVertexCode = std::make_shared<std::vector<char>>(std::move(ReadFile("./Shaders/MeshBasePass.vert.glsl")));
        CShaderCodeRef lMeshFragmentCode = std::make_shared<std::vector<char>>(std::move(ReadFile("./Shaders/MeshBasePass.frag.glsl")));
        mMeshVertexProgram = std::make_shared<CGPUShaderProgram>(CShaderCodeRefList{ lMeshVertexCode }, EShaderSourceType::VERTEX_SHADER, "MeshBasePassVS");
        mMeshFragmentProgram = std::make_shared<CGPUShaderProgram>(CShaderCodeRefList{ lSdfCommonCode, lMeshFragmentCode }, EShaderSourceType::FRAGMENT_SHADER, "MeshBasePassFS");
        std::vector<CGPUShaderProgramRef> lPrograms = { mMeshVertexProgram, mMeshFragmentProgram };
        mDrawMeshPipeline = std::make_shared<CGPUShaderPipeline>(lPrograms);

        glProgramUniform1i(mMeshFragmentProgram->GetHandler(), EUniformLoc::uRoughnessMap, ETexBinding::uRoughnessMap);
        glProgramUniform1i(mMeshFragmentProgram->GetHandler(), EUniformLoc::uDitheringMap, ETexBinding::uDitheringMap);
    }

    // Static uniforms
    const std::vector<uint32_t> lProgramHandlers
    {
        mComputeLutProgram->GetHandler(),
        mComputeAtlasProgram->GetHandler(),
        mColorFragmentProgram->GetHandler(),
        mMeshFragmentProgram->GetHandler(),
    };

    for (uint32_t lHandler : lProgramHandlers)
    {
        glProgramUniform1ui(lHandler, EUniformLoc::uMaxSlotsCount, 491520);
        float lVoxelExt = VOXEL_EXTENT;
        float lLutSize = float(LUT_RES);
        glProgramUniform4f(lHandler, EUniformLoc::uVoxelSide, lVoxelExt, 1.0f / lVoxelExt, lVoxelExt / 8.0f, 1.0f / (lVoxelExt / 8.0f));
        glProgramUniform4f(lHandler, EUniformLoc::uVolumeExtent, lLutSize, 1.0f / lLutSize, 0.0f, 0.0f);
        glProgramUniform1i(lHandler, EUniformLoc::uSdfLutTexture, ETexBinding::uSdfLut);
        glProgramUniform1i(lHandler, EUniformLoc::uSdfAtlasTexture, ETexBinding::uSdfAtlas);
    }
}

void CRenderer::UpdateSceneData(CScene const& aScene)
{
    if (aScene.IsDirty())
    {
        size_t lSizeBytes = aScene.mStrokesArray.size() * sizeof(stroke_t);

        if (lSizeBytes > mStrokesBuffer->GetStorageSize())
        {
            mStrokesBuffer = std::make_shared<CGPUBufferObject>(EGPUBufferBindTarget::SHADER_BUFFER_STORAGE);
            mStrokesBuffer->SetData(nullptr, lSizeBytes + (16 * sizeof(stroke_t)), EGPUBufferFlags::DYNAMIC_STORAGE);
            mStrokesBuffer->BindShaderStorage(EBlockBinding::strokes_buffer);
        }

        //stroke_t* lStrokesBufferMappedMemory = (stroke_t*)mStrokesBuffer->Map();
        for (size_t i = 0; i < aScene.mStrokesArray.size(); i++)
        {
            //::memcpy(lStrokesBufferMappedMemory + i, (void*)&aScene.mStrokesArray[i], sizeof(stroke_t));
            mStrokesBuffer->UpdateSubData(sizeof(stroke_t) * i, (void*)&aScene.mStrokesArray[i], sizeof(stroke_t));
        }
        //mStrokesBuffer->Unmap();

        const std::vector<uint32_t> lProgramHandlers
        {
            mComputeLutProgram->GetHandler(),
            mComputeAtlasProgram->GetHandler(),
            mColorFragmentProgram->GetHandler()
        };

        for (uint32_t lHandler : lProgramHandlers)
        {
            glProgramUniform1ui(lHandler, EUniformLoc::uStrokesNum, aScene.mStrokesArray.size() & 0xFFFFFFFF);
        }

        // clear slot count
        const static uint32_t sZero[] = { 0, 1, 1 };
        mSlotCounterBuffer->UpdateSubData(0, (void*)sZero, sizeof(uint32_t) * 3);

        // Execute compute lut
        mComputeLutPipeline->Bind();
        mSdfLut->BindImage(0, 0, EImgAccess::WRITE_ONLY);
        const uint32_t dispatchRes = LUT_RES / 8;
        glDispatchCompute(dispatchRes, dispatchRes, dispatchRes);
        
        // Execute compute atlas
        mComputeAtlasPipeline->Bind();
        mSlotCounterBuffer->BindTarget(EGPUBufferBindTarget::DISPATCH_INDIRECT_BUFFER);
        mSdfAtlas->BindImage(0, 0, EImgAccess::WRITE_ONLY);
        glDispatchComputeIndirect(0);
        mSlotCounterBuffer->UnbindTarget(EGPUBufferBindTarget::DISPATCH_INDIRECT_BUFFER);
    }

    if (aScene.IsMaterialDirty())
    {
        mMaterialBuffer->UpdateSubData(0, (void*)&aScene.mGlobalMaterial, sizeof(TGlobalMaterialBufferData));
    }

    //Update Matrix
    TViewData lViewData;
    lViewData.mProjectionMatrix = aScene.mCamera.GetProjectionMatrix();
    lViewData.mViewMatrix = aScene.mCamera.GetViewMatrix();
    mViewBuffer->UpdateSubData(0, (void*)&lViewData, sizeof(TViewData));

    glm::mat4 lProjection = aScene.mCamera.GetProjectionMatrix(); //glm::perspective(aScene.mCamera.mFOV, aScene.mCamera.mAspect, 0.1f, 100.0f);
    glm::mat4 lView = aScene.mCamera.GetViewMatrix(); //glm::lookAt(aScene.mCamera.mOrigin, aScene.mCamera.mLookAt, aScene.mCamera.mViewUp);
    //lProjection[1][1] *= -1; // Remember to do this in Vulkan
    //glm::mat4 lViewProjection = lProjection * lView;
    //glm::mat4 lInverseViewProjection = glm::inverse(lViewProjection);

    // Update program data
    //glProgramUniformMatrix4fv(mFullscreenVertexProgram->GetHandler(), 0, 1, false, glm::value_ptr(lInverseViewProjection));
    //glProgramUniformMatrix4fv(mFullscreenVertexProgram->GetHandler(), EUniformLoc::uViewMatrix, 1, false, glm::value_ptr(lView));
    //glProgramUniformMatrix4fv(mFullscreenVertexProgram->GetHandler(), EUniformLoc::uProjectionMatrix, 1, false, glm::value_ptr(lProjection));
    glProgramUniform4i(mColorFragmentProgram->GetHandler(), EUniformLoc::uVoxelPreview, aScene.mUseVoxels ? 1 : 0, aScene.mPreviewSlice, 0, 0);

#if DEBUG
    ETexFilter::Type lLutFilters = (aScene.mLutNearestFilter) ? ETexFilter::NEAREST : ETexFilter::LINEAR;
    mSdfLut->SetFilters(lLutFilters, lLutFilters);
    ETexFilter::Type lAtlasFilters = (aScene.mAtlasNearestFilter) ? ETexFilter::NEAREST : ETexFilter::LINEAR;
    mSdfAtlas->SetFilters(lAtlasFilters, lAtlasFilters);
#endif
}

void CRenderer::RenderFrame()
{
    glfwGetFramebufferSize(glfwGetCurrentContext(), &mViewWidth, &mViewHeight);

    glViewport(0, 0, mViewWidth, mViewHeight);
    //glClearColor(0.45f, 0.55f, 0.60f, 1.00f);
    glClearColor(0.237f, 0.237f, 0.267f, 1.00f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    mSdfLut->BindTexture(ETexBinding::uSdfLut);
    mSdfAtlas->BindTexture(ETexBinding::uSdfAtlas);
    mRoughnessMap->BindTexture(ETexBinding::uRoughnessMap);
    mDitheringMap->BindTexture(ETexBinding::uDitheringMap);
    
    // Draw full screen quad
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDepthMask(GL_FALSE);
    glBindVertexArray(mDummyVAO);
    mScreenQuadPipeline->Bind();
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glBindVertexArray(0);
    glDepthMask(GL_TRUE);

    // Draw mesh
    glEnable(GL_DEPTH_TEST);
    
    //glFrontFace(GL_CCW);
    mDrawMeshPipeline->Bind();
    mBoxGeometry->Draw(1);
    //glFrontFace(GL_CW);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);
}