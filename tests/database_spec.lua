--[[
	Copyright (c) 2014 Lexi Robinson

	This code is free software: you can redistribute it and/or modify it under
	the terms of the GNU Lesser General Public License as published by the Free
	Software Foundation, either version 3 of the License, or (at your option)
	any later version.

	This code is distributed in the hope that it will be useful, but WITHOUT ANY
	WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
	FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
	details.

	You should have received a copy of the GNU Lesser General Public License
	along with this code. If not, see <https://www.gnu.org/licenses/>.
--]]

-- Avoid spam
---@diagnostic disable-next-line: duplicate-set-field
_G.ErrorNoHalt = function() end
-- Given that busted doesn't do this (despite saying it does)
_G._TEST = true

local match = require("luassert.match")
local database = require "database"
local drivers = require "database_drivers"
local Deferred = require "promises"

local mockDB = {
	Name = "Mock",
	["Connect"] = function(self)
		return Deferred():Resolve(self):Promise()
	end,
	["Disconnect"] = function() end,
	["IsConnected"] = function()
		return true
	end,
	["Escape"] = function(text)
		return text
	end,
	["Query"] = function()
		return Deferred():Resolve():Promise()
	end,
	["PrepareAndRun"] = function()
		return Deferred():Resolve():Promise()
	end,
	["CanSelect"] = function()
		return true
	end,
}

local invalidDB = {
	Name = "Mock",
	["Connect"] = function() end,
	["Disconnect"] = function() end,
	["IsConnected"] = function() end,
	["Escape"] = function() end,
	["Query"] = function() end,
	["PrepareAndRun"] = function() end,
	["CanSelect"] = function() return false; end,
}

local emptyDB = {
	Name = "Mock",
	["Connect"] = function() end,
	["Disconnect"] = function() end,
	["IsConnected"] = function() end,
	["Escape"] = function() end,
	["Query"] = function() end,
	["PrepareAndRun"] = function() end,
	["CanSelect"] = function() return true; end,
}

-- safety
local function copy(tab)
	local new = {}
	for k, v in pairs(tab) do
		new[k] = v
	end
	return new
end

-- Stubs are tables and tables can't go into then
local function thenable(a)
	return function(...) return a(...) end
end

local function setupMockDriver()
	database.RegisterDBMethod(mockDB)
end

local function registerSQLite()
	local _mocksqlite = copy(mockDB)
	_mocksqlite.Name = "SQLite"
	database.RegisterDBMethod(_mocksqlite)
	return _mocksqlite
end

local function clearDrivers()
	for key, _ in pairs(database._registeredDatabaseMethods) do
		database._registeredDatabaseMethods[key] = nil
	end
end

local function _stub() return spy.new(function() end) end

-- Tests of internal functions
describe("_new", function()
	it("should not return the actual table passed", function()
		local value = { a = 1 }
		assert.are_not.equal(value, database._new(value))
	end)
	it("should return an instance of the passed table", function()
		local value = { a = 1, b = 2, c = { d = 4 } }
		local inst = database._new(value)
		for k, v in pairs(value) do
			assert.are.equal(inst[k], v)
		end
		inst.e = 5
		assert.is_nil(value.e)
	end)
	it("should call the Init function if available", function()
		local value = { Init = spy.new(function() end) }
		local one, two = "one", "two"
		local inst = database._new(value, one, two)
		assert.spy(value.Init).was.called(1)
		assert.spy(value.Init).was.called_with(inst, one, two)
	end)
end)

describe("_bind", function()
	it("should do nothing if passed nothing", function()
		local res = database._bind()
		assert.is_nil(res)
	end)
	it("should do nothing if not passed a self", function()
		local function func() end
		assert.is.equal(func, database._bind(func))
	end)
	it("should return a function that always gets called with self", function()
		local func = spy.new(function() end)
		local one, two, three = "one", "two", "three"
		local func2 = database._bind(func, one)
		---@diagnostic disable-next-line: need-check-nil
		func2(two, three)
		assert.spy(func).was.called(1)
		assert.spy(func).was.called_with(one, two, three)
	end)
end)

