# Background helper for the widgets: things Rainmeter can't read by itself.
# All replies are plain-text "key=value" lines.
#   GET /state         -> now playing (the media session in Windows' volume flyout):
#                         status, title, artist, app, pos, dur, cover
#   GET /cmd/<action>  -> playpause | next | prev, then returns /state
#   GET /valheim       -> local Valheim dedicated server:
#                         status (Offline|Starting|Online|Running), name, world, players, joincode, uptime
#                         (Running = up, but start_headless_server.bat has no -logFile, so no player info)
# Started by the NowPlaying and Valheim skins. Exits if another copy already owns the
# port, and exits on its own once Rainmeter is no longer running.

param([int]$Port = 8086)
$ErrorActionPreference = 'Stop'

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try { $listener.Start() } catch { exit 0 }

# ---------------------------------------------------------------- WinRT plumbing
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
	$_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
	$_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1

$asStreamForRead = [System.IO.WindowsRuntimeStreamExtensions].GetMethods() |
	Where-Object { $_.Name -eq 'AsStreamForRead' -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1

function Await($operation, [Type]$resultType) {
	$task = $asTaskGeneric.MakeGenericMethod($resultType).Invoke($null, @($operation))
	$task.Wait(5000) | Out-Null
	$task.Result
}

$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType = WindowsRuntime]
$manager = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) `
	([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])

# ---------------------------------------------------------------- Album art
$coverDir = Join-Path $env:TEMP 'RainmeterNowPlaying'
New-Item -ItemType Directory -Force $coverDir | Out-Null
Get-ChildItem $coverDir -File | Remove-Item -Force
$script:coverKey = ''
$script:coverPath = ''
$script:coverTries = 0
$script:coverCount = 0

# Some apps publish the artwork a moment after the title, so a missing cover is retried a few times.
function Update-Cover($key, $thumbnail) {
	if ($key -ne $script:coverKey) {
		$script:coverKey = $key
		$script:coverPath = ''
		$script:coverTries = 0
	}
	if ($script:coverPath -or -not $thumbnail -or $script:coverTries -ge 5) { return }
	$script:coverTries++
	try {
		$stream = Await ($thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
		# Apps like Chrome return a bare COM object PowerShell can't bind methods on,
		# so the conversion is invoked through reflection
		$source = $asStreamForRead.Invoke($null, @($stream))
		$buffer = New-Object System.IO.MemoryStream
		try { $source.CopyTo($buffer) } finally { $source.Dispose() }
		$bytes = $buffer.ToArray()
		if ($bytes.Length -eq 0) { return }
		$extension = if ($bytes[0] -eq 0x89) { 'png' } elseif ($bytes[0] -eq 0x42) { 'bmp' } else { 'jpg' }
		# A new file name per track, because Rainmeter caches images by path
		$script:coverCount++
		$path = Join-Path $coverDir "cover-$($script:coverCount).$extension"
		[System.IO.File]::WriteAllBytes($path, $bytes)
		Get-ChildItem $coverDir -File | Where-Object FullName -ne $path | Remove-Item -Force -ErrorAction SilentlyContinue
		$script:coverPath = $path
	} catch { }
}

# ---------------------------------------------------------------- State
function Get-AppName($id) {
	switch -Regex ($id) {
		'spotify'   { return 'Spotify' }
		'msedge'    { return 'Edge' }
		'chrome'    { return 'Chrome' }
		'firefox'   { return 'Firefox' }
		'ZuneMusic' { return 'Media Player' }
		'vlc'       { return 'VLC' }
	}
	return ($id -replace '!.*$', '' -replace '_\w+$', '' -replace '\.exe$', '')
}

function Clean($text) { return ("$text" -replace '[\r\n]+', ' ').Trim() }

function Get-State {
	$session = $manager.GetCurrentSession()
	if (-not $session) {
		return "status=None`ntitle=`nartist=`napp=`npos=0`ndur=0`ncover="
	}
	$props = Await ($session.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
	$status = "$($session.GetPlaybackInfo().PlaybackStatus)"
	$app = Get-AppName $session.SourceAppUserModelId

	$timeline = $session.GetTimelineProperties()
	$duration = ($timeline.EndTime - $timeline.StartTime).TotalSeconds
	$position = 0
	if ($duration -gt 0) {
		# The timeline is a snapshot from the app's last report; advance it while playing
		$position = $timeline.Position.TotalSeconds
		if ($status -eq 'Playing') { $position += ([DateTimeOffset]::Now - $timeline.LastUpdatedTime).TotalSeconds }
		$position = [Math]::Max(0, [Math]::Min($position, $duration))
	}

	Update-Cover "$app|$($props.Title)|$($props.Artist)" $props.Thumbnail
	return "status=$status`ntitle=$(Clean $props.Title)`nartist=$(Clean $props.Artist)`napp=$app`n" +
		"pos=$([int]$position)`ndur=$([int]$duration)`ncover=$($script:coverPath)"
}

function Get-Signature($session) {
	$props = Await ($session.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
	return "$($session.GetPlaybackInfo().PlaybackStatus)|$($props.Title)|$($props.Artist)"
}

# Sends the command, then waits (up to 600 ms) for the app to report the change,
# so the reply already carries the new state
function Invoke-MediaCommand($action) {
	$session = $manager.GetCurrentSession()
	if (-not $session) { return }
	$before = Get-Signature $session
	$operation = switch ($action) {
		'playpause' { $session.TryTogglePlayPauseAsync() }
		'next'      { $session.TrySkipNextAsync() }
		'prev'      { $session.TrySkipPreviousAsync() }
	}
	if (-not $operation) { return }
	Await $operation ([bool]) | Out-Null
	$deadline = [DateTime]::Now.AddMilliseconds(600)
	while ([DateTime]::Now -lt $deadline) {
		Start-Sleep -Milliseconds 25
		$session = $manager.GetCurrentSession()
		if (-not $session -or (Get-Signature $session) -ne $before) { return }
	}
}

# ---------------------------------------------------------------- Valheim server
$valheimDir = "${env:ProgramFiles(x86)}\Steam\steamapps\common\Valheim dedicated server"

# The end of the log, read without locking it (the server keeps it open)
function Read-LogTail($path, [int]$bytes = 262144) {
	$stream = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
	try {
		$start = [Math]::Max(0, $stream.Length - $bytes)
		$stream.Position = $start
		$reader = New-Object System.IO.StreamReader($stream)
		return $reader.ReadToEnd()
	} finally { $stream.Dispose() }
}

function Get-ValheimState {
	# Name, world and log file come from the .bat Steam runs to start the server
	$name = ''; $world = ''; $log = ''
	$bat = Join-Path $valheimDir 'start_headless_server.bat'
	if (Test-Path $bat) {
		$line = (Get-Content $bat | Where-Object { $_ -match '\s-name\s' -and $_ -notmatch '^\s*(rem|::|echo)' } | Select-Object -First 1)
		if ($line -match '-name\s+"([^"]*)"') { $name = $matches[1] }
		if ($line -match '-world\s+"([^"]*)"') { $world = $matches[1] }
		# Without -logFile the server only prints to its console, and there are no player details to read
		if ($line -match '-logFile\s+"([^"]+)"' -or $line -match '-logFile\s+(\S+)') {
			$log = $matches[1]
			if (-not [System.IO.Path]::IsPathRooted($log)) { $log = Join-Path $valheimDir $log }
		}
	}
	$process = Get-Process valheim_server -ErrorAction SilentlyContinue | Select-Object -First 1
	if (-not $process) {
		return "status=Offline`nname=$name`nworld=$world`nplayers=`njoincode=`nuptime=0"
	}
	$started = try { $process.StartTime } catch { [DateTime]::Now }
	$uptime = [int]([DateTime]::Now - $started).TotalSeconds

	# Running = up, but there's no log to read players from
	$status = 'Running'; $players = ''; $joinCode = ''
	# Only trust the log if it belongs to this run
	if ($log -and (Test-Path $log) -and (Get-Item $log).LastWriteTime -ge $started.AddSeconds(-5)) {
		$status = 'Online'
		$text = Read-LogTail $log
		# Crossplay servers log the count when someone joins or leaves ("...now 1 player(s)")
		# and every few minutes ("...is active with 1 player(s)"); the newest line wins
		$counts = [regex]::Matches($text, '(?:now|is active with) (\d+) player\(s\)')
		$codes = [regex]::Matches($text, 'join code (\d+)')
		$connections = [regex]::Matches($text, 'Connections (\d+) ZDOS')
		if ($codes.Count) { $joinCode = $codes[$codes.Count - 1].Groups[1].Value }
		if ($counts.Count) {
			$players = $counts[$counts.Count - 1].Groups[1].Value
		} elseif ($connections.Count) {
			$players = $connections[$connections.Count - 1].Groups[1].Value
		} elseif ($text -notmatch 'Game server connected') {
			$status = 'Starting'
		}
	}
	return "status=$status`nname=$name`nworld=$world`nplayers=$players`njoincode=$joinCode`nuptime=$uptime"
}

# ---------------------------------------------------------------- Request loop
$pending = $listener.GetContextAsync()
while ($true) {
	if (-not $pending.Wait(2000)) {
		if (-not (Get-Process Rainmeter -ErrorAction SilentlyContinue)) { break }
		continue
	}
	$context = $pending.Result
	$pending = $listener.GetContextAsync()
	try {
		$path = $context.Request.Url.AbsolutePath
		if ($path -eq '/valheim') {
			$reply = Get-ValheimState
		} else {
			if ($path -match '^/cmd/(\w+)$') {
				Invoke-MediaCommand $matches[1]
			}
			$reply = Get-State
		}
		$body = [System.Text.Encoding]::UTF8.GetBytes($reply)
		$context.Response.ContentType = 'text/plain; charset=utf-8'
	} catch {
		$body = [System.Text.Encoding]::UTF8.GetBytes("error=$(Clean $_.Exception.Message)")
		$context.Response.StatusCode = 500
	}
	$context.Response.OutputStream.Write($body, 0, $body.Length)
	$context.Response.Close()
}
$listener.Stop()
