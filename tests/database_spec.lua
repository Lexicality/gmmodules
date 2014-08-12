-- Avoid spam
_G.ErrorNoHalt = function() end
-- Given that busted doesn't do this (despite saying it does)
_G._TEST = true;

require "database";

local Deferred = require 'promises';

local mockDB = {
	["Connect"] = function()
		return Deferred():Resolve(self):Promise();
	end;
	["Disconnect"] = function() end;
	["IsConnected"] = function()
		return true;
	end;
	["Escape"] = function(text)
		return text;
	end;
	["Query"] = function()
		return Deferred():Reject("This method should be overriden!"):Promise();
	end;
	["CanSelect"] = function()
		return true;
	end;
}

local invalidDB = {
	["Connect"] = function() end;
	["Disconnect"] = function() end;
	["IsConnected"] = function() end;
	["Escape"] = function() end;
	["Query"] = function() end;
	["CanSelect"] = function() return false; end;
}

local emptyDB = {
	["Connect"] = function() end;
	["Disconnect"] = function() end;
	["IsConnected"] = function() end;
	["Escape"] = function() end;
	["Query"] = function() end;
	["CanSelect"] = function() return true; end;
}

-- safety
local function copy( tab )
	local new = {};
	for k, v in pairs(tab) do
		new[k] = v;
	end
	return new;
end

-- Stubs are tables and tables can't go into then
local function thenable(a)
	return function(...) return a(...) end
end

-- Tests of internal functions
describe("_new", function()
	it("should not return the actual table passed", function()
		local value = { a = 1};
		assert.are_not.equal( value, database._new(value) );
	end);
	it("should return an instance of the passed table", function()
		local value = { a = 1, b = 2, c = { d = 4 } };
		local inst = database._new( value );
		for k, v in pairs( value ) do
			assert.are.equal(inst[k], v);
		end
		inst.e = 5;
		assert.is_nil( value.e );
	end);
	it("should call the Init function if available", function()
		local value = { Init = spy.new(function() end) };
		local one, two = "one", "two";
		local inst = database._new( value, one, two );
		assert.spy(value.Init).was.called(1);
		assert.spy(value.Init).was.called_with( inst, one, two );
	end);
end)

describe("_bind", function()
	it("should do nothing if passed nothing", function()
		assert.is_nil( database._bind() );
	end);
	it("should do nothing if not passed a self", function()
		local function func() end;
		assert.is.equal(func, database._bind(func));
	end);
	it("should return a function that always gets called with self", function()
		local func = spy.new(function() end);
		local one, two, three = "one", "two", "three";
		local func2 = database._bind(func, one);
		func2(two, three);
		assert.spy(func).was.called(1);
		assert.spy(func).was.called_with(one, two, three);
	end);
end)

describe("_bindCArgs", function()
	it("should do nothing if not pased cargs", function()
		local function func() end
		assert.are.equal(database._bindCArgs(func), func);
	end);
	it("should return a function that unpacks the passed arugments into it as the second arguments", function()
		local func = spy.new(function() end);
		local one, two, three, four = "one", "two", "three", "four";
		local func2 = database._bindCArgs(func, {two, three});
		assert.are_not.equal(func, func2);
		func2(one, four);
		assert.spy(func).was.called(1);
		assert.spy(func).was.called_with(one, two, three);
	end);
end)

describe("_checkmodule", function()
	it("should not do anything outside of Garry's Mod", function()
		assert.is_false( database._checkmodule('tmysql') );
	end)
	-- This needs heavy mocking to work
	describe("in a faked environment", function()
		pending("should request a module suffixed for the system it's on")
		pending("should request a module prefixed for the state it is in")
		pending("should check if the requested module is available first")
		pending("should require the module if it is available")
	end);
end)

-- "Simple" tests
describe("NewDatabase", function()
	it("should be picky about its arguments", function()
		assert.has.errors(function() database.NewDatabase(); end)
		assert.has.errors(function() database.NewDatabase(false); end)
		function checkErrors(...)
			local tab = {}
			for _, name in pairs{...} do
				tab[name] = ""
			end
			assert.has.errors(function() database.NewDatabase(tab); end)
		end
		checkErrors("Hostname")
		checkErrors("Hostname", "Username")
		checkErrors("Hostname", "Username", "Password")
		checkErrors("Hostname", "Username", "Database")
		assert.has.errors(function() database.NewDatabase({
			Username = "";
			Hostname = "";
			Password = "";
			Database = "";
			Port = "Hi!";
		}) end);
	end)
	it("Should return an objet", function()
		assert.is_table(database.NewDatabase({
			Username = "";
			Hostname = "";
			Password = "";
			Database = "";
		}))
	end);
end)


