/*
 * @file    CRawBuffer.h
 * @author  David Gallardo Moreno
 */

#ifndef _SBX_RAW_BUFFER_H_
#define _SBX_RAW_BUFFER_H_


#include <stdint.h>

namespace sbx
{    
    class CRawBuffer
    {
    public:
        CRawBuffer();
        CRawBuffer(size_t aSize, const void* aOtherByteArray = 0);
        CRawBuffer(CRawBuffer const& aOtherRawBuffer);
        CRawBuffer(CRawBuffer&& aOther);
        CRawBuffer& operator=(CRawBuffer const& aOtherRawBuffer);
        ~CRawBuffer();

        void Init(size_t aSize, const void* aOtherByteArray = 0);
        void Realloc(size_t aSize);

        uint8_t*        GetByteArray()          { return mByteArray;    }
        uint8_t*        GetByteArray() const    { return mByteArray;    }
        size_t          GetSize     () const    { return mSize;         }
    private:
        uint8_t* mByteArray;
        size_t   mSize;
    };
} // sbx

#endif // _SBX_RAW_BUFFER_H_