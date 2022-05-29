// Copyright (c) 2022 David Gallardo and SDFEditor Project

#pragma once

#include <cstdint>
#include "SDFEditor/GPU/GPUShader.h"
#include "SDFEditor/GPU/GPUStorageBuffer.h"
#include "SDFEditor/GPU/GPUTexture.h"
#include "SDFEditor/GPU/GPUGeometry.h"

#include <glm/glm.hpp>

class CRenderer
{
public:
    void Init();
    void Shutdown();
    void SetRoughnessMap(uint32_t aWidth, uint32_t aHeight, void* aData);
    void ReloadShaders();
    void UpdateSceneData(class CScene const& aScene);
    void RenderFrame();

    CGPUBufferObjectRef GetStrokesBufferRef() { return mStrokesBuffer; }

private:
    // View data
    int32_t mViewWidth;
    int32_t mViewHeight;

    // Compute Voxel SDFs
    CGPUShaderProgramRef mComputeLutProgram;
    CGPUShaderPipelineRef mComputeLutPipeline;
    CGPUShaderProgramRef mComputeAtlasProgram;
    CGPUShaderPipelineRef mComputeAtlasPipeline;
    CGPUTextureRef mSdfLut;
    CGPUTextureRef mSdfAtlas;
    CGPUBufferObjectRef mStrokesBuffer;
    CGPUBufferObjectRef mSlotListBuffer;
    CGPUBufferObjectRef mSlotCounterBuffer;

    // Render full screen quad
    uint32_t mDummyVAO;
    CGPUShaderProgramRef mFullscreenVertexProgram;
    CGPUShaderProgramRef mColorFragmentProgram;
    CGPUShaderPipelineRef mScreenQuadPipeline;
    CGPUBufferObjectRef mViewBuffer;
    CGPUBufferObjectRef mMaterialBuffer;
    CGPUTextureRef mRoughnessMap;
    CGPUTextureRef mDitheringMap;

    // Render box
    CGPUGeometryRef mBoxGeometry;
    CGPUShaderProgramRef mMeshVertexProgram;
    CGPUShaderProgramRef mMeshFragmentProgram;
    CGPUShaderPipelineRef mDrawMeshPipeline;
    

   
};