describe("_bindCArgs", function()
	it("should do nothing if not pased cargs", function()
		local function func() end
		assert.are.equal(database._bindCArgs(func), func)
	end)
	it("should return a function that unpacks the passed arugments into it as the second arguments", function()
		local func = spy.new(function() end)
		local one, two, three, four = "one", "two", "three", "four"
		---@diagnostic disable-next-line: param-type-mismatch
		local func2 = database._bindCArgs(func, { two, three })
		assert.are_not.equal(func, func2)
		---@diagnostic disable-next-line: redundant-parameter, need-check-nil
		func2(one, four)
		assert.spy(func).was.called(1)
		assert.spy(func).was.called_with(one, two, three)
	end)
end)

describe("_checkmodule", function()
	it("should not do anything outside of Garry's Mod", function()
		assert.is_false(drivers._checkmodule("tmysql"))
	end)
	-- This needs heavy mocking to work
	-- describe("in a faked environment", function()
	-- 	pending("should request a module suffixed for the system it's on")
	-- 	pending("should request a module prefixed for the state it is in")
	-- 	pending("should check if the requested module is available first")
	-- 	pending("should require the module if it is available")
	-- end)
end)

-- "Simple" tests
describe("NewDatabase", function()
	after_each(clearDrivers)

	it("should be picky about its arguments", function()
		---@diagnostic disable-next-line: missing-parameter
		assert.has.error(function() database.NewDatabase(); end)
		---@diagnostic disable-next-line: param-type-mismatch
		assert.has.error(function() database.NewDatabase(false); end)
		local function checkErrors(...)
			database.RegisterDBMethod(mockDB)
			local tab = {}
			for _, name in pairs { ... } do
				tab[name] = ""
			end
			assert.has.error_matches(function() database.NewDatabase(tab); end,
				"You're missing '.+' from the connection parameters!")
		end

		checkErrors("Hostname")
		checkErrors("Hostname", "Username")
		checkErrors("Hostname", "Username", "Password")
		checkErrors("Hostname", "Username", "Database")
		assert.has.error(function()
			database.NewDatabase({
				Username = "",
				Hostname = "",
				Password = "",
				Database = "",
				---@diagnostic disable-next-line: assign-type-mismatch
				Port = "Hi!",
			})
		end, "You're missing 'Port' from the connection parameters!")
	end)

	it("Should return an object", function()
		database.RegisterDBMethod(mockDB)
		assert.is_table(database.NewDatabase({
			Username = "",
			Hostname = "",
			Password = "",
			Database = "",
		}))
	end)

	it("Validates the specified DB driver exists", function()
		assert.has.error(function()
				database.NewDatabase({
					Hostname = "",
					Username = "",
					Password = "",
					Database = "",
					DBMethod = "Invalid",
				})
			end,
			"Database module 'Invalid' does not exist!")
	end)

	it("Validates the specified DB driver can be selected", function()
		database.RegisterDBMethod(invalidDB)
		assert.has.error(function()
				database.NewDatabase({
					Hostname = "",
					Username = "",
					Password = "",
					Database = "",
					DBMethod = "Mock",
				})
			end,
			"Database module 'Mock' is not available!")
	end)

	it("Requires a database driver exists", function()
		registerSQLite()
		assert.has.error(function()
				database.NewDatabase({
					Hostname = "",
					Username = "",
					Password = "",
					Database = "",
				})
			end,
			"No valid database methods available!")
	end)

	it("Can select SQLite", function()
		registerSQLite()
		assert.has.no_error(function()
			database.NewDatabase({
				Hostname = "",
				Username = "",
				Password = "",
				Database = "",
				EnableSQLite = true,
			})
		end
		)
	end)
end)


