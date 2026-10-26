param([string]$EditorRoot='C:\Program Files\AI\AIVoice2\AIVoice2Editor',[switch]$Uninstall)
$ErrorActionPreference='Stop'
$log=Join-Path $PSScriptRoot 'installation-result.json'
$coreFiles=@('aivoice.exe','data/app.so','Lib/AITalk/aitalk_engine.dll')
$pluginFile='window_size_plugin.dll'
$originalFile='aivoice2_window_size_original.dll'
$observed=@{}
$selected=$null
$catalog=$null
function Reject([string]$Code,[string]$Message){
 if($Code -in @('UNVERIFIED_EDITOR_BUILD','UNVERIFIED_EDITOR_PLUGIN','INCOMPATIBLE_ORIGINAL_BACKUP') -and $catalog){
  $supported=(@($catalog.verified_builds|ForEach-Object {$_.editor_version+' ['+$_.id+']'}) -join ', ')
  $Message+=' Supported verified builds: '+$supported+'.'
 }
 $exception=[InvalidOperationException]::new($Message)
 $exception.Data['code']=$Code
 throw $exception
}
function Hash-File([string]$Path,[string]$Label){
 if(!(Test-Path -LiteralPath $Path -PathType Leaf)){Reject 'UNVERIFIED_EDITOR_BUILD' "Required file is missing: $Label"}
 $value=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
 $observed[$Label]=$value
 return $value
}
try {
 $catalogPath=Join-Path $PSScriptRoot 'editor-builds.json'
 if(!(Test-Path -LiteralPath $catalogPath -PathType Leaf)){
  $catalogPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'configs\editor-builds.json'
 }
 if(!(Test-Path -LiteralPath $catalogPath -PathType Leaf)){Reject 'INVALID_BUILD_CATALOG' 'Verified build catalog is missing from this package.'}
 $catalog=Get-Content -LiteralPath $catalogPath -Raw|ConvertFrom-Json
 if($catalog.schema_version -ne 1 -or @($catalog.verified_builds).Count -eq 0){Reject 'INVALID_BUILD_CATALOG' 'Invalid verified build catalog.'}
 $allFiles=@($coreFiles)+@($pluginFile)
 $profileIds=@{}
 $fingerprints=@{}
 foreach($profile in $catalog.verified_builds){
  if($profile.id -notmatch '^[A-Za-z0-9._-]+$' -or $profile.editor_version -notmatch '^[A-Za-z0-9._-]+$' -or $profile.abi_profile -notmatch '^[A-Za-z0-9._-]+$'){
   Reject 'INVALID_BUILD_CATALOG' 'Invalid profile identity.'
  }
  if($profileIds.ContainsKey($profile.id)){Reject 'INVALID_BUILD_CATALOG' 'Duplicate build profile id.'}
  $profileIds[$profile.id]=$true
  if(@($profile.files.PSObject.Properties).Count -ne 4){Reject 'INVALID_BUILD_CATALOG' 'Each profile must contain exactly four original files.'}
  foreach($file in $allFiles){if($profile.files.$file -cnotmatch '^[a-f0-9]{64}$'){Reject 'INVALID_BUILD_CATALOG' "Invalid SHA-256 for $file"}}
  $fingerprint=($allFiles|ForEach-Object {$profile.files.$_}) -join ':'
  if($fingerprints.ContainsKey($fingerprint)){Reject 'INVALID_BUILD_CATALOG' 'Duplicate original-file fingerprint combination.'}
  $fingerprints[$fingerprint]=$true
 }
 foreach($hash in $catalog.known_bridge_sha256){if($hash -cnotmatch '^[a-f0-9]{64}$'){Reject 'INVALID_BUILD_CATALOG' 'Invalid known bridge SHA-256.'}}
 $EditorRoot=(Resolve-Path -LiteralPath $EditorRoot).Path
 $target=Join-Path $EditorRoot $pluginFile
 $backup=Join-Path $EditorRoot $originalFile
 $payload=Join-Path $PSScriptRoot $pluginFile
 $running=@(Get-Process aivoice -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq (Join-Path $EditorRoot 'aivoice.exe')})
 if($running.Count){Reject 'EDITOR_RUNNING' 'Close the original editor before replacing its DLL.'}

 # Every original core file must belong to the same verified build, before any installation writes.
 foreach($file in $coreFiles){$null=Hash-File (Join-Path $EditorRoot $file) $file}
 $coreMatches=@($catalog.verified_builds|Where-Object {
  $candidate=$_
  @($coreFiles|Where-Object {$candidate.files.$_ -cne $observed[$_]}).Count -eq 0
 })
 if($coreMatches.Count -eq 0){
  $details=@($coreFiles|ForEach-Object {$_+' SHA256='+$observed[$_]}) -join '; '
  Reject 'UNVERIFIED_EDITOR_BUILD' "Editor core files do not match one verified build: $details. No editor files were changed."
 }
 $currentHash=Hash-File $target $pluginFile
 $backupExists=Test-Path -LiteralPath $backup -PathType Leaf
 $backupHash=if($backupExists){Hash-File $backup $originalFile}else{$null}
 $originalHash=if($backupExists){$backupHash}else{$currentHash}
 $matches=@($coreMatches|Where-Object {$_.files.$pluginFile -ceq $originalHash})
 if($matches.Count -ne 1){
  if($backupExists){Reject 'INCOMPATIBLE_ORIGINAL_BACKUP' "Original plugin backup $originalFile SHA256=$backupHash does not belong to the current verified editor core build. Restoration and installation refused; no editor files were changed. Restore the CURRENT version's factory plugin with the official installer, move the stale backup out of the Editor directory, then retry. Never restore an older backup into an updated Editor."}
  if($currentHash -cin @($catalog.known_bridge_sha256)){Reject 'BACKUP_MISSING' 'Original plugin backup is missing; a known bridge DLL cannot be used as an original backup.'}
  Reject 'UNVERIFIED_EDITOR_PLUGIN' "Unknown editor plugin version; installation refused. $pluginFile SHA256=$currentHash does not match the verified editor core build."
 }
 $selected=$matches[0]
 $expectedPayload=$null
 $payloadHashFile=Join-Path $PSScriptRoot 'SHA256.txt'
 if(!$Uninstall -or ((Test-Path -LiteralPath $payload -PathType Leaf) -and (Test-Path -LiteralPath $payloadHashFile -PathType Leaf))){
  $expectedPayload=(Get-Content -LiteralPath $payloadHashFile -Raw).Trim().Split(' ')[0]
  if($expectedPayload -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedPayload.ToLowerInvariant()){
   Reject 'BRIDGE_PAYLOAD_MISMATCH' 'Bridge payload hash mismatch.'
  }
  $expectedPayload=$expectedPayload.ToLowerInvariant()
 }
 $isOriginal=$currentHash -ceq $selected.files.$pluginFile
 $isBridge=($expectedPayload -and $currentHash -ceq $expectedPayload) -or $currentHash -cin @($catalog.known_bridge_sha256)
 if(!$isOriginal -and !$isBridge){Reject 'UNKNOWN_REPLACEMENT' 'An unknown replacement is present; restore the verified original plugin before installation or restoration.'}
 if(!$backupExists -and !$isOriginal){Reject 'BACKUP_MISSING' 'Original plugin backup is missing; a bridge DLL cannot be used as an original backup.'}

 # The backup is bound by the full core + original-plugin profile combination, including on uninstall.
 if($Uninstall){
  if(!$backupExists){Reject 'BACKUP_MISSING' 'Original plugin backup is missing.'}
  Copy-Item -LiteralPath $backup -Destination $target -Force
  if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $selected.files.$pluginFile){throw 'Restoration verification failed.'}
  @{ok=$true;action='restored';profile_id=$selected.id;editor_version=$selected.editor_version;target=$target;backup=$backup;observed_files=$observed;at=(Get-Date).ToString('o')}|
   ConvertTo-Json -Depth 5|Set-Content -LiteralPath $log -Encoding utf8
  exit 0
 }
 if(!$backupExists){Copy-Item -LiteralPath $target -Destination $backup}
 if((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant() -cne $selected.files.$pluginFile){throw 'Original plugin backup changed during installation.'}
 if($currentHash -cne $expectedPayload){
  try {Copy-Item -LiteralPath $payload -Destination $target -Force}
  catch {Copy-Item -LiteralPath $backup -Destination $target -Force;throw}
 }
 if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedPayload){
  Copy-Item -LiteralPath $backup -Destination $target -Force
  throw 'Installed DLL verification failed; verified original restored.'
 }
 @{ok=$true;action='installed';profile_id=$selected.id;editor_version=$selected.editor_version;target=$target;backup=$backup;sha256=$expectedPayload;observed_files=$observed;at=(Get-Date).ToString('o')}|
  ConvertTo-Json -Depth 5|Set-Content -LiteralPath $log -Encoding utf8
} catch {
 $code=if($_.Exception.Data.Contains('code')){$_.Exception.Data['code']}else{'INSTALLATION_ERROR'}
 @{ok=$false;code=$code;message=$_.Exception.Message;profile_id=if($selected){$selected.id}else{$null};supported_versions=@($catalog.verified_builds.editor_version|Select-Object -Unique);supported_profiles=@($catalog.verified_builds|ForEach-Object {@{id=$_.id;editor_version=$_.editor_version}});observed_files=$observed;at=(Get-Date).ToString('o')}|
  ConvertTo-Json -Depth 5|Set-Content -LiteralPath $log -Encoding utf8
 Write-Error $_
 exit 1
}
