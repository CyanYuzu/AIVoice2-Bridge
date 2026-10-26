param([ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version='0.1.1')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$payload=Join-Path $projectRoot 'drop-in\window_size_plugin.dll'
$hash=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.ToLowerInvariant()
$expected=(Get-Content -LiteralPath (Join-Path $projectRoot 'drop-in\SHA256.txt') -Raw).Trim().Split(' ')[0]
if($hash -ne $expected){throw 'Build payload hash mismatch. Run build-dropin.ps1 first.'}
& (Join-Path $PSScriptRoot 'generate-build-profiles.ps1') -Check
if(!$?){throw 'Embedded build profiles are stale.'}
$buildInfoPath=Join-Path $projectRoot 'build/dropin/build-info.json'
if(!(Test-Path -LiteralPath $buildInfoPath)){throw 'Build provenance is missing. Run build-dropin.ps1 first.'}
$buildInfo=Get-Content -LiteralPath $buildInfoPath -Raw|ConvertFrom-Json
if($buildInfo.schema_version -ne 1 -or $buildInfo.dll_sha256 -cne $hash){throw 'DLL does not match the recorded build. Run build-dropin.ps1 first.'}
foreach($inputFile in @('configs/editor-builds.json','src/generated-build-profiles.h','src/dropin.cpp','src/bridge.cpp','src/dropin.def')){
 $inputHash=(Get-FileHash -LiteralPath (Join-Path $projectRoot $inputFile) -Algorithm SHA256).Hash.ToLowerInvariant()
 if($inputHash -cne $buildInfo.inputs.$inputFile){throw "Build input changed: $inputFile. Rebuild the DLL before packaging."}
}
$releaseRoot=Join-Path $projectRoot "dist\releases\$Version"
$package=Join-Path $releaseRoot 'package'
New-Item -ItemType Directory -Path $package -Force | Out-Null
$files=@{
 'window_size_plugin.dll'=$payload
 'INSTALL.ps1'=(Join-Path $projectRoot 'drop-in\INSTALL.ps1')
 'SHA256.txt'=(Join-Path $projectRoot 'drop-in\SHA256.txt')
 'LICENSE.nlohmann-json.txt'=(Join-Path $projectRoot 'drop-in\LICENSE.nlohmann-json.txt')
 'README.md'=(Join-Path $projectRoot 'docs\INSTALLATION.md')
 'API.md'=(Join-Path $projectRoot 'drop-in\README.md')
 'editor-builds.json'=(Join-Path $projectRoot 'configs\editor-builds.json')
 'COLLECT-DIAGNOSTICS.ps1'=(Join-Path $projectRoot 'scripts\collect-editor-diagnostics.ps1')
}
foreach($name in $files.Keys){Copy-Item -LiteralPath $files[$name] -Destination (Join-Path $package $name) -Force}
$revision=(& git -C $projectRoot rev-parse HEAD).Trim()
if($LASTEXITCODE){throw 'Source revision is unavailable'}
$profiles=Get-Content -LiteralPath (Join-Path $projectRoot 'configs\editor-builds.json') -Raw|ConvertFrom-Json
$manifest=@{version=$Version;protocol=2;platform='Windows x64';editor_versions=@($profiles.verified_builds.editor_version|Select-Object -Unique);verified_build_ids=@($profiles.verified_builds.id);source_commit=$revision;dll_sha256=$hash;build_catalog_sha256=$buildInfo.inputs.'configs/editor-builds.json'}
$manifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $package 'release.json') -Encoding utf8
$archive=Join-Path $releaseRoot "AIVoice2-Bridge-$Version-win-x64.zip"
$entries=@($files.Keys|ForEach-Object {Join-Path $package $_}) + @(Join-Path $package 'release.json')
Compress-Archive -LiteralPath $entries -DestinationPath $archive -Force
$standalone=Join-Path $releaseRoot 'window_size_plugin.dll'
Copy-Item -LiteralPath $payload -Destination $standalone -Force
@($archive,$standalone)|ForEach-Object {((Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant())+'  '+[IO.Path]::GetFileName($_)}|
 Set-Content -LiteralPath (Join-Path $releaseRoot 'SHA256SUMS.txt') -Encoding ascii
Write-Output "Release files: $releaseRoot"
