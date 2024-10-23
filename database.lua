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

if (not ErrorNoHalt) then
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

--- @class DatabaseConnectionInfo
--- @field Hostname string
--- @field Username string
--- @field Password string
--- @field Database string
--- @field Port? integer
--- @field Socket? string

--- @class DatabaseDriver
--- @field Init? fun(self): nil
--- @field Connect fun(self, info: DatabaseConnectionInfo): Promise
--- @field Disconnect fun(self): nil
--- @field Query fun(self, sql: string): Deferred
--- @field Escape fun(self, value: string): string
--- @field IsConnected fun(self): boolean
--- @field CanSelect fun(self): boolean

--- The main Database object the developer will generally be interacting with
--- @class Database
local Database = {}

--- A client-side prepared query object.
--- @class DatabasePreparedQuery
--- @see Database.PrepareQuery
local PreparedQuery = {}

--- Does a basic form of OO
--- @param tab table The metatable to make an object from
--- @param ... any Stuff to pass to the ctor (if it exists)
--- @return any ye new object
local function new(tab, ...)
	local ret = setmetatable({}, { __index = tab })
	if (ret.Init) then
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
	if (not func) then
		return
	elseif (self) then
		return function(...) return func(self, ...); end
	else
		return func
	end
end

--
-- DBOBJ
--

--- CTor. Accepts the variables passed to NewDatabase
--- @see NewDatabase
--- @param tab DatabaseConnectionInfo connection details
function Database:Init(tab)
	self._conargs = tab
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
--- @see NewDatabase
function Database:Connect()
	if (not self._db) then
		local db = self._conargs.DBMethod
		if (db) then
			local success, errmsg = database.IsValidDBMethod(db)
			if (not success) then
				error("Cannot use database method '" .. db .. "': " .. errmsg, 2)
			end
		else
			db = database.FindFirstAvailableDBMethod(self._conargs.EnableSQLite)
			if (not db) then
				error("No valid database methods available!", 2)
			end
		end
		self._db = database.GetNewDBMethod(db)
	end
	return self._db:Connect(self._conargs, self)
		:Then(function(_) return self; end) -- Replace the dbobject with ourself
		:Fail(connectionFail)         -- Always thrown an errmsg
end

local function queryFail(errmsg)
	ErrorNoHalt("Query failed: ", errmsg, "\n")
end

--- Runs a query
--- @param text string The query to run
--- @return Promise #A promise object for the query's result
function Database:Query(text)
	if (not self:IsConnected()) then
		error("Cannot query a non-connected database!", 2)
	end
	return self._db:Query(text):Fail(queryFail)
end

--- Prepares a query for future runnage with placeholders
--- @param text string The querytext, complete with sprintf placeholders
--- @return DatabasePreparedQuery A prepared query object
--- @see PreparedQuery
function Database:PrepareQuery(text)
	if (not text) then
		error("No query text specified!", 2)
	end
	local _, narg = string.gsub(string.gsub(text, "%%%%", ""), "(%%[diouXxfFeEgGaAcsb])", "")
	return new(PreparedQuery, {
		Text    = text,
		DB      = self,
		NumArgs = narg,
	})
end

-- Forwarded functions

--- Nukes the database connection with an undefined effect on any queries currently running. It's generally advisable not to call this
function Database:Disconnect()
	if (self._db) then
		self._db:Disconnect()
	end
end

--- Sanitise a string for insertion into the database
--- @param text string The string to santise
--- @return string A ensafened string
function Database:Escape(text)
	if (not self._db) then
		error("Cannot escape without an active DB. (Have you called Connect()?)")
	end
	return self._db:Escape(text)
end

--- Checks to seee if Connect as been called and Disconnect hasn't
--- @return boolean
function Database:IsConnected()
	return self._db and self._db:IsConnected() or false
end

--
-- QueryOBJ
--

