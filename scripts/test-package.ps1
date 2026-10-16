param([string]$OriginalPlugin='C:\Program Files\AI\AIVoice2\AIVoice2Editor\aivoice2_window_size_original.dll')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$run=Join-Path $projectRoot ('build\release-validation\package-'+[guid]::NewGuid().ToString('N'))
$package=Join-Path $run 'package'
$editor=Join-Path $run 'editor'
New-Item -ItemType Directory -Path $package,$editor -Force|Out-Null
$archive=Join-Path $projectRoot 'dist\releases\0.1.0\AIVoice2-Bridge-0.1.0-win-x64.zip'
Expand-Archive -LiteralPath $archive -DestinationPath $package
$allowed=@('API.md','INSTALL.ps1','LICENSE.nlohmann-json.txt','README.md','SHA256.txt','release.json','window_size_plugin.dll')
$actual=@(Get-ChildItem -LiteralPath $package -File|Select-Object -ExpandProperty Name|Sort-Object)
if(Compare-Object ($allowed|Sort-Object) $actual){throw 'Unexpected archive contents'}
$originalHash='431767fa70d128427315b8b43a2be74a3da03a2d8a80679955522a917934ac4f'
if((Get-FileHash -LiteralPath $OriginalPlugin).Hash.ToLowerInvariant() -ne $originalHash){throw 'Original fixture hash mismatch'}
$expected=(Get-Content -LiteralPath (Join-Path $package 'SHA256.txt') -Raw).Trim().Split(' ')[0]
$target=Join-Path $editor 'window_size_plugin.dll'
$backup=Join-Path $editor 'aivoice2_window_size_original.dll'
Copy-Item -LiteralPath $OriginalPlugin -Destination $target
$checks=[Collections.Generic.List[object]]::new()
function Check($Name,$Passed){if(!$Passed){throw $Name};$checks.Add(@{name=$Name;passed=$true});Write-Output "PASS $Name"}
function Run-Installer([int]$ExpectedExit=0,[switch]$Uninstall){
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $package 'INSTALL.ps1'),'-EditorRoot',$editor)
 if($Uninstall){$arguments+='-Uninstall'}
 & powershell.exe @arguments 1> (Join-Path $run 'stdout.txt') 2> (Join-Path $run 'stderr.txt')
 if($LASTEXITCODE -ne $ExpectedExit){throw ('Installer exit '+$LASTEXITCODE+'; expected '+$ExpectedExit)}
}
Check 'archive includes only distributable payload and docs' ($actual.Count -eq 7)
Run-Installer
Check 'fresh install matches released payload' ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -eq $expected)
Check 'original backup preserved' ((Get-FileHash -LiteralPath $backup).Hash.ToLowerInvariant() -eq $originalHash)
Run-Installer
Check 'repeat installation succeeds' ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -eq $expected)
Run-Installer -Uninstall
Check 'uninstall restores verified original' ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -eq $originalHash)
$previous=Join-Path $projectRoot 'build\release-validation\previous-window_size_plugin.dll'
if(Test-Path -LiteralPath $previous){
 Copy-Item -LiteralPath $previous -Destination $target -Force
 Run-Installer
 Check 'known development build upgrades without overwriting backup' ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -eq $expected -and (Get-FileHash -LiteralPath $backup).Hash.ToLowerInvariant() -eq $originalHash)
}
[IO.File]::WriteAllText($target,'unknown replacement')
$unknown=(Get-FileHash -LiteralPath $target).Hash
Run-Installer -ExpectedExit 1
Check 'unknown replacement rejected and retained' ((Get-FileHash -LiteralPath $target).Hash -eq $unknown)
$summary=@{checks=$checks;dll_sha256=$expected;archive_entries=$actual;production_directory_modified=$false;installer_host='Windows PowerShell 5.1'}
$evidence=Join-Path $projectRoot 'evidence'
New-Item -ItemType Directory -Path $evidence -Force|Out-Null
$summary|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $evidence 'release-package.json') -Encoding utf8
