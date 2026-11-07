-- Helpers called from skins as inline section variables, e.g.
--   FontColor=[&MeasureScript:Color('MeasureGpuTemp', #GpuWarm#, #GpuHot#)]
-- They take a measure *name*: Rainmeter does not resolve [MeasureName] section
-- variables nested inside an inline Lua call. A value below 0 means "no data".

local function value(name)
	local measure = SKIN:GetMeasure(name)
	if not measure then return -1 end
	return measure:GetValue()
end

function Color(name, warm, hot)
	local v = value(name)
	if v < 0 then
		return SKIN:GetVariable('ColorDim')
	elseif v >= hot then
		return SKIN:GetVariable('ColorHot')
	elseif v >= warm then
		return SKIN:GetVariable('ColorWarm')
	end
	return SKIN:GetVariable('ColorCool')
end

-- Seconds as m:ss (or h:mm:ss)
function Duration(name)
	local v = value(name)
	if v < 0 then
		return '-:--'
	end
	v = math.floor(v)
	if v >= 3600 then
		return string.format('%d:%02d:%02d', math.floor(v / 3600), math.floor(v / 60) % 60, v % 60)
	end
	return string.format('%d:%02d', math.floor(v / 60), v % 60)
end

-- Now Playing: flip the play/pause icon the moment it's clicked. The helper's
-- reply arrives a moment later and confirms it through MeasureStatus.
function TogglePlayIcon()
	local playing = SKIN:GetMeasure('MeasureStatus'):GetStringValue() == 'Playing'
	-- The icon goes in as Rainmeter's [\xNNNN] code: passing the actual private-use
	-- character through Lua garbles it
	local icon = playing and 'E768' or 'E769'
	SKIN:Bang('[!SetOption MeterPlay Text "[\\x' .. icon .. ']"][!UpdateMeter MeterPlay][!Redraw]')
end

-- Seconds as a short "up 2h 14m" / "up 5m" / "up 3d 4h"
function Uptime(name)
	local v = math.floor(value(name))
	if v <= 0 then
		return ''
	end
	local days, hours, minutes = math.floor(v / 86400), math.floor(v / 3600) % 24, math.floor(v / 60) % 60
	if days > 0 then
		return string.format('up %dd %dh', days, hours)
	elseif hours > 0 then
		return string.format('up %dh %dm', hours, minutes)
	end
	return string.format('up %dm', minutes)
end

function Num(name, decimals)
	local v = value(name)
	if v < 0 then
		return '--'
	end
	return string.format('%.' .. (decimals or 0) .. 'f', v)
end
