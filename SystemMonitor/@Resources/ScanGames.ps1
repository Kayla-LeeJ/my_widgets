# Finds the installed games (Steam, Battle.net, Epic) and writes the dock's icons to Games.inc.
# The Dock skin runs this every minute; when the list of games changes, the file is rewritten
# and the skin is refreshed so the new icons show up.

param(
	[string]$Out,
	[string]$Rainmeter,
	[string]$Config,
	[int]$Columns = 8,
	# Comma-separated names or Steam app IDs to leave out
	[string]$Hide = ''
)
$ErrorActionPreference = 'Stop'

$iconDir = Join-Path $PSScriptRoot 'Icons'
$autoDir = Join-Path $iconDir 'auto'
New-Item -ItemType Directory -Force $autoDir | Out-Null
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------- Tweaks for particular games
# Icon: a file in @Resources\Icons. Launch: replaces the default launch action.
# Process: shows the "running" dot while this process is up (Steam games use Steam's own flag).
# Order: these come first, the rest follow alphabetically.
$custom = @{
	'steam:892970'  = @{ Order = 1; Name = 'Valheim (modded)'; Icon = 'valheim.png'
		Launch = '["conhost.exe" --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "#@#StartValheim.ps1" -Profile "#ThunderstoreProfile#"]' }
	'steam:896660'  = @{ Order = 2; Name = 'Valheim server (Steam)'; Icon = 'valheim-server.png'; Badge = 'SRV'; Process = 'valheim_server' }
	'steam:4358690' = @{ Order = 3; Icon = 'graveyard-keeper-2.png' }
	'bnet:WoW'      = @{ Order = 4; Icon = 'wow.png' }
	'bnet:Fen'      = @{ Order = 5; Icon = 'diablo-4.png' }
}

# Steam installs these alongside games, but they aren't games
$notGames = @(228980, 431960, 250820, 1070560, 1391110, 1628350, 1493710, 1580130, 1887720, 2180100,
	2348590, 2805730, 961940, 858280, 1054830, 1113280, 1245040, 1420170, 1826330)

# Battle.net launch codes and process names
$blizzard = @{
	'World of Warcraft'          = @('WoW', 'Wow')
	'Diablo IV'                  = @('Fen', 'Diablo IV')
	'Diablo III'                 = @('D3', 'Diablo III64')
	'Diablo II: Resurrected'     = @('OSI', 'D2R')
	'Diablo Immortal'            = @('ANBS', 'DiabloImmortal')
	'Overwatch'                  = @('Pro', 'Overwatch')
	'Hearthstone'                = @('WTCG', 'Hearthstone')
	'Heroes of the Storm'        = @('Hero', 'HeroesOfTheStorm_x64')
	'StarCraft II'               = @('S2', 'SC2_x64')
	'StarCraft'                  = @('S1', 'StarCraft')
	'Warcraft III'               = @('W3', 'Warcraft III')
	'Warcraft III: Reforged'     = @('W3', 'Warcraft III')
}

$hidden = $Hide -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

# ---------------------------------------------------------------- Icons
Add-Type -Namespace Native -Name Shell -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern uint PrivateExtractIcons(string file, int index, int cx, int cy, IntPtr[] icons, int[] ids, uint count, uint flags);
[DllImport("user32.dll")]
public static extern bool DestroyIcon(IntPtr icon);
'@

function Save-Png($bitmap, $path) {
	$bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
	$bitmap.Dispose()
}

# The biggest icon (up to 256px) inside an .exe or .ico
function Save-FileIcon($file, $path) {
	$handles = New-Object IntPtr[] 1
	$ids = New-Object int[] 1
	if ([Native.Shell]::PrivateExtractIcons($file, 0, 256, 256, $handles, $ids, 1, 0) -ne 1 -or $handles[0] -eq [IntPtr]::Zero) { return $false }
	try { Save-Png ([System.Drawing.Icon]::FromHandle($handles[0]).ToBitmap()) $path }
	finally { [void][Native.Shell]::DestroyIcon($handles[0]) }
	$true
}

# The game's own .exe: the biggest one in its folder that isn't a crash reporter, installer, etc.
function Find-GameExe($folder) {
	if (-not $folder -or -not (Test-Path $folder)) { return $null }
	Get-ChildItem $folder -Filter *.exe -Recurse -Depth 3 -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -notmatch 'crash|unins|setup|redist|prereq|report|helper|vc_|dxsetup|anticheat|cef|update|install' } |
		Sort-Object Length -Descending | Select-Object -First 1 -ExpandProperty FullName
}

