param(
 [string]$EditorRoot='C:\Program Files\AI\AIVoice2\AIVoice2Editor',
 [string]$OutFile
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$config=Join-Path $projectRoot 'configs\editor-builds.json'
if(!(Test-Path -LiteralPath $config)){$config=Join-Path $PSScriptRoot 'editor-builds.json'}
$profiles=if(Test-Path -LiteralPath $config){Get-Content -LiteralPath $config -Raw|ConvertFrom-Json}else{$null}
$root=(Resolve-Path -LiteralPath $EditorRoot).Path
$relativeFiles=@('aivoice.exe','data/app.so','Lib/AITalk/aitalk_engine.dll','window_size_plugin.dll','aivoice2_window_size_original.dll')
$hashes=@{}
$records=@(foreach($relative in $relativeFiles){
 $filePath=Join-Path $root $relative
 if(!(Test-Path -LiteralPath $filePath -PathType Leaf)){[ordered]@{file=$relative;missing=$true};continue}
 $file=Get-Item -LiteralPath $filePath
 $digest=(Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
 $hashes[$relative]=$digest
 [ordered]@{file=$relative;bytes=$file.Length;file_version=$file.VersionInfo.FileVersion;product_version=$file.VersionInfo.ProductVersion;sha256=$digest}
})
$matches=@(if($profiles){foreach($profile in $profiles.verified_builds){
 $coreMatch=$true
 foreach($name in @('aivoice.exe','data/app.so','Lib/AITalk/aitalk_engine.dll')){if($hashes[$name] -ne $profile.files.$name){$coreMatch=$false}}
 $original=$profile.files.'window_size_plugin.dll'
 [ordered]@{id=$profile.id;editor_version=$profile.editor_version;core_files_match=$coreMatch;target_is_original=($hashes['window_size_plugin.dll'] -eq $original);backup_is_original=($hashes['aivoice2_window_size_original.dll'] -eq $original);complete_original_build_match=($coreMatch -and ($hashes['window_size_plugin.dll'] -eq $original -or $hashes['aivoice2_window_size_original.dll'] -eq $original))}
}})
$knownBridge=$profiles -and ($hashes['window_size_plugin.dll'] -in @($profiles.known_bridge_sha256))
$report=[ordered]@{schema_version=1;read_only=$true;files=$records;known_bridge_in_target=[bool]$knownBridge;verified_profile_comparisons=$matches;notes=@('No license data, voice library contents, registry secrets, or absolute user paths are collected.','No installer is run and no Editor file is modified.','An unrecognized original DLL hash alone does not establish ABI incompatibility or compatibility.')}
$json=$report|ConvertTo-Json -Depth 8
if($OutFile){[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile),$json+"`n",[Text.UTF8Encoding]::new($false))}
Write-Output $json
