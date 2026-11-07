; Fetches LibreHardwareMonitor's whole sensor tree. Skins pick values out of it with
; child WebParser measures: URL=[MeasureLHM], StringIndex=1, RegExp=#SensorRegExp#<id>"

[MeasureLHM]
Measure=WebParser
URL=http://localhost:#Port#/data.json
UpdateRate=#SensorUpdateRate#
ForceReload=1
CodePage=65001
RegExp=(?s)^(.*)$
FinishAction=[!SetVariable LHMOk 1]
OnConnectErrorAction=[!SetVariable LHMOk 0]
OnRegExpErrorAction=[!SetVariable LHMOk 0]
