--[[
    ~ Universal Database GLua Module ~
    Copyright (c) 2012-2013 Lex Robinson

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
--]]


-- Lua
local error, type, unpack, pairs, ipairs, tonumber, setmetatable, require, string =
      error, type, unpack, pairs, ipairs, tonumber, setmetatable, require, string;
-- GLua
local file, system, SERVER, ErrorNoHalt =
      file, system, SERVER, ErrorNoHalt;

local Deferred = require 'promises';
-- Databases
local sqlite   = sql;
local mysqloo  = mysqloo;
local tmysql   = tmysql;

---
-- The Universal Database Module is an attempt to provide a single rational interface
--  that allows Developers to run SQL commands without caring which MySQL module the server has installed.
-- It also has client-side prepared queries which is nice.
-- @author Lex Robinson - lexi at lexi dot org dot uk
-- @copyright 2012-2013 Lex Robinson - Relased under the MIT License
-- @release Alpha v2
-- @usage see database.NewDatabase
-- @see NewDatabase
module( "database" );

---
-- The main Database object the developer will generally be interacting with
-- @name Database
-- @class table
-- @see NewDatabase
local Database = {};
---
-- A client-side prepared query object.
-- @name PreparedQuery
-- @class table
-- @see Database:PrepareQuery
local PreparedQuery = {};

--
-- Does a basic form of OO
-- @param tab The metatable to make an object from
-- @param ... Stuff to pass to the ctor (if it exists)
-- @return ye new object
local function new( tab, ... )
    local ret = setmetatable( {}, {__index=tab} );
    if ( ret.Init ) then
        ret:Init( ... );
    end
    return ret;
end
--
-- Binds a function's self var
-- @param func The function what needen ze selfen
-- @param self The selfen as above
-- @return function( ... ) return func( self, ... ) end
local function bind( func, self )
    if ( not func ) then
        return;
    elseif ( self ) then
        return function( ... ) return func( self, ... ); end
    else
        return func;
    end
end

--
-- DBOBJ
--

setmetatable( Database, { __index = function( self, key )
    -- Forward all the generic db methods down the line
    if ( self._db and self._db[ key ] ) then
        if ( string.sub( key, 1,1 ) == '_'
         or type( self._db ) ~= "function" ) then
            return nil;
        end
        return function( self, ... )
            return self._db[ key ]( self._db, ... );
        end
    end
end} );

--
-- CTor. Accepts the variables passed to NewDatabase
-- @see NewDatabase
-- @param tab connection details
function Database:Init( tab )
    self._conargs =  tab;
    local db = tab.DBMethod;
    if ( db ) then
        local success, errmsg = IsValidDBMethod( db );
        if ( not success ) then
            error( "Cannot use database method '" .. db .. "': " .. errmsg, 4 );
        end
    else
        db = FindFirstAvailableDBMethod( tab.EnableSQLite );
        if ( not db ) then
            error( "No valid database methods available!", 4 );
        end
    end
    self._db = GetNewDBMethod( db );
end

local function connectionFail( errmsg )
    ErrorNoHalt( "Could not connect to the database: ", errmsg, "\n" );
end

---
-- Connects with the stored args
-- @return Promise object for the DB connection
-- @see NewDatabase
function Database:Connect()
    return self._db:Connect( self._conargs, self )
        :Then( function( _ ) return self; end ) -- Replace the dbobject with ourself
        :Fail( connectionFail ); -- Always thrown an errmsg
end

local function queryFail( errmsg )
    ErrorNoHalt( "Query failed: ", errmsg, "\n" )
end

---
-- Runs a query
-- @param text The query to run
-- @return A promise object for the query's result
function Database:Query( text )
    return self._db:Query( text ):Fail(queryFail);
end

---
-- Prepares a query for future runnage with placeholders
-- @param text The querytext, complete with sprintf placeholders
-- @return A prepared query object
-- @see PreparedQuery
function Database:PrepareQuery( text )
    if ( not text ) then
        error( "No query text specified!", 2 );
    end
    local _, narg = string.gsub( text, '(%%[diouXxfFeEgGaAcsb])', '' );
    return new( PreparedQuery, {
        Text    = text,
        DB      = self,
        NumArgs = narg;
    } );
end

-- Forwarded functions

---
-- Nukes the database connection and any queries currently running. Generally advisable not to call this
-- @name Database:Disconnect
-- @class function
Database.Disconnect = nil;

