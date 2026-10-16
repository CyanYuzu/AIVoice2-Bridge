param([string]$EditorRoot='C:\Program Files\AI\AIVoice2\AIVoice2Editor',[switch]$Uninstall)
$ErrorActionPreference='Stop'
& (Join-Path (Split-Path $PSScriptRoot -Parent) 'drop-in\INSTALL.ps1') -EditorRoot $EditorRoot -Uninstall:$Uninstall
