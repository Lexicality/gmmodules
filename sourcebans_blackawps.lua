--[[
    ~ Sourcebans GLua Module ~
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

    WARNING:
    Do *NOT* run with sourcemod active. It will have unpredictable effects!
--]]

require("tmysql");
require("gatekeeper");

-- These are put here to lower the amount of upvalues and so they're grouped together
-- They provide something like the documentation the SM ones do. 
CreateConVar("sb_version", "1.521", FCVAR_SPONLY + FCVAR_REPLICATED + FCVAR_NOTIFY, "The current version of the SourceBans.lua module");
-- This creates a fake concommand that doesn't exist but makes the engine think it does. Useful.
AddConsoleCommand("sb_reload", "Doesn't do anything - Legacy from the SourceMod version.");

local error, ErrorNoHalt, GetConVarNumber, GetConVarString, Msg, pairs, print, ServerLog, tonumber, tostring, tobool, unpack =
      error, ErrorNoHalt, GetConVarNumber, GetConVarString, Msg, pairs, print, ServerLog, tonumber, tostring, tobool, unpack ;

local concommand, game, hook, math, os, player, string, table, timer, tmysql, gatekeeper =
      concommand, game, hook, math, os, player, string, table, timer, tmysql, gatekeeper ;

local HUD_PRINTCONSOLE, HUD_PRINTCENTER, HUD_PRINTNOTIFY, HUD_PRINTTALK = 
      HUD_PRINTCONSOLE, HUD_PRINTCENTER, HUD_PRINTNOTIFY, HUD_PRINTTALK ;

local nocmds;
if (SBANS_NO_COMMANDS) then
    nocmds = true;
    SBANS_NO_COMMANDS = nil;
end

-- Sourcebans.lua provides an interface to SourceBans through GLua, so that SourceMod is not required.
-- It also attempts to duplicate the effects that would be had by running SourceBans, such as the concommand and convars it creates.
-- @release version 1.53 With added sm_*say commands, the SBANS_NO_COMMANDS directive, a fix for edge cases and better sm_rehash support
-- module("sourcebans");
--[[
    CHANGELOG
    1.53  sm_rehash now goes through all online players and makes sure their group is up to date.
    1.521 Fixed a hang if an admin had no srv_flags and no srv_group
    1.52  Added various sm_#say commands at a request, and added a SBANS_NO_COMMANDS global variable to disable all admin commands (for pure lua usage)
    1.51  Made it work again
    1.5   Made it support gatekeeper
    1.41  Fixed yet another 'stop loading admins' glitch
    1.4   Added GetAdmins(), made it work a bit more.
    1.317 Added even more error prevention when an admin doesn't have a server group but is assigned to the server
    1.316 Added error prevention when an admin doesn't have a server group but is assigned to the server
    1.315 Made sure callback was always actually a function even when not passed one, fixed a typo.
    1.31  Added some error checks, removed some sloppy assumptions and fixed queued ban checks not working.
    1.3   Pimped up the concommands and made them report more details
    1.22  Added dogroups to the config to disable automatic usergroup setting
    1.21  Made it so that the player is only kicked if their user object is available
    1.2   Made CheckForBan() and BanPlayerBySteamIDAndIP() accessable
    1.12  Made the concommands check that the right amount of arguments had been passed.
    1.11  Fixed a typo that stopped the fix working
    1.1   Fixed the module freezing the server by pinging the database 10 times a second
--]]
--[[

    CreateConVar("sb_version", SB_VERSION, _, FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
    RegServerCmd("sm_rehash",sm_rehash,"Reload SQL admins");
    RegAdminCmd("sm_ban", CommandBan, ADMFLAG_BAN, "sm_ban <#userid|name> <minutes|0> [reason]");
    RegAdminCmd("sm_banip", CommandBanIp, ADMFLAG_BAN, "sm_banip <ip|#userid|name> <time> [reason]");
    RegAdminCmd("sm_addban", CommandAddBan, ADMFLAG_RCON, "sm_addban <time> <steamid> [reason]");
    RegAdminCmd("sb_reload", ADMFLAG_RCON, "Reload sourcebans config and ban reason menu options");
    RegAdminCmd("sm_unban", CommandUnban, ADMFLAG_UNBAN, "sm_unban <steamid|ip> [reason]");
--]]
--[[ Config ]]--
local config = {
    hostname = "localhost";
    username = "root";
    password = "";
    database = "sourcebans";
    dbprefix = "sb_";
    website  = "bans.BreakpointServers.com";
    portnumb = 3306;
    serverid = -1;
    dogroups = false;
    showbanreason = false;
};
--[[ Automatic IP Locator ]]--
local serverport = GetConVarNumber("hostport");
local serverip = GetConVarString( "ip" ); -- This may break some peoples servers, since not everyone may use the -ip startup command, but the conversion of the hostname thing wasn't returning the right IP for me.
--]]

