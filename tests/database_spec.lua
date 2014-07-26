require "database";

local Deferred = require 'promises';

local mockDB = {};

function mockDB:Connect(tab)
	return Deferred():Resolve(self):Promise();
end

function mockDB:Disconnect()
end

function mockDB:Query(text)
	return Deferred():Reject("This method should be overriden!"):Promise();
end

function mockDB:Escape(text)
	return text;
end

function mockDB:IsConnected()
	return true;
end

function mockDB.CanSelect()
	return true;
end


describe("GetNewDBMethod", function()
	setup(function()
		database.RegisterDBMethod("Mock", mockDB)
	end)

	it("should be picky about its arguments", function()
		assert.has.errors(function() database.GetNewDBMethod(); end)
	end)
	it("should return false for invalid methods", function()
		assert.is_false(database.GetNewDBMethod("doesn't exist"))
	end)
	it("should return an object for valid methods", function()
		assert.is_truthy(database.GetNewDBMethod("Mock"))
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
	local emptyDB = {
		["Connect"] = function() end;
		["Disconnect"] = function() end;
		["IsConnected"] = function() end;
		["Escape"] = function() end;
		["Query"] = function() end;
		["CanSelect"] = function() return true; end;
	}
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
		assert.is_equal(database.GetDBMethod("arg_test"), emptyDB)
	end)
	it("should overwite methods", function()
		database.RegisterDBMethod("overwrite_test", mockDB)
		database.RegisterDBMethod("overwrite_test", emptyDB)
		assert.is_equal(database.GetDBMethod("overwrite_test"), emptyDB)
	end)
end)

describe("IsValidDBMethod", function()
	setup(function()
		database.RegisterDBMethod("Mock", mockDB)
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
	it("should be picky about its arguments", function()
		assert.has.errors(function() database.GetNewMethod(); end)
	end)
	it("should return nil for invalid methods", function()
		assert.is_nil(database.GetDBMethod("doesn't exist"))
	end)
	it("should return an object for valid methods", function()
		assert.is_truthy(database.GetDBMethod("Mock"))
	end)
	it("should return the method that was registered", function()
		assert.is.equal(database.GetDBMethod("Mock"), mockDB);
	end)
end)
