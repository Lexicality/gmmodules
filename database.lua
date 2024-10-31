--[[
	~ Universal Database GLua Module ~
	Copyright (c) 2012 Lexi Robinson

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


-- Lua
local error, type, unpack, pairs, tonumber, setmetatable, require, string =
	error, type, unpack, pairs, tonumber, setmetatable, require, string
-- GLua
local ErrorNoHalt = ErrorNoHalt

if not ErrorNoHalt then
	ErrorNoHalt = function(...)
		print("[ERROR]", ...)
	end
end

---
--- The Universal Database Module is an attempt to provide a single rational interface
---  that allows Developers to run SQL commands without caring which MySQL module the server has installed.
--- It also has client-side prepared queries which is nice.
--- @author Lexi Robinson - lexi at lexi dot org dot uk
--- @copyright 2012 Lexi Robinson - Relased under the LGPLv3 License
--- @release 1.0.0
--- @see database.NewDatabase
local database = {}

--- @class database.ConnectionInfo
--- @field Hostname string
--- @field Username string
--- @field Password string
--- @field Database string
--- @field Port? integer
--- @field Socket? string
--- @field DBMethod? string
--- @field EnableSQLite? boolean

--- @class database.Driver
--- @field Name string
--- @field Init? fun(self): nil
--- @field Connect fun(self, info: database.ConnectionInfo): Promise
--- @field Disconnect fun(self): nil
--- @field Query fun(self, sql: string): Promise
--- @field Escape fun(self, value: string): string
--- @field IsConnected fun(self): boolean
--- @field CanSelect fun(self): boolean
--- @field PrepareAndRun fun(self, sql: string, ...: any): Promise

--- The main Database object the developer will generally be interacting with
--- @class database.Database
--- @field private _db database.Driver
local Database = {}

--- A client-side prepared query object.
--- @class database.PreparedQuery
--- @field private _db database.Database
--- @field private _sql string
--- @field private _cDone function | nil
--- @field private _cFail function | nil
--- @field private _cProg function | nil
--- @field private _callbackArgs any[] | nil
local PreparedQuery = {}

--- Does a basic form of OO
--- @param tab table The metatable to make an object from
--- @param ... any Stuff to pass to the ctor (if it exists)
--- @return any ye new object
local function new(tab, ...)
	local ret = setmetatable({}, { __index = tab })
	if ret.Init then
		ret:Init(...)
	end
	return ret
end

--- Binds a function's self var
--- @generic T
--- @param func fun(T, ...) The function what needen ze selfen
--- @param self `T`The selfen as above
--- @return fun( ... ) #return func( self, ... ) end
--- @overload fun(func: nil, v:any): nil
local function bind(func, self)
	if not func then
		return
	elseif self then
		return function(...) return func(self, ...); end
	else
		return func
	end
end

--
-- DBOBJ
--

--- CTor. Accepts the variables passed to NewDatabase
--- @see database.NewDatabase
--- @param tab database.ConnectionInfo connection details
--- @param db database.Driver the selected driver
function Database:Init(tab, db)
	self._conargs = tab
	self._db = db
end

local function connectionFail(errmsg)
	ErrorNoHalt("Could not connect to the database: ", errmsg, "\n")
end

--- Change a connection param
--- Note that changes will not apply until the next (re)connect
--- @param name string The parameter's key (see NewDatabase for keys)
--- @param value any The new value to set
function Database:SetConnectionParameter(name, value)
	self._conargs[name] = value
end

--- Connects with the stored args
--- @return Promise #object for the DB connection
--- @see database.NewDatabase
function Database:Connect()
	return self._db:Connect(self._conargs)
		:Then(function(_) return self; end) -- Replace the dbobject with ourself
		:Fail(connectionFail)         -- Always thrown an errmsg
end

local function queryFail(errmsg)
	ErrorNoHalt("Query failed: ", errmsg, "\n")
end

--- Runs a query
--- @param sql string The query to run
--- @param ... any The arguments to pass to the query
--- @return Promise #A promise object for the query's result
function Database:Query(sql, ...)
	if not self:IsConnected() then
		error("Cannot query a non-connected database!", 2)
	end
	local promise
	if ... == nil then
		promise = self._db:Query(sql)
	else
		promise = self._db:PrepareAndRun(sql, ...)
	end
	return promise:Fail(queryFail)
end

--- Prepares a query for future runnage with placeholders
--- @param sql string The querytext, complete with sprintf placeholders
--- @return database.PreparedQuery A prepared query object
--- @see PreparedQuery
function Database:PrepareQuery(sql)
	if not sql then
		error("No query specified!", 2)
	end
	return new(PreparedQuery, sql, self)
end

-- Forwarded functions

--- Nukes the database connection with an undefined effect on any queries currently running. It's generally advisable not to call this
function Database:Disconnect()
	self._db:Disconnect()
end

--- Sanitise a string for insertion into the database
--- @param value string The string to santise
--- @return string A ensafened string
function Database:Escape(value)
	return self._db:Escape(value)
end

--- Checks to seee if Connect as been called and Disconnect hasn't
--- @return boolean
function Database:IsConnected()
	return self._db:IsConnected()
end

--
-- QueryOBJ
--

--- CTor. Only ever called by Database:PrepareQuery
---@param sql string
---@param db database.Database
--- @see Database:PrepareQuery
function PreparedQuery:Init(sql, db)
	self._db  = db
	self._sql = sql
end

--- Set persistant callbacks to be called for every invocation.
--- The callbacks should be of the form of function( [context,] result [, arg1, arg2, ...] ) where arg1+ are arguments passed to SetCallbackArgs
--- @see PreparedQuery:SetCallbackArgs
--- @usage
--- ```lua
--- local query = db:PrepareQuery( "do player stuff" );
--- query:SetCallbacks( {
---      Done: GM.PlayerStuffDone,
---      Fail: GM.PlayerStuffFailed
--- }, GM )
--- ```
--- @param tab table A table of callbacks with names matching Promise object functions
--- @param context any A variable to always pass as the first argument. Typically self for objects/GM.
function PreparedQuery:SetCallbacks(tab, context)
	self._cDone = bind(tab.Done, context)
	self._cFail = bind(tab.Fail, context)
	self._cProg = bind(tab.Progress, context)
	return self
end

--- Sets any extra args that should be passed to the query's callbacks on the next invocation.
--- @param ... any The arguments to be unpacked after the result
function PreparedQuery:SetCallbackArgs(...)
	self._callbackArgs = { ... }
	if #self._callbackArgs == 0 then
		self._callbackArgs = nil
	end
	return self
end

---@param func function|nil
---@param cargs any[]|nil
---@return function|nil
local function bindCArgs(func, cargs)
	if not func or not cargs then
		return func
	end

	return function(res)
		func(res, unpack(cargs))
	end
end

--- Run a prepared query (and then reset it so it can be re-prepared with new data)
--- @param ... any The arguments to pass to the query
--- @return Promise #A promise object for the query's data
function PreparedQuery:Run(...)
	if not self._db:IsConnected() then
		error("Cannot execute query without a database!", 2)
	end
	local callbackArgs = self._callbackArgs
	self._callbackArgs = nil
	return self._db
		:Query(self._sql, ...)
		:Then(
			bindCArgs(self._cDone, callbackArgs),
			bindCArgs(self._cFail, callbackArgs),
			bindCArgs(self._cProg, callbackArgs)
		)
		:Fail(queryFail)
end

local registeredDatabaseMethods = {}
local SQLITE_NAME = "sqlite"

--- Finds the first enabled database method
--- @param enable_sqlite? boolean Wether or not SQLite is acceptable
--- @return database.Driver #The name of the DB method or false if none are available
local function findFirstAvailableDBMethod(enable_sqlite)
	for name, method in pairs(registeredDatabaseMethods) do
		if name ~= SQLITE_NAME and method.CanSelect() then
			return method
		end
	end
	-- Always treat SQLite as a last resort
	if enable_sqlite and registeredDatabaseMethods[SQLITE_NAME] then
		return registeredDatabaseMethods[SQLITE_NAME]
	end
	error("No valid database methods available!", 2)
end

local function req(tab, name)
	if not tab[name] then
		error("You're missing '" .. name .. "' from the connection parameters!", 3)
	end
end

---
--- The module's main function - Creates and returns a new database object
--- ```lua
--- local db = database.NewDatabase({
---     Hostname = "localhost", -- Where to find the MySQL server
---     Username = "root", -- Who to log in as
---     Password = "top secret password", -- The user's password
---     Database = "gmod", -- The database to work in
---     Port = 3306, -- [Optional] The port to connect to the server on
---     EnableSQLite = false, -- [Optional] If the server's local SQLite db is an acceptable 'MySQL server'.
---     DBMethod = false, -- [Optional] Override the automatic module checker
--- });
--- db:Connect() -- Returns a promise object
---     :Done(function() end) -- DB Connected
---     :Fail(function(err) end) -- DB could not connect. (Will trigger an error + server log automatically)
--- ```
--- @param connection database.ConnectionInfo A table composed of the following fields:
--- @return database.Database #A Database object
function database.NewDatabase(connection)
	if type(connection) ~= "table" then
		error("Invalid connection data passed!", 2)
	end
	req(connection, "Hostname")
	req(connection, "Username")
	req(connection, "Password")
	req(connection, "Database")
	connection.Port = connection.Port or 3306
	connection.Port = tonumber(connection.Port)
	req(connection, "Port")

	local db_name = connection.DBMethod
	--- @type database.Driver
	local db_driver
	if type(db_name) == "string" then
		db_driver = registeredDatabaseMethods[string.lower(db_name)]
		if not db_driver then
			error("Database module '" .. db_name .. "' does not exist!")
		elseif not db_driver:CanSelect() then
			error("Database module '" .. db_name .. "' is not available!")
		end
	else
		db_driver = findFirstAvailableDBMethod(connection.EnableSQLite)
	end
	return new(Database, connection, new(db_driver))
end

local function req(tab, name)
	if not tab[name] then
		error("You're missing '" .. name .. "' from the database methods!", 3)
	end
end

--- Registers a new Database method for usage
--- @param tab database.Driver The __index metatable for instances to have
function database.RegisterDBMethod(tab)
	req(tab, "Name")
	req(tab, "Connect")
	req(tab, "Disconnect")
	req(tab, "IsConnected")
	req(tab, "Escape")
	req(tab, "Query")
	req(tab, "PrepareAndRun")
	req(tab, "CanSelect")
	registeredDatabaseMethods[string.lower(tab.Name)] = tab
end

-- Expose our privates for dr test
if _TEST then
	database._registeredDatabaseMethods = registeredDatabaseMethods
	database._findFirstAvailableDBMethod = findFirstAvailableDBMethod
	database._Database = database.Database
	database._PreparedQuery = PreparedQuery
	database._new = new
	database._bind = bind
	database._bindCArgs = bindCArgs
end

return database