describe("findFirstAvailableDBMethod", function()
	after_each(clearDrivers)

	it("Should error if nothing is available", function()
		assert.has.error(function() print(database._findFirstAvailableDBMethod().Name) end)
	end)

	it("Returns an available method", function()
		database.RegisterDBMethod(mockDB)
		assert.is.equal(database._findFirstAvailableDBMethod(), mockDB)
	end)

	it("Should error if something is available but not selectable", function()
		database.RegisterDBMethod(invalidDB)
		assert.has.error(function() database._findFirstAvailableDBMethod() end)
	end)

	it("Should error if SQLite is available but unasked for", function()
		registerSQLite()
		assert.has.error(function() database._findFirstAvailableDBMethod() end)
	end)

	it("Should return SQLite if requested and nothing else is available", function()
		local sqlite = registerSQLite()
		assert.is.equal(database._findFirstAvailableDBMethod(true), sqlite)
	end)

	it("Should not return SQLite if something better is available", function()
		database.RegisterDBMethod(mockDB)
		registerSQLite()
		assert.is.equal(database._findFirstAvailableDBMethod(true), mockDB)
	end)

	it("Should check the validity of db methods", function()
		database.RegisterDBMethod(mockDB)
		local _spy = spy.on(mockDB, "CanSelect")
		assert.is.equal(database._findFirstAvailableDBMethod(), mockDB)
		assert.spy(_spy).was.called_at_least(1)
		_spy:revert()
	end)
end)

describe("RegisterDBMethod", function()
	after_each(clearDrivers)

	it("should be picky about its arguments", function()
		---@diagnostic disable-next-line: missing-parameter
		assert.has.error(function() database.RegisterDBMethod(); end)
		---@diagnostic disable-next-line: missing-fields
		assert.has.error(function() database.RegisterDBMethod({}); end)
		---@diagnostic disable-next-line: param-type-mismatch
		assert.has.error(function() database.RegisterDBMethod(""); end)
		local function checkErrors(...)
			local tab = { Name = "" }
			for _, name in pairs { ... } do
				tab[name] = function() end
			end
			assert.has.error(function() database.RegisterDBMethod(tab); end)
		end

		checkErrors("Connect")
		checkErrors("Connect", "Disconnect")
		checkErrors("Connect", "Disconnect", "IsConnected")
		checkErrors("Connect", "Disconnect", "IsConnected", "Escape")
		checkErrors("Connect", "Disconnect", "IsConnected", "Escape", "Query")
		checkErrors("Connect", "Disconnect", "IsConnected", "Escape", "CanSelect")
	end)
	it("should create methods", function()
		assert.has_no.error(function()
			database.RegisterDBMethod(emptyDB)
		end)
		assert.is.equal(database._registeredDatabaseMethods["mock"], emptyDB)
	end)
	it("should overwite methods", function()
		database.RegisterDBMethod(mockDB)
		database.RegisterDBMethod(emptyDB)
		assert.is_not.equal(database._registeredDatabaseMethods["mock"], mockDB)
		assert.is.equal(database._registeredDatabaseMethods["mock"], emptyDB)
	end)
end)

