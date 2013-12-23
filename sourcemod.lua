--[[
	~ SourceMod Replacement Service ~
    Copyright (c) 2011-2013 Lex Robinson
    This code is freely available under the terms of the MIT license.

  	*WARNING* This is not a module! Put it in /lua/autorun!

  	This file provides various concommands from SourceMod/SourceBans
--]]

local sourcebans = require "sourcebans";

-- Edit this config to match the one the website gives you

sourcebans.SetConfig("hostname", "localhost");       -- Database Hostname
sourcebans.SetConfig("username", "root");            -- Database Login name
sourcebans.SetConfig("password", "");                -- Database Login Password
sourcebans.SetConfig("database", "sourcebans");      -- Database 'database' or 'schema' selection
sourcebans.SetConfig("dbprefix", "sbans");           -- Prefix for tables in the database. (This example would say your tables are called sbans_bans and so on)
sourcebans.SetConfig("portnumb", 3306);	             -- Database Port number
sourcebans.SetConfig("serverid", 1);                 -- The ID given to this server by the SourceBans website
sourcebans.SetConfig("website", "bans.example.com"); -- The URL where people can find your sourcebans install (Do not put http:// or the kick reason will break!)
sourcebans.SetConfig("showbanreason", false);        -- Show the ban reason in the kick message. Do not use if you do not have gatekeeper installed or you will crash people sometimes.
sourcebans.SetConfig("dogroups", false);             -- Set user groups or not. Set this to false unless your admins are in a servergroup called 'Admin' and your superadmins are in 'SuperAdmin'.

-- Do not edit below this line





sourcebans.Activate();

local function notifymessage( ... )
    local words = table.concat( { "[" , os.date() , "][sourcemod.lua] " , ... }, "" ) .. "\n";
    ServerLog( words );
    Msg( words );
end

-- Borrowed from my gamemode, Applejack
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
    elseif ( time == 0 and not authorised( ply, sourcebans.FLAG_PERMA ) ) then
        return complain( ply, "You are not authorised to permaban!" );
    end
    return true;
end

concommand.Add( "sm_rehash", function(ply, cmd )
    if ( ply:IsValid()) then return not4u(ply, cmd ); end
    notifymessage( "Rehash command recieved, reloading admins:" );
    sourcebans.ReloadAdmins();
end, nil, "Reload the admin list from the SQL");

local usage = "\n - Usage: sm_psay <#userid|name|steamid> <words>";
concommand.Add( "sm_psay", function(ply, _, args )
    if ( #args < 2 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not authorised( ply, sourcebans.FLAG_CHAT ) ) then
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
    if ( #args < 1 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not authorised( ply, sourcebans.FLAG_CHAT ) ) then
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
    if ( #args < 1 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not authorised( ply, sourcebans.FLAG_CHAT ) ) then
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
    if ( #args < 1 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not authorised( ply, sourcebans.FLAG_CHAT ) ) then
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

local usage = "\n - Usage: sm_ban <#userid|name> <minutes|0> <reason>";
concommand.Add( "sm_ban", function(ply, _, args )
    if ( #args < 3 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not sourcebans.IsActive() ) then
        return complain( ply, "Sourcebans has not been activated! Your command could not be completed." );
    elseif ( not authorised( ply, sourcebans.FLAG_BAN ) ) then
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
    sourcebans.BanPlayer( pl, time * 60, reason, ply, callback );
    complain( ply, "sm_ban: Your ban request has been sent to the database." );
end, nil, "Bans a player" .. usage);

-- Author's note: Why would you want to only ban someone by only their IP when you have their SteamID? This is a stupid concommand. Hopefully no one will use it.
local usage = "\n - Usage: sm_banip <ip|#userid|name> <minutes|0> <reason>";
concommand.Add( "sm_banip", function(ply, _, args )
    if ( #args < 3 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not sourcebans.IsActive() ) then
        return complain( ply, "Sourcebans has not been activated! Your command could not be completed." );
    elseif ( not authorised( ply, sourcebans.FLAG_BAN ) ) then
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
    error("Whoops! Not yet worked out how to forward this function");
    -- FIXME doBan( '', id, name, time * 60, reason, ply, callback )
    complain( ply, "sm_banip: Your ban request has been sent to the database." );
end, nil, "Bans a player by only their IP" .. usage);

local usage = "\n - Usage: sm_addban <minutes|0> <steamid> <reason>";
concommand.Add( "sm_addban", function(ply, _, args )
    if ( #args < 3 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not sourcebans.IsActive() ) then
        return complain( ply, "Sourcebans has not been activated! Your command could not be completed." );
    elseif ( not authorised( ply, sourcebans.FLAG_ADDBAN ) ) then
        return complain( ply, "You do not have access to this command!" );
    end
    local time, id, reason = tonumber( table.remove( args,1)), getSteamID( args ), table.concat(args, " " ):Trim( );
    if ( not id ) then
        return complain( ply, "Invalid SteamID!" .. usage );
    elseif ( not time or time < 0 ) then
        return complain( ply, "Invalid time!" .. usage );
    elseif ( reason == "" ) then
        return complain( ply, "Invalid reason!" .. usage );
    elseif ( time == 0 and not authorised( ply, sourcebans.FLAG_PERMA ) ) then
        return complain( ply, "You are not authorised to permaban!" );
    end
    local function callback( res, err )
        if ( res ) then
            complain( ply, "sm_addban: " .. id .. " has been banned successfully." )
        else
            complain( ply, "sm_addban: " .. id .. " has not been banned. " .. err );
        end
    end
    sourcebans.BanPlayerBySteamID( id, time * 60, reason, ply, '', callback );
    complain( ply, "sm_addban: Your ban request has been sent to the database." );
end, nil, "Bans a player by their SteamID" .. usage);

local usage = "\n - Usage: sm_unban <steamid|ip> <reason>";
concommand.Add( "sm_unban", function(ply, _, args )
    if ( #args < 2 ) then
        return complain( ply, usage:sub(4) );
    elseif ( not sourcebans.IsActive() ) then
        return complain( ply, "Sourcebans has not been activated! Your command could not be completed." );
    elseif ( not authorised( ply, sourcebans.FLAG_UNBAN ) ) then
        return complain( ply, "You do not have access to this command!" );
    end
    local id, reason, func;
    if ( string.find( args[1], "%d+%.%d+%.%d+%.%d+" ) ) then
        id = table.remove( args,1 );
        func = sourcebans.UnbanPlayerByIPAddress;
    else
        id = getSteamID( args );
        func = sourcebans.UnbanPlayerBySteamID;
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
