param(
 [string]$OriginalPlugin,
 [string]$Version='0.1.1',
 [string]$EditorRoot='C:\Program Files\AI\AIVoice2\AIVoice2Editor'
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$run=Join-Path $projectRoot ('build\release-validation\package-'+[guid]::NewGuid().ToString('N'))
$package=Join-Path $run 'package'
$editor=Join-Path $run 'editor'
New-Item -ItemType Directory -Path $package,$editor -Force|Out-Null
$archive=Join-Path $projectRoot "dist\releases\$Version\AIVoice2-Bridge-$Version-win-x64.zip"
Expand-Archive -LiteralPath $archive -DestinationPath $package
$allowed=@('API.md','COLLECT-DIAGNOSTICS.ps1','INSTALL.ps1','LICENSE.nlohmann-json.txt','README.md','SHA256.txt','editor-builds.json','release.json','window_size_plugin.dll')
$actual=@(Get-ChildItem -LiteralPath $package -File|Select-Object -ExpandProperty Name|Sort-Object)
if(Compare-Object ($allowed|Sort-Object) $actual){throw 'Unexpected archive contents'}
$catalog=Get-Content -LiteralPath (Join-Path $package 'editor-builds.json') -Raw|ConvertFrom-Json
if($catalog.schema_version -ne 1 -or @($catalog.verified_builds).Count -eq 0){throw 'Invalid packaged build catalog'}
if($OriginalPlugin){
 $OriginalPlugin=(Resolve-Path -LiteralPath $OriginalPlugin).Path
 $originalRoot=Split-Path $OriginalPlugin -Parent
 if($PSBoundParameters.ContainsKey('EditorRoot') -and (Resolve-Path -LiteralPath $EditorRoot).Path -ne $originalRoot){
  throw 'OriginalPlugin and EditorRoot must refer to the same installed Editor build.'
 }
}else{
 $originalRoot=(Resolve-Path -LiteralPath $EditorRoot).Path
}
$coreFiles=@('aivoice.exe','data/app.so','Lib/AITalk/aitalk_engine.dll')
$coreHashes=@{}
foreach($relative in $coreFiles){
 $coreHashes[$relative]=(Get-FileHash -LiteralPath (Join-Path $originalRoot $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$coreMatches=@($catalog.verified_builds|Where-Object {
 $candidate=$_
 @($coreFiles|Where-Object {$candidate.files.$_ -cne $coreHashes[$_]}).Count -eq 0
})
if($coreMatches.Count -eq 0){throw 'Original fixture core files do not match a complete build in the packaged catalog.'}
$pluginCandidates=if($OriginalPlugin){@($OriginalPlugin)}else{
 @((Join-Path $originalRoot 'aivoice2_window_size_original.dll'),(Join-Path $originalRoot 'window_size_plugin.dll'))
}
$selectedProfile=$null
foreach($candidatePath in $pluginCandidates){
 if(!(Test-Path -LiteralPath $candidatePath -PathType Leaf)){continue}
 $candidateHash=(Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant()
 $matches=@($coreMatches|Where-Object {$_.files.'window_size_plugin.dll' -ceq $candidateHash})
 if($matches.Count -eq 1){
  $OriginalPlugin=$candidatePath;$originalHash=$candidateHash;$selectedProfile=$matches[0];break
 }
}
if(!$selectedProfile){throw 'Original fixture plugin does not belong to the same complete packaged Editor build as the core files.'}
$expected=(Get-Content -LiteralPath (Join-Path $package 'SHA256.txt') -Raw).Trim().Split(' ')[0]
$target=Join-Path $editor 'window_size_plugin.dll'
$backup=Join-Path $editor 'aivoice2_window_size_original.dll'
Copy-Item -LiteralPath $OriginalPlugin -Destination $target
foreach($relative in $coreFiles){
 $destination=Join-Path $editor $relative
 New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force|Out-Null
 Copy-Item -LiteralPath (Join-Path $originalRoot $relative) -Destination $destination
}
$checks=[Collections.Generic.List[object]]::new()
function Check($Name,$Passed){if(!$Passed){throw $Name};$checks.Add(@{name=$Name;passed=$true});Write-Output "PASS $Name"}
function Run-Installer([int]$ExpectedExit=0,[switch]$Uninstall){
 $start=[Diagnostics.ProcessStartInfo]::new()
 $start.FileName='powershell.exe'
 $start.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $package 'INSTALL.ps1')+'" -EditorRoot "'+$editor+'"'
 if($Uninstall){$start.Arguments+=' -Uninstall'}
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $start.EnvironmentVariables['PSModulePath']=(Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Modules')+';'+(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')
 $process=[Diagnostics.Process]::Start($start)
 try{
  if(!$process.WaitForExit(30000)){$process.Kill();throw 'Package fixture installer timed out'}
  $stdout=$process.StandardOutput.ReadToEnd();$stderr=$process.StandardError.ReadToEnd()
  [IO.File]::WriteAllText((Join-Path $run 'stdout.txt'),$stdout)
  [IO.File]::WriteAllText((Join-Path $run 'stderr.txt'),$stderr)
  if($process.ExitCode -ne $ExpectedExit){throw ('Installer exit '+$process.ExitCode+'; expected '+$ExpectedExit+': '+$stderr)}
 }finally{$process.Dispose()}
}
Check 'archive includes only distributable payload, build catalog and docs' ($actual.Count -eq 9)
Run-Installer
$installed=Get-Content -LiteralPath (Join-Path $package 'installation-result.json') -Raw|ConvertFrom-Json
Check 'installer selects the complete fixture build' ($installed.ok -and $installed.profile_id -ceq $selectedProfile.id)
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
$summary=@{checks=$checks;dll_sha256=$expected;archive_entries=$actual;profile_id=$selectedProfile.id;editor_version=$selectedProfile.editor_version;production_directory_modified=$false;installer_host='Windows PowerShell 5.1'}
$evidence=Join-Path $projectRoot 'evidence'
New-Item -ItemType Directory -Path $evidence -Force|Out-Null
$summary|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $evidence 'release-package.json') -Encoding utf8
