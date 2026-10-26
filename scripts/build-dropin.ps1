$ErrorActionPreference='Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
& (Join-Path $PSScriptRoot 'generate-build-profiles.ps1')
if(!$?){throw 'Verified build profile generation failed'}
$inputs=[ordered]@{}
foreach($file in @('configs/editor-builds.json','src/generated-build-profiles.h','src/dropin.cpp','src/bridge.cpp','src/dropin.def')){
 $inputs[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
}
$vs=& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'Visual Studio C++ x64 build tools required'}
New-Item -ItemType Directory -Force build/dropin,drop-in | Out-Null
$vc=Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
$line='@call "'+$vc+'" >nul'+"`r`n"+'@cl /nologo /std:c++17 /EHsc /utf-8 /LD /O2 /W4 /DNDEBUG /MT src\dropin.cpp /Fe:build\dropin\window_size_plugin.dll /Fo:build\dropin\dropin.obj /link /DEF:src\dropin.def advapi32.lib bcrypt.lib'
Set-Content -LiteralPath build/dropin/build.cmd -Value $line -Encoding utf8
& cmd.exe /c build\dropin\build.cmd
if($LASTEXITCODE){throw 'Native drop-in compilation failed'}
Copy-Item -LiteralPath build/dropin/window_size_plugin.dll -Destination drop-in/window_size_plugin.dll -Force
$hash=(Get-FileHash -LiteralPath drop-in/window_size_plugin.dll -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath drop-in/SHA256.txt -Value ($hash+'  window_size_plugin.dll') -Encoding ascii
foreach($file in $inputs.Keys){
 if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $inputs[$file]){throw "Build input changed during compilation: $file. Rebuild before packaging."}
}
@{schema_version=1;dll_sha256=$hash;inputs=$inputs}|ConvertTo-Json -Depth 4|
 Set-Content -LiteralPath build/dropin/build-info.json -Encoding utf8
Write-Output "Built drop-in/window_size_plugin.dll (SHA256: $hash)"
