--[[
	Drivers for the universal database system
	Copyright (c) 2014 Lex Robinson
	This code is freely available under the MIT License
--]]

local database = require('database');
local Deferred = require('promises');


-- Databases
local sqlite   = sql;
local mysqloo  = mysqloo;
local tmysql   = tmysql;

-- Lua tings
local ipairs, paris, string, require
	= ipairs, paris, string, require
-- GLua tings
local timer, file, system, SERVER, ErrorNoHalt
	= timer, file, system, SERVER, ErrorNoHalt or print

local _TEST = _TEST;

local drivers = {};

local function checkmodule( name )
	-- Not in Garry's Mod
	if (not system) then return false; end
	local prefix = ( SERVER ) and "gmsv" or "gmcl";
	local suffix;
	if ( system.IsWindows() ) then
		suffix = "win32";
	elseif ( system.IsLinux() ) then
		suffix = "linux";
	elseif ( system.IsOSX() ) then
		suffix = "osx";
	else
		ErrorNoHalt("Unknown system!");
		return false;
	end
	if ( file.Exists( "lua/bin/" .. prefix .. "_" .. name .. "_" .. suffix .. ".dll", "GAME" ) ) then
		return require( "lua/bin/" .. prefix .. "_" .. name .. "_" .. suffix .. ".dll" );
	end
end

if (_TEST) then
	drivers._checkmodule = checkmodule;
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

	database.RegisterDBMethod( "TMySQL", db );
	drivers.tmysql = db;
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

	function db:Init()
		self._queue = {};
	end

	function db:Connect( cdata )
		if ( self._db ) then
			self:Disconnect();
		end
		return self:_connect( mysqloo.connect( cdata.Hostname, cdata.Username, cdata.Password, cdata.Database, cdata.Port ) );
	end
	function db:_connect( dbobj )
		local deferred = Deferred();
		dbobj.onConnected = function( dbobj )
			self._db = dbobj;
			for _, q in pairs( self._queue ) do
				self:Query( q.text, q.deferred );
			end
			self._queue = {};
			deferred:Resolve( self );
		end
		dbobj.onConnectionFailed = function( _, err )
			deferred:Reject( self, err );
		end
		dbobj:connect();
		dbobj:wait();
		return deferred:Promise();
	end

	function db:Disconnect()
		if ( self._db ) then
			local db = self._db;
			self._db = nil; -- Make sure this is nil /FIRST/ so any aborting queries don't try to restart it
			db:AbortAllQueries();
		end
	end

	function db:qfail( errmsg, text )
		local deferred = Deferred();
		if ( self._db ) then
			local status = self._db:status();
			-- DB is fine - you just fucked up.
			if ( status == mysqloo.DATABASE_CONNECTED ) then
				return deferred:Reject( errmsg );
			-- DB fucked up, whoops
			elseif ( status == mysqloo.DATABASE_INTERNAL_ERROR ) then
				ErrorNoHalt( "The database has suffered an internal error!\n" );
				self:Connect(); -- Full restart the db
			-- DB timed out
			elseif ( status ~= mysqloo.DATABASE_CONNECTING ) then
				local db = self._db;
				self._db = nil;
				timer.Simple(0, function() self:_connect( db ); end);
			end
		end
		table.insert( self._queue, { text = text, deferred = deferred } );
		return deferred:Promise();
	end

	function db:Query( text, deferred )
		if ( not self._db ) then
			error( "Cannot query without a database connected!" );
		end
		deferred = deferred or Deferred();
		local q = self._db:query( text );
		if ( not q ) then
			return self:qfail( 'The DB is not connected!', text );
		end
		q.onError   = mysqloono;
		q.onSuccess = mysqlooyes;
		q.onData    = mysqloodata;
		q.deferred  = deferred;
		q:start();
		deferred:Then(nil, function( errmsg ) return self:qfail( errmsg, text ) end);
		-- I can't remember if queries are light userdata or not. If they are, this will break.
		-- table.insert( activeQueries, q );
		return deferred:Promise();
	end

	function db:Escape( text )
		if ( not self._db ) then
			error( "There is no database open to do this!" );
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

	database.RegisterDBMethod( "MySQLOO", db );
	drivers.mysqloo = db;
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

	database.RegisterDBMethod( "SQLite", db );
	drivers.sqlite = db;
end

return drivers;
