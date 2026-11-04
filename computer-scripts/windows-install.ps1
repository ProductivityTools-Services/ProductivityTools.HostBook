#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$TaskName   = "ProductivityTools.HostBook"
$ScriptPath = Join-Path $PSScriptRoot "windows.ps1"

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Nie znaleziono skryptu: $ScriptPath"
}

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
    -WorkingDirectory $PSScriptRoot

$TriggerRepeat  = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
$TriggerStartup = New-ScheduledTaskTrigger -AtStartup

$Principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger @($TriggerRepeat, $TriggerStartup) `
    -Principal $Principal `
    -Settings $Settings `
    -Description "Wysyla lokalne adresy IP komputera do Firebase Realtime Database (HostBook)." `
    -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName

Write-Output "OK: Zadanie '$TaskName' zostalo zarejestrowane i uruchomione dla skryptu: $ScriptPath"
