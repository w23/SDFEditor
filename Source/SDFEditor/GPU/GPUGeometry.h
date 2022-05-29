
#pragma once

#include <cstdint>
#include <memory>
#include "glm/glm.hpp"

using CGPUGeometryRef = std::shared_ptr<class CGPUGeometry>;

struct SVertex
{
    glm::vec3 Position;
};

class CGPUGeometry
{
public:
    CGPUGeometry();
    void SetData(void* aVertexData, size_t aVertexDataSize, void* aIndexData, size_t aIndexDataSize);
    void Draw(uint32_t aInstances);
private:
    uint32_t mNumIndices;
    uint32_t mNumVertices;

    uint32_t mVAOHandle;
    uint32_t mVBOHandle;
    uint32_t mEBOHandle;
};
