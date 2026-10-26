$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$run=Join-Path $projectRoot ('build\provenance-tests\'+[guid]::NewGuid().ToString('N'))
$checks=[Collections.Generic.List[object]]::new()
function New-Fixture([string]$Name){
 $root=Join-Path $run $Name
 foreach($relative in @('scripts/package-release.ps1','scripts/generate-build-profiles.ps1','configs/editor-builds.json','src/generated-build-profiles.h','src/dropin.cpp','src/bridge.cpp','src/dropin.def','drop-in/window_size_plugin.dll','drop-in/SHA256.txt','build/dropin/build-info.json')){
  $destination=Join-Path $root $relative
  New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force|Out-Null
  Copy-Item -LiteralPath (Join-Path $projectRoot $relative) -Destination $destination
 }
 return $root
}
function Expect-Rejection([string]$Root,[string]$Pattern,[string]$Name){
 $start=[Diagnostics.ProcessStartInfo]::new()
 $start.FileName='powershell.exe'
 $start.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $Root 'scripts/package-release.ps1')+'" -Version 0.1.1'
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $start.EnvironmentVariables['PSModulePath']=(Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Modules')+';'+(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')
 $process=[Diagnostics.Process]::Start($start)
 try{
  if(!$process.WaitForExit(30000)){$process.Kill();throw 'Provenance fixture timed out'}
  $output=$process.StandardOutput.ReadToEnd()+$process.StandardError.ReadToEnd()
  if($process.ExitCode -eq 0 -or $output -notmatch $Pattern -or (Test-Path -LiteralPath (Join-Path $Root 'dist'))){throw "FAILED: $Name`n$output"}
 }finally{$process.Dispose()}
 $checks.Add(@{name=$Name;passed=$true});Write-Output "PASS $Name"
}
$missing=New-Fixture 'missing-record'
$record=Join-Path $missing 'build/dropin/build-info.json'
# Only remove one explicitly named fixture file, never the real build record.
Remove-Item -LiteralPath $record
Expect-Rejection $missing 'Build provenance is missing' 'missing build record rejected before packaging'
$catalogRoot=New-Fixture 'changed-catalog'
$catalogFile=Join-Path $catalogRoot 'configs/editor-builds.json'
$catalog=Get-Content -LiteralPath $catalogFile -Raw|ConvertFrom-Json
$catalog.verified_builds[0].id+='-fixture'
$catalog|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $catalogFile -Encoding utf8
& (Join-Path $catalogRoot 'scripts/generate-build-profiles.ps1')|Out-Null
Expect-Rejection $catalogRoot 'Build input changed' 'regenerated catalog without DLL rebuild rejected'
$source=New-Fixture 'changed-source'
Add-Content -LiteralPath (Join-Path $source 'src/dropin.cpp') -Value '// fixture source change' -Encoding utf8
Expect-Rejection $source 'Build input changed: src/dropin.cpp' 'runtime source change without DLL rebuild rejected'
$payloadRoot=New-Fixture 'changed-payload'
$payload=Join-Path $payloadRoot 'drop-in/window_size_plugin.dll'
[IO.File]::WriteAllText($payload,'fixture replacement payload')
$hash=(Get-FileHash -LiteralPath $payload).Hash.ToLowerInvariant()
Set-Content -LiteralPath (Join-Path $payloadRoot 'drop-in/SHA256.txt') -Value ($hash+'  window_size_plugin.dll') -Encoding ascii
Expect-Rejection $payloadRoot 'DLL does not match the recorded build' 'replacement DLL with updated checksum still requires its build record'
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'evidence') -Force|Out-Null
@{checks=$checks;production_directory_modified=$false}|ConvertTo-Json -Depth 5|
 Set-Content -LiteralPath (Join-Path $projectRoot 'evidence/build-provenance-tests.json') -Encoding utf8
