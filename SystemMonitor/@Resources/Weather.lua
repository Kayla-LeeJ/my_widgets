-- Paints the Weather card: sky colors, sun, moon, stars, clouds, rain/snow and the text.
-- Refresh() runs when new data arrives from open-meteo; Update() repaints every 30 s so
-- the sky keeps following the clock.
-- Text with special characters goes through bang strings using Rainmeter's [\xNNNN]
-- codes: passing those characters through Lua directly garbles them.

local data

-- Sky colors as {top, bottom}
local SKY = {
	night = { {8, 12, 32}, {28, 36, 72} },
	dawn  = { {70, 80, 150}, {250, 160, 120} },
	day   = { {52, 120, 200}, {140, 195, 240} },
	dusk  = { {60, 50, 110}, {245, 120, 70} },
}
local OVERCAST_DAY = { {110, 120, 135}, {160, 165, 175} }
local OVERCAST_NIGHT = { {24, 26, 34}, {44, 46, 56} }

local KNOWN_NEW_MOON = 947182440        -- 2000-01-06 18:14 UTC
local LUNAR_MONTH = 29.530588853 * 86400

-- WMO weather codes: description, day icon, night icon, precipitation
local function describe(code)
	if code == 0 then return 'Clear', '2600', '263E'
	elseif code == 1 then return 'Mainly clear', '2600', '263E'
	elseif code == 2 then return 'Partly cloudy', '26C5', '2601'
	elseif code == 3 then return 'Overcast', '2601', '2601'
	elseif code == 45 or code == 48 then return 'Fog', '2601', '2601'
	elseif code >= 51 and code <= 57 then return 'Drizzle', '2602', '2602', 'rain'
	elseif code >= 61 and code <= 67 then return 'Rain', '2614', '2614', 'rain'
	elseif code >= 71 and code <= 77 then return 'Snow', '2744', '2744', 'snow'
	elseif code >= 80 and code <= 82 then return 'Showers', '2614', '2614', 'rain'
	elseif code == 85 or code == 86 then return 'Snow showers', '2744', '2744', 'snow'
	elseif code >= 95 then return 'Thunderstorm', '26C8', '26C8', 'storm'
	end
	return 'Unknown', '2601', '2601'
end

-- ---------------------------------------------------------------- helpers

local function round(x) return math.floor(x + 0.5) end

local function mix(a, b, t)
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function mixSky(a, b, t) return { mix(a[1], b[1], t), mix(a[2], b[2], t) } end

local function rgb(c) return round(c[1]) .. ',' .. round(c[2]) .. ',' .. round(c[3]) end

local function set(meter, option, value) SKIN:Bang('!SetOption', meter, option, value) end

-- For text containing [\xNNNN] codes
local function setText(meter, text) SKIN:Bang('[!SetOption ' .. meter .. ' Text "' .. text .. '"]') end

local function deg(x) return round(x) .. '[\\x00B0]' end

-- "2026-10-10T06:11" -> minutes after midnight
local function minutes(stamp)
	local h, m = stamp:match('T(%d+):(%d+)')
	return tonumber(h) * 60 + tonumber(m)
end

-- Repeatable "random" numbers so stars and raindrops don't jump around between repaints
local function sequence(seed)
	local state = seed
	return function(low, high)
		state = (state * 1103515245 + 12345) % 2147483648
		return low + (state / 2147483648) * (high - low)
	end
end

-- ---------------------------------------------------------------- data