# Steam keeps a 32px copy of each game's icon. Bigger ones: Steam's CDN (usually under the same
# name), then the game's .exe. The small one is the last resort.
function Get-SteamIcon($steamPath, $appId, $folder) {
	$png = Join-Path $autoDir "steam-$appId.png"
	if (Test-Path $png) { return $png }
	$small = Get-ChildItem (Join-Path $steamPath "appcache\librarycache\$appId") -File -Filter *.jpg -ErrorAction SilentlyContinue | Select-Object -First 1
	$offline = $false
	if ($small) {
		$ico = Join-Path $env:TEMP "steam-$appId.ico"
		try {
			Invoke-WebRequest "https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/$appId/$($small.BaseName).ico" -OutFile $ico -UseBasicParsing -TimeoutSec 10
			$ok = Save-FileIcon $ico $png
			Remove-Item $ico -Force
			if ($ok) { return $png }
		} catch [System.Net.WebException] {
			$offline = -not $_.Exception.Response
		}
	}
	$exe = Find-GameExe $folder
	if ($exe -and (Save-FileIcon $exe $png)) { return $png }
	if (-not $small) { return $null }
	# Offline: use the small one for now and try again next time
	if ($offline) { return $small.FullName }
	Copy-Item $small.FullName $png
	$png
}

function Get-ExeIcon($key, $exe) {
	$png = Join-Path $autoDir "$($key -replace '[^\w-]', '-').png"
	if (Test-Path $png) { return $png }
	if ($exe -and (Test-Path $exe) -and (Save-FileIcon $exe $png)) { return $png }
	$null
}

# ---------------------------------------------------------------- Steam
$games = New-Object System.Collections.ArrayList
$steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
if ($steamPath) {
	$libraries = @($steamPath)
	$vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
	if (Test-Path $vdf) {
		$libraries += [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }
	}
	$seen = @{}
	foreach ($manifest in $libraries | Select-Object -Unique | ForEach-Object { Get-ChildItem (Join-Path $_ 'steamapps\appmanifest_*.acf') -ErrorAction SilentlyContinue }) {
		$text = Get-Content $manifest.FullName -Raw
		$folder = Join-Path $manifest.DirectoryName ('common\' + [regex]::Match($text, '"installdir"\s+"([^"]+)"').Groups[1].Value)
		$id = [int][regex]::Match($text, '"appid"\s+"(\d+)"').Groups[1].Value
		$name = [regex]::Match($text, '"name"\s+"([^"]+)"').Groups[1].Value
		$flags = [int][regex]::Match($text, '"StateFlags"\s+"(\d+)"').Groups[1].Value
		# Flag 4 = fully installed (not mid-download or uninstalling)
		if ($seen[$id] -or $id -in $notGames -or -not ($flags -band 4) -or $name -in $hidden -or "$id" -in $hidden) { continue }
		$seen[$id] = $true
		[void]$games.Add(@{ Key = "steam:$id"; Name = $name; Launch = "[`"steam://rungameid/$id`"]"
			SteamId = $id; Icon = (Get-SteamIcon $steamPath $id $folder) })
	}
}

# ---------------------------------------------------------------- Battle.net (and anything else Blizzard installs)
$uninstall = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
foreach ($app in Get-ItemProperty $uninstall -ErrorAction SilentlyContinue | Where-Object { $_.Publisher -eq 'Blizzard Entertainment' -and $_.DisplayName -ne 'Battle.net' }) {
	if ($app.DisplayName -in $hidden) { continue }
	$exe = ($app.DisplayIcon -split ',')[0].Trim('"')
	$known = $blizzard[$app.DisplayName]
	if ($known) {
		$key = "bnet:$($known[0])"
		$launch = "[`"#BattleNet#`" --exec=`"launch $($known[0])`"]"
		$process = $known[1]
	} else {
		$key = "bnet:$($app.DisplayName)"
		$launch = '["#BattleNet#"]'
		$process = [IO.Path]::GetFileNameWithoutExtension($exe)
	}
	[void]$games.Add(@{ Key = $key; Name = $app.DisplayName; Launch = $launch; Process = $process; Icon = (Get-ExeIcon $key $exe) })
}

