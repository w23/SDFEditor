/*
 * @file    CRawBuffer.cpp
 * @author  David Gallardo Moreno
 */

#include "RawBuffer.h"

#include <stdlib.h>
#include <string.h>

namespace sbx
{
    CRawBuffer::CRawBuffer()
        : mByteArray(0)
        , mSize(0)
    {}

    CRawBuffer::CRawBuffer(size_t aSize, const void* aOtherByteArray)
        : mByteArray(0)
        , mSize(0)
    {
        Init(aSize, aOtherByteArray);
    }

    CRawBuffer::CRawBuffer(CRawBuffer const& aOtherRawBuffer)
        : mByteArray(0)
        , mSize(0)
    {
        Init(aOtherRawBuffer.mSize, aOtherRawBuffer.mByteArray);
    }

    CRawBuffer::CRawBuffer(CRawBuffer&& aOther)
        : mByteArray(aOther.mByteArray)
        , mSize(aOther.mSize)
    {
        aOther.mByteArray = nullptr;
        aOther.mSize = 0;
    }

    CRawBuffer& CRawBuffer::operator=(CRawBuffer const& aOtherRawBuffer)
    {
        Init(aOtherRawBuffer.mSize, aOtherRawBuffer.mByteArray);
        return *this;
    }

    CRawBuffer::~CRawBuffer()
    {
        if (mByteArray)
        {
            ::free(mByteArray);
            mByteArray = 0;
        }
    }

    void CRawBuffer::Init(size_t aSize, const void* aOtherByteArray)
    {
        if (0 != mByteArray)
        {
            ::free(mByteArray);
            mByteArray = 0;
        }

        mByteArray = reinterpret_cast<uint8_t*>(::malloc(aSize));
        mSize = aSize;
        if (0 != aOtherByteArray)
        {
            ::memcpy(mByteArray, aOtherByteArray, mSize);
        }
        else
        {
            ::memset(mByteArray, 0, mSize);
        }
    }

    void CRawBuffer::Realloc(size_t aSize)
    {
        if (aSize > mSize)
        {
            mSize = aSize;
            mByteArray = reinterpret_cast<uint8_t*>(::realloc(mByteArray, aSize));
        }
    }

} // sbx