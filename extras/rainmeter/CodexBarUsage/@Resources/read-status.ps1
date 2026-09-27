#Requires -Version 5.1
<#
.SYNOPSIS
    Print the desktop app's cached provider snapshot as one JSON line.

.DESCRIPTION
    Reads \\.\pipe\WinCodexBar.Status, which the CodexBar desktop app serves when
    Settings > Advanced > "PowerToys status pipe" is on (restart required). The app
    answers from its in-memory cache, so polling this makes no provider API calls.
    On failure prints {"error": "..."} so the skin can show why.
#>
$ErrorActionPreference = 'Stop'
try {
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'WinCodexBar.Status', [System.IO.Pipes.PipeDirection]::In)
    $pipe.Connect(2000)
    $reader = New-Object System.IO.StreamReader($pipe, [System.Text.Encoding]::UTF8)
    [Console]::Out.Write($reader.ReadLine())
    $reader.Dispose()
} catch [System.TimeoutException] {
    [Console]::Out.Write('{"error":"CodexBar is not running, or its status pipe is off (Settings > Advanced)."}')
} catch {
    $msg = $_.Exception.Message -replace '["\\]', ''
    [Console]::Out.Write('{"error":"' + $msg + '"}')
}
