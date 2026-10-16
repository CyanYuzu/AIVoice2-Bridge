param([string]$EditorRoot='C:\Program Files\AI\AIVoice2\AIVoice2Editor',[switch]$Uninstall)
$ErrorActionPreference='Stop'
$originalHash='431767fa70d128427315b8b43a2be74a3da03a2d8a80679955522a917934ac4f'
$target=Join-Path $EditorRoot 'window_size_plugin.dll'
$backup=Join-Path $EditorRoot 'aivoice2_window_size_original.dll'
$payload=Join-Path $PSScriptRoot 'window_size_plugin.dll'
$log=Join-Path $PSScriptRoot 'installation-result.json'
try {
 $running=@(Get-Process aivoice -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq (Join-Path $EditorRoot 'aivoice.exe')})
 if($running.Count){throw 'Close the original editor before replacing its DLL.'}
 if($Uninstall){
  if(!(Test-Path -LiteralPath $backup)){throw 'Original plugin backup is missing.'}
  if((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant() -ne $originalHash){throw 'Original plugin backup hash mismatch.'}
  Copy-Item -LiteralPath $backup -Destination $target -Force
  if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $originalHash){throw 'Restoration verification failed.'}
  @{ok=$true;action='restored';target=$target;at=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $log -Encoding utf8
  exit 0
 }
 $expectedPayload=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'SHA256.txt') -Raw).Trim().Split(' ')[0]
 if((Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedPayload){throw 'Bridge payload hash mismatch.'}
 if(!(Test-Path -LiteralPath $backup)){
  if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $originalHash){throw 'Unknown editor plugin version; installation refused.'}
  Copy-Item -LiteralPath $target -Destination $backup
 }
 if((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant() -ne $originalHash){throw 'Original plugin backup hash mismatch.'}
 $currentHash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
 if($currentHash -ne $originalHash -and $currentHash -ne $expectedPayload){throw 'An unknown replacement is present; refusing to overwrite it.'}
 if($currentHash -ne $expectedPayload){
  try {Copy-Item -LiteralPath $payload -Destination $target -Force}
  catch {Copy-Item -LiteralPath $backup -Destination $target -Force;throw}
 }
 if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedPayload){Copy-Item -LiteralPath $backup -Destination $target -Force;throw 'Installed DLL verification failed; original restored.'}
 @{ok=$true;action='installed';target=$target;backup=$backup;sha256=$expectedPayload;at=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $log -Encoding utf8
} catch {
 @{ok=$false;message=$_.Exception.Message;at=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $log -Encoding utf8
 Write-Error $_
 exit 1
}
