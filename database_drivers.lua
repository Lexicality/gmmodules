--[[
	Drivers for the universal database system
	Copyright (c) 2014 Lexi Robinson

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

local database = require("database")
local Deferred = require("promises")


-- Databases
local sqlite  = sql
local mysqloo = mysqloo
local tmysql  = tmysql


-- Lua tings
local ipairs, pairs, string, require = ipairs, pairs, string, require
-- GLua tings
local timer, file, system, SERVER, ErrorNoHalt = timer, file, system, SERVER, ErrorNoHalt or print


local _TEST = _TEST


local drivers = {}

local function checkmodule(name)
	-- Not in Garry's Mod
	if not system then return false; end
	local prefix = (SERVER) and "gmsv" or "gmcl"
	local suffix
	if system.IsWindows() then
		suffix = "win32"
	elseif system.IsLinux() then
		suffix = "linux"
	elseif system.IsOSX() then
		suffix = "osx"
	else
		ErrorNoHalt("Unknown system!")
		return false
	end
	if file.Exists("lua/bin/" .. prefix .. "_" .. name .. "_" .. suffix .. ".dll", "GAME") then
		return require("lua/bin/" .. prefix .. "_" .. name .. "_" .. suffix .. ".dll")
	end
end

if _TEST then
	drivers._checkmodule = checkmodule
end

do -- TMySQL
	---@param deferred Deferred
	---@param result TMySQLResult
	local function mcallback(deferred, result)
		if result.success then
			for _, result in ipairs(result.results) do
				deferred:Notify(result)
			end
			deferred:Resolve(result.results)
		else
			deferred:Reject(result.error)
		end
	end

	--- @class  database.TMySQLDriver:  database.Driver
	--- @field private _db? TMySQLDB
	--- @field private _prepared TMySQLPreparedStatement[]
	local db = {
		Name = "TMySQL",
	}

	function db:Init()
		self._prepared = {}
	end

	---@param tab  database.ConnectionInfo
	---@return Promise
	function db:Connect(tab)
		local deferred = Deferred()
		if self._db then
			self:Disconnect()
		end
		local db = tmysql.Create(
			tab.Hostname,
			tab.Username,
			tab.Password,
			tab.Database,
			tab.Port,
			tab.Socket
		)
		self._db = db
		local res, err = db:Connect()
		if res then
			-- "You have to manually poll now - it's faster, by a lot. Trust me." 🙄
			hook.Add("Think", db, db.Poll)
			deferred:Resolve(self)
		else
			deferred:Reject(string.gsub(err --[[@as string]], "^Error connecting to DB: ", ""))
		end
		return deferred:Promise()
	end

	function db:Disconnect()
		if self._db then
			self._db:Disconnect()
			self._db = nil
		end
		self._prepared = {}
	end

	---@param sql string
	---@return Promise
	function db:Query(sql)
		if not self._db then
			error("Cannot query without a database connected!")
		end
		local deferred = Deferred()
		self._db:Query(sql, mcallback, deferred)
		return deferred:Promise()
	end

	---@param sql string
	---@param ... any
	---@return Promise
	function db:PrepareAndRun(sql, ...)
		local deferred = Deferred()
		local query = self._prepared[sql]
		if not query or not query:IsValid() then
			local reason
			query, reason = self._db:Prepare(sql)
			if not query then
				return deferred:Reject(reason):Promise()
			end
			self._prepared[sql] = query
		end
		-- For some insane reason `Run` takes the vararg *FIRST* so we need to muck about with
		local args = { ... }
		table.insert(args, mcallback)
		table.insert(args, deferred)
		query:Run(unpack(args))
		return deferred:Promise()
	end

	---@param value string
	---@return string
	function db:Escape(value)
		if not self._db then
			error("There is no database open to do this!")
		end
		return self._db:Escape(value)
	end

	function db:IsConnected()
		return self._db and self._db:IsConnected() or false
	end

	function db.CanSelect()
		tmysql = tmysql or checkmodule("tmysql4")
		if not tmysql then
			return false, "TMySQL4 is not available!"
		end
		return true
	end

	database.RegisterDBMethod(db)
	drivers.tmysql = db
end
do -- MySQLOO
	--- @class  database.MySQLOOQuery : MySQLOOQuery
	--- @field deferred Deferred

	local mysqlooyes, mysqloono, mysqlooack, mysqloodata
	---@param query  database.MySQLOOQuery
	---@param results MySQLOOResults
	function mysqlooyes(query, results)
		query.deferred:Resolve(results)
	end

	---@param query  database.MySQLOOQuery
	---@param err string
	function mysqloono(query, err)
		query.deferred:Reject(err)
	end

	---@param query  database.MySQLOOQuery
	---@param result MySQLOOResult
	function mysqloodata(query, result)
		query.deferred:Notify(result)
	end

	--- @class  database.MySQLOODriver:  database.Driver
	--- @field private _queue {sql: string, deferred: Deferred}[]
	--- @field private _db? MySQLOODatabase
	--- @field private _cdata?  database.ConnectionInfo
	local db = {
		Name = "MySQLOO",
	}

	function db:Init()
		self._queue = {}
	end

	---@param cdata  database.ConnectionInfo
	---@return Promise
	function db:Connect(cdata)
		if self._db then
			self:Disconnect()
		end
		self._cdata = cdata
		return self:_connect(mysqloo.connect(
			cdata.Hostname,
			cdata.Username,
			cdata.Password,
			cdata.Database,
			cdata.Port,
			cdata.Socket
		))
	end

	---@param dbobj MySQLOODatabase
	---@return Promise
	function db:_connect(dbobj)
		local deferred = Deferred()
		dbobj.onConnected = function(dbobj)
			self._db = dbobj
			for _, q in pairs(self._queue) do
				self:Query(q.sql, q.deferred)
			end
			self._queue = {}
			deferred:Resolve(self)
		end
		dbobj.onConnectionFailed = function(_, err)
			deferred:Reject(self, err)
		end
		dbobj:connect()
		dbobj:wait()
		return deferred:Promise()
	end

	function db:Disconnect()
		local db = self._db
		if db then
			db:abortAllQueries()
			self._db = nil -- Make sure this is nil /FIRST/ so any aborting queries don't try to restart it
		end
	end

	---@param errmsg string
	---@param sql string
	---@return Promise
	function db:qfail(errmsg, sql)
		local deferred = Deferred()
		local db = self._db
		if db then
			local status = self._db:status()
			if status == mysqloo.DATABASE_CONNECTED then
				-- DB is fine - you just fucked up.
				return deferred:Reject(errmsg)
			elseif status == mysqloo.DATABASE_INTERNAL_ERROR then
				-- DB fucked up, whoops
				ErrorNoHalt("The database has suffered an internal error!\n")
				self:Connect(self._cdata) -- Full restart the db
			elseif status ~= mysqloo.DATABASE_CONNECTING then
				-- DB timed out
				self._db = nil
				timer.Simple(0, function() self:_connect(db); end)
			end
		end
		table.insert(self._queue, { sql = sql, deferred = deferred })
		return deferred:Promise()
	end

	---@param sql string
	---@param deferred? Deferred
	---@return Promise
	function db:Query(sql, deferred)
		if not self._db then
			error("Cannot query without a database connected!")
		end
		deferred = deferred or Deferred()
		local q = self._db:query(sql)
		if not q then
			return self:qfail("The DB is not connected!", sql)
		end
		--- @cast q  database.MySQLOOQuery
		q.onError   = mysqloono
		q.onSuccess = mysqlooyes
		q.onData    = mysqloodata
		q.deferred  = deferred
		q:start()
		deferred:Then(nil, function(errmsg) return self:qfail(errmsg, sql) end)
		-- I can't remember if queries are light userdata or not. If they are, this will break.
		-- table.insert( activeQueries, q )
		return deferred:Promise()
	end

	---@param sql string
	---@param ... any
	---@return Promise
	function db:PrepareAndRun(sql, ...)
		local q = self._db:prepare(sql)
		local idx = 1
		for value in ... do
			local value_type = type(value)
			if value_type == "nil" then
				q:setNull(idx)
			elseif value_type == "number" then
				q:setNumber(idx, value)
			elseif value_type == "boolean" then
				q:setBoolean(idx, value)
			else
				q:setString(idx, tostring(value))
			end
			idx = idx + 1
		end
		local deferred = Deferred()
		---@diagnostic disable-next-line: inject-field
		q.deferred     = deferred
		q.onError      = mysqloono
		q.onSuccess    = mysqlooyes
		q.onData       = mysqloodata

		q:start()
		deferred:Then(
			nil,
			function(errmsg)
				return self:qfail(errmsg, sql)
			end
		)
		return deferred:Promise()
	end

	---@param value string
	---@return string
	function db:Escape(value)
		if not self._db then
			error("There is no database open to do this!")
		end
		return self._db:escape(value)
	end

	-- function db:IsConnected()
	--     if not self._db then
	--         return false
	--     end
	--     local status = self._db:status()
	--     if status == mysqloo.DATABASE_CONNECTED then
	--         return true
	--     end
	--     connected = false
	--     if status == mysqloo.DATABASE_INTERNAL_ERROR then
	--         ErrorNoHalt( "The MySQLOO database has encountered an internal error!\n" )
	--     end
	--     return false
	-- end
	function db:IsConnected()
		return self._db ~= nil
	end

	function db.CanSelect()
		mysqloo = mysqloo or checkmodule("mysqloo")
		if not mysqloo then
			return false, "MySQLOO is not available!"
		end
		return true
	end

	database.RegisterDBMethod(db)
	drivers.mysqloo = db
end
do -- SQLite
	--- @class  database.SQLiteDriver :  database.Driver
	local db = {
		Name = "SQLite",
	}

	---@param _  database.ConnectionInfo
	---@return Promise
	function db:Connect(_)
		local deferred = Deferred()
		deferred:Resolve(self)
		return deferred:Promise()
	end

	function db:Disconnect()
	end

	---@param sql string
	---@return Promise
	function db:Query(sql)
		local deferred = Deferred()
		local results = sqlite.Query(sql)
		if results then
			for _, result in ipairs(results) do
				deferred:Notify(result)
			end
			deferred:Resolve(results)
		else
			deferred:Reject(sqlite.LastError())
		end
		return deferred:Promise()
	end

	---@param sql string
	---@param ... any
	---@return Promise
	function db:PrepareAndRun(sql, ...)
		local values = { ... }
		-- good fucking luck if your query has a ? in a string in it
		local encoded = string.gsub(sql, "%?", function(_)
			local value = table.remove(values, 1)
			local value_type = type(value)
			if value_type == "nil" then
				return "NULL"
			elseif value_type == "number" or value_type == "boolean" then
				return tostring(value)
			end
			return '"' + self:Escape(tostring(value)) + '"'
		end)
		return self:Query(encoded)
	end

	function db:IsConnected()
		return true
	end

	---@param value string
	---@return string
	function db:Escape(value)
		return sqlite.SQLStr(value)
	end

	function db.CanSelect()
		return true
	end

	database.RegisterDBMethod(db)
	drivers.sqlite = db
end

return drivers
