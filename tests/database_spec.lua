require "busted";
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

database.RegisterDBMethod("Mock", mockDB)

describe("RegisterDBMethod", function()
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
			database.RegisterDBMethod("arg_test", {
				["Connect"] = function() end;
				["Disconnect"] = function() end;
				["IsConnected"] = function() end;
				["Escape"] = function() end;
				["Query"] = function() end;
				["CanSelect"] = function() return true; end;
			});
		end);
		assert.is_true(database.IsValidDBMethod("arg_test"))
	end)
end)

describe("IsValidDBMethod", function()
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
end)
