/*
 * @file    CTextureUtils.h
 * @author  David Gallardo Moreno
 */

#ifndef _SBX_TEXTURE_UTILS_H_
#define _SBX_TEXTURE_UTILS_H_

#include <sbx/Texture/Texture.h>
#include <string>
#include <vector>

namespace sbx
{
    enum class ETextureFileType
    {
        PNG,
        TGA,
        HDR,
        JPEG
    };

    namespace texutil
    {
        bool IsHDR           (std::string const & aPath);
        void LoadFromFile    (std::string const & aPath, TTexture & aTexture, bool aGray);
        void SaveToFile      (std::string const & aPath, ETextureFileType aFileType, TTextureView const & aTextureView);
             
        bool StoreTexturePack    (std::string const & aPath, std::vector< TTexture > const & aTexturePack);
        bool LoadTexturePack     (std::string const & aPath, std::vector< TTexture > & aTexturePack);
    }
};

#endif // _SBX_TEXTURE_UTILS_H_