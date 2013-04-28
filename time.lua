--[[
    ~ String Based Time Module ~
    Copyright (c) 2011 Lexi Robinson

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
    associated documentation files (the "Software"), to deal in the Software without restriction,
    including without limitation the rights to use, copy, modify, merge, publish, distribute,
    sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or
    substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
    NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
    WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--]]

local error, tonumber, math, string = error, tonumber, math, string;

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
module("time");

-- Unit Definitions
YEAR    = 31556926;
WEEK    = 604800;
DAY     = 86400;
HOUR    = 3600;
MINUTE  = 60;

---
-- Converts time of one unit to seconds
-- @param time The time
-- @param unit The unit the time is in
-- @return The time in seconds
function UnitToSeconds(time, unit)
    if (not time) then
        error("No time specified!", 2);
    elseif (not (unit and tonumber(unit))) then
        error("Invalid unit specified!", 2);
    end
    return math.floor(time * unit);
end

---
-- Converts a time in seconds into units
-- @param time The time
-- @param unit The unit to convert the time to
-- @return The time in the unit specified
function SecondsToUnit(time, unit)
    if (not time) then
        error("No time specified!", 2);
    elseif (not (unit and tonumber(unit))) then
        error("Invalid unit specified!", 2);
    end
    return math.floor(time / unit);
end

---
-- Converts a timestring into seconds
-- @param str The timestring to converty
-- @return The specified time
function TimestringToSeconds(str)
    if (not str) then
        error("No timestring specified!", 2);
    elseif (str == "") then
        return 0;
    end
    local years, weeks, days, hours, mins, secs;
    years = tonumber(string.match(str,"(%d+)%s?y")) or 0;
    weeks = tonumber(string.match(str,"(%d+)%s?w")) or 0;
    days  = tonumber(string.match(str,"(%d+)%s?d")) or 0;
    hours = tonumber(string.match(str,"(%d+)%s?h")) or 0;
    mins  = tonumber(string.match(str,"(%d+)%s?m")) or 0;
    secs  = tonumber(string.match(str,"(%d+)%s?s")) or 0;
    return  secs + 
            mins  * MINUTE + 
            hours * HOUR   +
            days  * DAY    +
            weeks * WEEK   +
            years * YEAR   ;
end

---
-- Converts a time into a timestring
-- @param time The time in seconds
-- @return A human readable timestring
function SecondsToTimestring(time)
    if (not time) then
        error("No time specified!", 2);
    end
    time = math.floor(time);
    local years, weeks, days, hours, minutes, seconds;
    years = SecondsToUnit(time, YEAR);
    time = time - years * YEAR;
    weeks = SecondsToUnit(time, WEEK);
    time = time - weeks * WEEK;
    days = SecondsToUnit(time, DAY);
    time = time - days * DAY;
    hours = SecondsToUnit(time, HOUR);
    time = time - hours * HOUR;
    minutes = SecondsToUnit(time, MINUTE);
    time = time - minutes * MINUTE;
    seconds = time;
    local str = "";
    if (years > 0) then
        str = str .. years .. "y";
    end if (weeks > 0) then
        str = str .. weeks .. "w";
    end if (days > 0) then
        str = str .. days .. "d";
    end if (hours > 0) then
        str = str .. hours .. "h";
    end if (minutes > 0) then
        str = str .. minutes .. "m";
    end if (seconds > 0) then
        str = str .. seconds .. "s";
    end
    return str;
end
