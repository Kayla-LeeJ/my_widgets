# Packs SystemMonitor into a .rmskin: double-click it and Rainmeter installs everything.
#   powershell -ExecutionPolicy Bypass -File .\tools\Build-Rmskin.ps1 -Version 1.2.0
# The file lands in dist\. GitHub builds one for every release tag (see .github\workflows).

param([string]$Version = '1.0.0')
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot
$skin = Join-Path $root 'SystemMonitor'
$dist = Join-Path $root 'dist'
$out = Join-Path $dist "my_widgets_$Version.rmskin"
New-Item -ItemType Directory -Force $dist | Out-Null
Remove-Item $out -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

# VariableFiles: on reinstall, Rainmeter keeps the user's own values in these files
$ini = @"
[rmskin]
Name=my_widgets
Author=Kayla-LeeJ
Version=$Version
MinimumRainmeter=4.5.0
MinimumWindows=10.0
LoadType=Skin
Load=SystemMonitor\Weather\Weather.ini
VariableFiles=SystemMonitor\@Resources\Variables.inc
"@

$zip = [IO.Compression.ZipFile]::Open($out, 'Create')
try {
	$entry = $zip.CreateEntry('RMSKIN.ini')
	$writer = New-Object IO.StreamWriter($entry.Open(), (New-Object Text.UTF8Encoding $false))
	$writer.Write(($ini -replace "`r?`n", "`r`n") + "`r`n")
	$writer.Dispose()

	# Leave out what each PC makes for itself
	$files = Get-ChildItem $skin -Recurse -File | Where-Object { $_.FullName -notmatch '\\Icons\\auto\\' -and $_.Name -ne 'Games.inc' }
	foreach ($file in $files) {
		$name = 'Skins/SystemMonitor/' + $file.FullName.Substring($skin.Length + 1).Replace('\', '/')
		[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $name, 'Optimal')
	}
} finally { $zip.Dispose() }

# Rainmeter recognises a .rmskin by a 16-byte footer after the zip: its size (8 bytes),
# a flags byte (0) and "RMSKIN\0"
$size = (Get-Item $out).Length
$stream = [IO.File]::Open($out, 'Append')
try {
	$footer = [BitConverter]::GetBytes([int64]$size) + [byte[]]@(0) + [Text.Encoding]::ASCII.GetBytes("RMSKIN`0")
	$stream.Write($footer, 0, $footer.Length)
} finally { $stream.Dispose() }

"Built $out ($($files.Count) files, $([math]::Round((Get-Item $out).Length / 1KB)) KB)"