--[[ Tables ]]--
local admins, adminsByID, adminGroups;
local queries = {
    -- BanChkr
    ["Check for Bans"] = "SELECT bid, name, ends, authid, ip, length, reason FROM %s_bans WHERE (length = 0 OR ends > UNIX_TIMESTAMP()) AND removetype IS NULL AND (authid = '%s' OR ip = '%s') LIMIT 1";
    ["Check for Bans by IP"] = "SELECT bid, name, ends, authid, ip, length FROM %s_bans WHERE (length = 0 OR ends > UNIX_TIMESTAMP()) AND removetype IS NULL AND ip = '%s' LIMIT 1";
    ["Check for Bans by SteamID"] = "SELECT bid, name, ends, authid, ip, length, reason FROM %s_bans WHERE (length = 0 OR ends > UNIX_TIMESTAMP()) AND removetype IS NULL AND authid = '%s' LIMIT 1";
    ["Get All Active Bans"] = "SELECT ip, authid, name, created, ends, length, reason, aid  FROM %s_bans WHERE (length = 0 OR ends > UNIX_TIMESTAMP()) AND removetype IS NULL;";
    
    ["Log Join Attempt"] = "INSERT INTO %s_banlog (sid, time, name, bid) VALUES( %i, %i, '%s', %i)";
    
    -- Admins
    ["Select Server Groups"] = "SELECT g.gid, g.name FROM %s_groups g, %s_servers_groups s WHERE g.type = 3 AND s.server_id = %i AND g.gid = s.group_id";
    ["Select Admin Groups"] = "SELECT id, flags, immunity, name FROM %s_srvgroups";
    ["Select Admins"] = "SELECT a.aid, a.user, a.authid, a.srv_group, a.srv_flags, a.immunity FROM %s_admins a, %s_admins_servers_groups g WHERE g.server_id = %i AND g.admin_id = a.aid";
    ["Select Admins by server group"] = "SELECT a.aid, a.user, a.authid, a.srv_group, a.srv_flags, a.immunity FROM %s_admins a, %s_admins_servers_groups g WHERE g.srv_group_id = %i AND g.admin_id = a.aid";
    
    -- Bannin
    ["Ban Player"] = "INSERT INTO %s_bans (ip, authid, name, created, ends, length, reason, aid, adminIp, sid, country) VALUES('%s', '%s', '%s', %i, %i, %i, '%s', %i, '%s', %i, ' ')";
    -- Unbannin
    ["Unban SteamID"] = "UPDATE %s_bans SET RemovedBy = %i, RemoveType = 'U', RemovedOn = UNIX_TIMESTAMP(), ureason = '%s' WHERE (length = 0 OR ends > UNIX_TIMESTAMP()) AND removetype IS NULL AND authid = '%s'";
    ["Unban IPAddress"] = "UPDATE %s_bans SET RemovedBy = %i, RemoveType = 'U', RemovedOn = UNIX_TIMESTAMP(), ureason = '%s' WHERE (length = 0 OR ends > UNIX_TIMESTAMP()) AND removetype IS NULL AND ip = '%s'";
};
local idLookup = {};

--[[ ENUMs ]]--
-- Sourcebans
FLAG_BAN    = "d";
FLAG_PERMA  = "e";
FLAG_UNBAN  = "e";
FLAG_ADDBAN = "m";
FLAG_CHAT   = "j";

--[[ Convenience Functions ]]--
local function notifyerror(...)
    ErrorNoHalt("[", os.date(), "][SourceBans.lua] ", ...);
    ErrorNoHalt("\n");
    print();
end
local function notifymessage(...)
    local words = table.concat({"[",os.date(),"][SourceBans.lua] ",...},"").."\n";
    ServerLog(words);
    Msg(words);
end
local function banid(id)
    game.ConsoleCommand(string.format("banid 5 %s \n", id));
end
local function kickid(id, reason)
    -- Returns reason if reason isn't "" and isn't nil, or the other message.
    -- Probably shouldn't be allowed to do things like this but I am so hahahaha >:]
    reason = (reason ~= "" and string.format( "\nBANNED\nReason: %s", reason )) or "You are BANNED! Please check " .. config.website;
    local uid = idLookup[id];
    if (uid and gatekeeper) then
        gatekeeper.Drop(uid, reason);
        idLookup[id] = nil;
    else
        game.ConsoleCommand(string.format("kickid %s %s\n", id, reason));
    end
end
local function cleanIP(ip)
    return string.match(ip, "(%d+%.%d+%.%d+%.%d+)");
end
local function getIP(ply)
    return cleanIP(ply:IPAddress());
end
local function getAdminDetails(admin)
    if (admin and admin:IsValid()) then
        local data = admins[admin:SteamID()]
        if (data) then
            return data.aid, getIP(admin);
        end
    end
    return 0, serverip;
