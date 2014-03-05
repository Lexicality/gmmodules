--[[
	promises.lua
	Copyright (c) 2013 Lex Robinson
	This code is freely available under the MIT License
--]]

local setmetatable, pcall, table, pairs, error, type, unpack, ipairs, ErrorNoHalt =
	  setmetatable, pcall, table, pairs, error, type, unpack, ipairs, ErrorNoHalt or print;

---
-- This module is a pure Lua implementation of the CommonJS Promises/A spec, using a basic version of jQuery's interface.
-- It returns a single function, Deferred.
-- @author Lex Robinson - lexi at lexi dot org dot uk
-- @copyright 2013 Lex Robinson - This code is released under the MIT License
-- @release 1.0<!--
--[[ goddamnit luadoc -->
module('promises');
]]
local Deferred = nil;

--
-- Does a basic form of OO
-- @param tab The metatable to make an object from
-- @param ... Stuff to pass to the ctor
-- @return ye new object
local function new( tab, ... )
	local ret = setmetatable( {}, {__index=tab} );
	ret:_init( ... );
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
-- Creates a "safe" function that will never error
-- @param func 1x potentially unsafe function
-- @return 1x completely harmless function.
local function pbind( func )
	return function( ... )
		local r, e = pcall( func, ... );
		if ( not r ) then
			ErrorNoHalt( 'Callback failed: ', e, "\n" );
		end
	end
end

---
-- The 'clientside' promise object suitable for hookage.
-- Note that any handlers added after the promise has been resolved or rejected will be called ( if relevent ) before the handle function returns.
-- @name Promise
-- @class table
local Promise = {
	_IsPromise = true;
}
---
-- CommonJS Promises/A compliant Then function. <br />
-- Adds handlers that get called when the Promise object is resolved, rejected, or progressing.
-- All arguments are optional and non-function values are ignored. <br />
-- If done or fail returns a value, the returned promise is resolved with that value.
-- If they cause an error, the returned promise is rejected with the error.
-- If they return a Promise object, any action taken on that promise object will be forwarded to the returned promise object.
-- @param done An optional function that is called when the Promise is resolved.
-- @param fail An optional function that is called when the Promise is rejected.
-- @param prog An optional function that is called when progress notifications are sent to the Promise.
-- @return A new promise object that will be resolved, rejected or notified when this one is - after the values have been filtered through the above functions.
function Promise:Then( done, fail, prog )
	local def = Deferred();
	if ( type( done ) == 'function' ) then
		local d = done;
		done = function( ... )
			local ret = { pcall( d, ... ) };
			if ( not ret[1] ) then
				def:Reject( ret[2] );
				return;
			end
			if ( type( ret[2] ) == 'table' and ret[2]._IsPromise ) then
				local r = ret[2];
				r:Progress( bind( def.Notify, def ), true );
				r:Done( bind( def.Resolve, def ),    true );
				r:Fail( bind( def.Reject, def ),     true );
			else
				def:Resolve( unpack( ret, 2 ) );
			end
		end
	else
		done = bind( def.Resolve, def );
	end
	if ( type( fail ) == 'function' ) then
		local f = fail;
		fail = function( ... )
			local ret = { pcall( f, ... ) };
			if ( not ret[1] ) then
				def:Reject( ret[2] );
				return;
			end
			if ( type( ret[2] ) == 'table' and ret[2]._IsPromise ) then
				local r = ret[2];
				r:Progress( bind( def.Notify, def ), true );
				r:Done( bind( def.Resolve, def ),    true );
				r:Fail( bind( def.Reject, def ),     true );
			else
				def:Resolve( unpack( ret, 2 ) );
			end
		end
	else
		fail = bind( def.Reject, def );
	end
	-- Promises/A barely mentions progress handlers, so I've just made this up.
	if ( type( prog ) == 'function' ) then
		local p = prog;
		prog = function( ... )
			local ret = { pcall( p, ... ) };
			if ( not ret[1] ) then
				ErrorNoHalt( "Progress handler failed: ", ret[2], "\n" );
				-- Carry on as if that never happened
				def:Notify( ... );
			else
				def:Notify( unpack( ret, 2 ) );
			end
		end
	else
		prog = bind( def.Notify, def );
	end
	-- Run progress first so any progs happen before the resolution
	self:Progress( prog, true );
	self:Done( done, true );
	self:Fail( fail, true );
	return def:Promise();
end

