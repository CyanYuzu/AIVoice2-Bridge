$ErrorActionPreference='Stop'
$sessionPath=Join-Path $env:LOCALAPPDATA 'AIVoice2Bridge\v2\editor-session.json'
$session=Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
$checks=[Collections.Generic.List[object]]::new()
function Call-Editor($Request){
 $pipe=[IO.Pipes.NamedPipeClientStream]::new('.',('AIVoice2Bridge2-'+$session.pid),[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
 try {$pipe.Connect(3000);$b=[Text.Encoding]::UTF8.GetBytes(($Request | ConvertTo-Json -Depth 20 -Compress));$pipe.Write($b,0,$b.Length);$buffer=[byte[]]::new(65536);$read=$pipe.ReadAsync($buffer,0,$buffer.Length);if(!$read.Wait(10000)){throw 'Pipe timeout'};$r=[Text.Encoding]::UTF8.GetString($buffer,0,$read.Result) | ConvertFrom-Json;if(!$r.ok){throw ($r.error | ConvertTo-Json -Compress)};return $r.result} finally {$pipe.Dispose()}
}
function Check($Name,$Passed,$Detail=$null){$checks.Add(@{name=$Name;passed=[bool]$Passed;detail=$Detail});Write-Output "$Name : $Passed";if(!$Passed){throw $Name}}
function Wait-Job($Id){$deadline=(Get-Date).AddSeconds(60);do {$j=Call-Editor @{op='status';id=$Id};if($j.state -in @('succeeded','failed','cancelled','interrupted')){return $j};Start-Sleep -Milliseconds 100}while((Get-Date) -lt $deadline);throw 'Task timeout'}
try {
 $beforePid=$session.pid;$prior=Get-Content -LiteralPath evidence/dropin-e2e.json -Raw | ConvertFrom-Json
 $last=@(Call-Editor @{op='jobs';limit=1})[0];Check 'prior task committed' ($last.state -eq 'succeeded')
 $request=@{op='submit';request_id=('restart-active-'+[guid]::NewGuid());text=('再起動の復旧を確認する長いテストです。'*200);voice='YuzukiYukari_ns_48'}
 $active=Call-Editor $request
 $request.request_id='restart-queued-'+[guid]::NewGuid();$request.text='再起動の後に合成します。';$queued=Call-Editor $request
 $deadline=(Get-Date).AddSeconds(10);do {$j=Call-Editor @{op='status';id=$active.id};if($j.state -eq 'running'){break};Start-Sleep -Milliseconds 50}while((Get-Date) -lt $deadline)
 Check 'active synthesis before restart' ($j.state -eq 'running')
 $q=Call-Editor @{op='status';id=$queued.id};Check 'pending synthesis before restart' ($q.state -eq 'queued')
 $editor=Get-Process -Id $beforePid
 if($editor.MainWindowTitle -ne 'A.I.VOICE2 Editor - (新規プロジェクト)'){throw 'Unexpected editor project; restart validation aborted'}
 if(!$editor.CloseMainWindow()){throw 'Normal close rejected'}
 if(!$editor.WaitForExit(10000)){throw 'Editor remains open; not forcibly terminated'}
 Check 'original editor closed normally' $true
 $editorRoot=Split-Path $session.exe_path -Parent
 $next=Start-Process -FilePath $session.exe_path -WorkingDirectory $editorRoot -PassThru
 $deadline=(Get-Date).AddSeconds(90)
 do {
  Start-Sleep -Milliseconds 250
  $session=Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
  if($session.pid -ne $next.Id){continue}
  try {$h=Call-Editor @{op='health'};if($h.ready){break}}catch{}
 }while((Get-Date) -lt $deadline)
 Check 'auto loaded after normal restart' ($session.pid -eq $next.Id -and $session.pid -ne $beforePid -and $h.ready) $h
 $historical=Call-Editor @{op='status';id=$last.id};Check 'task history persists' ($historical.state -eq 'succeeded' -and $historical.result.sha256 -eq $last.result.sha256)
 $interrupted=Call-Editor @{op='status';id=$active.id};Check 'active task marked interrupted' ($interrupted.state -eq 'interrupted') $interrupted.error
 Check 'interrupted partial removed' (!(Test-Path -LiteralPath ($interrupted.output+'.partial')))
 $resumed=Wait-Job $queued.id;Check 'queued task resumes' ($resumed.state -eq 'succeeded') $resumed.error
 $recovered=Call-Editor @{op='recover'};Check 'explicit recovery' $recovered.recovered
 $request.request_id='restart-smoke-'+[guid]::NewGuid();$request.text='こんにちは。音声合成のテストです。';$smoke=Call-Editor $request;$smoke=Wait-Job $smoke.id
 Check 'synthesis after restart and recovery' ($smoke.state -eq 'succeeded')
 Check 'same waveform across editor restarts' ($smoke.result.sha256 -eq $prior.results[0].sha256)
 $modules=@((Get-Process -Id $session.pid).Modules | Where-Object {$_.ModuleName -match 'window_size|aitalk_engine'} | Select-Object ModuleName,FileName)
 Check 'drop-in bridge automatically loaded' (@($modules | Where-Object {$_.ModuleName -eq 'window_size_plugin.dll'}).Count -eq 1)
 $children=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$session.pid));Check 'no helper child process after restart' ($children.Count -eq 0)
} finally {
 @{at=(Get-Date).ToString('o');before_pid=$beforePid;after_pid=$session.pid;checks=$checks;modules=$modules;interrupted=$interrupted;resumed=$resumed;smoke=$smoke} | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath evidence/dropin-restart.json -Encoding utf8
}