---
-- Sanitise a string for insertion into the database
-- @name Database:Escape
-- @class function
-- @param text The string to santise
-- @return A ensafened string
Database.Escape = nil;

---
-- Checks to seee if Connect as been called and Disconnect hasn't
-- @name Database:IsConnected
-- @class function
-- @return boolean
Database.IsConnected = nil;

--
-- QueryOBJ
--

--
-- CTor. Only ever called by Database:PrepareQuery
-- @param qargs data from the mothership
-- @see Database:PrepareQuery
function PreparedQuery:Init( qargs )
    self._db     = qargs.DB;
    self.Text    = qargs.Text;
    self.NumArgs = qargs.NumArgs;
end

---
-- Set persistant callbacks to be called for every invocation.<br />
-- The callbacks should be of the form of function( [context,] result [, arg1, arg2, ...] ) where arg1+ are arguments passed to SetCallbackArgs
-- @see PreparedQuery:SetCallbackArgs
-- @usage <pre>
-- local query = db:PrepareQuery( "do player stuff" ); <br />
-- query:SetCallbacks( { <br />
-- &nbsp;&nbsp; Done: GM.PlayerStuffDone, <br />
-- &nbsp;&nbsp; Fail: GM.PlayerStuffFailed <br />
-- }, GM );
-- </pre>
-- @param tab A table of callbacks with names matching Promise object functions
-- @param context A variable to always pass as the first argument. Typically self for objects/GM.
function PreparedQuery:SetCallbacks( tab, context )
    self._cDone = bind( tab.Done, context );
    self._cFail = bind( tab.Fail, context );
    self._cProg = bind( tab.Progress, context );
end

