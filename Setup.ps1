# Setup wizard: fills in SystemMonitor\@Resources\Variables.inc for this PC.
#   - CPU, GPU and drive sensor IDs, read from LibreHardwareMonitor's web server
#   - drive labels, matched to their Windows drive letters
#   - weather location, looked up from a city name (open-meteo.com, no key needed)
# Run it from the repo folder:   powershell -ExecutionPolicy Bypass -File .\Setup.ps1
# Add -WhatIf to see what would change without writing anything.

[CmdletBinding(SupportsShouldProcess)]
param(
	[string]$City,
	[ValidateSet('celsius', 'fahrenheit')][string]$Units,
	[int]$Port = 8085
)
$ErrorActionPreference = 'Stop'

$varsPath = Join-Path $PSScriptRoot 'SystemMonitor\@Resources\Variables.inc'
$text = [IO.File]::ReadAllText($varsPath)
$changes = [ordered]@{}

function Get-Var($name) { [regex]::Match($text, "(?m)^$name=(.*?)\r?$").Groups[1].Value }
function Say($icon, $msg, $color = 'Gray') { Write-Host "  $icon  $msg" -ForegroundColor $color }

Write-Host ''
Write-Host '  ✨ my_widgets setup ✨' -ForegroundColor Magenta
Write-Host ''

# ---------------------------------------------------------------- Sensors (LibreHardwareMonitor)
Write-Host '  🌡️  Hardware sensors' -ForegroundColor Cyan
try {
	$tree = Invoke-RestMethod "http://localhost:$Port/data.json" -TimeoutSec 5
} catch {
	$tree = $null
	Say '⚠️' "LibreHardwareMonitor isn't answering on port $Port." Yellow
	Say '  ' 'Start it as administrator and turn on Options > Remote Web Server > Run, then run this again.' Yellow
	Say '  ' 'Skipping CPU, GPU and drive sensors for now.' Yellow
}

if ($tree) {
	# Flatten to one row per sensor, remembering which piece of hardware it belongs to
	$sensors = New-Object System.Collections.ArrayList
	function Walk($node, $hardware) {
		if ($node.SensorId) {
			[void]$sensors.Add([pscustomobject]@{
				Id = $node.SensorId; Name = $node.Text; Type = $node.Type; Hardware = $hardware
				Device = ($node.SensorId -split '/')[1..2] -join '/'
			})
		}
		foreach ($child in $node.Children) {
			# Hardware nodes carry a HardwareId; sensor groups ("Temperatures"…) don't change the hardware
			$hw = if ($child.HardwareId) { $child.Text.Trim() } else { $hardware }
			Walk $child $hw
		}
	}
	Walk $tree ''

	function Find($device, $type, [string[]]$names) {
		foreach ($n in $names) {
			$hit = $sensors | Where-Object { $_.Device -match $device -and $_.Type -eq $type -and $_.Name -eq $n } | Select-Object -First 1
			if ($hit) { return $hit }
		}
	}

	# CPU
	$pkg = Find '^(intelcpu|amdcpu)/' 'Temperature' 'CPU Package', 'Core (Tctl/Tdie)', 'Package', 'CPU (Tctl/Tdie)'
	$max = Find '^(intelcpu|amdcpu)/' 'Temperature' 'Core Max', 'Core (Tctl/Tdie)', 'CPU (Tctl/Tdie)', 'CPU Package'
	if ($pkg) {
		$changes.CpuPackageTemp = $pkg.Id
		$changes.CpuCoreMaxTemp = $max.Id
		Say '🧠' "CPU: $($pkg.Hardware)" Green
	} else { Say '⚠️' 'No CPU temperature found.' Yellow }

	# GPU
	$gpu = '^gpu-(amd|nvidia|intel)/'
	$load = Find $gpu 'Load' 'GPU Core', 'D3D 3D'
	if ($load) {
		$changes.GPUName = $load.Hardware -replace '^(AMD Radeon|NVIDIA GeForce|Intel\(R\)|Intel)\s+', ''
		$changes.GpuLoad = $load.Id
		foreach ($pair in @(
				@('GpuTemp', 'Temperature', @('GPU Core')),
				@('GpuHotSpot', 'Temperature', @('GPU Hot Spot', 'GPU Core')),
				@('GpuVramUsed', 'SmallData', @('GPU Memory Used', 'D3D Dedicated Memory Used')),
				@('GpuVramTotal', 'SmallData', @('GPU Memory Total', 'D3D Dedicated Memory Total')))) {
			$hit = Find ($load.Device) $pair[1] $pair[2]
			if ($hit) { $changes[$pair[0]] = $hit.Id }
		}
		Say '🎨' "GPU: $($load.Hardware)" Green
	} else { Say '⚠️' 'No GPU found.' Yellow }

	# Drives: match LibreHardwareMonitor's drive names to Windows' disks to get the drive letters
	$disks = foreach ($d in Get-Disk) {
		$letters = ($d | Get-Partition -ErrorAction SilentlyContinue | Where-Object DriveLetter | ForEach-Object { "$($_.DriveLetter):" }) -join ' '
		if ($letters) { [pscustomobject]@{ Number = $d.Number; Model = $d.FriendlyName.Trim(); Letters = $letters; Bus = $d.BusType } }
	}
	$drives = foreach ($dev in $sensors | Where-Object { $_.Device -match '^(nvme|hdd|ssd)/' } | Group-Object Device) {
		$hw = $dev.Group[0].Hardware
		# LibreHardwareMonitor numbers drives like Windows does (/hdd/2 = disk 2); the name is a fallback
		# (USB enclosures report a different name than the drive inside)
		$disk = $disks | Where-Object { $_.Number -eq [int]($dev.Name -split '/')[1] } | Select-Object -First 1
		if (-not $disk) { $disk = $disks | Where-Object { $_.Model -eq $hw -or $_.Model -like "*$hw*" -or $hw -like "*$($_.Model)*" } | Select-Object -First 1 }
		if (-not $disk) { continue }
		$temp = $dev.Group | Where-Object Type -eq 'Temperature' | Sort-Object { $_.Name -notin 'Composite Temperature', 'Temperature' } | Select-Object -First 1
		$used = $dev.Group | Where-Object Name -eq 'Used Space' | Select-Object -First 1
		$kind = if ($dev.Name -like 'nvme/*') { 'NVMe SSD' } elseif ($disk.Bus -eq 'USB') { 'USB drive' } elseif ($dev.Name -like 'ssd/*') { 'SSD' } else { 'Hard drive' }
		[pscustomobject]@{ Letters = $disk.Letters; Label = "$($disk.Letters)  $kind"; Temp = $temp.Id; Used = $used.Id }
	}
	$drives = @($drives | Where-Object { $_.Temp -and $_.Used } | Sort-Object Letters | Select-Object -First 3)
	for ($i = 0; $i -lt $drives.Count; $i++) {
		$n = $i + 1
		# Keep a label you've already customised for the same drive letter
		$old = Get-Var "Drive${n}Label"
		$changes["Drive${n}Label"] = if ($old -like "$($drives[$i].Letters)*") { $old } else { $drives[$i].Label }
		$changes["Drive${n}Temp"] = $drives[$i].Temp
		$changes["Drive${n}Used"] = $drives[$i].Used
		Say '💾' $changes["Drive${n}Label"] Green
	}
	if ($drives.Count -lt 3) { Say '⚠️' "Found $($drives.Count) drive(s); the Drives card has 3 rows, so the others keep their current settings." Yellow }
}