describe("FindFirstAvailableDBMethod", function()
	-- These test assumes that all the default methods will be
	--  unavailable to start off with. This is a ~farily~ reasonable
	--  assumption, given they're glua specific.
	it("Should return false if nothing is available", function()
		assert.is_false(database.FindFirstAvailableDBMethod());
	end)
	it("Should return SQLite if you ask for it", function()
		assert.is.equal(database.FindFirstAvailableDBMethod(true), 'sqlite');
	end)
	it("Should return the mock db method when available", function()
		database.RegisterDBMethod("Mock", mockDB)
		assert.is.equal(database.FindFirstAvailableDBMethod(), 'mock');
		database.RegisterDBMethod("Mock", invalidDB)
		assert.is_false(database.FindFirstAvailableDBMethod());
	end)
	it("Should check the validity of db methods", function()
		database.RegisterDBMethod("Mock", mockDB)
		spy.on(mockDB, "CanSelect");
		assert.is_true(database.IsValidDBMethod("Mock"))
		assert.is.equal(database.FindFirstAvailableDBMethod(), 'mock');
		assert.spy(mockDB.CanSelect).was.called()
		mockDB.CanSelect:revert()
		database.RegisterDBMethod("Mock", invalidDB)
	end)
end)

describe("GetNewDBMethod", function()
	setup(function()
		database.RegisterDBMethod("Mock", mockDB)
	end)
	teardown(function()
		database.RegisterDBMethod("Mock", invalidDB)
	end)

	it("should be picky about its arguments", function()
		assert.has.errors(function() database.GetNewDBMethod(); end)
	end)
	it("should return false for invalid methods", function()
		assert.is_false(database.GetNewDBMethod("doesn't exist"))
	end)
	it("should return an object for valid methods", function()
		assert.is_table(database.GetNewDBMethod("Mock"))
	end)
	it("should check if the method is valid", function()
		spy.on(database, "IsValidDBMethod")
		database.GetNewDBMethod("Mock");
		assert.spy(database.IsValidDBMethod).was.called()
		database.IsValidDBMethod:revert()
	end)
	it("should return an instance of a valid method", function()
		local method = database.GetNewDBMethod("Mock");
		assert.is_not_false(method);
		assert.is.equal(method.Connect, mockDB.Connect);
	end)
end)

describe("RegisterDBMethod", function()
	teardown(function()
		database.RegisterDBMethod("arg_test", invalidDB)
		database.RegisterDBMethod("overwrite_test", invalidDB)
	end)
	it("should be picky about its arguments", function()
		assert.has.errors(function() database.RegisterDBMethod(); end)
		assert.has.errors(function() database.RegisterDBMethod({}); end)
		assert.has.errors(function() database.RegisterDBMethod(""); end)
		assert.has.errors(function() database.RegisterDBMethod("", {}); end)
		function checkErrors(...)
			local tab = {}
			for _, name in pairs{...} do
				tab[name] =  function() end
			end
			assert.has.errors(function() database.RegisterDBMethod("", tab); end)
		end
		checkErrors("Connect")
		checkErrors("Connect", "Disconnect")
		checkErrors("Connect", "Disconnect", "IsConnected")
		checkErrors("Connect", "Disconnect", "IsConnected", "Escape")
		checkErrors("Connect", "Disconnect", "IsConnected", "Escape", "Query")
		checkErrors("Connect", "Disconnect", "IsConnected", "Escape", "CanSelect")
	end)
	it("should create methods", function()
		assert.has_no.errors(function()
			database.RegisterDBMethod("arg_test", emptyDB);
		end);
		assert.is_true(database.IsValidDBMethod("arg_test"))
		assert.is.equal(database._registeredDatabaseMethods["arg_test"], emptyDB)
	end)
	it("should overwite methods", function()
		database.RegisterDBMethod("overwrite_test", mockDB)
		database.RegisterDBMethod("overwrite_test", emptyDB)
		assert.is_not.equal(database._registeredDatabaseMethods["overwrite_test"], mockDB)
		assert.is.equal(database._registeredDatabaseMethods["overwrite_test"], emptyDB)
	end)
end)