local function parse(raw)
	local current = raw:match('"current":(%b{})')
	if not current then return nil end
	local function number(key) return tonumber(current:match('"' .. key .. '":([%-%d%.]+)')) end
	local function list(key)
		local items = {}
		local body = raw:match('"' .. key .. '":%[(.-)%]')
		if body then
			for item in body:gmatch('[^,]+') do items[#items + 1] = (item:gsub('"', '')) end
		end
		return items
	end
	return {
		temp = number('temperature_2m'),
		feels = number('apparent_temperature'),
		code = number('weather_code'),
		cover = number('cloud_cover') or 0,
		days = list('time'),
		codes = list('weather_code'),
		highs = list('temperature_2m_max'),
		lows = list('temperature_2m_min'),
		sunrises = list('sunrise'),
		sunsets = list('sunset'),
	}
end

-- ---------------------------------------------------------------- painting

-- Sky colors for the time of day, plus how "night" it is (0 day .. 1 night)
local function skyFor(now, sunrise, sunset)
	if now < sunrise - 60 or now > sunset + 60 then return SKY.night, 1 end
	if now < sunrise then
		local t = (now - (sunrise - 60)) / 60
		return mixSky(SKY.night, SKY.dawn, t), 1 - t
	end
	if now < sunrise + 60 then return mixSky(SKY.dawn, SKY.day, (now - sunrise) / 60), 0 end
	if now < sunset - 60 then return SKY.day, 0 end
	if now < sunset then return mixSky(SKY.day, SKY.dusk, (now - (sunset - 60)) / 60), 0 end
	local t = (now - sunset) / 60
	return mixSky(SKY.dusk, SKY.night, t), t
end

local previewPhase
local function paintMoon(alpha)
	local phase = previewPhase or ((os.time() - KNOWN_NEW_MOON) % LUNAR_MONTH) / LUNAR_MONTH   -- 0 new, 0.5 full
	local southern = tonumber(SKIN:GetVariable('WeatherLat')) < 0
	local r, c = 13, 16
	local cosine = math.cos(2 * math.pi * phase)
	local terminator = math.max(0.1, math.abs(cosine) * r)
	-- Waxing moons are lit on the right in the north and on the left in the south
	local litRight = (phase < 0.5) ~= southern
	local half = litRight and c or (c - r)
	local a = round(alpha)
	set('MeterMoon', 'Shape', 'Ellipse ' .. c .. ',' .. c .. ',' .. r .. ' | Fill Color 70,76,100,' .. round(alpha * 0.5) .. ' | StrokeWidth 0')
	set('MeterMoon', 'Shape2', 'Ellipse ' .. c .. ',' .. c .. ',' .. r .. ' | Fill Color 240,236,215,' .. a .. ' | StrokeWidth 0')
	set('MeterMoon', 'Shape3', 'Rectangle ' .. half .. ',' .. (c - r) .. ',' .. r .. ',' .. (2 * r))
	set('MeterMoon', 'Shape4', 'Ellipse ' .. c .. ',' .. c .. ',' .. terminator .. ',' .. r)
	-- Gibbous (more than half lit) adds the terminator ellipse, crescent cuts it away
	set('MeterMoon', 'Shape5', 'Combine Shape2 | Intersect Shape3 | ' .. (cosine < 0 and 'Union' or 'Exclude') .. ' Shape4')
end

local precipKind
local function paintPrecip(kind)
	if kind == precipKind then return end
	precipKind = kind
	local random = sequence(7)
	for i = 1, 20 do
		local x, y = random(150, 325), random(56, 112)
		local shape
		if kind == 'snow' then
			shape = 'Ellipse ' .. round(x) .. ',' .. round(y) .. ',1.8 | Fill Color 255,255,255,220 | StrokeWidth 0'
		else
			shape = 'Line ' .. round(x) .. ',' .. round(y) .. ',' .. round(x - 4) .. ',' .. round(y + 9) ..
				' | StrokeWidth 1.3 | Stroke Color 185,210,255,180 | StrokeStartCap Round | StrokeEndCap Round'
		end
		set('MeterPrecip', i == 1 and 'Shape' or ('Shape' .. i), shape)
	end
end

-- Set by Preview() to try other times of day / weather
local previewMinutes, previewCode, previewCover

local function paint()
	local today = os.date('%Y-%m-%d')
	local index = 1
	for i, day in ipairs(data.days) do if day == today then index = i end end

	local now = os.date('*t')
	local nowMinutes = previewMinutes or (now.hour * 60 + now.min)
	local realCode, realCover = data.code, data.cover
	data.code, data.cover = previewCode or realCode, previewCover or realCover
	local sunrise = data.sunrises[index] and minutes(data.sunrises[index]) or 360
	local sunset = data.sunsets[index] and minutes(data.sunsets[index]) or 1080
	local name, dayIcon, nightIcon, precip = describe(data.code or 0)

	-- Sky: time of day, then washed toward grey by cloud cover and bad weather
	local sky, night = skyFor(nowMinutes, sunrise, sunset)
	local cover = data.cover / 100
	local grey = cover * 0.65
	if precip or name == 'Fog' then grey = math.max(grey, 0.8) end
	sky = mixSky(sky, mixSky(OVERCAST_DAY, OVERCAST_NIGHT, night), grey)
	SKIN:Bang('!SetVariable', 'SkyTop', rgb(sky[1]))
	SKIN:Bang('!SetVariable', 'SkyBottom', rgb(sky[2]))

	-- Stars and moon fade in at night and hide behind clouds
	local clearness = 1 - math.min(1, grey * 1.3)
	SKIN:Bang('!SetVariable', 'StarAlpha', round(255 * night * clearness))
	SKIN:Bang('!SetVariable', 'StarAlphaDim', round(120 * night * clearness))
	if night > 0.2 and clearness > 0.15 then
		paintMoon(255 * math.min(1, night * 1.2) * clearness)
		SKIN:Bang('!ShowMeter', 'MeterMoon')
	else
		SKIN:Bang('!HideMeter', 'MeterMoon')
	end

	-- Sun travels an arc from sunrise to sunset
	if nowMinutes > sunrise and nowMinutes < sunset and grey < 0.8 then
		local f = (nowMinutes - sunrise) / (sunset - sunrise)
		local x, y = 22 + f * 296, 86 - math.sin(math.pi * f) * 66
		set('MeterSun', 'X', round(x - 24))
		set('MeterSun', 'Y', round(y - 24))
		SKIN:Bang('!ShowMeter', 'MeterSun')
	else
		SKIN:Bang('!HideMeter', 'MeterSun')
	end

	-- More clouds the cloudier it is; grey when it's raining, dim at night
	local cloudColor = mix({ 245, 248, 255 }, { 120, 130, 160 }, night)
	if precip then cloudColor = mix(cloudColor, { 150, 155, 168 }, 0.6) end
	SKIN:Bang('!SetVariable', 'CloudColor', rgb(cloudColor))
	local thresholds = { 0.12, 0.4, 0.7 }
	for i, threshold in ipairs(thresholds) do
		local visible = cover >= threshold or (precip and i <= 2)
		SKIN:Bang('!SetVariable', 'CloudAlpha' .. i, visible and round(150 + 80 * cover) or 0)
		SKIN:Bang(visible and '!ShowMeter' or '!HideMeter', 'MeterCloud' .. i)
	end

	if precip then
		paintPrecip(precip == 'snow' and 'snow' or 'rain')
		SKIN:Bang('!ShowMeter', 'MeterPrecip')
	else
		SKIN:Bang('!HideMeter', 'MeterPrecip')
	end
	SKIN:Bang(precip == 'storm' and '!ShowMeter' or '!HideMeter', 'MeterBolt')

	-- Text
	local isDay = night < 0.5
	setText('MeterTemp', data.temp and deg(data.temp) or '--')
	local condition = (not isDay and (name == 'Clear' or name == 'Mainly clear')) and (name .. ' night') or name
	if data.feels then condition = condition .. '  [\\x00B7]  feels ' .. deg(data.feels) end
	setText('MeterCondition', condition)
	if data.highs[index] then
		setText('MeterHiLo', 'H ' .. deg(tonumber(data.highs[index])) .. '   L ' .. deg(tonumber(data.lows[index])))
	end
	for n = 1, 3 do
		local i = index + n
		if data.days[i] then
			local y, m, d = data.days[i]:match('(%d+)-(%d+)-(%d+)')
			local weekday = os.date('%a', os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }))
			local _, icon = describe(tonumber(data.codes[i]) or 0)
			setText('MeterDay' .. n, weekday .. ' [\\x' .. icon .. '] ' ..
				deg(tonumber(data.highs[i])) .. '/' .. deg(tonumber(data.lows[i])))
		end
	end

	data.code, data.cover = realCode, realCover
	SKIN:Bang('!UpdateMeter', '*')
	SKIN:Bang('!Redraw')
