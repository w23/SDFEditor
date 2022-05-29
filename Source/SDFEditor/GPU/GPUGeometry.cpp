
#include "GPUGeometry.h"

#include "ThirdParty/glad/glad.h"

CGPUGeometry::CGPUGeometry()
    : mNumVertices(0)
    , mNumIndices(0)
{
    glGenVertexArrays(1, &mVAOHandle);
    glGenBuffers(1, &mVBOHandle);
    glGenBuffers(1, &mEBOHandle);
}

void CGPUGeometry::SetData(void* aVertexData, size_t aVertexDataSize, void* aIndexData, size_t aIndexDataSize)
{
    mNumVertices = (aVertexDataSize / sizeof(SVertex)) & 0xFFFFFFFF;
    mNumIndices = (aIndexDataSize / sizeof(std::uint16_t)) & 0xFFFFFFFF;

    glBindVertexArray(mVAOHandle);
    glBindBuffer(GL_ARRAY_BUFFER, mVBOHandle);

    glBufferData(GL_ARRAY_BUFFER, aVertexDataSize, aVertexData, GL_STATIC_DRAW);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, mEBOHandle);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, aIndexDataSize, aIndexData, GL_STATIC_DRAW);

    // vertex positions
    // TODO: make configurable
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(SVertex), (void*)0);

    glBindVertexArray(0);
}

void CGPUGeometry::Draw(uint32_t aInstances)
{
    glBindVertexArray(mVAOHandle);
    glDrawElementsInstanced(GL_TRIANGLES, mNumIndices, GL_UNSIGNED_SHORT, 0, aInstances);
    glBindVertexArray(0);
}