# ---------------------------------------------------------------- Epic Games
foreach ($item in Get-ChildItem 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests\*.item' -ErrorAction SilentlyContinue) {
	$m = Get-Content $item.FullName -Raw | ConvertFrom-Json
	if ($m.bIsIncompleteInstall -or $m.DisplayName -in $hidden -or $m.AppCategories -notcontains 'games') { continue }
	$exe = Join-Path $m.InstallLocation $m.LaunchExecutable
	$key = "epic:$($m.AppName)"
	[void]$games.Add(@{ Key = $key; Name = $m.DisplayName; Process = [IO.Path]::GetFileNameWithoutExtension($exe); Icon = (Get-ExeIcon $key $exe)
		Launch = "[`"com.epicgames.launcher://apps/$($m.CatalogNamespace)%3A$($m.CatalogItemId)%3A$($m.AppName)?action=launch&silent=true`"]" })
}

# ---------------------------------------------------------------- Apply tweaks and sort
foreach ($game in $games) {
	$tweak = $custom[$game.Key]
	if (-not $tweak) { continue }
	foreach ($k in $tweak.Keys) { $game[$k] = $tweak[$k] }
	if ($tweak.Icon) { $game.Icon = Join-Path $iconDir $tweak.Icon }
}
$games = @($games | Sort-Object { if ($_.Order) { $_.Order } else { 99 } }, { $_.Name })

# ---------------------------------------------------------------- Write Games.inc
$Columns = [Math]::Max(1, $Columns)
$cols = [Math]::Max(1, [Math]::Min($Columns, $games.Count))
$rows = [Math]::Max(1, [Math]::Ceiling($games.Count / $Columns))

$sb = New-Object System.Text.StringBuilder
$line = { param($s) [void]$sb.AppendLine($s) }
& $line '; Written by @Resources\ScanGames.ps1 - changes here are overwritten.'
& $line ''
& $line '[Variables]'
& $line "DockW=$($cols * 52 + 11)"
& $line "DockH=$(65 + ($rows - 1) * 52)"

for ($i = 0; $i -lt $games.Count; $i++) {
	$g = $games[$i]
	$n = $i + 1
	$x = 12 + ($i % $Columns) * 52
	$y = 10 + [Math]::Floor($i / $Columns) * 52
	& $line ''
	& $line "; $($g.Name)"
	& $line "[MeasureGame$n]"
	if ($g.SteamId -and -not $g.Process) {
		& $line 'Measure=Registry'
		& $line 'RegHKey=HKEY_CURRENT_USER'
		& $line "RegKey=Software\Valve\Steam\Apps\$($g.SteamId)"
		& $line 'RegValue=Running'
	} else {
		& $line 'Measure=Plugin'
		& $line 'Plugin=UsageMonitor'
		& $line 'Category=Process'
		& $line 'Counter=ID Process'
		& $line "Name=$($g.Process)"
	}
	& $line "IfCondition=MeasureGame$n > 0"
	& $line "IfTrueAction=[!ShowMeter DotGame$n]"
	& $line "IfFalseAction=[!HideMeter DotGame$n]"
	& $line ''
	& $line "[IconGame$n]"
	if ($g.Icon) {
		& $line 'Meter=Image'
		& $line "ImageName=$($g.Icon)"
	} else {
		# No icon found: a tile with the game's initial
		& $line 'Meter=String'
		& $line "Text=$($g.Name.Substring(0, 1))"
	}
	& $line "MeterStyle=StyleIcon$(if (-not $g.Icon) { ' | StyleLetter' })"
	# Centered text is placed by its middle
	$c = if ($g.Icon) { 0 } else { 20 }
	& $line "X=$($x + $c)"
	& $line "Y=$($y + $c)"
	& $line "ToolTipText=$($g.Name)"
	& $line "LeftMouseUpAction=$($g.Launch)"
	& $line "MouseOverAction=[!SetOption #CURRENTSECTION# Y $($y + $c - 4)][!UpdateMeter #CURRENTSECTION#][!Redraw]"
	& $line "MouseLeaveAction=[!SetOption #CURRENTSECTION# Y $($y + $c)][!UpdateMeter #CURRENTSECTION#][!Redraw]"
	if ($g.Badge) {
		& $line ''
		& $line "[BadgeGame$n]"
		& $line 'Meter=String'
		& $line 'MeterStyle=StyleBadge'
		& $line "X=$($x + 40)"
		& $line "Y=$($y + 32)"
		& $line "Text=$($g.Badge)"
	}
	& $line ''
	& $line "[DotGame$n]"
	& $line 'Meter=Shape'
	& $line 'MeterStyle=StyleDot'
	& $line "X=$($x + 17.5)"
	& $line "Y=$($y + 46)"
}

$text = $sb.ToString()
$old = if (Test-Path $Out) { [IO.File]::ReadAllText($Out) } else { '' }
if ($text -ne $old) {
	# UTF-16 so Rainmeter shows non-English game names correctly
	[IO.File]::WriteAllText($Out, $text, [Text.Encoding]::Unicode)
	if ($Rainmeter -and $Config) { & $Rainmeter '!Refresh' $Config }
}
