$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$run=Join-Path $projectRoot ('build\profile-tests\'+[guid]::NewGuid().ToString('N'))
$package=Join-Path $run 'package'
New-Item -ItemType Directory -Path $package -Force|Out-Null
$installer=Join-Path $package 'INSTALL.ps1'
Copy-Item -LiteralPath (Join-Path $projectRoot 'drop-in\INSTALL.ps1') -Destination $installer
$fixtureFiles=@('aivoice.exe','data/app.so','Lib/AITalk/aitalk_engine.dll','window_size_plugin.dll')
function Put-File([string]$Path,[string]$Contents){
 New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force|Out-Null
 [IO.File]::WriteAllText($Path,$Contents,[Text.UTF8Encoding]::new($false))
 return (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()
}
function New-Profile([string]$Name){
 $hashes=[ordered]@{}
 foreach($file in $fixtureFiles){$hashes[$file]=Put-File (Join-Path $run ('fixture-'+$Name+'\'+$file)) ('fixture '+$Name+' '+$file)}
 return [pscustomobject]@{id=('fixture-'+$Name);editor_version=($Name+'.0.0-fixture');abi_profile='fixture-abi';files=[pscustomobject]$hashes}
}
$profileA=New-Profile '1'
$profileB=New-Profile '2'
$payload=Join-Path $package 'window_size_plugin.dll'
$payloadHash=Put-File $payload 'fixture current bridge'
Set-Content -LiteralPath (Join-Path $package 'SHA256.txt') -Value ($payloadHash+'  window_size_plugin.dll') -Encoding ascii
$legacy=Join-Path $run 'legacy-bridge.dll'
$legacyHash=Put-File $legacy 'fixture legacy bridge'
$catalog=[pscustomobject]@{schema_version=1;verified_builds=@($profileA,$profileB);known_bridge_sha256=@($legacyHash)}
function Save-Catalog($Value){$Value|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $package 'editor-builds.json') -Encoding utf8}
Save-Catalog $catalog
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed){if(!$Passed){throw "FAILED: $Name"};$checks.Add(@{name=$Name;passed=$true});Write-Output "PASS $Name"}
function New-Editor($Profile,[string]$Name){
 $root=Join-Path $run $Name
 foreach($file in $fixtureFiles){
  $source=Join-Path $run ('fixture-'+$Profile.id.Substring(8)+'\'+$file)
  $destination=Join-Path $root $file
  New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force|Out-Null
  Copy-Item -LiteralPath $source -Destination $destination
 }
 return $root
}
function Snapshot([string]$Root){
 $files=@(Get-ChildItem -LiteralPath $Root -Recurse -File|Sort-Object FullName|ForEach-Object {
  $_.FullName.Substring($Root.Length)+'='+(Get-FileHash -LiteralPath $_.FullName).Hash
 })
 return $files -join "`n"
}
function Install([string]$Root,[string]$ExpectedCode='',[switch]$Uninstall){
 $start=[Diagnostics.ProcessStartInfo]::new()
 $start.FileName='powershell.exe'
 $start.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$installer+'" -EditorRoot "'+$Root+'"'
 if($Uninstall){$start.Arguments+=' -Uninstall'}
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 # A direct ProcessStartInfo launch otherwise inherits the bundled PowerShell 7 module path.
 $start.EnvironmentVariables['PSModulePath']=(Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Modules')+';'+(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')
 $process=[Diagnostics.Process]::Start($start)
 if(!$process.WaitForExit(15000)){$process.Kill();throw 'Fixture installer timed out'}
 $stdout=$process.StandardOutput.ReadToEnd();$stderr=$process.StandardError.ReadToEnd()
 $report=Get-Content -LiteralPath (Join-Path $package 'installation-result.json') -Raw|ConvertFrom-Json
 if($ExpectedCode){
  if($process.ExitCode -ne 1 -or $report.ok -or $report.code -ne $ExpectedCode){throw "Expected $ExpectedCode; got $($report.code), exit $($process.ExitCode): $stderr"}
 }elseif($process.ExitCode -ne 0 -or !$report.ok){throw "Unexpected fixture installer failure: $stderr $stdout"}
 $process.Dispose()
 return $report
}
function Reject-Unchanged([string]$Name,[string]$Root,[string]$Code,[switch]$Uninstall){
 $before=Snapshot $Root
 $null=Install $Root $Code -Uninstall:$Uninstall
 Check $Name ($before -ceq (Snapshot $Root))
}

$editorA=New-Editor $profileA 'fresh-A'
$target=Join-Path $editorA 'window_size_plugin.dll'
$backup=Join-Path $editorA 'aivoice2_window_size_original.dll'
$result=Install $editorA
Check 'fresh install selects full profile A' ($result.profile_id -eq $profileA.id -and (Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -eq $payloadHash)
Check 'fresh install preserves correct original backup' ((Get-FileHash -LiteralPath $backup).Hash.ToLowerInvariant() -eq $profileA.files.'window_size_plugin.dll')
$null=Install $editorA
Check 'repeat install is idempotent and backup unchanged' ((Get-FileHash -LiteralPath $backup).Hash.ToLowerInvariant() -eq $profileA.files.'window_size_plugin.dll')
$null=Install $editorA -Uninstall
Check 'uninstall restores original from the same full profile' ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -eq $profileA.files.'window_size_plugin.dll')
Copy-Item -LiteralPath $legacy -Destination $target -Force
$null=Install $editorA
Check 'known bridge upgrade retains original backup' ((Get-FileHash -LiteralPath $backup).Hash.ToLowerInvariant() -eq $profileA.files.'window_size_plugin.dll')
Copy-Item -LiteralPath $legacy -Destination $target -Force
$null=Install $editorA -Uninstall
Check 'legacy bridge uninstall remains supported after full profile verification' ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -eq $profileA.files.'window_size_plugin.dll')

$editorB=New-Editor $profileB 'fresh-B'
$result=Install $editorB
Check 'second complete fixture build selects profile B' ($result.profile_id -eq $profileB.id)
$null=Install $editorB -Uninstall
Check 'profile B restoration uses B original rather than A' ((Get-FileHash -LiteralPath (Join-Path $editorB 'window_size_plugin.dll')).Hash.ToLowerInvariant() -eq $profileB.files.'window_size_plugin.dll')

$mixed=New-Editor $profileA 'mixed-core'
Copy-Item -LiteralPath (Join-Path $run 'fixture-2\Lib\AITalk\aitalk_engine.dll') -Destination (Join-Path $mixed 'Lib\AITalk\aitalk_engine.dll') -Force
Reject-Unchanged 'mixed-version core files rejected before any editor write' $mixed 'UNVERIFIED_EDITOR_BUILD'
$mixedPlugin=New-Editor $profileA 'mixed-plugin'
Copy-Item -LiteralPath (Join-Path $run 'fixture-2\window_size_plugin.dll') -Destination (Join-Path $mixedPlugin 'window_size_plugin.dll') -Force
Reject-Unchanged 'new original plugin cannot be independently added to an old core' $mixedPlugin 'UNVERIFIED_EDITOR_PLUGIN'

$stale=New-Editor $profileB 'stale-backup'
Copy-Item -LiteralPath (Join-Path $run 'fixture-1\window_size_plugin.dll') -Destination (Join-Path $stale 'aivoice2_window_size_original.dll')
Reject-Unchanged 'old backup cannot be restored into a new complete core' $stale 'INCOMPATIBLE_ORIGINAL_BACKUP' -Uninstall
Reject-Unchanged 'new install does not silently overwrite a stale backup' $stale 'INCOMPATIBLE_ORIGINAL_BACKUP'
Copy-Item -LiteralPath $legacy -Destination (Join-Path $stale 'window_size_plugin.dll') -Force
Reject-Unchanged 'known legacy bridge does not authorize a cross-version backup restore' $stale 'INCOMPATIBLE_ORIGINAL_BACKUP' -Uninstall

$unknown=New-Editor $profileA 'unknown-replacement'
Copy-Item -LiteralPath (Join-Path $unknown 'window_size_plugin.dll') -Destination (Join-Path $unknown 'aivoice2_window_size_original.dll')
$null=Put-File (Join-Path $unknown 'window_size_plugin.dll') 'unknown third-party replacement'
Reject-Unchanged 'unknown replacement rejected during install despite a valid original backup' $unknown 'UNKNOWN_REPLACEMENT'
Reject-Unchanged 'unknown replacement rejected during uninstall despite a valid original backup' $unknown 'UNKNOWN_REPLACEMENT' -Uninstall

$noBackup=New-Editor $profileA 'no-backup'
Reject-Unchanged 'uninstall requires an original backup' $noBackup 'BACKUP_MISSING' -Uninstall
Copy-Item -LiteralPath $legacy -Destination (Join-Path $noBackup 'window_size_plugin.dll') -Force
Reject-Unchanged 'known bridge without original backup cannot install' $noBackup 'BACKUP_MISSING'

$corruptPayload=New-Editor $profileA 'corrupt-payload'
$null=Put-File $payload 'tampered bridge'
Reject-Unchanged 'tampered bridge payload rejected before backup creation' $corruptPayload 'BRIDGE_PAYLOAD_MISMATCH'
$null=Put-File $payload 'fixture current bridge'

$badBackup=New-Editor $profileA 'corrupt-backup'
$null=Put-File (Join-Path $badBackup 'aivoice2_window_size_original.dll') 'not an original plugin'
Reject-Unchanged 'corrupt original backup rejected without writes' $badBackup 'INCOMPATIBLE_ORIGINAL_BACKUP'

$missing=New-Editor $profileA 'missing-core'
$missingPath=Join-Path $missing 'data\app.so'
Remove-Item -LiteralPath $missingPath
Reject-Unchanged 'missing core file rejected before writes' $missing 'UNVERIFIED_EDITOR_BUILD'

$duplicateCatalog=[pscustomobject]@{schema_version=1;verified_builds=@($profileA,$profileA);known_bridge_sha256=@($legacyHash)}
Save-Catalog $duplicateCatalog
Reject-Unchanged 'duplicate profile id rejected before writes' $corruptPayload 'INVALID_BUILD_CATALOG'
Save-Catalog $catalog

$summary=@{checks=$checks;fixture_profiles_only=$true;production_installation_modified=$false;installer_host='Windows PowerShell 5.1'}
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'evidence') -Force|Out-Null
$summary|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $projectRoot 'evidence\build-profile-tests.json') -Encoding utf8
Write-Output "All $($checks.Count) full-build profile checks passed."