# ---------------------------------------------------------------- Weather location
Write-Host ''
Write-Host '  🌦️  Weather' -ForegroundColor Cyan
if (-not $City) {
	$current = Get-Var 'WeatherCity'
	$City = Read-Host "  Your city (Enter keeps $current)"
	if (-not $City) { $City = $current }
}
try {
	$place = (Invoke-RestMethod "https://geocoding-api.open-meteo.com/v1/search?name=$([uri]::EscapeDataString($City))&count=1" -TimeoutSec 10).results | Select-Object -First 1
} catch { $place = $null }
if ($place) {
	$changes.WeatherCity = $place.name
	$changes.WeatherLat = [math]::Round($place.latitude, 2).ToString([Globalization.CultureInfo]::InvariantCulture)
	$changes.WeatherLon = [math]::Round($place.longitude, 2).ToString([Globalization.CultureInfo]::InvariantCulture)
	Say '📍' "$($place.name), $($place.country)" Green
} else { Say '⚠️' "Couldn't find '$City' (or no internet), so the location stays as it is." Yellow }
if ($Units) { $changes.WeatherUnits = $Units }

# ---------------------------------------------------------------- Write Variables.inc
Write-Host ''
$updated = $text
$diff = foreach ($key in $changes.Keys) {
	$old = Get-Var $key
	if ($old -eq $changes[$key]) { continue }
	$updated = [regex]::Replace($updated, "(?m)^$key=.*?(?=\r?$)", { param($m) "$key=$($changes[$key])" })
	"$key`: $old  →  $($changes[$key])"
}
if (-not $diff) {
	Say '🎉' 'Everything already matches this PC. Nothing to change!' Green
	return
}
$diff | ForEach-Object { Say '✏️' $_ }
if ($PSCmdlet.ShouldProcess($varsPath, 'Update settings')) {
	[IO.File]::WriteAllText($varsPath, $updated)
	Say '✅' 'Saved Variables.inc' Green
	$rainmeter = Get-Process Rainmeter -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($rainmeter) {
		& $rainmeter.Path '!RefreshApp'
		Say '🔄' 'Refreshed Rainmeter' Green
	}
}
Write-Host ''
