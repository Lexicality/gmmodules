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
CreateConVar( "sb_version", "2.0.0", FCVAR_SPONLY + FCVAR_REPLICATED + FCVAR_NOTIFY, "The current version of the SourceBans.lua module" );
-- This creates a fake concommand that doesn't exist but makes the engine think it does. Useful.
AddConsoleCommand( "sb_reload", "Doesn't do anything - Legacy from the SourceMod version." );

local error, ErrorNoHalt, GetConVarNumber, GetConVarString, Msg, pairs, print, ServerLog, tonumber, tostring, tobool, IsValid =
      error, ErrorNoHalt, GetConVarNumber, GetConVarString, Msg, pairs, print, ServerLog, tonumber, tostring, tobool, IsValid ;

local game, hook, os, player, string, table, timer, bit =
      game, hook, os, player, string, table, timer, bit ;

local Deferred = require( 'promises' );
local database = require( 'database' );

---
-- Sourcebans.lua provides an interface to SourceBans through GLua, so that SourceMod is not required.
-- It also attempts to duplicate the effects that would be had by running SourceBans, such as the concommand and convars it creates.
-- @author Lex Robinson - lexi at lex dot me dot uk
-- @copyright 2011-2013 Lex Robinson - This code is released under the MIT License
-- @release version 2.0.0
module( "sourcebans" );
--[[
    CHANGELOG
    2.0.0 Rewrote database handling & added fixes provided by Blackawps
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
local dbConfig = {
    hostname = Hostname;
    username = Username;
    password = Password;
    database = Database;
    portnumb = Port    ;
}

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
    local function errPrint(err, midformat)
        if ( midformat ) then
            notifyerror( string.format( text, midformat, err ) );
        else
            notifyerror( string.format( text, err ) );
        end
    end
    if ( hascontext ) then
        return function( _, ... )
            return errPrint(...)
        end
    else
        return errPrint;
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
    Progress = function( data, name, steamID )
    -- TODO: Reason, time left
        notifymessage( name, " has been identified as ", data.name, ", who is banned. Kicking ... " );
        kickid( steamID );
        banid( steamID );
        queries["Log Join Attempt"]
            :Prepare( config.dbprefix, config.serverid, os.time(), name, data.bid )
            :SetCallbackArgs( name )
            :Run();
    end;
    Fail = errCallback( "check %s's ban status" );
} );
queries["Check for Bans by SteamID"]:SetCallbacks( {
    Fail = errCallback( "check %s's ban status" );
} );
queries["Get All Active Bans"]:SetCallbacks( {
    Fail = errCallback( "aquire every ban ever" );
} );
queries["Get Active Bans"]:SetCallbacks( {
    Fail = errCallback( "aquire page #%d of bans" );
} );
queries["Log Join Attempt"]:SetCallbacks( {
    Fail = errCallback( "store %s's foiled join attempt" );
} );
queries["Look up serverID"]:SetCallbacks( {
    Progress = function( data )
        config.serverid = data.sid;
    end;
    Fail = errCallback( "lookup the server's ID" );
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
    if not isActive() then return end
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
        end )
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
        :Then( loadAdmins );
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

        if ( not isActive() ) then
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
-- Checks to see if the database connection is currently active
-- @return bool
function IsActive()
    return isActive();
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
        :Prepare( config.dbprefix, numPerPage, offset )
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
    if ( dbConfig[key] ) then
        db:SetConnectionParameter( dbConfig[key], value );
    end
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

---
-- Reloads the admin list from the server.
function ReloadAdmins()
    loadAdmins();
end
