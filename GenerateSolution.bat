mkdir Build
Xcopy .\Resources\resource.h .\Build\ /K /D /H /Y
Xcopy .\Resources\SDFEditor.rc .\Build\ /K /D /H /Y
Xcopy .\Resources\icon_1EB_icon.ico .\Build\ /K /D /H /Y
.\Tools\Premake\Windows\premake5.exe --file=SDFEditor_premake5.lua vs2019
pause