-- Somewhat more involved tests
describe("Database", function()
	local db, mockObj, cparams
	before_each(function()
		mockObj = mock(copy(mockDB))
		database.RegisterDBMethod(mockObj)
		cparams = {
			Username = "username",
			Hostname = "hostname",
			Password = "password",
			Database = "database",
		}
		db = database.NewDatabase(cparams)
	end)
	after_each(function()
		cparams = nil
		db = nil
		mockObj = nil
		clearDrivers()
	end)

	describe(":Connect", function()
		it("Should default to the only available method", function()
			db:Connect()
			assert.spy(mockObj.CanSelect).was.called_at_least(1)
			assert.spy(mockObj.Connect).was.called(1)
			assert.spy(mockObj.Connect).was.called_with(match._, cparams)
		end)

		it("Should use the requested method", function()
			-- Setup
			local _mockObj1 = copy(mockDB)
			_mockObj1.Name = "Mock 1"
			local mockObj1 = mock(_mockObj1)
			database.RegisterDBMethod(mockObj1)

			local _mockObj2 = copy(mockDB)
			_mockObj2.Name = "Mock 2"
			local mockObj2 = mock(_mockObj2)
			database.RegisterDBMethod(mockObj2)

			local _mockObj3 = copy(mockDB)
			_mockObj3.Name = "Mock 3"
			local mockObj3 = mock(_mockObj3)
			database.RegisterDBMethod(mockObj3)

			cparams["DBMethod"] = "Mock 2"
			db = database.NewDatabase(cparams)

			-- Test
			db:Connect()
			assert.spy(mockObj.Connect).was.called(0)
			assert.spy(mockObj1.Connect).was.called(0)
			assert.spy(mockObj3.Connect).was.called(0)
			assert.spy(mockObj2.Connect).was.called(1)
			assert.spy(mockObj2.Connect).was.called_with(match._, cparams)
		end)

		it("Should return itself on successful connect", function()
			local a, b = _stub(), _stub()
			db:Connect():Then(thenable(a), thenable(b))
			assert.spy(a).was.called(1)
			assert.spy(a).was.called_with(db)
			assert.spy(b).was.called(0)
		end)
	end)

	describe(":Query", function()
		-- TODO: Query Queue!
		it("should throw an error if the database disconnects", function()
			local IsConnected = true
			mockObj.IsConnected = spy.new(function() return IsConnected; end)
			db:Connect()
			assert.has_no.error(function() db:Query("foo") end)
			IsConnected = false
			assert.has.error(function() db:Query("foo") end)
		end)
		it("Should call the underlying method with no changes", function()
			db:Connect()
			local query = "foo"
			db:Query(query)
			assert.spy(mockObj.Escape).was.called(0)
			assert.spy(mockObj.Query).was.called(1)
			assert.spy(mockObj.Query).was.called_with(mockObj, query)
		end)
		it("Should return a promise", function()
			local resp = "It worked!"
			mockObj.Query = spy.new(function()
				return Deferred():Resolve(resp):Promise()
			end)
			local query = "foo"
			db:Connect()
			local a, b = _stub(), _stub()
			db:Query(query):Then(thenable(a), thenable(b))
			assert.spy(a).was.called(1)
			assert.spy(a).was.called_with(resp)
			assert.spy(b).was.called(0)
		end)
	end)

	describe(":Escape", function()
		it("passes arguments verbatum to the db method", function()
			db:Connect()
			local value = "foobar"
			db:Escape(value)
			assert.spy(mockObj.Escape).was.called(1)
			assert.spy(mockObj.Escape).was.called_with(mockObj, value)
		end)
		it("returns the db method's responses", function()
			local value, response = "foobar", "barfoo"
			mockObj.Escape = spy.new(function() return response end)
			db:Connect()
			local ret = db:Escape(value)
			assert.is.equal(ret, response)
		end)
	end)

	describe(":Disconnect", function()
		it("calls the db method", function()
			db:Connect()
			assert.has_no.error(function() db:Disconnect() end)
			assert.spy(mockObj.Disconnect).was.called(1)
		end)
	end)

	describe(":PrepareQuery", function()
		it("does not require a connected database", function()
			local query
			assert.has_no.error(function()
				query = db:PrepareQuery("foo")
			end)
			assert.is_not_nil(query)
		end)
		it("should error if not given any text", function()
			db:Connect()
			assert.has.error(function() db:PrepareQuery() end)
		end)
		it("should return a prepared query", function()
			-- TODO: Use the database._PreparedQuery private somehow?
			db:Connect()
			local query = db:PrepareQuery("foo")
			assert.is.table(query)
		end)
	end)

	describe(":SetConnectionParameter", function()
		local constub, orighost
		before_each(function()
			constub = _stub()
			local prevc = mockObj.Connect
			mockObj.Connect = spy.new(function(obj, args)
				constub(args.Hostname)
				return prevc(obj.args)
			end)
			orighost = cparams.Hostname
		end)
		after_each(function()
			constub = nil
		end)
		it("overrides connection parameters", function()
			local newval = "foobar"
			db:SetConnectionParameter("Hostname", newval)
			db:Connect()
			assert.spy(constub).was.called_with(newval)
			assert.spy(constub).was.not_called_with(orighost)
		end)
		it("does nothing to active connections", function()
			local newval = "foobar"
			db:Connect()
			db:SetConnectionParameter("Hostname", newval)
			assert.spy(constub).was.not_called_with(newval)
			assert.spy(constub).was.called_with(orighost)
		end)
		it("sets the parameters for the next Connect call", function()
			local newval = "foobar"
			db:Connect()
			db:SetConnectionParameter("Hostname", newval)
			db:Connect()
			assert.spy(constub).was.called_with(newval)
		end)
	end)
end)

