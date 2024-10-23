--[[
	~ String Based Time Module ~
	Copyright (c) 2011 Lexi Robinson

	This module is free software: you can redistribute it and/or modify it under
	the terms of the GNU Lesser General Public License as published by the Free
	Software Foundation, either version 3 of the License, or (at your option)
	any later version.

	This module is distributed in the hope that it will be useful, but WITHOUT
	ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
	FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License
	for more details.

	You should have received a copy of the GNU Lesser General Public License
	along with this module. If not, see <https://www.gnu.org/licenses/>.
--]]

local error, tonumber, math, string = error, tonumber, math, string


---
-- This module provides various methods of describing time other than in terms of seconds, such as 6y5w4d3h2m1s to describe 6 years, 5 weeks, 4 days, 3 hours, 2 minutes and one second.
-- This can be used for making user input simplyer, as 6y is far more user friendly than 189341556.</p><p>
-- <!-- TODO: perhaps not have raw HTML in the lua file? :/ -->
-- <small><b>Constants:</b></small><ul style="font-size:small;">
-- <li><b>YEAR</b>: Used to specify years in unit conversions</li>
-- <li><b>WEEK</b>: Used to specify weeks in unit conversions</li>
-- <li><b>DAY</b>: Used to specify days in unit conversions</li>
-- <li><b>HOUR</b>: Used to specify hours in unit conversions</li>
-- <li><b>MINUTE</b>: Used to specify minutes in unit conversions</li></ul>
-- @release Version 1.0 Preemtive Release
local _time = {}


-- Unit Definitions
_time.YEAR   = 31556926
_time.WEEK   = 604800
_time.DAY    = 86400
_time.HOUR   = 3600
_time.MINUTE = 60

---
-- Converts time of one unit to seconds
-- @param time The time
-- @param unit The unit the time is in
-- @return The time in seconds
function _time.UnitToSeconds(time, unit)
	if not time then
		error("No time specified!", 2)
	elseif not (unit and tonumber(unit)) then
		error("Invalid unit specified!", 2)
	end
	return math.floor(time * unit)
end

---
-- Converts a time in seconds into units
-- @param time The time
-- @param unit The unit to convert the time to
-- @return The time in the unit specified
function _time.SecondsToUnit(time, unit)
	if not time then
		error("No time specified!", 2)
	elseif not (unit and tonumber(unit)) then
		error("Invalid unit specified!", 2)
	end
	return math.floor(time / unit)
end

---
-- Converts a timestring into seconds
-- @param str The timestring to converty
-- @return The specified time
function _time.TimestringToSeconds(str)
	if not str then
		error("No timestring specified!", 2)
	elseif str == "" then
		return 0
	end
	local years, weeks, days, hours, mins, secs
	years = tonumber(string.match(str, "(%d+)%s?y")) or 0
	weeks = tonumber(string.match(str, "(%d+)%s?w")) or 0
	days  = tonumber(string.match(str, "(%d+)%s?d")) or 0
	hours = tonumber(string.match(str, "(%d+)%s?h")) or 0
	mins  = tonumber(string.match(str, "(%d+)%s?m")) or 0
	secs  = tonumber(string.match(str, "(%d+)%s?s")) or 0
	return secs +
		mins * _time.MINUTE +
		hours * _time.HOUR +
		days * _time.DAY +
		weeks * _time.WEEK +
		years * _time.YEAR
end

---
-- Converts a time into a timestring
-- @param time The time in seconds
-- @return A human readable timestring
function _time.SecondsToTimestring(time)
	if not time then
		error("No time specified!", 2)
	end
	time = math.floor(time)
	local years, weeks, days, hours, minutes, seconds
	years = _time.SecondsToUnit(time, _time.YEAR)
	time = time - years * _time.YEAR
	weeks = _time.SecondsToUnit(time, _time.WEEK)
	time = time - weeks * _time.WEEK
	days = _time.SecondsToUnit(time, _time.DAY)
	time = time - days * _time.DAY
	hours = _time.SecondsToUnit(time, _time.HOUR)
	time = time - hours * _time.HOUR
	minutes = _time.SecondsToUnit(time, _time.MINUTE)
	time = time - minutes * _time.MINUTE
	seconds = time
	local str = ""
	if years > 0 then
		str = str .. years .. "y"
	end
	if weeks > 0 then
		str = str .. weeks .. "w"
	end
	if days > 0 then
		str = str .. days .. "d"
	end
	if hours > 0 then
		str = str .. hours .. "h"
	end
	if minutes > 0 then
		str = str .. minutes .. "m"
	end
	if seconds > 0 then
		str = str .. seconds .. "s"
	end
	return str
end

return _time
