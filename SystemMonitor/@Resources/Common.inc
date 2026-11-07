; Shared by every card. Each skin sets CardH in its own [Variables] section.

[Rainmeter]
Update=1000
AccurateText=1

[MeasureScript]
Measure=Script
ScriptFile=#@#Helpers.lua

[MeterBackground]
Meter=Shape
Shape=Rectangle 0.5,0.5,(#CardW#-1),(#CardH#-1),12 | Fill Color #ColorBg# | StrokeWidth 1 | Stroke Color #ColorBorder#

[StyleText]
FontFace=#FontFace#
FontColor=#ColorText#
AntiAlias=1

[StyleLabel]
FontFace=#FontFace#
FontColor=#ColorDim#
FontSize=8
AntiAlias=1

[StyleTitle]
FontFace=#FontFace#
FontColor=#ColorDim#
FontSize=9
StringStyle=Bold
AntiAlias=1
X=16
Y=12

[StyleBig]
FontFace=#FontFace#
FontColor=#ColorText#
FontSize=24
StringStyle=Bold
AntiAlias=1
