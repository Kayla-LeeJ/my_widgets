# Starts Valheim through Steam with a Thunderstore (BepInEx) profile loaded, the same
# way Thunderstore Mod Manager's "Start modded" does.

param([string]$Profile = 'Default')
$ErrorActionPreference = 'Stop'

$preloader = "$env:APPDATA\Thunderstore Mod Manager\DataFolder\Valheim\profiles\$Profile\BepInEx\core\BepInEx.Preloader.dll"
if (-not (Test-Path $preloader)) { throw "Thunderstore profile '$Profile' not found: $preloader" }

$steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam').SteamExe
Start-Process $steam -ArgumentList "-applaunch 892970 --doorstop-enabled true --doorstop-target-assembly `"$preloader`""
