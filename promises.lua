--[[
	promises.lua
	Copyright (c) 2013 Lex Robinson
	This code is freely available under the MIT License
--]]

local setmetatable, pcall, table, pairs, error, ErrorNoHalt =
	  setmetatable, pcall, table, pairs, error, ErrorNoHalt or print;

local function new(tab, ...)
    local ret = setmetatable({}, tab);
    ret:_init(...);
    return ret;
end
local function contextcall(what, context, ...)
	if (context) then
		return what(context, ...);
	else
		return what(...);
	end
end

local function contextpcall(what, context, ...)
	if (context) then
		return pcall(what, context, ...);
	else
		return pcall(what, ...);
	end
end

local function bind(what, context)
	return function(...)
		return contextcall(what, context, ...);
	end
end

local function pbind(func)
	return function()
		pcall(func);
	end
end

local promise = {
	_IsPromise = true;
	Then = function(self, succ, fail, prog, ctx)
		local def = Deferred();
		if (type(succ) == 'function') then
			local s = succ;
			succ = function(...)
				local ret = { contextpcall(s, ctx, ...) };
				if (not ret[1]) then
					def:Reject(ret[2]);
					return;
				end
				if (ret[2]._IsDeferred) then
					ret[2]:Then(def.Resolve, def.Reject, def.Notify, def);
				else
					def:Resolve(unpack(ret));
				end
			end
		else
			succ = bind(def.Resolve, def);
		end
		if (type(fail) == 'function') then
			local f = fail;
			fail = function(...)
				local ret = { contextpcall(f, ctx, ...) };
				if (not ret[1]) then
					def:Reject(ret[2]);
					return;
				end
				if (ret[2]._IsDeferred) then
					ret[2]:Then(def.Resolve, def.Reject, def.Notify, def);
				else
					def:Resolve(unpack(ret));
				end
			end
		else
			fail = bind(def.Reject, def);
		end
		-- Promises/A barely mentions progress handlers, so I've just made this up.
		if (type(prog) == 'function') then
			local p = prog;
			prog = function(...)
				local ret = { contextpcall(p, ctx, ...) };
				if (not ret[1]) then
					ErrorNoHalt("Progress handler failed: ", ret[2], "\n");
					-- Carry on as if that never happened
					def:Notify(...);
				else
					def:Notify( unpack(ret) );
				end
			end
		else
			prog = bind(def.Notify, def);
		end
		-- Run progress first so any progs happen before the resolution
		self:Progress(prog, true);
		self:Done(succ, true);
		self:Fail(fail, true);
		return def:Promise();
	end;
	Done = function(self, succ, nobind)
		if (not nobind) then
			succ = pbind(succ);
		end
		if (self._state == 'done') then
			succ(unpack(self._res));
		else
			table.insert(self._succs, succ);
		end
	end;
	Fail = function(self, fail, nobind)
		if (not nobind) then
			fail = pbind(fail);
		end
		if (self._state == 'fail') then
			fail(unpack(self._res))
		else
			table.insert(self._fails, fail);
		end
	end;
	Progress = function(self, prog, nobind)
		if (not nobind) then
			prog = pbind(prog);
		end
		table.insert(self._progs, prog);
		if (self._progd) then
			for _, d in ipairs(self._progd) do
				prog(unpack(d));
			end
		end
	end;
	Always = function(self, alwy, nobind)
		if (not nobind) then
			alwy = pbind(alwy);
		end
		if (self._state ~= 'pending') then
			alwy(unpack(self._res));
		else
			table.insert(self._alwys, alwy)
		end
	end;

	_init = function(self)
		self._state = 'pending';
		self._succs = {};
		self._fails = {};
		self._progs = {};
		self._alwys = {};
	end;
};
local deferred = {
	_IsDeferred = true;
	Resolve = function(self, ...)
		local p = self._promise;
		if (p._state ~= 'pending') then
			error("Tried to resolve an already " .. (state == "done" and "resolved" or "rejected") .. " deferred!", 2);
		end
		p._state = 'done';
		p._res = {...};
		for _, f in pairs(p._succs) do
			f(...);
		end
		for _, f in pairs(p._alwys) do
			f(...);
		end
	end;

	Reject = function(self, ...)
		local p = self._promise;
		if (p._state ~= 'pending') then
			error("Tried to reject an already " .. (state == "done" and "resolved" or "rejected") .. " deferred!", 2);
		end
		p._state = 'fail';
		p._res = {...};
		for _, f in pairs(p._fails) do
			f(...);
		end
		for _, f in pairs(p._alwys) do
			f(...);
		end
	end;

	Notify = function(self, ...)
		local p = self._promise;
		if (p._state ~= 'pending') then
			error("Tried to notify an already " .. (state == "done" and "resolved" or "rejected") .. " deferred!", 2);
		end
		p._progd = p._progd or {};
		table.insert(p._progd, {...});
		for _, f in pairs(p._progs) do
			f(...);
		end
	end;

	_init = function(self)
		self._promise = new(promise);
	end;

	Promise = function(self) return self._promise; end;

	-- Proxies
	_IsPromise = true;
	Then = function(self, ...) return self._promise:Then(...); end;
	Done = function(self, ...) self._promise:Done(...); end;
	Fail = function(self, ...) self._promise:Fail(...); end;
	Progress = function(self, ...) self._promise:Progress(...); end;
	Always = function(self, ...) self._promise:Always(...); end;
};


function Deferred()
	return new(deferred);
end