--- CTor. Only ever called by Database:PrepareQuery
--- @param qargs table data from the mothership
--- @see Database:PrepareQuery
function PreparedQuery:Init(qargs)
	self._db     = qargs.DB
	self.Text    = qargs.Text
	self.NumArgs = qargs.NumArgs
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
	if (#self._callbackArgs == 0) then
		self._callbackArgs = nil
	end
	return self
end

--- Prepares the query for the next invocation.
--- @param ... any The arguments to escape and sprintf into the query
function PreparedQuery:Prepare(...)
	if (self.NumArgs == 0) then
		return
	end
	self._preped = true
	local args = { ... }
	local nargs = #args
	if (nargs < self.NumArgs) then
		error("Argument count missmatch! Expected " .. self.NumArgs .. " but only received " .. nargs .. "!", 2)
	end
	for i, arg in pairs(args) do
		args[i] = self._db:Escape(arg)
	end
	self._prepedText = string.format(self.Text, ...)
	return self
end

local function bindCArgs(func, cargs)
	if (not cargs) then
		return func
	else
		return function(res)
			func(res, unpack(cargs))
		end
	end
end

--- Run a prepared query (and then reset it so it can be re-prepared with new data)
--- @return Promise #A promise object for the query's data
function PreparedQuery:Run()
	if (not self._db:IsConnected()) then
		error("Cannot execute query without a database!", 2)
	end
	local text
	if (self.NumArgs == 0) then
		text = self.Text
	elseif (not self._preped) then
		error("Tried to run an unprepared query!", 2)
	else
		text = self._prepedText
	end

	local p = self._db:Query(text)
	-- Deal w/ callbacks
	local _ca = self._callbackArgs
	if (self._cDone) then
		p:Done(bindCArgs(self._cDone, _ca))
	end
	if (self._cFail) then
		p:Fail(bindCArgs(self._cFail, _ca))
	end
	if (self._cProg) then
		p:Progress(bindCArgs(self._cProg, _ca))
	end
	-- Reset state
	self._preped = false
	self._callbackArgs = nil
	return p
end

local registeredDatabaseMethods = {}

local function req(tab, name)
	if (not tab[name]) then
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
--- @param connection DatabaseConnectionInfo A table composed of the following fields:
--- @return Database #A Database object
function database.NewDatabase(connection)
	if (type(connection) ~= "table") then
		error("Invalid connection data passed!", 2)
	end
	req(connection, "Hostname")
	req(connection, "Username")
	req(connection, "Password")
	req(connection, "Database")
	connection.Port = connection.Port or 3306
	connection.Port = tonumber(connection.Port)
	req(connection, "Port")
	return new(Database, connection)
end

--- Finds the first enabled database method
--- @param EnableSQLite? boolean Wether or not SQLite is acceptable
--- @return string | boolean #The name of the DB method or false if none are available
function database.FindFirstAvailableDBMethod(EnableSQLite)
	for name, method in pairs(registeredDatabaseMethods) do
		if (method.CanSelect() and (EnableSQLite or name ~= "sqlite")) then
			return name
		end
	end
	return false
end

--- Creates and returns a new instance of a DB method
--- @param name string The name to instantatiationonate
--- @return Database | boolean, string? #An instance if it worked, false and an error message if it didn't
function database.GetNewDBMethod(name)
	if (not name) then
		error("No method name passed!", 2)
	end
	local s, e = database.IsValidDBMethod(name)
	if (not s) then
		return s, e
	end
	return new(database.GetDBMethod(name))
end

local function req(tab, name)
	if (not tab[name]) then
		error("You're missing '" .. name .. "' from the database methods!", 3)
	end
end

--- Registers a new Database method for usage
--- @param name string The name of the new method
--- @param tab DatabaseDriver The __index metatable for instances to have
function database.RegisterDBMethod(name, tab)
	if (type(name) ~= "string") then
		error("Expected a string for argument 1 of database.RegisterDBMethod!", 2)
	elseif (type(tab) ~= "table") then
		error("Expected a table for argument 2 of database.RegisterDBMethod!", 2)
	end
	tab.Name = name
	req(tab, "Connect")
	req(tab, "Disconnect")
	req(tab, "IsConnected")
	req(tab, "Escape")
	req(tab, "Query")
	req(tab, "CanSelect")
	registeredDatabaseMethods[string.lower(tab.Name)] = tab
end

--- Checks to see if a Database method is available for use
--- @param name string
--- @return boolean success, string? error #true or false and an error message
function database.IsValidDBMethod(name)
	if (not name) then
		error("No method name passed!", 2)
	end
	local db = registeredDatabaseMethods[string.lower(name)]
	if (not db) then
		return false, "Database method '" .. name .. "' does not exist!"
	end
	return db.CanSelect()
end

--- Returns a DB method's master metatable
--- @param name string
--- @return DatabaseDriver
function database.GetDBMethod(name)
	if (not name) then
		error("No method name passed!", 2)
	end
	return registeredDatabaseMethods[string.lower(name)]
end

-- Expose our privates for dr test
if (_TEST) then
	database._registeredDatabaseMethods = registeredDatabaseMethods
	database._Database = Database
	database._PreparedQuery = PreparedQuery
	database._new = new
	database._bind = bind
	database._bindCArgs = bindCArgs
end

return database