end
local function blankCallback() end


--[[ Query Functions ]]--
local banCheckerOnData, banCheckerOnFailure;
local joinAttemptLoggerOnFailure;
local adminGroupLoaderOnSuccess, adminGroupLoaderOnFailure;
local adminServerGroupLoaderOnSuccess, adminServerGroupLoaderOnFailure;
local loadAdmins, adminLoaderOnSuccess, adminLoaderOnData, adminLoaderOnFailure;
local doBan, banOnSuccess, banOnFailure;
local databaseOnConnected;
local activeBansOnSuccess, activeBansOnFailure;
local doUnban, unbanOnFailure;
local checkBanBySteamID, checkSIDOnSuccess, checkSIDOnFailure;

-- Functions --
function checkBan(steamID, ip, name)	

	local info = {
		steamID = steamID,
		name = name,
	}

	tmysql.query( queries["Check for Bans"]:format(config.dbprefix, steamID, ip), function( result, status, err )
		if status then
			for _,data in pairs( result ) do
				banCheckerOnData( info, data, dontkick )
			end
		else
			banCheckerOnFailure( info, data )
		end
	end, 1 )
end

function checkBanBySteamID(steamID, callback)
	tmysql.query( queries["Check for Bans by SteamID"]:format(config.dbprefix, steamID), function( result, status, err )
		if status then
			checkSIDOnSuccess( callback, result )
		else
			checkSIDOnFailure( callback, steamID, err )
		end
	end, 1 )
end

function GetCurrentBansByIP(ip, callback)
	tmysql.query( queries["Check for Bans by IP"]:format(config.dbprefix, ip), function( result, status, err )
		if status then
			callback( result )
		else
			checkIPOnFailure( callback, ip, err )
		end
	end, 1 )
end

function loadAdmins()
	admins = {};
	adminGroups = {};
	adminsByID = {};
	
	notifymessage("Loading Admin Groups . . .");
	
	tmysql.query( queries["Select Admin Groups"]:format(config.dbprefix), function( result, status, err )
		if status then
			adminGroupLoaderOnSuccess( result )
		else
			adminGroupLoaderOnFailure( err )
		end
	end, 1 )
	
	notifymessage("Loading Server Groups . . .");
	
	tmysql.query( queries["Select Server Groups"]:format(config.dbprefix,config.dbprefix,config.serverid), function( result, status, err )
		if status then
			adminServerGroupLoaderOnSuccess( result )
		else
			adminServerGroupLoaderOnFailure( err )
		end
	end, 1 )
end

function doUnban(id, reason, admin)
	tmysql.query( queries["Unban SteamID"]:format(config.dbprefix, aid, tmysql.escape(reason), id), function( result, status, err )
		if !status then
			unbanOnFailure( id, err )
		end
	end )
end

function doBan(steamID, ip, name, length, reason, admin, callback)
    local time = os.time();
    local adminID, adminIP = getAdminDetails(admin);
    name = name or "";
	
	tmysql.query( queries["Ban Player"]:format(config.dbprefix, ip, steamID, tmysql.escape(name), time, time + length, length, tmysql.escape(reason), adminID, adminIP, config.serverid), function( result, status, err )
		if status then
			banOnSuccess( callback )
		else
			banOnFailure( callback, name, err )
		end
	end )
	
    if (config.showbanreason) then
        if (reason and string.Trim(reason) == "") then
            reason = nil;
        end
        if (reason == nil) then
            reason = "No reason specified.";
        end
        reason = "BANNED: " .. reason;
    else
        reason = nil;
    end
    if (steamID ~= "") then
        kickid(steamID, reason);
        banid(steamID);
    end
	
end
-- Data --
function banCheckerOnData(self, data)
    notifymessage(self.name, " has been identified as ", data.name, ", who is banned. Kicking ... ");
    kickid(self.steamID, data.reason);
    banid(self.steamID);
	
	tmysql.query( queries["Log Join Attempt"]:format(config.dbprefix, config.serverid, os.time(), tmysql.escape(self.name), data.bid), function( result, status, err )
		if !status then
			joinAttemptLoggerOnFailure( self.name, err )
		end
	end )
end

function adminLoaderOnSuccess()
    for _, ply in pairs(player.GetAll()) do
        local info = admins[ply:SteamID()];
        if (info) then
            if (config.dogroups) then
                ply:SetUserGroup(string.lower(info.srv_group))
            end
            ply.sourcebansinfo = info;
            notifymessage(ply:Name() .. " is now a " .. info.srv_group .. "!");
        end
    end
end

