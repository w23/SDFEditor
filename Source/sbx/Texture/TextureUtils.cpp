/*
 * @file    CTextureUtils.cpp
 * @author  David Gallardo Moreno
 */

#include "TextureUtils.h"

#include <sbx/Core/ErrorHandling.h>

#include <fstream>
#include <sstream>

#   define STB_IMAGE_IMPLEMENTATION
#   include <stb/stb_image.h>

#   define STB_IMAGE_WRITE_IMPLEMENTATION
#   include <stb/stb_image_write.h>

//#include <DataStructures/CRawBuffer.h>

namespace sbx { namespace texutil
{
    bool IsHDR(std::string const& aPath)
    {
        return stbi_is_hdr(aPath.c_str());
    }

    void LoadFromFile(std::string const& aPath, TTexture& aTexture, bool aGray)
    {
        int32_t lWidth = 0, lHeight = 0, lComponents = 0;
        if (IsHDR(aPath))
        {
            float* lTextureBuffer = stbi_loadf(aPath.c_str(), &lWidth, &lHeight, &lComponents, 4);
            if (lTextureBuffer)
            {
                aTexture.Init(lWidth, lHeight, 1, ETextureFormat::RGBA32F);
                ::memcpy(aTexture.mBuffer.GetByteArray(), lTextureBuffer, lWidth * lHeight * sizeof(TColor32F));
                stbi_image_free(lTextureBuffer);
            }
        }
        else
        {
            uint32_t lComps = (aGray) ? 1 : 4;
            ETextureFormat::Type lFormat = (aGray) ? ETextureFormat::R8 : ETextureFormat::RGBA8;

            uint8_t* lTextureBuffer = stbi_load(aPath.c_str(), &lWidth, &lHeight, &lComponents, lComps);
            if (lTextureBuffer)
            {
                aTexture.Init(lWidth, lHeight, 1, lFormat);
                ::memcpy(aTexture.mBuffer.GetByteArray(), lTextureBuffer, lWidth * lHeight * lComps);
                stbi_image_free(lTextureBuffer);
            }
        }
    }

    void SaveToFile(std::string const& aPath, ETextureFileType aFileType, TTextureView const& aTextureView)
    {
        SBX_ASSERT(aTextureView.mTexture);

        const TTexture& lTexture = *aTextureView.mTexture;
        const int32_t lSlice = aTextureView.mSlice;

        switch (aFileType)
        {
        case ETextureFileType::PNG:
            stbi_write_png(aPath.c_str(), lTexture.mWidth, lTexture.mHeight, lTexture.GetComponents(), lTexture.AsR8Buffer() + (lTexture.mWidth * lTexture.mHeight * lSlice * lTexture.GetComponents()), 0);
            break;
        case ETextureFileType::TGA:
            stbi_write_tga(aPath.c_str(), lTexture.mWidth, lTexture.mHeight, 4, lTexture.AsRGBA8Buffer() + (lTexture.mWidth * lTexture.mHeight * lSlice));
            break;
        case ETextureFileType::HDR:
            stbi_write_hdr(aPath.c_str(), lTexture.mWidth, lTexture.mHeight, 4, (float*)(lTexture.AsRGBA32FBuffer() + (lTexture.mWidth * lTexture.mHeight * lSlice)));
            break;
        default:
            SBX_ERROR("[CTextureUtils::SaveToFile] Invalid texture file type.");
        }
    }

    bool StoreTexturePack(std::string const& aPath, std::vector< TTexture > const& aTexturePack)
    {
        std::ofstream lOutput(aPath, std::ios::binary);

        uint8_t lNumTextures = aTexturePack.size() & 0xFF;
        lOutput.write((char*)&lNumTextures, sizeof(uint8_t));

        for (uint32_t iTextureIndex = 0; iTextureIndex < aTexturePack.size(); iTextureIndex++)
        {
            const TTexture& lTexture = aTexturePack[iTextureIndex];
            uint32_t lTexWidth = lTexture.mWidth;
            lOutput.write((char*)&lTexWidth, sizeof(uint32_t));

            uint32_t lTexHeight = lTexture.mHeight;
            lOutput.write((char*)&lTexHeight, sizeof(uint32_t));

            uint32_t lTexSlices = lTexture.mSlices;
            lOutput.write((char*)&lTexSlices, sizeof(uint32_t));

            uint32_t lTexFormat = lTexture.mFormat;
            lOutput.write((char*)&lTexFormat, sizeof(uint32_t));

            uint64_t lBufferSize = lTexture.GetSliceSize() * lTexture.mSlices;
            lOutput.write((char*)&lBufferSize, sizeof(uint64_t));

            //write all texture
            lOutput.write((char*)lTexture.mBuffer.GetByteArray(), lBufferSize);
        }

        char lEnd = 0;
        lOutput.write(&lEnd, sizeof(char));
        lOutput.close();

        return true;
    }

    bool LoadTexturePack(std::string const& aPath, std::vector< TTexture >& aTexturePack)
    {
        //aTexturePack.clear();
        std::ifstream lInput(aPath, std::ios::binary);
        if (lInput.good())
        {
            uint8_t lTexNum = 0;
            lInput.read((char*)&lTexNum, sizeof(uint8_t));

            for (int32_t iTextureIndex = 0; iTextureIndex < lTexNum; iTextureIndex++)
            {
                uint32_t lTexWidth = 0;
                lInput.read((char*)&lTexWidth, sizeof(uint32_t));

                uint32_t lTexHeight = 0;
                lInput.read((char*)&lTexHeight, sizeof(uint32_t));

                uint32_t lTexSlices = 0;
                lInput.read((char*)&lTexSlices, sizeof(uint32_t));

                uint32_t lTexFormat = 0;
                lInput.read((char*)&lTexFormat, sizeof(uint32_t));

                uint64_t lBufferSize = 0;
                lInput.read((char*)&lBufferSize, sizeof(uint64_t));

                aTexturePack.emplace_back();
                TTexture& lTexture = aTexturePack.back();
                lTexture.Init(lTexWidth, lTexHeight, lTexSlices, ETextureFormat::Type(lTexFormat));

                //Read all the texture
                lInput.read((char*)lTexture.mBuffer.GetByteArray(), lBufferSize);
            }

            lInput.close();
            return true;
        }

        lInput.close();
        return false;
    }
}} // sbx::TextureUtils
