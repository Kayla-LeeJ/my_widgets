; For skins that read from DeskHelper.ps1 (http://localhost:#HelperPort#).
; The skin's WebParser sets HelperOk to 1 when the helper answers and 0 when it doesn't.

; Starts the helper when it isn't answering (at load, then every 15 s while down).
; A second copy exits on its own, so an extra launch is harmless.
[MeasureHelper]
Measure=Calc
Formula=#HelperOk#
DynamicVariables=1
UpdateDivider=15
IfCondition=MeasureHelper = 0
IfTrueAction=["conhost.exe" --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "#@#DeskHelper.ps1" -Port #HelperPort#]
IfConditionMode=1