end

-- ---------------------------------------------------------------- Rainmeter entry points

function Initialize()
	-- Fixed star field above the forecast strip; every third star is dimmer.
	-- #*Var*# keeps the variable unresolved, so the stars follow StarAlpha as it changes.
	local random = sequence(42)
	for i = 1, 28 do
		local alpha = (i % 3 == 0) and '#*StarAlphaDim*#' or '#*StarAlpha*#'
		local radius = (i % 5 == 0) and 1.3 or 0.8
		set('MeterStars', i == 1 and 'Shape' or ('Shape' .. i),
			'Ellipse ' .. round(random(8, 332)) .. ',' .. round(random(8, 112)) .. ',' .. radius ..
			' | Fill Color 255,255,255,' .. alpha .. ' | StrokeWidth 0')
	end
end

function Refresh()
	local parsed = parse(SKIN:GetMeasure('MeasureWeather'):GetStringValue())
	if parsed and parsed.temp then
		data = parsed
		paint()
	end
end

function Update()
	if data then paint() end
end

-- Try how the card looks at another time and weather, e.g. midday rain:
--   [!CommandMeasure MeasureSky "Preview(13, 61, 90)"]   (hour, WMO code, cloud cover %, moon phase 0-1)
-- Preview() with no arguments goes back to the real time and weather.
function Preview(hour, code, cover, phase)
	previewMinutes = hour and hour * 60 or nil
	previewCode, previewCover, previewPhase = code, cover, phase
	precipKind = nil
	Update()
end