describe("IsValidDBMethod", function()
	setup(function()
		database.RegisterDBMethod("Mock", mockDB)
	end)
	teardown(function()
		database.RegisterDBMethod("Mock", invalidDB)
	end)
	it("should return true for valid methods", function()
		assert.is_true(database.IsValidDBMethod("Mock"));
	end)
	it("should return false for invalid methods", function()
		assert.is_false(database.IsValidDBMethod("doesn't exist"));
	end)
	it("should be case insensitive", function()
		assert.is_true(database.IsValidDBMethod("Mock"))
		assert.is_true(database.IsValidDBMethod("mock"))
		assert.is_true(database.IsValidDBMethod("MOCK"))
		assert.is_true(database.IsValidDBMethod("MoCk"))
	end)
	it("should ask the method", function()
		spy.on(mockDB, "CanSelect");
		assert.is_true(database.IsValidDBMethod("Mock"))
		assert.spy(mockDB.CanSelect).was.called()
		mockDB.CanSelect:revert()
	end)
end)

describe("GetDBMethod", function()
	setup(function()
		database.RegisterDBMethod("Mock", mockDB)
	end)
	teardown(function()
		database.RegisterDBMethod("Mock", invalidDB)
	end)
	it("should be picky about its arguments", function()
		assert.has.errors(function() database.GetNewMethod(); end)
	end)
	it("should return nil for invalid methods", function()
		assert.is_nil(database.GetDBMethod("doesn't exist"))
	end)
	it("should return an object for valid methods", function()
		assert.is_table(database.GetDBMethod("Mock"))
	end)
	it("should return the method that was registered", function()
		assert.is.equal(database.GetDBMethod("Mock"), mockDB);
	end)
end)

-- Somewhat more involved tests
describe("Database", function()
	local db, mockObj, cparams;
	before_each(function()
		mockObj = mock(copy(mockDB));
		database.RegisterDBMethod("Mock", mockObj);
		cparams = {
			Username = "";
			Hostname = "";
			Password = "";
			Database = "";
		};
		db = database.NewDatabase(cparams);
	end)
	after_each(function()
		cparams = nil;
		db = nil;
		mockObj = nil;
		database.RegisterDBMethod("Mock", invalidDB);
	end)
	describe(":Connect", function()
		it("Should default to the only available method", function()
			db:Connect()
			assert.spy(mockObj.CanSelect).was.called();
			assert.spy(mockObj.Connect).was.called(1);
			assert.spy(mockObj.Connect).was.called_with(mockObj, cparams, db);
		end)

		it("Should use the requested method", function()
			-- Teardown
			finally(function()
				database.RegisterDBMethod("Mock 1", invalidDB);
				database.RegisterDBMethod("Mock 2", invalidDB);
				database.RegisterDBMethod("Mock 3", invalidDB);
			end);

			-- Setup
			local mockObj1 = mock(copy(mockDB));
			local mockObj2 = mock(copy(mockDB));
			local mockObj3 = mock(copy(mockDB));
			database.RegisterDBMethod("Mock 1", mockObj1);
			database.RegisterDBMethod("Mock 2", mockObj2);
			database.RegisterDBMethod("Mock 3", mockObj3);

			cparams["DBMethod"] = "Mock 2";
			db = database.NewDatabase(cparams);

			-- Test
			db:Connect()
			assert.spy(mockObj.Connect).was_not.called();
			assert.spy(mockObj1.Connect).was_not.called();
			assert.spy(mockObj3.Connect).was_not.called();
			assert.spy(mockObj2.Connect).was.called(1);
			assert.spy(mockObj2.Connect).was.called_with(mockObj2, cparams, db);
		end)

		it("should error if asked to use an invalid db method", function()
			cparams["DBMethod"] = "doesn't exist";
			db = database.NewDatabase(cparams);
			assert.has.errors(function() db:Connect() end)
		end)

		it("should error if there are no db methods available", function()
			database.RegisterDBMethod("Mock", invalidDB);
			assert.has.errors(function() db:Connect() end);
		end)

		it("Should return itself on successful connect", function()
			local a, b = stub.new(), stub.new();
			db:Connect():Then(thenable(a), thenable(b));
			assert.spy(a).was.called(1);
			assert.spy(a).was.called_with(db);
			assert.spy(b).was_not.called();
		end)
	end)

	describe(":Query", function()
		it("Should throw an error if the database has never connected", function()
			assert.has.error(function() db:Query("foo") end);
			db:Connect();
			assert.has_no.errors(function() db:Query("foo") end);
		end);
		-- TODO: Query Queue!
		it("should throw an error if the database disconnects", function()
			local IsConnected = true
			mockObj.IsConnected = spy.new(function() return IsConnected; end)
			db:Connect();
			assert.has_no.errors(function() db:Query("foo") end);
			IsConnected = false;
			assert.has.errors(function() db:Query("foo") end);
		end)
		it("Should call the underlying method with no changes", function()
			db:Connect();
			local query = "foo";
			db:Query(query);
			assert.spy(mockObj.Escape).was_not.called();
			assert.spy(mockObj.Query).was.called(1)
			assert.spy(mockObj.Query).was.called_with(mockObj, query);
		end)
		it("Should return a promise", function()
			local resp = "It worked!";
			mockObj.Query = spy.new(function()
				return Deferred():Resolve(resp):Promise();
			end)
			local query = "foo";
			db:Connect();
			local a, b = stub.new(), stub.new();
			db:Query(query):Then(thenable(a), thenable(b));
			assert.spy(a).was.called(1);
			assert.spy(a).was.called_with(resp);
			assert.spy(b).was_not.called();
		end)
	end)

	describe(":Escape", function()

		it("causes an error on a non-connected database", function()
			assert.has_errors(function() db:Escape("foobar") end);
		end)
		it("passes arguments verbatum to the db method", function()
			db:Connect();
			local value = "foobar";
			db:Escape(value);
			assert.spy( mockObj.Escape ).was.called(1);
			assert.spy( mockObj.Escape ).was.called_with( mockObj, value );
		end)
		it("returns the db method's responses", function()
			local value, response = "foobar", "barfoo";
			mockObj.Escape = spy.new(function() return response end)
			db:Connect();
			local ret = db:Escape(value);
			assert.is.equal(ret, response);
		end)
	end)

	describe(":Disconnect", function()
		it("does nothing on a non-connected database", function()
			assert.has_no_errors(function() db:Disconnect() end);
			assert.spy(mockObj.Disconnect).was_not.called();
		end)
		it("calls the db method", function()
			db:Connect();
			assert.has_no_errors(function() db:Disconnect() end);
			assert.spy(mockObj.Disconnect).was.called(1);
		end)
	end)

	describe(":PrepareQuery", function()
		it("should error if not given any text", function()
			db:Connect();
			assert.has.errors(function() db:PrepareQuery() end);
		end)
		it("should return a prepared query", function()
			-- TODO: Use the database._PreparedQuery private somehow?
			db:Connect();
			local query = db:PrepareQuery("foo");
			assert.is.table(query);
		end)
	end)
end);

