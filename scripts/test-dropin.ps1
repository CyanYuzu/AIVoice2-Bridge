$ErrorActionPreference='Stop'
$session=Get-Content -LiteralPath "$env:LOCALAPPDATA\AIVoice2Bridge\v2\editor-session.json" -Raw | ConvertFrom-Json
$run=Join-Path (Resolve-Path evidence).Path ('dropin-'+(Get-Date -Format yyyyMMdd-HHmmss))
New-Item -ItemType Directory -Path $run | Out-Null
$checks=[Collections.Generic.List[object]]::new()
$results=[Collections.Generic.List[object]]::new()
function Call-Editor($Request) {
 $pipe=[IO.Pipes.NamedPipeClientStream]::new('.',('AIVoice2Bridge2-'+$session.pid),[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
 try {
  $pipe.Connect(5000)
  $bytes=[Text.Encoding]::UTF8.GetBytes(($Request | ConvertTo-Json -Depth 20 -Compress))
  $pipe.Write($bytes,0,$bytes.Length)
  $buffer=[byte[]]::new(65536);$read=$pipe.ReadAsync($buffer,0,$buffer.Length)
  if(!$read.Wait(15000)){throw 'Pipe request timed out'}
  $response=[Text.Encoding]::UTF8.GetString($buffer,0,$read.Result) | ConvertFrom-Json
  if(!$response.ok){throw ($response.error | ConvertTo-Json -Compress)}
  return $response.result
 } finally {$pipe.Dispose()}
}
function Check($Name,$Passed,$Detail=$null){
 $checks.Add(@{name=$Name;passed=[bool]$Passed;detail=$Detail})
 Write-Output "$Name : $Passed"
 if(!$Passed){throw $Name}
}
function Submit($Name,$Voice='YuzukiYukari_ns_48',$Parameters=@{},$Text='こんにちは。音声合成のテストです。'){
 return Call-Editor @{op='submit';request_id=([guid]::NewGuid().ToString());text=$Text;voice=$Voice;parameters=$Parameters;output_path=(Join-Path $run ($Name+'.wav'))}
}
function Wait-Job($Id){
 $deadline=(Get-Date).AddSeconds(120)
 do {$j=Call-Editor @{op='status';id=$Id};if($j.state -in @('succeeded','failed','cancelled','interrupted')){return $j};Start-Sleep -Milliseconds 60} while((Get-Date) -lt $deadline)
 throw 'Task timed out'
}
function Render($Name,$Voice='YuzukiYukari_ns_48',$Parameters=@{}){
 $j=Submit $Name $Voice $Parameters;$j=Wait-Job $j.id
 Check ($Name+' succeeded') ($j.state -eq 'succeeded') $j.error
 $r=$j.result;$bytes=[IO.File]::ReadAllBytes($r.output_path)
 Check ($Name+' WAV') (($bytes.Length -gt 44) -and ([Text.Encoding]::ASCII.GetString($bytes,0,4) -eq 'RIFF') -and ([BitConverter]::ToInt32($bytes,24) -eq 48000) -and ([BitConverter]::ToInt16($bytes,22) -eq 1) -and ([BitConverter]::ToInt16($bytes,34) -eq 16))
 Check ($Name+' hash') ((Get-FileHash -LiteralPath $r.output_path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $r.sha256)
 $r | Add-Member -NotePropertyName test_name -NotePropertyValue $Name
 $results.Add($r);return $r
}
try {
 $startupDeadline=(Get-Date).AddSeconds(90)
 do {$health=Call-Editor @{op='health'};if($health.ready){break};Start-Sleep -Milliseconds 250} while((Get-Date) -lt $startupDeadline)
 Check 'native drop-in ready' ($health.ready -and $health.protocol -eq 2 -and $null -eq $health.fault) $health
 $voices=@(Call-Editor @{op='voices'})
 Check 'eight licensed voices' (($voices.Count -eq 8) -and @($voices | Where-Object {!$_.available}).Count -eq 0) $voices
 $bounds=Call-Editor @{op='parameters'}
 Check 'native rate bounds' ($bounds.native_bounds.rate.min -eq .5 -and $bounds.native_bounds.rate.max -eq 4)
 # Check writes are sent to the existing editor by this validation shell. No client program is created.
 $base=@(Render 'baseline')[-1]
 $again=@(Render 'repeat')[-1]
 Check 'repeat bit identical' ($base.sha256 -eq $again.sha256)
 $rate=@(Render 'faster' 'YuzukiYukari_ns_48' @{rate=1.4})[-1]
 Check 'rate changes duration' ($rate.duration_seconds -lt $base.duration_seconds*.85)
 foreach($p in @(@{pitch=1.2},@{volume=.5},@{emphasis=1.3},@{styles=@{J=.7}})){
  $name='parameter-'+@($p.Keys)[0];$changed=@(Render $name 'YuzukiYukari_ns_48' $p)[-1]
  Check ($name+' changes waveform') ($changed.sha256 -ne $base.sha256)
 }
 $reset=@(Render 'reset')[-1];Check 'parameters isolated' ($reset.sha256 -eq $base.sha256)
 foreach($v in $voices){if($v.id -ne 'YuzukiYukari_ns_48'){$null=Render $v.id $v.id}}
 $bad=Submit 'invalid-rate' 'YuzukiYukari_ns_48' @{rate=100};$bad=Wait-Job $bad.id
 Check 'original setter error reported' ($bad.state -eq 'failed' -and $bad.error.stage -eq 'ai_TalkerConfig_setRate') $bad.error
 Check 'invalid task has no WAV' (!(Test-Path -LiteralPath (Join-Path $run 'invalid-rate.wav')))
 $recovered=@(Render 'after-error')[-1];Check 'recovery retains original waveform' ($recovered.sha256 -eq $base.sha256)
 $long=Submit 'cancel-active' 'YuzukiYukari_ns_48' @{} ('音声合成のキャンセルを確認します。'*100)
 $queued=Submit 'cancel-queued'
 $cancelled=Call-Editor @{op='cancel';id=$queued.id};Check 'queued cancellation' ($cancelled.state -eq 'cancelled')
 Start-Sleep -Milliseconds 120;$null=Call-Editor @{op='cancel';id=$long.id};$cancelled=Wait-Job $long.id
 Check 'active cancellation' ($cancelled.state -eq 'cancelled') $cancelled.error
 Check 'cancel cleans partial' (!(Test-Path -LiteralPath (Join-Path $run 'cancel-active.wav.partial')))
 $afterCancel=@(Render 'after-cancel')[-1];Check 'after cancellation recovery' ($afterCancel.sha256 -eq $base.sha256)
 $batch=[Collections.Generic.List[object]]::new();$clock=[Diagnostics.Stopwatch]::StartNew()
 for($i=0;$i -lt 8;$i++){$batch.Add((Submit ('batch-'+$i)))}
 $completed=@(foreach($j in $batch){Wait-Job $j.id});$clock.Stop()
 Check 'batch queue completes' (@($completed | Where-Object {$_.state -ne 'succeeded'}).Count -eq 0)
 Check 'batch repeatability' (@($completed.result.sha256 | Select-Object -Unique).Count -eq 1)
 $sorted=@($completed | Sort-Object started);$serial=$true;for($i=1;$i -lt $sorted.Count;$i++){if($sorted[$i-1].finished -gt $sorted[$i].started){$serial=$false}}
 Check 'serialized native execution' $serial
 $audioSeconds=($completed.result | Measure-Object duration_seconds -Sum).Sum
 $batchMetrics=@{wall_seconds=$clock.Elapsed.TotalSeconds;audio_seconds=$audioSeconds;real_time_factor=$clock.Elapsed.TotalSeconds/$audioSeconds}
 $id='same-'+[guid]::NewGuid().ToString();$request=@{op='submit';request_id=$id;text='同じジョブです。';voice='YuzukiYukari_ns_48'}
 $a=Call-Editor $request;$b=Call-Editor $request;Check 'idempotent task ID' ($a.id -eq $b.id);$null=Wait-Job $a.id
 $request.text='異なる内容です。';$rejected=$false;try {$null=Call-Editor $request}catch {$rejected=$_.Exception.Message -match 'ID_CONFLICT'};Check 'ID conflict rejected' $rejected
 $modules=@((Get-Process -Id $session.pid).Modules | Where-Object {$_.ModuleName -match 'window_size|aitalk_engine'} | Select-Object ModuleName,FileName)
 Check 'proxy and original loaded' (@($modules | Where-Object {$_.ModuleName -in @('window_size_plugin.dll','aivoice2_window_size_original.dll','aitalk_engine.dll')}).Count -eq 3)
 Check 'API module installed in editor root' (@($modules | Where-Object {$_.ModuleName -eq 'window_size_plugin.dll' -and $_.FileName -eq (Join-Path (Split-Path $session.exe_path -Parent) 'window_size_plugin.dll')}).Count -eq 1)
 $children=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$session.pid))
 Check 'editor has no child process' ($children.Count -eq 0)
 $identity=Call-Editor @{op='health'}
 Check 'API belongs to original editor PID' ($identity.pid -eq $session.pid -and $identity.protocol -eq 2)
} finally {
 $report=@{at=(Get-Date).ToString('o');pid=$session.pid;deployment='editor-drop-in-dll';checks=$checks;results=$results;voices=$voices;modules=$modules;batch=$batchMetrics}
 $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $run 'report.json') -Encoding utf8
 $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath evidence/dropin-e2e.json -Encoding utf8
}
