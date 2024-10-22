--[[
	promises.lua
	Copyright (c) 2013 Lexi Robinson

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

local setmetatable, pcall, table, pairs, error, type, unpack, ipairs, ErrorNoHalt =
	setmetatable, pcall, table, pairs, error, type, unpack, ipairs, ErrorNoHalt or print

---
--- This module is a pure Lua implementation of the CommonJS Promises/A spec, using a basic version of jQuery's interface.
--- It returns a single function, Deferred.
--- @author Lexi Robinson - lexi at lexi dot org dot uk
--- @copyright 2013 Lexi Robinson - This code is released under the LGPLv3 License
--- @release 1.1.0
-- @module promises
-- <!--
--[[ goddamnit luadoc -->
module('promises')
]]

--- @class Deferred
local Deferred = nil

---
--- Does a basic form of OO
--- @param tab table The metatable to make an object from
--- @param ... any Stuff to pass to the ctor
--- @return any #ye new object
local function new(tab, ...)
	local ret = setmetatable({}, { __index = tab })
	ret:_init(...)
	return ret
end

---
--- Binds a function's self var
--- @param func function The function what needen ze selfen
--- @param self any The selfen as above
--- @return function # function( ... ) return func( self, ... ) end
--- @overload fun(func: nil, self: any): nil
local function bind(func, self)
	if (not func) then
		return
	elseif (self) then
		return function(...) return func(self, ...); end
	else
		return func
	end
end

---
--- Creates a "safe" function that will never error
--- @generic T : function
--- @param func `T`  1x potentially unsafe function
--- @return T #1x completely harmless function.
local function pbind(func)
	return function(...)
		local r, e = pcall(func, ...)
		if (not r) then
			ErrorNoHalt("Callback failed: ", e, "\n")
		end
	end
end

--- @alias ThenCallback fun(...: any): any
--- @
---
--- The 'clientside' promise object suitable for hookage.
--- Note that any handlers added after the promise has been resolved or rejected will be called ( if relevent ) before the handle function returns.
--- @class Promise
--- @field package _IsPromise boolean
--- @field package _state "pending" | "done" | "fail"
--- @field package _errd boolean
--- @field package _progd any[][] | nil
--- @field package _res any[]
--- @field package _dones ThenCallback[]
--- @field package _fails ThenCallback[]
--- @field package _progs ThenCallback[]
--- @field package _alwys ThenCallback[]
--- @field package _errs ThenCallback[]
local Promise = {
	_IsPromise = true,
}


---
--- CommonJS Promises/A compliant Then function. <br />
--- Adds handlers that get called when the Promise object is resolved, rejected, or progressing.
--- All arguments are optional and non-function values are ignored. <br />
--- If done or fail returns a value, the returned promise is resolved with that value.
--- If they cause an error, the returned promise is rejected with the error.
--- If they return a Promise object, any action taken on that promise object will be forwarded to the returned promise object.
--- @param done? ThenCallback An optional function that is called when the Promise is resolved.
--- @param fail? ThenCallback An optional function that is called when the Promise is rejected.
--- @param prog? ThenCallback An optional function that is called when progress notifications are sent to the Promise.
--- @return Promise A new promise object that will be resolved, rejected or notified when this one is - after the values have been filtered through the above functions.
function Promise:Then(done, fail, prog)
	--- @type Deferred
	local def = new(Deferred)
	if (type(done) == "function") then
		local d = done
		done = function(...)
			local ret = { pcall(d, ...) }
			if (not ret[1]) then
				def._promise._errd = true
				def:Reject(ret[2])
				return
			end
			if (type(ret[2]) == "table" and ret[2]._IsPromise) then
				local r = ret[2]
				r:Progress(bind(def.Notify, def), true)
				r:Done(bind(def.Resolve, def), true)
				r:Fail(bind(def.Reject, def), true)
			else
				def:Resolve(unpack(ret, 2))
			end
		end
	else
		done = function(...) return def:Resolve(...) end
	end
	if (type(fail) == "function") then
		local f = fail
		fail = function(...)
			local ret = { pcall(f, ...) }
			if (not ret[1]) then
				def._promise._errd = true
				def:Reject(ret[2])
				return
			end
			if (type(ret[2]) == "table" and ret[2]._IsPromise) then
				local r = ret[2]
				r:Progress(bind(def.Notify, def), true)
				r:Done(bind(def.Resolve, def), true)
				r:Fail(bind(def.Reject, def), true)
			else
				def:Resolve(unpack(ret, 2))
			end
		end
	else
		fail = function(...) return def:Reject(...) end
	end
	-- Promises/A barely mentions progress handlers, so I've just made this up.
	if (type(prog) == "function") then
		local p = prog
		prog = function(...)
			local ret = { pcall(p, ...) }
			if (not ret[1]) then
				ErrorNoHalt("Progress handler failed: ", ret[2], "\n")
				-- Carry on as if that never happened
				def:Notify(...)
			else
				def:Notify(unpack(ret, 2))
			end
		end
	else
		prog = function(...) return def:Notify(...) end
	end
	-- Run progress first so any progs happen before the resolution
	self:Progress(prog, true)
	self:Done(done, true)
	self:Fail(fail, true)
	return def:Promise()
end

---
--- Adds a handler to be called when the Promise object is resolved
--- @param done ThenCallback The handler function
--- @return self
function Promise:Done(done, _)
	if (not _) then
		done = pbind(done)
	end
	if (self._state == "done") then
		done(unpack(self._res))
	else
		table.insert(self._dones, done)
	end
	return self
end

---
--- Adds a handler to be called when the Promise object is rejected
--- @param fail ThenCallback The handler function
--- @return self
function Promise:Fail(fail, _)
	if (not _) then
		fail = pbind(fail)
	end
	if (self._state == "fail") then
		fail(unpack(self._res))
	else
		table.insert(self._fails, fail)
	end
	return self
end

---
--- Adds a handler to be called when the Promise object is notified of a progress event
--- @param prog ThenCallback The handler function
--- @return self
function Promise:Progress(prog, _)
	if (not _) then
		prog = pbind(prog)
	end
	table.insert(self._progs, prog)
	if (self._progd) then
		for _, d in ipairs(self._progd) do
			prog(unpack(d))
		end
	end
	return self
end

---
--- Adds a handler to be called when the Promise object is rejected due to an error
--- @param err ThenCallback The handler function
--- @return self
function Promise:Error(err, _)
	if (not _) then
		err = pbind(err)
	end
	if (self._state == "fail") then
		if (self._errd) then
			err(unpack(self._res))
		end
	else
		table.insert(self._errs, err)
	end
	return self
end

---
--- Adds a handler that gets called when the promise is either resolved or rejected
--- @param alwy ThenCallback The handler function
--- @return self
function Promise:Always(alwy, _)
	if (not _) then
		alwy = pbind(alwy)
	end
	if (self._state ~= "pending") then
		alwy(unpack(self._res))
	else
		table.insert(self._alwys, alwy)
	end
	return self
end

---
--- ctor
--- @see Deferred:Promise
function Promise:_init()
	self._state = "pending"
	self._errd  = false
	self._dones = {}
	self._fails = {}
	self._progs = {}
	self._alwys = {}
	self._errs  = {}
end

---
--- The 'serverside' deferred object w/ the mutation functions.
--- Also implements all the promise functions because why not
--- @class Deferred: Promise
--- @field package _promise Promise
--- @field package _IsDeferred boolean
Deferred = {
	_IsDeferred = true,
	_IsPromise = true,
}
-- Proxies
Deferred.Then = function(self, ...)
	return self._promise:Then(...)
end
Deferred.Done = function(self, ...)
	self._promise:Done(...)
	return self
end
Deferred.Fail = function(self, ...)
	self._promise:Fail(...)
	return self
end
Deferred.Progress = function(self, ...)
	self._promise:Progress(...)
	return self
end
Deferred.Always = function(self, ...)
	self._promise:Always(...)
	return self
end

---
--- Resolves the Deferred object.
--- Note that it is an error to attempt to mutate a Deferred's state after is is resolved or rejected.
--- @param ... any The params to pass to the handlers
--- @return self
function Deferred:Resolve(...)
	local p = self._promise
	if (p._state ~= "pending") then
		error("Tried to resolve an already " .. (p._state == "done" and "resolved" or "rejected") .. " deferred!", 2)
	end
	p._state = "done"
	p._res = { ... }
	for _, f in pairs(p._dones) do
		f(...)
	end
	for _, f in pairs(p._alwys) do
		f(...)
	end
	return self
end

---
--- Rejects the Deferred object.
--- Note that it is an error to attempt to mutate a Deferred's state after is is resolved or rejected.
--- @param ... any The params to pass to the handlers
--- @return self
function Deferred:Reject(...)
	local p = self._promise
	if (p._state ~= "pending") then
		error("Tried to reject an already " .. (p._state == "done" and "resolved" or "rejected") .. " deferred!", 2)
	end
	p._state = "fail"
	p._res = { ... }
	for _, f in pairs(p._fails) do
		f(...)
	end
	if (self._promise._errd) then
		for _, f in pairs(p._errs) do
			f(...)
		end
	end
	for _, f in pairs(p._alwys) do
		f(...)
	end
	return self
end

---
--- Notifies the Deferred object of a progress update.
--- Note that it is an error to attempt to notify a resolved or rejected Deferred.
--- @param ... any The params to pass to the handlers
--- @return self
function Deferred:Notify(...)
	local p = self._promise
	if (p._state ~= "pending") then
		error("Tried to notify an already " .. (p._state == "done" and "resolved" or "rejected") .. " deferred!", 2)
	end
	p._progd = p._progd or {}
	table.insert(p._progd, { ... })
	for _, f in pairs(p._progs) do
		f(...)
	end
	return self
end

---
--- Returns the non-mutatable Promise for this Deferred object
--- @return Promise a Promise object
--- @see Promise
function Deferred:Promise()
	return self._promise
end

---
--- ctor
--- @see Deferred
function Deferred:_init()
	self._promise = new(Promise)
end

---
--- Creates and returns a new deferred object
--- @return Deferred
return function()
	return new(Deferred)
end