describe("PreparedQuery", function()
	local db, mockObj, cparams, queryFunc
	local one, two, three = "one", "two", "three"
	before_each(function()
		mockObj = mock(copy(mockDB))
		local function mockQuery(...)
			local def = Deferred()
			queryFunc(def, ...)
			return def:Promise()
		end
		mockObj.Query = spy.new(mockQuery)
		mockObj.PrepareAndRun = spy.new(mockQuery)
		queryFunc = function(def)

		end
		database.RegisterDBMethod(mockObj)
		cparams = {
			Username = "username",
			Hostname = "hostname",
			Password = "password",
			Database = "database",
		}
		db = database.NewDatabase(cparams)
		db:Connect()
	end)
	after_each(function()
		cparams = nil
		db = nil
		mockObj = nil
		clearDrivers()
	end)
	describe(":SetCallbacks", function()
		local done, fail, prog, query
		before_each(function()
			query = db:PrepareQuery("foobar")
			done, fail, prog = _stub(), _stub(), _stub()
			query:SetCallbacks({
				Done = done,
				Fail = fail,
				Progress = prog,
			})
		end)
		after_each(function()
			done, fail, prog = nil, nil, nil
			query = nil
		end)

		it("calls the done callback on a successful query", function()
			queryFunc = function(def)
				def:Resolve(one)
			end
			query:Run()
			assert.spy(done).was.called(1)
			assert.spy(done).was.called_with(one)
			assert.spy(fail).was.called(0)
		end)
		it("calls the fail callback on a failed query", function()
			queryFunc = function(def)
				def:Reject(one)
			end
			query:Run()
			assert.spy(fail).was.called(1)
			assert.spy(fail).was.called_with(one)
			assert.spy(done).was.called(0)
		end)
		it("calls the prog callback on query progress", function()
			queryFunc = function(def)
				def:Notify(one)
				def:Notify(two)
				def:Resolve(three)
			end
			query:Run()
			assert.spy(prog).was.called(2)
			assert.spy(prog).was.called_with(one)
			assert.spy(prog).was.called_with(two)
			assert.spy(prog).was.not_called_with(three)
		end)
		it("overwrites previous callbacks", function()
			queryFunc = function(def)
				def:Resolve(one)
			end
			local newdone = _stub()
			query:SetCallbacks({
				Done = newdone,
			})
			query:Run()
			assert.spy(done).was.called(0)
			assert.spy(newdone).was.called(1)
			assert.spy(newdone).was.called_with(one)
		end)
		it("binds callbacks to the passed context", function()
			queryFunc = function(def)
				def:Resolve(two)
			end
			query:SetCallbacks({
				Done = done,
			}, one)
			query:Run()
			assert.spy(done).was.called(1)
			assert.spy(done).was.called_with(one, two)
		end)
		it("doesn't require all three arguments", function()
			assert.has_no.error(function()
				query:SetCallbacks({
					Done = nil,
					Fail = fail,
					Progress = prog,
				})
			end)
			assert.has_no.error(function()
				query:SetCallbacks({
					Done = done,
					Fail = nil,
					Progress = prog,
				})
			end)
			assert.has_no.error(function()
				query:SetCallbacks({
					Done = done,
					Fail = fail,
					Progress = nil,
				})
			end)
			assert.has_no.error(function()
				query:SetCallbacks({
					Done = done,
					Fail = nil,
					Progress = nil,
				})
			end)
			assert.has_no.error(function()
				query:SetCallbacks({
					Done = nil,
					Fail = fail,
					Progress = nil,
				})
			end)
			assert.has_no.error(function()
				query:SetCallbacks({
					Done = nil,
					Fail = nil,
					Progress = prog,
				})
			end)
			assert.has_no.error(function()
				query:SetCallbacks({
					Done = done,
					Fail = nil,
					Progress = prog,
				})
			end)
		end)
		it("removes unspecified callbacks when overwriting", function()
			queryFunc = function(def)
				def:Resolve(one)
			end
			query:SetCallbacks({
				Done = nil,
				Fail = fail,
				Progress = prog,
			})
			query:Run()
			assert.spy(done).was.called(0)
		end)
	end)
	describe(":SetCallbackArgs", function()
		local done, fail, prog, query
		local one, two, three = "one", "two", "three"
		before_each(function()
			query = db:PrepareQuery("foobar")
			done, fail, prog = _stub(), _stub(), _stub()
			query:SetCallbacks({
				Done = done,
				Fail = fail,
				Progress = prog,
			})
			queryFunc = function(def)
				def:Resolve(one)
			end
		end)
		after_each(function()
			done, fail, prog = nil, nil, nil
			queryFunc = nil
			query = nil
		end)

		describe("passes the arguments to", function()
			before_each(function()
				query:SetCallbackArgs(two, three)
			end)

			it("progress callbacks", function()
				queryFunc = function(def)
					def:Notify(one)
				end
				query:Run()
				assert.spy(prog).was.called(1)
				assert.spy(prog).was.called_with(one, two, three)
			end)
			it("success callbacks", function()
				queryFunc = function(def)
					def:Resolve(one)
				end
				query:Run()
				assert.spy(done).was.called(1)
				assert.spy(done).was.called_with(one, two, three)
			end)
			it("failure callbacks", function()
				queryFunc = function(def)
					def:Reject(one)
				end
				query:Run()
				assert.spy(fail).was.called(1)
				assert.spy(fail).was.called_with(one, two, three)
			end)
		end)
		it("only passes each set once per run", function()
			query:SetCallbackArgs(two, three)
			query:Run()
			query:Run()
			assert.spy(done).was.called(2)
			assert.spy(done).was.called_with(one, two, three)
			assert.spy(done).was.called_with(one)
		end)
		it("can be reset by passing nothing", function()
			query:SetCallbackArgs(two, three)
			query:SetCallbackArgs()
			query:Run()
			assert.spy(done).was.called(1)
			assert.spy(done).was.not_called_with(one, two, three)
			assert.spy(done).was.called_with(one)
		end)
	end)
	describe(":Run", function()
		-- TODO: Query Queue!
		it("throws an error if the database has disconnected", function()
			local IsConnected = true
			mockObj.IsConnected = spy.new(function() return IsConnected; end)
			db:Connect()
			local query = db:PrepareQuery("foobar")
			assert.has_no.error(function() query:Run() end)
			IsConnected = false
			assert.has.error(function() query:Run() end)
		end)
		it("It calls :Query if there are no parameters", function()
			local qtext = "foobar"
			local query = db:PrepareQuery(qtext)
			assert.has_no.error(function() query:Run() end)
			assert.spy(mockObj.Query).was.called(1)
			assert.spy(mockObj.Query).was.called_with(mockObj, qtext)
			assert.spy(mockObj.Escape).was.called(0)
		end)
		it("It calls :PrepareAndRun if there are parameters", function()
			local qtext = "foobar"
			local query = db:PrepareQuery(qtext)
			assert.has_no.error(function() query:Run(1, 2) end)
			assert.spy(mockObj.PrepareAndRun).was.called(1)
			assert.spy(mockObj.PrepareAndRun).was.called_with(mockObj, qtext, 1, 2)
			assert.spy(mockObj.Escape).was.called(0)
		end)
		it("returns a promise", function()
			local query = db:PrepareQuery("foobar")
			local done = _stub()
			local one = "one"
			queryFunc = function(def)
				def:Resolve()
			end


			local prom = query:Run()
			assert.is.table(prom)
			assert.is_true(prom._IsPromise)
			assert.is_function(prom.Then)
			prom:Then(thenable(done))
			assert.spy(done).was.called(1)
		end)
		it("returns a promise for this run only", function()
			local query = db:PrepareQuery("foobar")
			local done1, done2 = _stub(), _stub()
			local one, two = "one", "two"
			local retval
			queryFunc = function(def)
				def:Resolve(retval)
			end

			retval = one
			query:Run():Then(thenable(done1))
			retval = two
			query:Run():Then(thenable(done2))

			assert.spy(done1).was.called(1)
			assert.spy(done2).was.called(1)
			assert.spy(done1).was.called_with(one)
			assert.spy(done2).was.called_with(two)
			assert.spy(done1).was.not_called_with(two)
			assert.spy(done2).was.not_called_with(one)
		end)
	end)
end)