---
-- Sets any extra args that should be passed to the query's callbacks on the next invocation.
-- @param ... The arguments to be unpacked after the result
function PreparedQuery:SetCallbackArgs( ... )
    self._callbackArgs = {...};
    if ( #self._callbackArgs == 0 ) then
        self._callbackArgs = nil;
    end
end

---
-- Prepares the query for the next invocation.
-- @param ... The arguments to escape and sprintf into the query
function PreparedQuery:Prepare( ... )
    if ( self.NumArgs == 0 ) then
        return;
    end
    self._preped = true;
    local args = {...};
    local nargs = #args;
    if ( nargs < self.NumArgs ) then
        error( "Argument count missmatch! Expected " .. self.NumArgs .. " but only received " .. nargs .. "!", 2 );
    end
    for i, arg in pairs(args) do
        args[i] = self._db:Escape(arg);
    end
    self._prepedText = string.format( self.Text, ... );
end

local function bindCArgs( func, cargs )
    if ( not cargs ) then
        return func;
    else
        return function( res )
            func( res, unpack( cargs ) );
        end
    end
end

---
-- Run a prepared query (and then reset it so it can be re-prepared with new data)
-- @return A promise object for the query's data
function PreparedQuery:Run()
    local text;
    if ( self.NumArgs == 0 ) then
        text = self.Text;
    elseif ( not self._preped ) then
        error( "Tried to run an unprepared query!", 2 );
    else
        text = self._prepedText;
    end

    local p = self._db:Query( text );
    -- Deal w/ callbacks
    local _ca = self._callbackArgs;
    if ( self._cDone ) then
        p:Done( bindCArgs( self._cDone, _ca ) );
    end
    if ( self._cFail ) then
        p:Fail( bindCArgs( self._cFail, _ca ) );
    end
    if ( self._cProg ) then
        p:Progress( bindCArgs( self._cProg, _ca ) );
    end
    -- Reset state
    self._preped = false;
    self._callbackArgs = nil;
    return p;
end

local registeredDatabaseMethods = {};

local function req( tab, name )
    if ( not tab[name] ) then
        error( "You're missing '" .. name .. "' from the connection parameters!", 3 );
    end
end

---
-- The module's main function - Creates and returns a new database object
-- @usage <pre>
-- local db = database.NewDatabase( { <br />
-- &nbsp&nbsp; Hostname = "localhost"; -- Where to find the MySQL server <br />
-- &nbsp&nbsp; Username = "root"; -- Who to log in as <br />
-- &nbsp&nbsp; Password = "top secret password"; -- The user's password <br />
-- &nbsp&nbsp; Database = "gmod"; -- The database to work in <br />
-- &nbsp&nbsp; Port = 3306; -- [Optional] The port to connect to the server on <br />
-- &nbsp&nbsp; EnableSQLite = false; -- [Optional] If the server's local SQLite db is an acceptable 'MySQL server'. <br />
-- &nbsp&nbsp; DBMethod = false; -- [Optional] Override the automatic module checker <br />
-- } ); <br />
-- db:Connect() -- Returns a promise object <br />
-- &nbsp;&nbsp; :Done( function() end ) -- DB Connected <br />
-- &nbsp;&nbsp; :Fail( function( err ) end); -- DB could not connect. (Will trigger an error + server log automatically)
--</pre>
-- @param connection A table composed of the following fields:
-- @return A Database object
-- @see Database
function NewDatabase( connection )
    if ( not type( connection ) == "table" ) then
        error( "Invalid connection data passed!", 2 );
    end
    req( connection, "Hostname" );
    req( connection, "Username" );
    req( connection, "Password" );
    req( connection, "Database" );
    connection.Port = connection.Port or 3306;
    connection.Port = tonumber( connection.Port );
    req( connection, "Port" );
    return new( Database, connection );
end

--
-- Finds the first enabled database method
-- @param EnableSQLite Wether or not SQLite is acceptable
-- @return The name of the DB method or false if none are available
function FindFirstAvailableDBMethod( EnableSQLite )
    for name, method in pairs( registeredDatabaseMethods ) do
        if ( method.CanSelect() and ( EnableSQLite or name ~= "sqlite" ) ) then
            return name;
        end
    end
    return false;
end

--
-- Creates and returns a new instance of a DB method
-- @param name The name to instantatiationonate
-- @return An instance or false, errmsg
function GetNewDBMethod( name )
    if ( not name ) then
        error( "No method name passed!", 2 );
    end
    local s, e = IsValidDBMethod( name );
    if ( not s ) then
        return s, e;
    end
    return new( GetDBMethod( name ) );
end

local function req( tab, name )
    if ( not tab[name] ) then
        error( "You're missing '" .. name .. "' from the database methods!", 3 );
    end
end

---
-- Registers a new Database method for usage
-- @param name The name of the new method
-- @param tab The __index metatable for instances to have
function RegisterDBMethod( name, tab )
    if ( type( name ) ~= "string" ) then
        error( "Expected a string for argument 1 of database.RegisterDBMethod!", 2 );
    elseif ( type( tab ) ~= "table" ) then
        error( "Expected a table for argument 2 of database.RegisterDBMethod!", 2 );
    end
    tab.Name = name;
    req( tab, "Connect" );
    req( tab, "Disconnect" );
    req( tab, "IsConnected" );
    req( tab, "Escape" );
    req( tab, "Query" );
    req( tab, "CanSelect" );
    registeredDatabaseMethods[string.lower( tab.Name )] = tab;
end

---
-- Checks to see if a Database method is available for use
-- @param name
-- @return true or false and an error message
function IsValidDBMethod( name )
    if ( not name ) then
        error( "No method name passed!", 2 );
    end
    local db = registeredDatabaseMethods[string.lower( name )];
    if ( not db ) then
        return false, "Database method '" .. name .. "' does not exist!";
    end
    return db.CanSelect();
end

--
-- Returns a DB method's master metatable
-- @param name
-- @return see above
function GetDBMethod( name )
    if ( not name ) then
        error( "No method name passed!", 2 );
    end
    return registeredDatabaseMethods[string.lower( name )];
end

local function checkmodule( name )
    local prefix = ( SERVER ) and "gmsv" or "gmcl";
    local suffix;
    if ( system.IsWindows() ) then
        suffix = "win32";
    elseif ( system.IsLinux() ) then
        suffix = "linux";
    elseif ( system.IsOSX() ) then
        suffix = "osx";
    else
        error( "The fuck kind of a system are you running me on?!" );
    end
    if ( file.Exists( "lua/bin/" .. prefix .. "_" .. name .. "_" .. suffix .. ".dll", "GAME" ) ) then
        return require( "lua/bin/" .. prefix .. "_" .. name .. "_" .. suffix .. ".dll" );
    end
end
do -- TMySQL
    local function mcallback( deferred, results, success, err )
        if ( success ) then
            for _, result in ipairs( results ) do
                deferred:Notify( result );
            end
            deferred:Resolve( results );
        else
            deferred:Reject( err );
        end
    end

    local db = {};

    function db:Connect( tab )
        local deferred = Deferred();
        if ( self._db ) then
            self:Disconnect();
        end
        local err;
        self._db, err = tmysql.initialize( tab.Hostname, tab.Username, tab.Password, tab.Database, tab.Port );
        if ( self._db ) then
            deferred:Resolve( self );
        else
            deferred:Reject( string.gsub( err, "^Error connecting to DB: ", "" ) );
        end
        return deferred:Promise();
    end

    function db:Disconnect()
        if ( self._db ) then
            self._db:Disconnect();
            self._db = nil;
        end
    end

    function db:Query( text )
        if ( not self._db ) then
            error( "Cannot query without a database connected!" );
        end
        local deferred = Deferred();
        self._db:Query( text, mcallback, 1, deferred );
        return deferred:Promise();
    end

    function db:Escape( text )
        return tmysql.escape( text );
    end

    function db:IsConnected()
        return self._db ~= nil;
    end

    function db.CanSelect()
        tmysql = tmysql or checkmodule( 'tmysql4' );
        if ( not tmysql ) then
            return false, "TMySQL4 is not available!";
        end
        return true;
    end

    RegisterDBMethod( "TMySQL", db );
end
do -- MySQLOO
    local mysqlooyes, mysqloono, mysqlooack, mysqloodata;
    function mysqlooyes( query, results )
        query.deferred:Resolve( results );
    end

    function mysqloono( query, err )
        query.deferred:Reject( err );
    end

    function mysqlooack( query )
        mysqloono( query, 'Aborted!' );
    end

    function mysqloodata( query, result )
        query.deferred:Notify( result );
    end

    local db = {};

    function db:Connect( cdata )
        local deferred = Deferred();
        if ( self._db ) then
            self:Disconnect();
        end
        self._db = mysqloo.connect( cdata.Hostname, cdata.Username, cdata.Password, cdata.Database, cdata.Port );
        self._db.onConnected = function( _ )
            deferred:Resolve( self );
        end
        self._db.onConnectionFailed = function( _, err )
            deferred:Reject( self, err );
        end
        self._db:connect();
        return deferred:Promise();
    end

    function db:Disconnect()
        if ( self._db ) then
            self._db:AbortAllQueries();
            self._db = nil;
        end
    end

    function db:Query( text )
        if ( not self._db ) then
            error( "Cannot query without a database connected!" );
        end
        local deferred = Deferred();
        local q = self._db:query( text );
        q.onError   = mysqloono;
        q.onSuccess = mysqlooyes;
        q.onData    = mysqloodata;
        q.deferred  = deferred;
        q:start();
        -- TODO: Autoreconnect on disconnection w/ queued queries etc etc
        -- I can't remember if queries are light userdata or not. If they are, this will break.
        -- table.insert( activeQueries, q );
        return deferred:Promise();
    end

    function db:Escape( text )
        if ( not self._db ) then
            error( "There is no database open to perform this act!", 2 );
        end
        return self._db:escape( text );
    end

    -- function db:IsConnected()
    --     if ( not self._db ) then
    --         return false;
    --     end
    --     local status = self._db:status();
    --     if ( status == mysqloo.DATABASE_CONNECTED ) then
    --         return true;
    --     end
    --     connected = false;
    --     if ( status == mysqloo.DATABASE_INTERNAL_ERROR ) then
    --         ErrorNoHalt( "The MySQLOO database has encountered an internal error!\n" );
    --     end
    --     return false;
    -- end
    function db:IsConnected()
        return self._db ~= nil;
    end


    function db.CanSelect()
        mysqloo = mysqloo or checkmodule( 'mysqloo' );
        if ( not mysqloo ) then
            return false, "MySQLOO is not available!";
        end
        return true;
    end

    RegisterDBMethod( "MySQLOO", db );
end
do -- SQLite
    local db = {};

    function db:Connect( _ )
        local deferred = Deferred();
        deferred:Resolve( self );
        return deferred:Promise();
    end

    function db:Disconnect()
    end

    function db:Query( text )
        local deferred = Deferred();
        local results = sqlite.Query( text );
        if ( results ) then
            for _, result in ipairs( results ) do
                deferred:Notify( result );
            end
            deferred:Resolve( results );
        else
            deferred:Reject( sqlite.LastError() );
        end
        return deferred:Promise();
    end

    function db:IsConnected()
        return true;
    end

    function db:Escape( text )
        return sqlite.SQLStr( text );
    end

    function db.CanSelect()
        return true;
    end

    RegisterDBMethod( "SQLite", db );
end