function adminLoaderOnData(data)
    data.srv_group = data.srv_group or "NO GROUP ASSIGNED";
    data.srv_flags = data.srv_flags or "";
    local group = adminGroups[data.srv_group];
    if (group) then
        data.srv_flags = data.srv_flags .. (group.flags or "");
        if (data.immunity < group.immunity) then
            data.immunity = group.immunity;
        end
    end
    if (string.find(data.srv_flags, 'z')) then
        data.zflag = true;
    end
    admins[data.authid] = data;
    adminsByID[data.aid] = data;
    notifymessage("Loaded admin ", data.user, " with group ", tostring(data.srv_group), ".");
end

-- Success --
function adminGroupLoaderOnSuccess(data)
    notifymessage("Loading Admins . . .");
    for _, data in pairs(data) do
        adminGroups[data.name] = data;
        notifymessage("Loaded admin group ", data.name);
		
		tmysql.query( queries["Select Admins"]:format(config.dbprefix,config.dbprefix,data.id), function( result, status, err )
			if status then
				for _,data in pairs( result ) do
					adminLoaderOnData( data )
				end
				adminLoaderOnSuccess( data )
			else
				adminLoaderOnFailure( err )
			end
		end, 1 )
    end
end

function adminServerGroupLoaderOnSuccess(data)
    notifymessage("Loading Server Groups . . .");
    for _, data in pairs(data) do
        adminGroups[data.name] = data;
        notifymessage("Loaded server group ", data.name);
		
		tmysql.query( queries["Select Admins by server group"]:format(config.dbprefix,config.dbprefix,data.gid), function( result, status, err )
			if status then
				for _,data in pairs( result ) do
					adminLoaderOnData( data )
				end
				adminLoaderOnSuccess( data )
			else
				adminLoaderOnFailure( err )
			end
		end, 1 )
		
    end
end

function banOnSuccess(callback)
    callback(true);
end

function activeBansOnSuccess(callback, result)
    local ret = {}
    local adminName, adminID;
    for _, data in pairs(result) do
        if (data.aid ~= 0) then
            local admin = adminsByID[data.aid];
            if (not admin) then -- 
                adminName = "Unknown";
                adminID = "STEAM_ID_UNKNOWN";
            else
                adminName = admin.user;
                adminID = admin.authid
            end
        else
            adminName = "Console";
            adminID = "STEAM_ID_SERVER";
        end
        
        ret[#ret + 1] = {
            IPAddress   = data.ip;
            SteamID     = data.authid;
            Name        = data.name;
            BanStart    = data.created;
            BanEnd      = data.ends;
            BanLength   = data.length;
            BanReason   = data.reason;
            AdminName   = adminName;
            AdminID     = adminID;
        }
    end
    callback(ret);
end

