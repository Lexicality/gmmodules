--[[ 
    ~ CSVars ~
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

-- Server functions
local umsg, pairs, error, SERVER, tostring = umsg, pairs, error, SERVER, tostring;
-- Client functions
local ErrorNoHalt, pcall, usermessage = ErrorNoHalt, pcall, usermessage;
-- Enums
CLASS_STRING    = 1;
CLASS_LONG      = 2;
CLASS_SHORT     = 3;
CLASS_BOOL      = 4;
CLASS_VECTOR    = 5;
CLASS_ENTITY    = 6;
CLASS_ANGLE     = 7;
CLASS_CHAR      = 8;
CLASS_FLOAT     = 9;
-- locals
local c_str = CLASS_STRING;
local c_lng = CLASS_LONG;
local c_srt = CLASS_SHORT;
local c_bln = CLASS_BOOL;
local c_vec = CLASS_VECTOR;
local c_ent = CLASS_ENTITY;
local c_ang = CLASS_ANGLE;
local c_chr = CLASS_CHAR;
local c_flt = CLASS_FLOAT;

if (CLIENT) then
    hook.Add("LocalPlayerCreated", "CSVars Startup", function(ply)
        CSVars.PlayerInitialized(ply)
    end);
end

---
-- Provides a method of automagically setting variables on a client's player object.
-- @version 0.1 Pre-release beta
module("CSVars")

local inverted = {
    [c_str] = "String";
    [c_lng] = "Long";
    [c_srt] = "Short";
    [c_bln] = "Bool";
    [c_vec] = "Vector";
    [c_ent] = "Entity";
    [c_ang] = "Angle";
    [c_chr] = "Char";
    [c_flt] = "Float";
}


if (SERVER) then
    local function handle(ply, class, key, value)
        umsg.Start("CSVar", ply);
            umsg.Char(class);
            umsg.String(key);
            local name = inverted[class];
            if (not name) then
                error("Unknown class '" .. tostring(class) .. "' for CSVar '" .. key .."'='" .. tostring(value) .."'!", 3);
            end
            umsg[name](value);
        umsg.End();
    end
    
    ---
    -- Sets a variable clientside on the player. Will not send the value if a player already has it
    -- @param ply The player to set the var on
    -- @param class One of the CLASS_ enums indicating the kind of variable
    -- @param key The name of the variable to set on the client
    -- @param value The value to set
    function SetPlayer(ply, class, key, value)
    if (ply.CSVars[key] == nil or ply.CSVars[key] ~= value) then
        ply.CSVars[key] = value;
        handle(ply, class, key, value);
        end
    end
    
    ---
    -- Sets a variable clientside on all players. *Will* send the value even if a client already has it.
    -- @param class One of the CLASS_ enums indicating the kind of variable
    -- @param key The name of the variable to set on the client
    -- @param value The value to set
    function SetGlobal(class, key, value)
        handle(nil, class, key, value);
        for _, ply in pairs(player.GetAll()) do
            ply.CSVars[key] = value;
        end
    end
    
    
else
    vars = {}
    local hooks = {};
    local lpl = NULL;
    ---
    -- Adds a hook to be called every time a CSVar is updated
    -- @param key The name of the CSVar to hook on
    -- @param name The unique name of the hook
    -- @param func (value, class) the hook callback
    function Hook(key, name, func)
        hooks[key] = hooks[key] or {};
        hooks[key][name] = func;
    end
    
    ---
    -- Removes a perviously active hook
    -- @param key The name of the CSVar the hook was on on
    -- @param name The unique name of the hook
    function UnHook(key, name)
        if (hooks[key] and hooks[key][name]) then
            hooks[key][name] = nil;
        end
    end
    local function singleVar(msg)
        local class = msg:ReadChar();
        local key = msg:ReadString();
        
        local name = inverted[class];
        if (not name) then
            ErrorNoHalt("Unknown class sent for CSVar '",key,"': ", class, "!");
            return;
        end
        local var = msg["Read" .. name](msg);
        vars[key] = var;
        if (hooks[key]) then
            for _, func in pairs(hooks[key]) do
                local res, err = pcall(func, var, class);
                if (not res) then
                    ErrorNoHalt("Error in CSVar hook '", name, "' for '", key, "': ", err);
                end
            end
        end
        -- Check if the local player is a valid entity.
        if (lpl ~= NULL) then
            lpl[key] = var;
        end
    end
    local function massVars(msg)
        local num = msg:ReadChar();
        for i = 1, num do
            singleVar(msg);
        end
    end
    usermessage.Hook("CSVar", singleVar);
    usermessage.Hook("MassCSVars", massVars);
    
    ---
    -- Called when the player's object is created and assigned to the global lpl
    function PlayerInitialized(ply)
        lpl = ply;
        for k, v in pairs(vars) do
            lpl[k] = v;
        end
    end
end

