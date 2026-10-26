param([switch]$Check)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$source=Join-Path $projectRoot 'configs\editor-builds.json'
$destination=Join-Path $projectRoot 'src\generated-build-profiles.h'
$catalog=Get-Content -LiteralPath $source -Raw|ConvertFrom-Json
$files=@('aivoice.exe','data/app.so','Lib/AITalk/aitalk_engine.dll','window_size_plugin.dll')
if($catalog.schema_version -ne 1 -or @($catalog.verified_builds).Count -eq 0){throw 'Invalid verified build catalog'}
$ids=@{}
$fingerprints=@{}
$lines=[Collections.Generic.List[string]]::new()
$lines.Add('// Generated from configs/editor-builds.json. Run scripts/generate-build-profiles.ps1; do not edit.')
$lines.Add('#pragma once')
$lines.Add('#include <array>')
$lines.Add('namespace verified_builds {')
$lines.Add('struct Pin { const wchar_t* file; const char* sha256; };')
$lines.Add('struct Profile { const char* id; const char* editor_version; const char* abi_profile; std::array<Pin, 4> pins; };')
$lines.Add(('inline constexpr std::array<Profile, {0}> profiles{{{{' -f @($catalog.verified_builds).Count))
foreach($profile in $catalog.verified_builds){
 foreach($key in @('id','editor_version','abi_profile')){if($profile.$key -notmatch '^[A-Za-z0-9._-]+$'){throw "Invalid profile $key"}}
 if($ids.ContainsKey($profile.id)){throw 'Duplicate build profile id'}
 $ids[$profile.id]=$true
 if(@($profile.files.PSObject.Properties).Count -ne 4){throw 'Profiles must contain exactly four original files'}
 foreach($file in $files){if($profile.files.$file -cnotmatch '^[a-f0-9]{64}$'){throw "Invalid SHA-256 for $file"}}
 $fingerprint=($files|ForEach-Object {$profile.files.$_}) -join ':'
 if($fingerprints.ContainsKey($fingerprint)){throw 'Duplicate original-file fingerprint combination'}
 $fingerprints[$fingerprint]=$true
 $lines.Add(('    Profile{{"{0}", "{1}", "{2}", {{{{' -f $profile.id,$profile.editor_version,$profile.abi_profile))
 foreach($file in $files){
  $runtimePath=if($file -eq 'window_size_plugin.dll'){'aivoice2_window_size_original.dll'}else{$file}
  $lines.Add(('        Pin{{L"{0}", "{1}"}},' -f $runtimePath,$profile.files.$file))
 }
 $lines.Add('    }}},')
}
$lines.Add('}};')
$lines.Add('} // namespace verified_builds')
$expected=($lines -join "`n")+"`n"
if($Check){
 if(!(Test-Path -LiteralPath $destination) -or ([IO.File]::ReadAllText($destination).Replace("`r`n","`n") -cne $expected)){
  throw 'Generated build profiles are stale. Run scripts/generate-build-profiles.ps1.'
 }
 Write-Output 'Verified embedded build profiles match the source catalog.'
}else{
 [IO.File]::WriteAllText($destination,$expected,[Text.UTF8Encoding]::new($false))
 Write-Output "Generated $(@($catalog.verified_builds).Count) verified build profile(s)."
}