function checkSIDOnSuccess(callback, data)
    callback(#data > 0);
end

-- Failure --
function banCheckerOnFailure(self, err)
    notifyerror("SQL Error while checking ", self.name, "'s ban status! ", err);
    kickid(self.steamID, "Failed to detect if you are banned!");
end

function joinAttemptLoggerOnFailure(name, err)
    notifyerror("SQL Error while storing ", name, "'s foiled join attempt! ", err);
end

function adminGroupLoaderOnFailure(err)
    notifyerror("SQL Error while loading the admin groups! ", err);
end

function adminServerGroupLoaderOnFailure(err)
    notifyerror("SQL Error while loading the server groups! ", err);
end

function adminLoaderOnFailure(err)
    notifyerror("SQL Error while loading the admins! ", err);
end

function banOnFailure(callback, name, err)
    notifyerror("SQL Error while storing ", name, "'s ban! ", err);
    callback(false, err);
end

function activeBansOnFailure(callback, err)
    notifyerror("SQL Error while loading all active bans! ", err);
    callback(false, err);
end

function unbanOnFailure(self, err)
    notifyerror("SQL Error while removing the ban for ", self.id, "! ", err);
end

function checkSIDOnFailure(callback, steamID, err)
    notifyerror("SQL Error while checking ", steamID, "'s ban status! ", err);
    callback(false, err);
end

function checkIPOnFailure(callback, ip, err)
    notifyerror("SQL Error while checking ", ip, "'s ban status! ", err);
    callback(false, err);
end
--[[ Hooks ]]--
do
    local function PlayerAuthed(ply, steamID)
        -- Always have this running.
        idLookup[steamID] = ply:UserID();
        checkBan(steamID, getIP(ply), ply:Name());
        if (not admins) then
            return;
        end
        local info = admins[ply:SteamID()];
        if (info) then
            if (config.dogroups) then
                ply:SetUserGroup(string.lower(info.srv_group))
            end
            ply.sourcebansinfo = info;
            notifymessage(ply:Name(), " has joined, and they are a ", tostring(info.srv_group), "!");
        end
    end
    
    local function PlayerDisconnected(ply)
        idLookup[ply:SteamID()] = nil;
    end
       
    hook.Add("PlayerAuthed", "SourceBans.lua - PlayerAuthed", PlayerAuthed);
    hook.Add("PlayerDisconnected", "SourceBans.lua - PlayerDisconnected", PlayerDisconnected);
end

---
-- Starts the database and activates the module's functionality.
function Activate()
    if (config.serverid < 0) then
        tmysql.query( string.format( "SELECT sid FROM %s_servers WHERE ip = '%s' AND port = '%s' LIMIT 1", config.dbprefix, serverip, serverport ), function( result, status, err )
			if status then
				for _,data in pairs( result ) do
					config.serverid = data.sid
				end
				if (not admins) then
					loadAdmins();
				end
			end
		end, 1 )
    end
    notifymessage("Starting the database.");
end

---
-- Bans a player by object
-- @param ply The player to ban
-- @param time How long to ban the player for (in seconds)
-- @param reason Why the player is being banned
-- @param admin (Optional) The admin who did the ban. Leave nil for CONSOLE.
-- @param callback (Optional) A function to call with the results of the ban. Passed true if it worked, false and a message if it didn't.
function BanPlayer(ply, time, reason, admin, callback)
    callback = callback or blankCallback;
    if (not ply:IsValid()) then
        error("Expected player, got NULL!", 2);
    end
    doBan(ply:SteamID(), getIP(ply), ply:Name(), time, reason, admin, callback);
end

---
-- Bans a player by steamID
-- @param steamID The SteamID to ban
-- @param time How long to ban the player for (in seconds)
-- @param reason Why the player is being banned
-- @param admin (Optional) The admin who did the ban. Leave nil for CONSOLE.
-- @param name (Optional) The name to give the ban if no active player matches the SteamID.
-- @param callback (Optional) A function to call with the results of the ban. Passed true if it worked, false and a message if it didn't.
function BanPlayerBySteamID(steamID, time, reason, admin, name, callback)
    callback = callback or blankCallback;
    for _, ply in pairs(player.GetAll()) do
        if (ply:SteamID() == steamID) then
            return BanPlayer(ply, time, reason, admin, callback);
        end
    end
    doBan(steamID, '', name, time, reason, admin, callback)
end

---
-- Bans a player by IPAddress
-- @param ip The IPAddress to ban
-- @param time How long to ban the player for (in seconds)
-- @param reason Why the player is being banned
-- @param admin (Optional) The admin who did the ban. Leave nil for CONSOLE.
-- @param name (Optional) The name to give the ban if no active player matches the IP.
-- @param callback (Optional) A function to call with the results of the ban. Passed true if it worked, false and a message if it didn't.
function BanPlayerByIP(ip, time, reason, admin, name, callback)
    callback = callback or blankCallback;
    for _, ply in pairs(player.GetAll()) do
        if (getIP(ply) == ip) then
            return BanPlayer(ply, time, reason, admin, callback);
        end
    end
    doBan('', cleanIP(ip), name, time, reason, admin, callback);
    game.ConsoleCommand("addip 5 " .. ip .. "\n");
end

---
-- Bans a player by SteamID and IPAddress
-- @param steamID The SteamID to ban
-- @param ip The IPAddress to ban
-- @param time How long to ban the player for (in seconds)
-- @param reason Why the player is being banned
-- @param admin (Optional) The admin who did the ban. Leave nil for CONSOLE.
-- @param name (Optional) The name to give the ban
-- @param callback (Optional) A function to call with the results of the ban. Passed true if it worked, false and a message if it didn't.
function BanPlayerBySteamIDAndIP(steamID, name, ip, time, reason, admin, callback)
    callback = callback or blankCallback;
    doBan(steamID, cleanIP(ip), name, time, reason, admin, callback);
end


---
-- Unbans a player by SteamID
-- @param steamID The SteamID to unban
-- @param reason The reason they are being unbanned.
-- @param admin (Optional) The admin who did the unban. Leave nil for CONSOLE.
function UnbanPlayerBySteamID(steamID, reason, admin)
    doUnban(steamID, reason, admin);
    game.ConsoleCommand("removeid " .. steamID .. "\n");
end

---
-- Unbans a player by IPAddress. If multiple players match the IP, they will all be unbanned.
-- @param ip The IPAddress to unban
-- @param reason The reason they are being unbanned.
-- @param admin (Optional) The admin who did the unban. Leave nil for CONSOLE.
function UnbanPlayerByIPAddress(ip, reason, admin)
    doUnban(ip, reason, admin);
    game.ConsoleCommand("removeip " .. ip .. "\n");
end

---
-- Fetches all currently active bans in a table.
-- If the ban was inacted by the server, the AdminID will be "STEAM_ID_SERVER".<br />
-- If the server does not know who the admin who commited the ban is, the AdminID will be "STEAM_ID_UNKNOWN".<br/>
-- Example table structure: <br/>
-- <pre>{ <br/>
-- &nbsp; BanStart = 1271453312, <br/>
-- &nbsp; BanEnd = 1271453312, <br/>
-- &nbsp; BanLength = 0, <br/>
-- &nbsp; BanReason = "'Previously banned for repeately crashing the server'", <br/>
-- &nbsp; IPAddress = "99.101.125.168", <br/>
-- &nbsp; SteamID = "STEAM_0:0:20924001", <br/>
-- &nbsp; Name = "MINOTAUR", <br/>
-- &nbsp; AdminName = "Lexi", <br/>
-- &nbsp; AdminID = "STEAM_0:1:16678762" <br/>
-- }</pre> <br/>
-- Bear in mind that SteamID or IPAddress may be a blank string.
-- @param callback The function to be given the table
function GetAllActiveBans(callback)
    if (not callback) then
        error("Function expected, got nothing!", 2);
    end
	
	tmysql.query( queries["Get All Active Bans"]:format(config.dbprefix), function( result, status, err )
		if status then
			activeBansOnSuccess( callback, result )
		else
			activeBansOnFailure( callback, err )
		end
	end, 1 )
end

---
-- Set the config variables. Most will not take effect until the next database connection.<br />
-- NOTE: These settings do *NOT* persist. You will need to set them all each time.
-- @param key The settings key to set
-- @param value The value to set the key to.
-- @usage Acceptable keys: hostname, username, password, database, dbprefix, portnumb, serverid, website, showbanreason and dogroups.
function SetConfig(key, value)
    if (config[key] == nil) then
        error("Invalid key provided. Please check your information.",2);
    end
    if (key == "portnumb" or key == "serverid") then
        value = tonumber(value);
    elseif (key == "showbanreason" or key == "dogroups") then
        value = tobool(value);
    end
    config[key] = value;
end

---
-- Checks to see if a SteamID is banned from the system
-- @param steamID The SteamID to check
-- @param callback The callback function to tell the results to
function CheckForBan(steamID, callback)
    if (not callback) then
        error("Callback function required!", 2);
    elseif (not steamID) then
        error("SteamID required!", 2);
    end
    checkBanBySteamID(steamID, callback);
end

---
-- Gets all the admins active on this server
-- @returns A table.
function GetAdmins()
    local ret = {}
    for id,data in pairs(admins) do
        ret[id] = {
            Name = data.user;
            SteamID = id;
            UserGroup = data.srv_group;
            AdminID = data.aid;
            Flags = data.srv_flags;
            ZFlagged = data.zflag;
            Immunity = data.immunity;
        }
    end
    return ret;
end



--[[ ConCommands ]]--



-- Borrowed from my gamemode
local function playerGet(id)
    local res, len, name, num, pname, lon;
    id = string.Trim(id);
    name = string.lower(id);
    num = tonumber(id);
    id = string.upper(id);
    for _, ply in pairs(player.GetAll()) do
        pname = ply:Name():lower();
        if (ply:UserID() == num or ply:SteamID() == id or pname == name) then
            return ply;
        elseif (string.find(pname, name, 1, true)) then
            lon = pname:len();
            if (res) then
                if (lon < len) then
                    res = ply;
                    len = lon;
                end
            else
                res = ply;
                len = lon;
            end
        end
    end
    return res;
end
local function complain(ply, msg, lvl)
    if (not (ply and ply:IsValid())) then
        print(msg);
    else
        ply:PrintMessage(lvl or HUD_PRINTCONSOLE, msg);
    end
    return false;
end
local function not4u(ply, cmd)
    ply:ChatPrint("Unknown Command: '" .. cmd .. "'\n");
end
-- Gets a steamID from concommand calls that don't bother to quote it.
local function getSteamID(tab)
    local a,b,c,d,e = tab[1], tab[2], tonumber(tab[3]), tab[4], tonumber(tab[5]);
    if (string.find(a, "STEAM_%d:%d:%d+")) then
        return table.remove(tab, 1);
    elseif (string.find(a, "STEAM_") and b == ":" and c and d == ":" and e) then
        -- Kill the five entries as if they were one
        table.remove(tab, 1);
        table.remove(tab, 1);
        table.remove(tab, 1);
        table.remove(tab, 1);
        table.remove(tab, 1);
        return a .. b .. c .. d .. e;
    end
end
-- Check if a player has authorisation to run the command.
local function authorised(ply, flag)
    if (not (ply and ply:IsValid())) then
        return true;
    elseif (not ply.sourcebansinfo) then
        return false;
    end
    return ply.sourcebansinfo.zflag or string.find(ply.sourcebansinfo.srv_flags, flag);
end

local function complainer(ply, pl, time, reason, usage)
    if (not pl) then
        return complain(ply, "Invalid player!" .. usage);
    elseif (not time or time < 0) then
        return complain(ply, "Invalid time!" .. usage);
    elseif (reason == "") then
        return complain(ply, "Invalid reason!" .. usage);
    elseif (time == 0 and not authorised(ply, FLAG_PERMA)) then
        return complain(ply, "You are not authorised to permaban!");
    end
    return true;
end

concommand.Add("sm_rehash", function(ply, cmd)
    if (ply:IsValid()) then return not4u(ply, cmd); end
    notifymessage("Rehash command recieved, reloading admins:");
    loadAdmins();
end, nil, "Reload the admin list from the SQL");

local usage = "\n - Usage: sm_psay <#userid|name|steamid> <words>";
concommand.Add("sm_psay", function(ply, _, args)
    if (nocmds and ply:IsValid()) then
        return not4u(ply);
    elseif (#args < 2) then
        return complain(ply, usage:sub(4));
    elseif (not authorised(ply, FLAG_CHAT)) then
        return complain(ply, "You do not have access to this command!");
    end
    local pl, words = table.remove(args,1), table.concat(args, " "):Trim();
    pl = playerGet(pl);
    if (not pl) then
        return complain(ply, "Invalid player!" .. usage);
    elseif (words == "") then
        return complain(ply, "Invalid message!".. usage);
    end
    local name1 = ply:IsValid() and ply:Name() or "CONSOLE";
    local name2 = pl:Name();
    complain(ply, "(Private: " .. name2 .. ") " .. name1 .. ": " .. words, HUD_PRINTCHAT);
    complain(pl,  "(Private: " .. name2 .. ") " .. name1 .. ": " .. words, HUD_PRINTCHAT);
    notifymessage(name1, " triggered sm_psay to ", name2, " (text ", words, ")");
end, nil, "Sends a private message to a player" .. usage);

local usage = "\n - Usage: sm_say <words>";
concommand.Add("sm_say", function(ply, _, args)
    if (nocmds and ply:IsValid()) then
        return not4u(ply);
    elseif (#args < 1) then
        return complain(ply, usage:sub(4));
    elseif (not authorised(ply, FLAG_CHAT)) then
        return complain(ply, "You do not have access to this command!");
    end
    local words = table.concat(args, " "):Trim();
    if (words == "") then
        return complain(ply, "Invalid message!"..usage);
    end
    local name1 = ply:IsValid() and ply:Name() or "CONSOLE";
    for _, pl in pairs(player.GetAll()) do
        if (pl:IsValid() and not pl:IsBot()) then
            complain(pl, name1 .. ": " .. words, HUD_PRINTCHAT);
        end
    end
    notifymessage(name1, " triggered sm_say (text ", words, ")");
end, nil, "Sends a message to everyone" .. usage);

local usage = "\n - Usage: sm_csay <words>";
concommand.Add("sm_csay", function(ply, _, args)
    if (nocmds and ply:IsValid()) then
        return not4u(ply);
    elseif (#args < 1) then
        return complain(ply, usage:sub(4));
    elseif (not authorised(ply, FLAG_CHAT)) then
        return complain(ply, "You do not have access to this command!");
    end
    local words = table.concat(args, " "):Trim();
    if (words == "") then
        return complain(ply, "Invalid message!"..usage);
    end
    local name1 = ply:IsValid() and ply:Name() or "CONSOLE";
    for _, pl in pairs(player.GetAll()) do
        if (pl:IsValid() and not pl:IsBot()) then
            complain(pl, name1 .. ": " .. words, HUD_PRINTCENTER);
        end
    end
    notifymessage(name1, " triggered sm_csay (text ", words, ")");
end, nil, "Sends a message to everyone in the center of their screen" .. usage);

local usage = "\n - Usage: sm_chat <words>";
concommand.Add("sm_chat", function(ply, _, args)
    if (nocmds and ply:IsValid()) then
        return not4u(ply);
    elseif (#args < 1) then
        return complain(ply, usage:sub(4));
    elseif (not authorised(ply, FLAG_CHAT)) then
        return complain(ply, "You do not have access to this command!");
    end
    local words = table.concat(args, " "):Trim();
    if (words == "") then
        return complain(ply, "Invalid message!"..usage);
    end
    local name1 = ply:IsValid() and ply:Name() or "CONSOLE";
    for _, pl in pairs(player.GetAll()) do
        if (pl:IsValid() and pl:IsAdmin()) then
            complain(pl, "(ADMINS) " .. name1 .. ": " .. words, HUD_PRINTCHAT);
        end
    end
    notifymessage(name1, " triggered sm_chat (text ", words, ")");
end, nil, "Sends a message to all online admins" .. usage);

if (nocmds) then
    return;
end

local usage = "\n - Usage: sm_ban <#userid|name> <minutes|0> <reason>";
local function banCommand(ply, _, args)
	if (#args < 3) then
        return complain(ply, usage:sub(4));
    elseif (not authorised(ply, FLAG_BAN)) then
        return complain(ply, "You do not have access to this command!");
    end
    local pl, time, reason = table.remove(args,1), tonumber(table.remove(args,1)), table.concat(args, " "):Trim();
    pl = playerGet(pl);
    if (not complainer(ply, pl, time, reason, usage)) then
        return;
    end
    local name = pl:Name();
    local function callback(res, err)
        if (res) then
            complain(ply, "sm_ban: " .. name .. " has been banned successfully.")
        else
            complain(ply, "sm_ban: " .. name .. " has not been banned. " .. err);
        end
    end
    BanPlayer(pl, time * 60, reason, ply, callback);
    complain(ply, "sm_ban: Your ban request has been sent to the database.");
end
concommand.Add("sm_ban", banCommand, nil, "Bans a player" .. usage);

-- Author's note: Why would you want to only ban someone by only their IP when you have their SteamID? This is a stupid concommand. Hopefully no one will use it.
local usage = "\n - Usage: sm_banip <ip|#userid|name> <minutes|0> <reason>";
local function banIPCommand(ply, _, args)
	if (#args < 3) then
        return complain(ply, usage:sub(4));
    elseif (not authorised(ply, FLAG_BAN)) then
        return complain(ply, "You do not have access to this command!");
    end
    local id, time, reason = table.remove(args,1), tonumber(table.remove(args,1)), table.concat(args, " "):Trim();
    local pl;
    if (string.find(id, "%d+%.%d+%.%d+%.%d+")) then
        for _, ply in pairs(player.GetAll()) do
            if (ply:SteamID() == id) then
                pl = ply; 
                break;
            end
        end
        id = cleanIP(id);
    else
        pl = playerGet(id)
        id = nil;
        if (pl) then
            id = getIP(pl);
        end
    end
    if (not complainer(ply, pl, time, reason, usage)) then
        return;
    end
    local name = pl:Name();
    kickid(pl:SteamID(), config.showbanreason and "Banned: " .. reason);
    game.ConsoleCommand("addip 5 " .. id .. "\n");
    local function callback(res, err)
        if (res) then
            complain(ply, "sm_banip: " .. name .. " has been IP banned successfully.")
        else
            complain(ply, "sm_banip: " .. name .. " has not been IP banned. " .. err);
        end
    end
    doBan('', id, name, time * 60, reason, ply, callback)
    complain(ply, "sm_banip: Your ban request has been sent to the database.");
end
concommand.Add("sm_banip", banIPCommand, nil, "Bans a player by only their IP" .. usage);

local usage = "\n - Usage: sm_addban <minutes|0> <steamid> <reason>";
local function banCommand(ply, _, args)
	if (#args < 3) then
        return complain(ply, usage:sub(4));
    elseif (not authorised(ply, FLAG_ADDBAN)) then
        return complain(ply, "You do not have access to this command!");
    end
    local time, id, reason = tonumber(table.remove(args,1)), getSteamID(args), table.concat(args, " "):Trim();
    if (not id) then
        return complain(ply, "Invalid SteamID!" .. usage);
    elseif (not time or time < 0) then
        return complain(ply, "Invalid time!" .. usage);
    elseif (reason == "") then
        return complain(ply, "Invalid reason!" .. usage);
    elseif (time == 0 and not authorised(ply, FLAG_PERMA)) then
        return complain(ply, "You are not authorised to permaban!");
    end
    local function callback(res, err)
        if (res) then
            complain(ply, "sm_addban: " .. id .. " has been banned successfully.")
        else
            complain(ply, "sm_addban: " .. id .. " has not been banned. " .. err);
        end
    end
    BanPlayerBySteamID(id, time * 60, reason, ply, '', callback);
    complain(ply, "sm_addban: Your ban request has been sent to the database.");
end
concommand.Add("sm_addban", banCommand, nil, "Bans a player by their SteamID" .. usage);

local usage = "\n - Usage: sm_unban <steamid|ip> <reason>";
local function unBanCommand(ply, _, args)
	if (#args < 2) then
        return complain(ply, usage:sub(4));
    elseif (not authorised(ply, FLAG_UNBAN)) then
        return complain(ply, "You do not have access to this command!");
    end
    local id, reason, func;
    if (string.find(args[1], "%d+%.%d+%.%d+%.%d+")) then
        id = table.remove(args,1);
        func = UnbanPlayerByIPAddress;
    else
        id = getSteamID(args);
        func = UnbanPlayerBySteamID;
    end
    if (not id) then
        return complain(ply, "Invalid SteamID!" .. usage);
    end
    reason = table.concat(args, " "):Trim()
    if (reason == "") then
        return complain(ply, "Invalid reason!" .. usage);
    end
    func(id, reason, ply);
    complain(ply, "Your unban request has been sent to the database.");
end
concommand.Add("sm_unban", unBanCommand, nil, "Unbans a player" .. usage);
