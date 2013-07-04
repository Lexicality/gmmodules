--[[
    ~ Sourcebans GLua Module ~
    Copyright (c) 2011-2013 Lex Robinson

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
    associated documentation files ( the "Software" ), to deal in the Software without restriction,
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

-- These are put here to lower the amount of upvalues and so they're grouped together
-- They provide something like the documentation the SM ones do. 
CreateConVar( "sb_version", "2.0", FCVAR_SPONLY + FCVAR_REPLICATED + FCVAR_NOTIFY, "The current version of the SourceBans.lua module" );
-- This creates a fake concommand that doesn't exist but makes the engine think it does. Useful.
AddConsoleCommand( "sb_reload", "Doesn't do anything - Legacy from the SourceMod version." );

local error, ErrorNoHalt, GetConVarNumber, GetConVarString, Msg, pairs, print, ServerLog, tonumber, tostring, tobool, unpack =
      error, ErrorNoHalt, GetConVarNumber, GetConVarString, Msg, pairs, print, ServerLog, tonumber, tostring, tobool, unpack ;

local concommand, game, hook, math, os, player, string, table, timer =
      concommand, game, hook, math, os, player, string, table, timer ;

local HUD_PRINTCONSOLE, HUD_PRINTCENTER, HUD_PRINTNOTIFY, HUD_PRINTTALK = 
      HUD_PRINTCONSOLE, HUD_PRINTCENTER, HUD_PRINTNOTIFY, HUD_PRINTTALK ;

local Deferred = require( 'promises' );
local database = require( 'database' );

local nocmds;
if ( SBANS_NO_COMMANDS ) then
    nocmds = true;
    SBANS_NO_COMMANDS = nil;
end

---
-- Sourcebans.lua provides an interface to SourceBans through GLua, so that SourceMod is not required.
-- It also attempts to duplicate the effects that would be had by running SourceBans, such as the concommand and convars it creates.
-- @author Lex Robinson - lexi at lex dot me dot uk
-- @copyright 2011-2013 Lex Robinson - This code is released under the MIT License
-- @release version 2.0
module( "sourcebans" );
--[[
    CHANGELOG
    2.0   Rewrote database handling & added fixes provided by Blackawps
    1.54  Fixed the serverID grabber not actually grabbing serverIDs
    1.53  sm_rehash now goes through all online players and makes sure their group is up to date.
    1.521 Fixed a hang if an admin had no srv_flags and no srv_group
    1.52  Added various sm_#say commands at a request, and added a SBANS_NO_COMMANDS global variable to disable all admin commands ( for pure lua usage )
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
    1.2   Made CheckForBan( ) and BanPlayerBySteamIDAndIP( ) accessable
    1.12  Made the concommands check that the right amount of arguments had been passed.
    1.11  Fixed a typo that stopped the fix working
    1.1   Fixed the module freezing the server by pinging the database 10 times a second
--]]
--[[ Config ]]--
local config = {
    hostname = "localhost";
    username = "root";
    password = "";
    database = "sourcebans";
    dbprefix = "sbans";
    website  = "";
    portnumb = 3306;
    serverid = -1;
    dogroups = false;
    showbanreason = true;
};

local db = database.NewDatabase({
    Hostname = config.hostname;
    Username = config.username;
    Password = config.password;
    Database = config.database;
    Port     = config.portnumb;
});

--[[ Automatic IP Locator ]]--
local serverport = GetConVarNumber( "hostport" );
local serverip   = GetConVarString( 'ip' );
if ( not serverip ) then -- Thanks raBBish! http://www.facepunch.com/showpost.php?p=23402305&postcount=1382
    local hostip = GetConVarNumber( "hostip" );
    serverip = table.concat( {
        bit.band( hostip / 2^24, 0xFF );
        bit.band( hostip / 2^16, 0xFF );
        bit.band( hostip / 2^8,  0xFF );
        bit.band( hostip,        0xFF );
    }, '.' );
end

--[[ Tables ]]--
local admins, adminsByID, adminGroups, database;
local queries = {
    -- BanChkr
    ["Check for Bans"] = "SELECT bid, name, ends, authid, ip FROM %s_bans WHERE ( length = 0 OR ends > UNIX_TIMESTAMP()) AND removetype IS NULL AND (authid = '%s' OR ip = '%s' ) LIMIT 1";
    -- ["Check for Bans by IP"] = "SELECT bid, name, ends, authid, ip FROM %s_bans WHERE ( length = 0 OR ends > UNIX_TIMESTAMP() ) AND removetype IS NULL AND ip = '%s' LIMIT 1";
    ["Check for Bans by SteamID"] = "SELECT bid, name, ends, authid, ip FROM %s_bans WHERE ( length = 0 OR ends > UNIX_TIMESTAMP() ) AND removetype IS NULL AND authid = '%s' LIMIT 1";
    ["Get All Active Bans"] = "SELECT ip, authid, name, created, ends, length, reason, aid  FROM %s_bans WHERE ( length = 0 OR ends > UNIX_TIMESTAMP() ) AND removetype IS NULL;";
    ["Get Active Bans"] = "SELECT ip, authid, name, created, ends, length, reason, aid  FROM %s_bans WHERE (length = 0 OR ends > UNIX_TIMESTAMP()) AND removetype IS NULL LIMIT %d OFFSET %d;";
    
    ["Log Join Attempt"] = "INSERT INTO %s_banlog ( sid, time, name, bid) VALUES( %i, %i, '%s', %i )";
    
    -- Admins
    ["Select Admin Groups"] = "SELECT flags, immunity, name FROM %s_srvgroups";
    ["Select Admins"] = "SELECT a.aid, a.user, a.authid, a.srv_group, a.srv_flags, a.immunity FROM %s_admins a, %s_admins_servers_groups g WHERE g.server_id = %i AND g.admin_id = a.aid";

    -- Misc
    ["Look up serverID"] = "SELECT sid FROM %s_servers WHERE ip = '%s' AND port = '%s' LIMIT 1";
    
    -- Bannin
    ["Ban Player"] = "INSERT INTO %s_bans ( ip, authid, name, created, ends, length, reason, aid, adminIp, sid, country) VALUES('%s', '%s', '%s', %i, %i, %i, '%s', %i, '%s', %i, ' ' )";
    -- Unbannin
    ["Unban SteamID"] = "UPDATE %s_bans SET RemovedBy = %i, RemoveType = 'U', RemovedOn = UNIX_TIMESTAMP( ), ureason = '%s' WHERE ( length = 0 OR ends > UNIX_TIMESTAMP( ) ) AND removetype IS NULL AND authid = '%s'";
    ["Unban IPAddress"] = "UPDATE %s_bans SET RemovedBy = %i, RemoveType = 'U', RemovedOn = UNIX_TIMESTAMP( ), ureason = '%s' WHERE ( length = 0 OR ends > UNIX_TIMESTAMP( ) ) AND removetype IS NULL AND ip = '%s'";
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
local function notifyerror( ... )
    ErrorNoHalt( "[", os.date(), "][SourceBans.lua] ", ... );
    ErrorNoHalt( "\n" );
    print();
end
local function notifymessage( ... )
    local words = table.concat( { "[" , os.date() , "][SourceBans.lua] " , ... }, "" ) .. "\n";
    ServerLog( words );
    Msg( words );
end
local function banid( id )
    notifymessage( 'Blocked ', id, ' for 5 minutes' );
    game.ConsoleCommand( string.format( "banid 5 %s \n", id ) );
end

local function kickid( id, reason )
    reason = reason or "N/a";
    notifymessage( 'Kicked ', id, ' for ', reason );
    reason = string.format( "BANNED:\n%s\n%s", reason, config.website );
    local ply = idLookup[ id ];
    if ( IsValid( ply ) ) then
        ply:Kick( reason ); -- Thanks Garry!
    else
        game.ConsoleCommand( string.format( "kickid %s %s\n", id, reason:gsub("\n", " ") ) );
    end
end
local function cleanIP( ip )
    return string.match( ip, "(%d+%.%d+%.%d+%.%d+)" );
end
-- FIXME: Why?
local function getIP( ply )
    return cleanIP( ply:IPAddress() );
end
local function getAdminDetails( admin )
    if ( admin and admin:IsValid() ) then
        local data = admins[ admin:SteamID() ]
        if ( data ) then
            return data.aid, getIP( admin );
        end
    end
    return 0, serverip;
end
local function errCallback( midtext, hascontext )
    local text = string.format( "Unable to %s: %%s", midtext );
    notifyerror( "SQL Error while checking ", self.name, "'s ban status! ", err );
    if ( hascontext ) then
        return function( _, err, midformat )
            if ( midformat ) then
                notifyerror( string.format( text, midformat, err ) );
            else
                notifyerror( string.format( text, err ) );
            end
        end
    else
        return function( err, midformat )
            if ( midformat ) then
                notifyerror( string.format( text, midformat, err ) );
            else
                notifyerror( string.format( text, err ) );
            end
        end
    end
end
local function handleLegacyCallback( callback, promise )
    return promise
        :Done( function( result ) callback(true,  result); end )
        :Fail( function( errmsg ) callback(false, errmsg); end );
end
local function isActive()
    return db:IsConnected();
end
local function blankCallback() end

--[[ Set up Queries ]]--
for key, qtext in pairs( queries ) do
    queries[key] = db:PrepareQuery( qtext );
end

queries["Check for Bans"]:SetCallbacks( {
    Progress: function( data, name, steamID )
    -- TODO: Reason, time left
        notifymessage( name, " has been identified as ", data.name, ", who is banned. Kicking ... " );
        kickid( steamID );
        banid( steamID );
        queries["Log Join Attempt"]
            :Prepare( config.dbprefix, config.serverid, os.time(), name, data.bid )
            :SetCallbackArgs( name )
            :Run();
    end;
    Fail: errCallback( "check %s's ban status" );
} );
queries["Check for Bans by SteamID"]:SetCallbacks( {
    Fail: errCallback( "check %s's ban status" );
} );
queries["Get All Active Bans"]:SetCallbacks( {
    Fail: errCallback( "aquire every ban ever" );
} );
queries["Get Active Bans"]:SetCallbacks( {
    Fail: errCallback( "aquire page #%d of bans" );
} );
queries["Log Join Attempt"]:SetCallbacks( {
    Fail: errCallback( "store %s's foiled join attempt" );
} );
queries["Look up serverID"]:SetCallbacks( {
    Progress: function( data )
        config.serverid = data.sid;
    end;
    Fail: errCallback( "lookup the server's ID" );
});
--[[ Query Functions ]]--
local checkBan
local adminGroupLoaderOnSuccess, adminGroupLoaderOnFailure;
local loadAdmins, adminLoaderOnSuccess, adminLoaderOnData, adminLoaderOnFailure;
local doBan, banOnSuccess, banOnFailure;
local startDatabase, databaseOnConnected, databaseOnFailure;
local doUnban, unbanOnFailure;

-- Functions --
--
-- See if a player is banned and kick/ban them if they are.
-- @param ply The player
function checkBan( ply )-- steamID, ip, name )
    local steamID = ply:SteamID();
    return queries["Check for Bans"]
        :Prepare( config.dbprefix, steamID, getIP( ply ) )
        :SetCallbackArgs( ply:Name(), steamID )
        :Run();
end

function loadAdmins()
    admins = {};
    adminGroups = {};
    adminsByID = {};
    local query = database:query( queries["Select Admin Groups"]:format( config.dbprefix ) );
    query.onFailure = adminGroupLoaderOnFailure;
    query.onSuccess = adminGroupLoaderOnSuccess;
    query:start();
    notifymessage( "Loading Admin Groups . . ." );
end

function startDatabase( deferred )
    -- I don't see how but it might I guess
    if ( isActive() ) then
        if ( deferred ) then
            return deferred:Resolve();
        end
    end
    local deferred = deferred or Deferred();
    local cb = errCallback( "activate Sourcebans" );
    db:Connect()
        :Fail( function( errmsg )
            cb( errmsg );
            notifymessage( "Setting a reconnection timer for 60 seconds!" );
            timer.Simple( 60, function() startDatabase( deferred ); end );
        end );
        :Then( function()
            if ( config.serverid < 0 ) then
                return queries["Look up serverID"]
                    :Prepare( config.dbprefix, serverip, serverport )
                    :Run();
            end
        end )
        :Then( function()
            deferred:Resolve();
            for _, ply in pairs( player.GetAll() ) do
                checkBan( ply );
            end
        end)
        :Then( loadAdmins )
    return deferred:Promise();
end

function doUnban( query, id, reason, admin )
    local aid = getAdminDetails( admin )
    query = database:query( query:format( config.dbprefix, aid, database:escape( reason ), id ) );
    query.onFailure = unbanOnFailure;
    query.id = id;
    query:start();
end

function doBan( steamID, ip, name, length, reason, admin, callback )
    local time = os.time();
    local adminID, adminIP = getAdminDetails( admin );
    name = name or "";
    local query = database:query( queries["Ban Player"]:format( config.dbprefix, ip, steamID, database:escape( name), time, time + length, length, database:escape(reason ), adminID, adminIP, config.serverid ) );
    query.onSuccess = banOnSuccess;
    query.onFailure = banOnFailure;
    query.callback = callback;
    query.name = name;
    query:start();
    if ( config.showbanreason ) then
        if ( reason and string.Trim( reason ) == "" ) then
            reason = nil;
        end
        if ( reason == nil ) then
            reason = "No reason specified.";
        end
        reason = "BANNED: " .. reason;
    else
        reason = nil;
    end
    if ( steamID ~= "" ) then
        kickid( steamID, reason );
        banid( steamID );
    end
end
-- Data --
function adminLoaderOnSuccess( self )
    notifymessage( "Finished loading admins!" );
    for _, ply in pairs( player.GetAll() ) do
        local info = admins[ply:SteamID()];
        if ( info ) then
            if ( config.dogroups ) then
                ply:SetUserGroup( string.lower( info.srv_group ) )
            end
            ply.sourcebansinfo = info;
            notifymessage( ply:Name() .. " is now a " .. info.srv_group .. "!" );
        end
    end
end

function adminLoaderOnData( self, data )
    data.srv_group = data.srv_group or "NO GROUP ASSIGNED";
    data.srv_flags = data.srv_flags or "";
    local group = adminGroups[data.srv_group];
    if ( group ) then
        data.srv_flags = data.srv_flags .. ( group.flags or "" );
        if ( data.immunity < group.immunity ) then
            data.immunity = group.immunity;
        end
    end
    if ( string.find( data.srv_flags, 'z' ) ) then
        data.zflag = true;
    end
    admins[data.authid] = data;
    adminsByID[data.aid] = data;
    notifymessage( "Loaded admin ", data.user, " with group ", tostring( data.srv_group ), "." );
end

-- Success --
function adminGroupLoaderOnSuccess( self )
    local data = self:getData();
    for _, data in pairs( data ) do
        adminGroups[data.name] = data;
        notifymessage( "Loaded admin group ", data.name );
    end
    local query = database:query( queries["Select Admins"]:format( config.dbprefix,config.dbprefix,config.serverid ) );
    query.onSuccess = adminLoaderOnSuccess;
    query.onFailure = adminLoaderOnFailure;
    query.onData = adminLoaderOnData;
    query:start();  
    notifymessage( "Loading Admins . . ." );
end

function banOnSuccess( self )
    self.callback( true );
end

local function activeBansDataTransform( results )
    local ret = {}
    local adminName, adminID;
    for _, data in pairs( results ) do
        if ( data.aid ~= 0 ) then
            local admin = adminsByID[data.aid];
            if ( not admin ) then -- 
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
    return ret;
end

-- Failure --

function adminGroupLoaderOnFailure( self, err )
    notifyerror( "SQL Error while loading the admin groups! ", err );
end

function adminLoaderOnFailure( self, err )
    notifyerror( "SQL Error while loading the admins! ", err );
end

function banOnFailure( self, err )
    notifyerror( "SQL Error while storing ", self.name, "'s ban! ", err );
    self.callback( false, err );
end

function activeBansOnFailure( self, err )
    notifyerror( "SQL Error while loading all active bans! ", err );
    self.callback( false, err );
end

function unbanOnFailure( self, err )
    notifyerror( "SQL Error while removing the ban for ", self.id, "! ", err );
end

--[[ Hooks ]]--
do

    local function PlayerAuthed( ply, steamID )
        -- Always have this running.
        idLookup[steamID] = ply;

        if ( not  ) then
            notifyerror( "Player ", ply:Name(), " joined, but SourceBans.lua is not active!" );
            return;
        end
        checkBan( ply );
        if ( not admins ) then
            return;
        end
        local info = admins[ply:SteamID()];
        if ( info ) then
            if ( config.dogroups ) then
                ply:SetUserGroup( string.lower( info.srv_group ) )
            end
            ply.sourcebansinfo = info;
            notifymessage( ply:Name( ), " has joined, and they are a ", tostring(info.srv_group ), "!" );
        end
    end
    
    local function PlayerDisconnected( ply )
        idLookup[ply:SteamID()] = nil;
    end
        
    hook.Add( "PlayerAuthed", "SourceBans.lua - PlayerAuthed", PlayerAuthed );
    hook.Add( "PlayerDisconnected", "SourceBans.lua - PlayerDisconnected", PlayerDisconnected );
end


--[[ Exported Functions ]]--
local activated = false;

---
-- Starts the database and activates the module's functionality.
-- @return A promise object that will resolve once the module is active.
function Activate()
    if ( activated ) then
        error( "Do not call Activate() more than once!", 2 );
    end
    activated = true;
    notifymessage( "Starting the database." );
    return startDatabase();
end

---
-- Bans a player by object
-- @param ply The player to ban
-- @param time How long to ban the player for ( in seconds )
-- @param reason Why the player is being banned
-- @param admin ( Optional ) The admin who did the ban. Leave nil for CONSOLE.
-- @param callback ( Optional ) A function to call with the results of the ban. Passed true if it worked, false and a message if it didn't.
function BanPlayer( ply, time, reason, admin, callback )
    callback = callback or blankCallback;
    if ( not isActive() ) then
        return callback( false, "No Database Connection" );
    elseif ( not ply:IsValid() ) then
        error( "Expected player, got NULL!", 2 );
    end
    doBan( ply:SteamID( ), getIP( ply ), ply:Name( ), time, reason, admin, callback );
end

---
-- Bans a player by steamID
-- @param steamID The SteamID to ban
-- @param time How long to ban the player for ( in seconds )
-- @param reason Why the player is being banned
-- @param admin ( Optional ) The admin who did the ban. Leave nil for CONSOLE.
-- @param name ( Optional ) The name to give the ban if no active player matches the SteamID.
-- @param callback ( Optional ) A function to call with the results of the ban. Passed true if it worked, false and a message if it didn't.
function BanPlayerBySteamID( steamID, time, reason, admin, name, callback )
    callback = callback or blankCallback;
    if ( not isActive() ) then
        return callback( false, "No Database Connection" );
    end
    for _, ply in pairs( player.GetAll() ) do
        if ( ply:SteamID() == steamID ) then
            return BanPlayer( ply, time, reason, admin, callback );
        end
    end
    doBan( steamID, '', name, time, reason, admin, callback )
end

---
-- Bans a player by IPAddress
-- @param ip The IPAddress to ban
-- @param time How long to ban the player for ( in seconds )
-- @param reason Why the player is being banned
-- @param admin ( Optional ) The admin who did the ban. Leave nil for CONSOLE.
-- @param name ( Optional ) The name to give the ban if no active player matches the IP.
-- @param callback ( Optional ) A function to call with the results of the ban. Passed true if it worked, false and a message if it didn't.
function BanPlayerByIP( ip, time, reason, admin, name, callback )
    callback = callback or blankCallback;
    if ( not isActive() ) then
        return callback( false, "No Database Connection" );
    end
    for _, ply in pairs( player.GetAll() ) do
        if ( getIP( ply ) == ip ) then
            return BanPlayer( ply, time, reason, admin, callback );
        end
    end
    doBan( '', cleanIP( ip ), name, time, reason, admin, callback );
    game.ConsoleCommand( "addip 5 " .. ip .. "\n" );
end

---
-- Bans a player by SteamID and IPAddress
-- @param steamID The SteamID to ban
-- @param ip The IPAddress to ban
-- @param time How long to ban the player for ( in seconds )
-- @param reason Why the player is being banned
-- @param admin ( Optional ) The admin who did the ban. Leave nil for CONSOLE.
-- @param name ( Optional ) The name to give the ban
-- @param callback ( Optional ) A function to call with the results of the ban. Passed true if it worked, false and a message if it didn't.
function BanPlayerBySteamIDAndIP( steamID, ip, time, reason, admin, name, callback )
    callback = callback or blankCallback;
    if ( not isActive() ) then
        return callback( false, "No Database Connection" );
    end
    doBan( steamID, cleanIP( ip ), name, time, reason, admin, callback );
end


---
-- Unbans a player by SteamID
-- @param steamID The SteamID to unban
-- @param reason The reason they are being unbanned.
-- @param admin ( Optional ) The admin who did the unban. Leave nil for CONSOLE.
function UnbanPlayerBySteamID( steamID, reason, admin )
    if ( not isActive() ) then
        return false, "No Database Connection";
    end
    doUnban( queries["Unban SteamID"], steamID, reason, admin );
    game.ConsoleCommand( "removeid " .. steamID .. "\n" );
end

---
-- Unbans a player by IPAddress. If multiple players match the IP, they will all be unbanned.
-- @param ip The IPAddress to unban
-- @param reason The reason they are being unbanned.
-- @param admin ( Optional ) The admin who did the unban. Leave nil for CONSOLE.
function UnbanPlayerByIPAddress( ip, reason, admin )
    if ( not isActive() ) then
        return false, "No Database Connection";
    end
    doUnban( queries["Unban IPAddress"], ip, reason, admin );
    game.ConsoleCommand( "removeip " .. ip .. "\n" );
end

---
-- DEPRECATED Fetches all currently active bans in a table.
-- This function is deprecated in favour of GetActiveBans and exists purely for legacy. Do not use it in new code.
-- @see GetActiveBans
-- @param callback (optional) The function to be given the table
-- @return A promise object for the query
function GetAllActiveBans( callback )
    if ( not isActive() ) then
        error( "Not activated yet!", 2 );
    end
    local promise = queries["Get All Active Bans"]
        :Prepare( config.dbprefix )
        :Run()
        :Then( activeBansDataTransform );
    if ( callback ) then
        handleLegacyCallback(callback, promise);
    end
    return promise;
end

---
-- Fetches a page of currently active bans. <br />
-- This is preferred over GetAllActiveBans for load reasons. <br />
-- Fetches numPerPage bans starting with ban #((pageNum - 1) * numPerPage) <br />
-- If the ban was inacted by the server, the AdminID will be "STEAM_ID_SERVER". <br />
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
-- @param pageNum [Default: 1] The page # to fetch
-- @param numPerPage [Default: 20] The number of bans per page to fetch
-- @param callback (Optional, deprecated) The function to be passed the table.
-- @return A promise object for the query
function GetActiveBans( pageNum, numPerPage, callback )
    if ( not isActive() ) then
        error( "Not activated yet!", 2 );
    end
    pageNum = pageNum or 1;
    numPerPage = numPerPage or 20;
    local offset = ((pageNum - 1) * numPerPage);
    local promise = queries["Get Active Bans"]
        :Prepare( config.dbprefix, limit, offset )
        :SetCallbackArgs( pageNum )
        :Run()
        :Then( activeBansDataTransform );
    if ( callback ) then
        handleLegacyCallback(callback, promise);
    end
    return promise;
end

---
-- Set the config variables. This will trigger an error if you call it after Activate(). <br/>
-- NOTE: These settings do *NOT* persist. You will need to set them all each time.
-- @param key The settings key to set
-- @param value The value to set the key to.
-- @usage Acceptable keys: hostname, username, password, database, dbprefix, portnumb, serverid, website, showbanreason and dogroups.
function SetConfig( key, value )
    if ( activated ) then
        error( "Do not call SetConfig() after calling Activate()!", 2 );
    elseif ( config[key] == nil ) then
        error( "Invalid key provided. Please check your information.",2 );
    elseif ( key == "portnumb" or key == "serverid" ) then
        value = tonumber( value );
    elseif ( key == "showbanreason" or key == "dogroups" ) then
        value = tobool( value );
    end
    config[key] = value;
end


-- No longer required
function CheckStatus()
end

---
-- Checks to see if a SteamID is banned from the system
-- @param steamID The SteamID to check
-- @param callback (optional, deprecated) The callback function to tell the results to
-- @return A promise 
function CheckForBan( steamID, callback )
    if ( not isActive() ) then
        error( "Not activated yet!", 2 );
    elseif ( not steamID ) then
        error( "SteamID required!", 2 );
    end
    local promise = queries["Check for Bans by SteamID"]
        :Prepare( config.dbprefix, steamID )
        :SetCallbackArgs( steamID )
        :Run()
        :Then( function( results ) return #results > 0; end );
    if ( callback ) then
        handleLegacyCallback(callback, promise);
    end
    return promise;
end

---
-- Gets all the admins active on this server
-- @returns A table.
function GetAdmins()
    if ( not isActive() ) then
        error( "Not activated yet!", 2 );
    end
    local ret = {}
    for id,data in pairs( admins ) do
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
local function playerGet( id )
    local res, len, name, num, pname, lon;
    id = string.Trim( id );
    name = string.lower( id );
    num = tonumber( id );
    id = string.upper( id );
    for _, ply in pairs( player.GetAll() ) do
        pname = ply:Name( ):lower( );
        if ( ply:UserID( ) == num or ply:SteamID( ) == id or pname == name ) then
            return ply;
        elseif ( string.find( pname, name, 1, true ) ) then
            lon = pname:len();
            if ( res ) then
                if ( lon < len ) then
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
local function complain( ply, msg, lvl )
    if ( not ( ply and ply:IsValid() ) ) then
        print( msg );
    else
        ply:PrintMessage( lvl or HUD_PRINTCONSOLE, msg );
    end
    return false;
end
local function not4u( ply, cmd )
    ply:ChatPrint( "Unknown Command: '" .. cmd .. "'\n" );
end
-- Gets a steamID from concommand calls that don't bother to quote it.
local function getSteamID( tab )
    local a,b,c,d,e = tab[1], tab[2], tonumber( tab[3]), tab[4], tonumber(tab[5] );
    if ( string.find( a, "STEAM_%d:%d:%d+" ) ) then
        return table.remove( tab, 1 );
    elseif ( string.find( a, "STEAM_" ) and b == ":" and c and d == ":" and e ) then
        -- Kill the five entries as if they were one
        table.remove( tab, 1 );
        table.remove( tab, 1 );
        table.remove( tab, 1 );
        table.remove( tab, 1 );
        table.remove( tab, 1 );
        return a .. b .. c .. d .. e;
    end
end
-- Check if a player has authorisation to run the command.
local function authorised( ply, flag )
    if ( not ( ply and ply:IsValid() ) ) then
        return true;
    elseif ( not ply.sourcebansinfo ) then
        return false;
    end
    return ply.sourcebansinfo.zflag or string.find( ply.sourcebansinfo.srv_flags, flag );
end

local function complainer( ply, pl, time, reason, usage )
    if ( not pl ) then
        return complain( ply, "Invalid player!" .. usage );
    elseif ( not time or time < 0 ) then
        return complain( ply, "Invalid time!" .. usage );
    elseif ( reason == "" ) then
        return complain( ply, "Invalid reason!" .. usage );
    elseif ( time == 0 and not authorised( ply, FLAG_PERMA ) ) then
        return complain( ply, "You are not authorised to permaban!" );
    end
    return true;
end

concommand.Add( "sm_rehash", function(ply, cmd )
    if ( ply:IsValid()) then return not4u(ply, cmd ); end
    notifymessage( "Rehash command recieved, reloading admins:" );
    loadAdmins();
end, nil, "Reload the admin list from the SQL");

local usage = "\n - Usage: sm_psay <#userid|name|steamid> <words>";
concommand.Add( "sm_psay", function(ply, _, args )
    if ( nocmds and ply:IsValid() ) then
        return not4u( ply );
    elseif ( #args < 2 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not authorised( ply, FLAG_CHAT ) ) then
        return complain( ply, "You do not have access to this command!" );
    end
    local pl, words = table.remove( args,1), table.concat( args, " " ):Trim( );
    pl = playerGet( pl );
    if ( not pl ) then
        return complain( ply, "Invalid player!" .. usage );
    elseif ( words == "" ) then
        return complain( ply, "Invalid message!".. usage );
    end
    local name1 = ply:IsValid( ) and ply:Name( ) or "CONSOLE";
    local name2 = pl:Name();
    complain( ply, "( Private: " .. name2 .. " ) " .. name1 .. ": " .. words, HUD_PRINTCHAT );
    complain( pl,  "( Private: " .. name2 .. " ) " .. name1 .. ": " .. words, HUD_PRINTCHAT );
    notifymessage( name1, " triggered sm_psay to ", name2, " ( text ", words, " )" );
end, nil, "Sends a private message to a player" .. usage);

local usage = "\n - Usage: sm_say <words>";
concommand.Add( "sm_say", function(ply, _, args )
    if ( nocmds and ply:IsValid() ) then
        return not4u( ply );
    elseif ( #args < 1 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not authorised( ply, FLAG_CHAT ) ) then
        return complain( ply, "You do not have access to this command!" );
    end
    local words = table.concat( args, " "):Trim( );
    if ( words == "" ) then
        return complain( ply, "Invalid message!"..usage );
    end
    local name1 = ply:IsValid( ) and ply:Name( ) or "CONSOLE";
    for _, pl in pairs( player.GetAll() ) do
        if ( pl:IsValid( ) and not pl:IsBot( ) ) then
            complain( pl, name1 .. ": " .. words, HUD_PRINTCHAT );
        end
    end
    notifymessage( name1, " triggered sm_say ( text ", words, " )" );
end, nil, "Sends a message to everyone" .. usage);

local usage = "\n - Usage: sm_csay <words>";
concommand.Add( "sm_csay", function(ply, _, args )
    if ( nocmds and ply:IsValid() ) then
        return not4u( ply );
    elseif ( #args < 1 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not authorised( ply, FLAG_CHAT ) ) then
        return complain( ply, "You do not have access to this command!" );
    end
    local words = table.concat( args, " "):Trim( );
    if ( words == "" ) then
        return complain( ply, "Invalid message!"..usage );
    end
    local name1 = ply:IsValid( ) and ply:Name( ) or "CONSOLE";
    for _, pl in pairs( player.GetAll() ) do
        if ( pl:IsValid( ) and not pl:IsBot( ) ) then
            complain( pl, name1 .. ": " .. words, HUD_PRINTCENTER );
        end
    end
    notifymessage( name1, " triggered sm_csay ( text ", words, " )" );
end, nil, "Sends a message to everyone in the center of their screen" .. usage);

local usage = "\n - Usage: sm_chat <words>";
concommand.Add( "sm_chat", function(ply, _, args )
    if ( nocmds and ply:IsValid() ) then
        return not4u( ply );
    elseif ( #args < 1 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not authorised( ply, FLAG_CHAT ) ) then
        return complain( ply, "You do not have access to this command!" );
    end
    local words = table.concat( args, " "):Trim( );
    if ( words == "" ) then
        return complain( ply, "Invalid message!"..usage );
    end
    local name1 = ply:IsValid( ) and ply:Name( ) or "CONSOLE";
    for _, pl in pairs( player.GetAll() ) do
        if ( pl:IsValid( ) and pl:IsAdmin( ) ) then
            complain( pl, "( ADMINS ) " .. name1 .. ": " .. words, HUD_PRINTCHAT );
        end
    end
    notifymessage( name1, " triggered sm_chat ( text ", words, " )" );
end, nil, "Sends a message to all online admins" .. usage);

if ( nocmds ) then
    return;
end

local usage = "\n - Usage: sm_ban <#userid|name> <minutes|0> <reason>";
concommand.Add( "sm_ban", function(ply, _, args )
    if ( #args < 3 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not isActive() ) then
        return complain( ply, "Sourcebans has not been activated! Your command could not be completed." );
    elseif ( not authorised( ply, FLAG_BAN ) ) then
        return complain( ply, "You do not have access to this command!" );
    end
    local pl, time, reason = table.remove( args,1), tonumber( table.remove( args,1) ), table.concat(args, " " ):Trim( );
    pl = playerGet( pl );
    if ( not complainer( ply, pl, time, reason, usage ) ) then
        return;
    end
    local name = pl:Name();
    local function callback( res, err )
        if ( res ) then
            complain( ply, "sm_ban: " .. name .. " has been banned successfully." )
        else
            complain( ply, "sm_ban: " .. name .. " has not been banned. " .. err );
        end
    end
    BanPlayer( pl, time * 60, reason, ply, callback );
    complain( ply, "sm_ban: Your ban request has been sent to the database." );
end, nil, "Bans a player" .. usage);

-- Author's note: Why would you want to only ban someone by only their IP when you have their SteamID? This is a stupid concommand. Hopefully no one will use it.
local usage = "\n - Usage: sm_banip <ip|#userid|name> <minutes|0> <reason>";
concommand.Add( "sm_banip", function(ply, _, args )
    if ( #args < 3 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not isActive() ) then
        return complain( ply, "Sourcebans has not been activated! Your command could not be completed." );
    elseif ( not authorised( ply, FLAG_BAN ) ) then
        return complain( ply, "You do not have access to this command!" );
    end
    local id, time, reason = table.remove( args,1), tonumber( table.remove( args,1) ), table.concat(args, " " ):Trim( );
    local pl;
    if ( string.find( id, "%d+%.%d+%.%d+%.%d+" ) ) then
        for _, ply in pairs( player.GetAll() ) do
            if ( ply:SteamID() == id ) then
                pl = ply; 
                break;
            end
        end
        id = cleanIP( id );
    else
        pl = playerGet( id )
        id = nil;
        if ( pl ) then
            id = getIP( pl );
        end
    end
    if ( not complainer( ply, pl, time, reason, usage ) ) then
        return;
    end
    local name = pl:Name();
    kickid( pl:SteamID(), config.showbanreason and "Banned: " .. reason );
    game.ConsoleCommand( "addip 5 " .. id .. "\n" );
    local function callback( res, err )
        if ( res ) then
            complain( ply, "sm_banip: " .. name .. " has been IP banned successfully." )
        else
            complain( ply, "sm_banip: " .. name .. " has not been IP banned. " .. err );
        end
    end
    doBan( '', id, name, time * 60, reason, ply, callback )
    complain( ply, "sm_banip: Your ban request has been sent to the database." );
end, nil, "Bans a player by only their IP" .. usage);

local usage = "\n - Usage: sm_addban <minutes|0> <steamid> <reason>";
concommand.Add( "sm_addban", function(ply, _, args )
    if ( #args < 3 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not isActive() ) then
        return complain( ply, "Sourcebans has not been activated! Your command could not be completed." );
    elseif ( not authorised( ply, FLAG_ADDBAN ) ) then
        return complain( ply, "You do not have access to this command!" );
    end
    local time, id, reason = tonumber( table.remove( args,1)), getSteamID( args ), table.concat(args, " " ):Trim( );
    if ( not id ) then
        return complain( ply, "Invalid SteamID!" .. usage );
    elseif ( not time or time < 0 ) then
        return complain( ply, "Invalid time!" .. usage );
    elseif ( reason == "" ) then
        return complain( ply, "Invalid reason!" .. usage );
    elseif ( time == 0 and not authorised( ply, FLAG_PERMA ) ) then
        return complain( ply, "You are not authorised to permaban!" );
    end
    local function callback( res, err )
        if ( res ) then
            complain( ply, "sm_addban: " .. id .. " has been banned successfully." )
        else
            complain( ply, "sm_addban: " .. id .. " has not been banned. " .. err );
        end
    end
    BanPlayerBySteamID( id, time * 60, reason, ply, '', callback );
    complain( ply, "sm_addban: Your ban request has been sent to the database." );
end, nil, "Bans a player by their SteamID" .. usage);

local usage = "\n - Usage: sm_unban <steamid|ip> <reason>";
concommand.Add( "sm_unban", function(ply, _, args )
    if ( #args < 2 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not isActive() ) then
        return complain( ply, "Sourcebans has not been activated! Your command could not be completed." );
    elseif ( not authorised( ply, FLAG_UNBAN ) ) then
        return complain( ply, "You do not have access to this command!" );
    end
    local id, reason, func;
    if ( string.find( args[1], "%d+%.%d+%.%d+%.%d+" ) ) then
        id = table.remove( args,1 );
        func = UnbanPlayerByIPAddress;
    else
        id = getSteamID( args );
        func = UnbanPlayerBySteamID;
    end
    if ( not id ) then
        return complain( ply, "Invalid SteamID!" .. usage );
    end
    reason = table.concat( args, " "):Trim( )
    if ( reason == "" ) then
        return complain( ply, "Invalid reason!" .. usage );
    end
    func( id, reason, ply );
    complain( ply, "Your unban request has been sent to the database." );
end, nil, "Unbans a player" .. usage);
