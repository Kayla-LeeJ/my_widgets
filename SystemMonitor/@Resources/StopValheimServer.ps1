# Stops the Valheim dedicated server the safe way: sends Ctrl+C to its console window,
# exactly like pressing Ctrl+C there, so the server saves the world before exiting.
# Then closes the leftover start_headless_server.bat window.
#   -DryRun  only reports what it would do

param([switch]$DryRun, [int]$TimeoutSeconds = 120)
$ErrorActionPreference = 'Stop'

$server = Get-CimInstance Win32_Process -Filter "Name='valheim_server.exe'" | Select-Object -First 1
if (-not $server) { 'No Valheim server running.'; exit 0 }
$parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($server.ParentProcessId)"
"Server pid $($server.ProcessId), console host: $($parent.Name) $($parent.ProcessId)"
if ($DryRun) { 'Dry run: would send Ctrl+C to the server console.'; exit 0 }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class ConsoleControl {
	[DllImport("kernel32.dll")] public static extern bool FreeConsole();
	[DllImport("kernel32.dll")] public static extern bool AttachConsole(uint processId);
	[DllImport("kernel32.dll")] public static extern bool SetConsoleCtrlHandler(IntPtr handler, bool add);
	[DllImport("kernel32.dll")] public static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint processGroupId);
}
"@

# Join the server's console, ignore Ctrl+C in this script, and send Ctrl+C to everything on that console
[ConsoleControl]::FreeConsole() | Out-Null
if (-not [ConsoleControl]::AttachConsole([uint32]$server.ProcessId)) { throw 'Could not attach to the server console.' }
[ConsoleControl]::SetConsoleCtrlHandler([IntPtr]::Zero, $true) | Out-Null
[ConsoleControl]::GenerateConsoleCtrlEvent(0, 0) | Out-Null
Start-Sleep -Milliseconds 500
[ConsoleControl]::FreeConsole() | Out-Null

# Wait for the save to finish, then close the batch window (it would otherwise sit on
# "Terminate batch job (Y/N)?")
$process = Get-Process -Id $server.ProcessId -ErrorAction SilentlyContinue
if ($process -and -not $process.WaitForExit($TimeoutSeconds * 1000)) { throw 'Server is still running after the timeout.' }
if ($parent.Name -eq 'cmd.exe') { Stop-Process -Id $parent.ProcessId -ErrorAction SilentlyContinue }