---
-- Adds a handler to be called when the Promise object is resolved
-- @param done The handler function
-- @return self
function Promise:Done( done, _ )
	if ( not _ ) then
		done = pbind( done );
	end
	if ( self._state == 'done' ) then
		done( unpack( self._res ) );
	else
		table.insert( self._dones, done );
	end
	return self;
end;

---
-- Adds a handler to be called when the Promise object is rejected
-- @param fail The handler function
-- @return self
function Promise:Fail( fail, _ )
	if ( not _ ) then
		fail = pbind( fail );
	end
	if ( self._state == 'fail' ) then
		fail( unpack( self._res ) )
	else
		table.insert( self._fails, fail );
	end
	return self;
end;

---
-- Adds a handler to be called when the Promise object is notified of a progress event
-- @param prog The handler function
-- @return self
function Promise:Progress( prog, _ )
	if ( not _ ) then
		prog = pbind( prog );
	end
	table.insert( self._progs, prog );
	if ( self._progd ) then
		for _, d in ipairs( self._progd ) do
			prog( unpack(d) );
		end
	end
	return self;
end;

---
-- Adds a handler that gets called when the promise is either resolved or rejected
-- @param alwy The handler function
-- @return self
function Promise:Always( alwy, _ )
	if ( not _ ) then
		alwy = pbind( alwy );
	end
	if ( self._state ~= 'pending' ) then
		alwy( unpack( self._res ) );
	else
		table.insert( self._alwys, alwy )
	end
	return self;
end;

--
-- ctor
-- @see Deferred:Promise
function Promise:_init()
	self._state = 'pending';
	self._dones = {};
	self._fails = {};
	self._progs = {};
	self._alwys = {};
end;

---
-- The 'serverside' deferred object w/ the mutation functions.
-- Also implements all the promise functions because why not
-- @name Deferred
-- @class table
Deferred = {
	_IsDeferred = true;
	-- Proxies
	_IsPromise = true;
	Then = function( self, ... ) return self._promise:Then( ... ); end;
	Done = function( self, ... ) self._promise:Done( ... ); return self; end;
	Fail = function( self, ... ) self._promise:Fail( ... ); return self; end;
	Progress = function( self, ... ) self._promise:Progress( ... ); return self; end;
	Always = function( self, ... ) self._promise:Always( ... ); return self; end;
};

---
-- Resolves the Deferred object.
-- Note that it is an error to attempt to mutate a Deferred's state after is is resolved or rejected.
-- @param ... The params to pass to the handlers
-- @return self
function Deferred:Resolve( ... )
	local p = self._promise;
	if ( p._state ~= 'pending' ) then
		error( "Tried to resolve an already " .. ( p._state == "done" and "resolved" or "rejected" ) .. " deferred!", 2 );
	end
	p._state = 'done';
	p._res = { ... };
	for _, f in pairs( p._dones ) do
		f( ... );
	end
	for _, f in pairs( p._alwys ) do
		f( ... );
	end
	return self;
end;

---
-- Rejects the Deferred object.
-- Note that it is an error to attempt to mutate a Deferred's state after is is resolved or rejected.
-- @param ... The params to pass to the handlers
-- @return self
function Deferred:Reject( ... )
	local p = self._promise;
	if ( p._state ~= 'pending' ) then
		error( "Tried to reject an already " .. ( p._state == "done" and "resolved" or "rejected" ) .. " deferred!", 2 );
	end
	p._state = 'fail';
	p._res = { ... };
	for _, f in pairs( p._fails ) do
		f( ... );
	end
	for _, f in pairs( p._alwys ) do
		f( ... );
	end
	return self;
end;

---
-- Notifies the Deferred object of a progress update.
-- Note that it is an error to attempt to notify a resolved or rejected Deferred.
-- @param ... The params to pass to the handlers
-- @return self
function Deferred:Notify( ... )
	local p = self._promise;
	if ( p._state ~= 'pending' ) then
		error( "Tried to notify an already " .. ( p._state == "done" and "resolved" or "rejected" ) .. " deferred!", 2 );
	end
	p._progd = p._progd or {};
	table.insert( p._progd, { ... } );
	for _, f in pairs( p._progs ) do
		f( ... );
	end
	return self;
end;

---
-- Returns the non-mutatable Promise for this Deferred object
-- @return a Promise object
-- @see Promise
function Deferred:Promise()
	return self._promise;
end;

--
-- ctor
-- @see Deferred
function Deferred:_init()
	self._promise = new( Promise );
end;


---
-- Creates and returns a new deferred object
-- @name Deferred
-- @class function
return function()
	return new( Deferred );
end
