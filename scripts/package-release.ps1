param([ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version='0.1.0')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$payload=Join-Path $projectRoot 'drop-in\window_size_plugin.dll'
$hash=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.ToLowerInvariant()
$expected=(Get-Content -LiteralPath (Join-Path $projectRoot 'drop-in\SHA256.txt') -Raw).Trim().Split(' ')[0]
if($hash -ne $expected){throw 'Build payload hash mismatch. Run build-dropin.ps1 first.'}
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
}
foreach($name in $files.Keys){Copy-Item -LiteralPath $files[$name] -Destination (Join-Path $package $name) -Force}
$revision=(& git -C $projectRoot rev-parse HEAD).Trim()
if($LASTEXITCODE){throw 'Source revision is unavailable'}
$manifest=@{version=$Version;protocol=2;platform='Windows x64';editor_version='2.13.0';source_commit=$revision;dll_sha256=$hash}
$manifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $package 'release.json') -Encoding utf8
$archive=Join-Path $releaseRoot "AIVoice2-Bridge-$Version-win-x64.zip"
$entries=@($files.Keys|ForEach-Object {Join-Path $package $_}) + @(Join-Path $package 'release.json')
Compress-Archive -LiteralPath $entries -DestinationPath $archive -Force
$standalone=Join-Path $releaseRoot 'window_size_plugin.dll'
Copy-Item -LiteralPath $payload -Destination $standalone -Force
@($archive,$standalone)|ForEach-Object {((Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant())+'  '+[IO.Path]::GetFileName($_)}|
 Set-Content -LiteralPath (Join-Path $releaseRoot 'SHA256SUMS.txt') -Encoding ascii
Write-Output "Release files: $releaseRoot"
