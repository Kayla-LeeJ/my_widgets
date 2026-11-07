; Defaults for every widget. Don't put your own settings here: run Setup.ps1, or put them in
; MyVariables.inc next to this file. It's loaded last, overrides anything below and isn't committed.
[Variables]
; ---------------------------------------------------------------- LibreHardwareMonitor
; Remote Web Server port (LibreHardwareMonitor: Options > Remote Web Server > Port)
Port=8085
; How often sensors are fetched, in skin updates (1 update = 1 second)
SensorUpdateRate=2
; Set by each skin at runtime: 1 when LibreHardwareMonitor answers, 0 when it can't be reached
LHMOk=0
; Grabs the whole number part of the sensor whose SensorId follows. Sensor IDs are
; listed in LibreHardwareMonitor's web page (http://localhost:8085) or data.json.
SensorRegExp=(?si)"Value":\s*"(\d+)[^"]*",\s*"Max":\s*"[^"]*",\s*"SensorId":\s*"

; ---------------------------------------------------------------- DeskHelper.ps1
; Local port for the helper behind the music and Valheim cards
HelperPort=8086
; Set by skins at runtime: 1 while the helper answers
HelperOk=0

; ---------------------------------------------------------------- Sensors
; Example IDs (Intel CPU, AMD GPU, three drives). Setup.ps1 finds yours and saves them to
; MyVariables.inc; the IDs are listed at http://localhost:8085 too.
CpuPackageTemp=/intelcpu/0/temperature/10
CpuCoreMaxTemp=/intelcpu/0/temperature/0

GPUName=GPU
GpuLoad=/gpu-amd/0/load/0
GpuTemp=/gpu-amd/0/temperature/0
GpuHotSpot=/gpu-amd/0/temperature/7
GpuVramUsed=/gpu-amd/0/smalldata/0
GpuVramTotal=/gpu-amd/0/smalldata/2

; Drive rows: label, temperature sensor, used-space sensor
Drive1Label=C:  System
Drive1Temp=/nvme/1/temperature/0
Drive1Used=/nvme/1/load/30
Drive2Label=D:  Data
Drive2Temp=/hdd/0/temperature/0
Drive2Used=/hdd/0/load/30
Drive3Label=E:  Backup
Drive3Temp=/hdd/2/temperature/0
Drive3Used=/hdd/2/load/30

; ---------------------------------------------------------------- Weather (open-meteo.com, no key needed)
; Example location. Setup.ps1 looks yours up from a city name.
WeatherCity=London
WeatherLat=51.51
WeatherLon=-0.13
; celsius or fahrenheit
WeatherUnits=celsius

; ---------------------------------------------------------------- Games
; Thunderstore Mod Manager profile used for modded Valheim (dock)
ThunderstoreProfile=Default
BattleNet=C:\Program Files (x86)\Battle.net\Battle.net.exe
; Icons per row in the dock before it wraps to a new row
DockColumns=9
; Games to leave out of the dock: names or Steam app IDs, comma-separated (e.g. Outlast,2124490)
DockHide=

; ---------------------------------------------------------------- Thresholds (warm / hot)
; Temperatures in degrees C
CpuWarm=60
CpuHot=80
GpuWarm=70
GpuHot=85
HotSpotWarm=85
HotSpotHot=100
; Drives: SSDs run hotter than spinning disks
Drive1Warm=55
Drive1Hot=70
Drive2Warm=45
Drive2Hot=55
Drive3Warm=45
Drive3Hot=55
; Drive fullness in percent
DiskWarm=85
DiskHot=95

; ---------------------------------------------------------------- Look
; Colour theme: a file in @Resources\Themes (Midnight, Sakura, Forest, Ocean, Mono).
; Right-click any widget > Theme to switch (saved in MyVariables.inc). The colours below are the fallback.
Theme=Midnight
ColorBg=18,18,24,190
ColorBorder=255,255,255,25
ColorText=235,235,240
ColorDim=140,140,155
ColorTrack=255,255,255,30
ColorCool=80,200,255
ColorWarm=255,180,60
ColorHot=255,80,80
ColorUpload=200,130,255
ColorGood=110,220,130
; Graph fill transparency (0-255)
GraphFillAlpha=50

FontFace=Segoe UI
; Icon font for the music buttons. Windows 10 doesn't have Segoe Fluent Icons: use Segoe MDL2 Assets there
IconFont=Segoe Fluent Icons

; ---------------------------------------------------------------- This PC
; Last, so it wins; then the theme it picks
@IncludeMine=#@#MyVariables.inc
@IncludeTheme=#@#Themes\#Theme#.inc