describe("PreparedQuery", function()
	local db, mockObj, cparams, queryFunc;
	before_each(function()
		mockObj = mock(copy(mockDB));
		mockObj.Query = spy.new(function(...)
			local def = Deferred();
			queryFunc(def, ...);
			return def:Promise();
		end);
		queryFunc = function(def)

		end
		database.RegisterDBMethod("Mock", mockObj);
		cparams = {
			Username = "";
			Hostname = "";
			Password = "";
			Database = "";
		};
		db = database.NewDatabase(cparams);
		db:Connect();
	end)
	after_each(function()
		cparams = nil;
		db = nil;
		mockObj = nil;
		database.RegisterDBMethod("Mock", invalidDB);
	end)
	describe(":SetCallbacks", function()
		local done, fail, prog, query;
		before_each(function()
			query = db:PrepareQuery("foobar");
			done, fail, prog = stub(), stub(), stub();
			query:SetCallbacks(done, fail, prog);
		end);
		after_each(function()
			done, fail, prog = nil, nil, nil;
			query = nil;
		end)

		pending("calls the done callback on a successful query");
		pending("calls the fail callback on a successful query");
		pending("calls the prog callback on query progress");
		pending("overwrites previous callbacks")
		pending("doesn't require all three arguments")
		pending("removes unspecified callbacks when overwriting")
	end)
	describe(":SetCallbackArgs", function()
		local done, fail, prog, query;
		local one, two, three = "one", "two", "three";
		before_each(function()
			query = db:PrepareQuery("foobar");
			done, fail, prog = stub(), stub(), stub();
			query:SetCallbacks(done, fail, prog);
			queryFunc = function(def)
				def:Resolve(one);
			end
		end);
		after_each(function()
			done, fail, prog = nil, nil, nil;
			queryFunc = nil;
			query = nil;
		end)

		pending("passes the arguments to all callbacks")
		pending("only passes each set once per run")
		pending("can be reset by passing nothing")
	end)
	describe(":Prepare", function()
		pending("does nothing if the query has no placeholders")
		pending("calls Database:Escape for each arg")
		pending("errors if there are more placeholders than args")
		pending("silently discards extra args")
		pending("sprintfs arguments into the query")
		pending("is only valid for a single run")
	end)
	describe(":Run", function()
		-- TODO: Query Queue!
		pending("throws an error if the database has disconnected");
		pending("executes instantly if the query has no placeholders");
		pending("throws an error if the query has placeholders and hasn't been prepared")
		pending("calls Database:Query")
		pending("returns a promise")
		pending("returns a promise for this run only")
	end)
end);
