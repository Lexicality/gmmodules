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
local Deferred = require "promises"

local busted = require("busted")

-- Tests stolen from https:--github.com/domenic/promise-tests
local function _fulfilled(value)
	local d = Deferred()
	d:Resolve(value)
	return d:Promise()
end
local function _rejected(reason)
	local d = Deferred()
	d:Reject(reason)
	return d:Promise()
end
local function _pending()
	local d = Deferred()
	return {
		promise = function() return d:Promise(); end,
		fulfill = function(value) return d:Resolve(value); end,
		reject = function(reason) return d:Reject(reason); end,
		notify = function(value) return d:Notify(value); end,
	}
end

local other = { a = 1 }    -- a dummy value we don't want to be strict equal to
local sentinel = { b = 2 } -- a sentinel fulfillment value to test for with strict equality

-- Stubs are tables and tables can't go into then
local function thenable(a)
	return function(...) return a(...) end
end

local function fail(message) error(message, 0) end

describe("[Promises/A] Basic characteristics of `then`", function()
	describe("for fulfilled promises", function()
		it("must return a new promise", function()
			local promise1 = _fulfilled()
			local promise2 = promise1:Then()

			assert.are_not.equal(promise1, promise2)
		end)

		it("calls the fulfillment callback", function()
			_fulfilled(sentinel):Then(function(value)
				assert.are.equal(value, sentinel)
			end):Error(fail, true)
		end)
	end)

	describe("for rejected promises", function()
		it("must return a new promise", function()
			local promise1 = _rejected()
			local promise2 = promise1:Then()

			assert.are_not.equal(promise1, promise2)
		end)

		it("calls the rejection callback", function()
			_rejected(sentinel):Then(nil, function(reason)
				assert.are.equal(reason, sentinel)
			end):Error(fail, true)
		end)
	end)

	describe("for pending promises", function()
		it("must return a new promise", function()
			local promise1 = _pending().promise()
			local promise2 = promise1:Then()

			assert.are_not.equal(promise1, promise2)
		end)
	end)
end)

describe("[Promises/A] State transitions", function()
	-- NOTE: Promises/A does not specify that attempts to change state twice
	-- should be silently ignored, so we allow implementations to throw
	-- exceptions. See resolution-races.js for more info.
	it("cannot fulfill twice", function()
		local tuple = _pending()
		tuple.promise():Then(function(value)
			assert.are.equal(value, sentinel)
		end):Error(fail, true)

		tuple.fulfill(sentinel)
		pcall(function()
			tuple.fulfill(other)
		end)
	end)

	it("cannot reject twice", function()
		local tuple = _pending()
		tuple.promise():Then(nil, function(reason)
			assert.are.equal(reason, sentinel)
		end):Error(fail, true)

		tuple.reject(sentinel)
		pcall(function()
			tuple.reject(other)
		end)
	end)

	it("cannot fulfill then reject", function()
		local tuple = _pending()
		tuple.promise():Then(function(value)
			assert.are.equal(value, sentinel)
		end):Error(fail, true)

		tuple.fulfill(sentinel)
		pcall(function()
			tuple.reject(other)
		end)
	end)

	it("cannot reject then fulfill", function()
		local tuple = _pending()
		tuple.promise():Then(nil, function(reason)
			assert.are.equal(reason, sentinel)
		end):Error(fail, true)

		tuple.reject(sentinel)
		pcall(function()
			tuple.fulfill(other)
		end)
	end)
end)


describe("[Promises/A] Chaining off of a fulfilled promise", function()
	describe("when the first fulfillment callback returns a new value", function()
		it("should call the second fulfillment callback with that new value", function()
			_fulfilled(other):Then(function()
				return sentinel
			end):Then(function(value)
				assert.are.equal(value, sentinel)
			end):Error(fail, true)
		end)
	end)

	describe("when the first fulfillment callback throws an error", function()
		it("should call the second rejection callback with that error as the reason", function()
			_fulfilled(other):Then(function()
				error(sentinel)
			end):Then(nil, function(reason)
				assert.are.equal(reason, sentinel)
			end):Error(fail, true)
		end)
	end)

	describe("with only a rejection callback", function()
		it("should call the second fulfillment callback with the original value", function()
			_fulfilled(sentinel):Then(nil, function()
				return other
			end):Then(function(value)
				assert.are.equal(value, sentinel)
			end):Error(fail, true)
		end)
	end)
end)

describe("[Promises/A] Chaining off of a rejected promise", function()
	describe("when the first rejection callback returns a new value", function()
		it("should call the second fulfillment callback with that new value", function()
			_rejected(other):Then(nil, function()
				return sentinel
			end):Then(function(value)
				assert.are.equal(value, sentinel)
			end):Error(fail, true)
		end)
	end)

	describe("when the first rejection callback throws a new reason", function()
		it("should call the second rejection callback with that new reason", function()
			_rejected(other):Then(nil, function()
				error(sentinel)
			end):Then(nil, function(reason)
				assert.are.equal(reason, sentinel)
			end):Error(fail, true)
		end)
	end)

	describe("when there is only a fulfillment callback", function()
		it("should call the second rejection callback with the original reason", function()
			_rejected(sentinel):Then(function()
				return other
			end):Then(nil, function(reason)
				assert.are.equal(reason, sentinel)
			end):Error(fail, true)
		end)
	end)
end)

describe("[Promises/A] Multiple handlers", function()
	describe("when there are multiple fulfillment handlers for a fulfilled promise", function()
		it("should call them all, in order, with the same fulfillment value", function()
			local promise = _fulfilled(sentinel)

			-- Don't let their return value *or* thrown exceptions impact each other.
			local handler1 = spy.new(function() return other; end)
			local handler2 = spy.new(function() error("Whoops"); end)
			local handler3 = spy.new(function() return other; end)

			local rejection = spy.new(function() end)
			promise:Then(thenable(handler1), thenable(rejection))
			promise:Then(thenable(handler2), thenable(rejection))
			promise:Then(thenable(handler3), thenable(rejection))

			promise:Then(function(value)
				assert.are.equal(value, sentinel)

				assert.spy(rejection).was_not.called()
				assert.spy(handler1).was.called_with(sentinel)
				assert.spy(handler2).was.called_with(sentinel)
				assert.spy(handler3).was.called_with(sentinel)
			end):Error(fail, true)
		end)

		it("should generate multiple branching chains with their own fulfillment values", function()
			local promise = _fulfilled(other)

			local sentinel2 = {}

			promise:Then(function()
				return sentinel
			end):Then(function(value)
				assert.are.equal(value, sentinel)
			end):Error(fail, true)

			promise:Then(function()
				return sentinel2
			end):Then(function(value)
				assert.are.equal(value, sentinel2)
			end):Error(fail, true)
		end)
	end)

	describe("when there are multiple rejection handlers for a rejected promise", function()
		it("should call them all, in order, with the same rejection reason", function()
			local promise = _rejected(sentinel)

			-- Don't let their return value *or* thrown exceptions impact each other.
			local fulfillment = spy.new(function() end)
			local handler1 = spy.new(function() return other; end)
			local handler2 = spy.new(function() error("Whoops"); end)
			local handler3 = spy.new(function() return other; end)

			promise:Then(thenable(fulfillment), thenable(handler1))
			promise:Then(thenable(fulfillment), thenable(handler2))
			promise:Then(thenable(fulfillment), thenable(handler3))

			promise:Then(nil, function(value)
				assert.are.equal(value, sentinel)

				assert.spy(handler1).was.called_with(sentinel)
				assert.spy(handler2).was.called_with(sentinel)
				assert.spy(handler3).was.called_with(sentinel)
				assert.spy(fulfillment).was_not.called()
			end):Error(fail, true)
		end)
	end)
end)

describe("[Extension] Returning a promise from a fulfilled promise's fulfillment callback", function()
	describe("when the returned promise is fulfilled", function()
		it("should call the second fulfillment callback with the value", function()
			_fulfilled(other):Then(function()
				return _fulfilled(sentinel)
			end):Then(function(value)
				assert.are.equal(value, sentinel)
			end):Error(fail, true)
		end)
	end)

	describe("when the returned promise is rejected", function()
		it("should call the second rejection callback with the reason", function()
			_fulfilled(other):Then(function()
				return _rejected(sentinel)
			end):Then(nil, function(reason)
				assert.are.equal(reason, sentinel)
			end):Error(fail, true)
		end)
	end)
end)

describe("[Extension] Returning a promise from a rejected promise's rejection callback", function()
	describe("when the returned promise is fulfilled", function()
		it("should call the second fulfillment callback with the value", function()
			_rejected(other):Then(nil, function()
				return _fulfilled(sentinel)
			end):Then(function(value)
				assert.are.equal(value, sentinel)
			end):Error(fail, true)
		end)
	end)

	describe("when the returned promise is rejected", function()
		it("should call the second rejection callback with the reason", function()
			_rejected(other):Then(nil, function()
				return _rejected(sentinel)
			end):Then(nil, function(reason)
				assert.are.equal(reason, sentinel)
			end):Error(fail, true)
		end)
	end)
end)

describe("Promise:Done", function()
	it("does not return a new promise", function()
		local p = _pending().promise()
		assert.are.equal(p, p:Done(function() end))
	end)
	it("is called as if it was added with :Then", function()
		local pending = _pending()
		local promise = pending.promise()
		local one = spy.new(function() end)
		local two = spy.new(function() end)
		promise:Done(thenable(one))
		assert.spy(one).was_not.called()
		pending.fulfill(sentinel)
		assert.spy(one).was.called(1)
		assert.spy(one).was.called_with(sentinel)
		promise:Done(thenable(two))
		assert.spy(two).was.called(1)
		assert.spy(two).was.called_with(sentinel)
	end)
	it("cannot mutate the promise return", function()
		local one = spy.new(function() return other; end)
		local two = spy.new(function() end)
		_fulfilled(sentinel):Done(thenable(one)):Done(thenable(two))
		assert.spy(one).was.called(1)
		assert.spy(one).was.called_with(sentinel)
		assert.spy(two).was.called(1)
		assert.spy(two).was.called_with(sentinel)
	end)
	it("silently absorbs errors", function()
		_fulfilled(sentinel):Done(function() error("Whoops!") end)
	end)
end)

describe("Promise:Fail", function()
	it("does not return a new promise", function()
		local p = _pending().promise()
		assert.are.equal(p, p:Fail(function() end))
	end)
	it("is called as if it was added with :Then", function()
		local pending = _pending()
		local promise = pending.promise()
		local one = spy.new(function() end)
		local two = spy.new(function() end)
		promise:Fail(thenable(one))
		assert.spy(one).was_not.called()
		pending.reject(sentinel)
		assert.spy(one).was.called(1)
		assert.spy(one).was.called_with(sentinel)
		promise:Fail(thenable(two))
		assert.spy(two).was.called(1)
		assert.spy(two).was.called_with(sentinel)
	end)
	it("cannot mutate the promise return", function()
		local one = spy.new(function() return other; end)
		local two = spy.new(function() end)
		_rejected(sentinel):Fail(thenable(one)):Fail(thenable(two))
		assert.spy(one).was.called(1)
		assert.spy(one).was.called_with(sentinel)
		assert.spy(two).was.called(1)
		assert.spy(two).was.called_with(sentinel)
	end)
	it("silently absorbs errors", function()
		_rejected(sentinel):Fail(function() error("Whoops!") end)
	end)
end)


describe("Promise:Always", function()
	it("does not return a new promise", function()
		local p = _pending().promise()
		assert.are.equal(p, p:Always(function() end))
	end)
	it("is called as if it was added with :Then (fulfill)", function()
		local pending = _pending()
		local promise = pending.promise()
		local one = spy.new(function() end)
		local two = spy.new(function() end)
		promise:Always(thenable(one))
		assert.spy(one).was_not.called()
		pending.fulfill(sentinel)
		assert.spy(one).was.called(1)
		assert.spy(one).was.called_with(sentinel)
		promise:Always(thenable(two))
		assert.spy(two).was.called(1)
		assert.spy(two).was.called_with(sentinel)
	end)
	it("is called as if it was added with :Then (reject)", function()
		local pending = _pending()
		local promise = pending.promise()
		local one = spy.new(function() end)
		local two = spy.new(function() end)
		promise:Always(thenable(one))
		assert.spy(one).was_not.called()
		pending.reject(sentinel)
		assert.spy(one).was.called(1)
		assert.spy(one).was.called_with(sentinel)
		promise:Always(thenable(two))
		assert.spy(two).was.called(1)
		assert.spy(two).was.called_with(sentinel)
	end)
	it("cannot mutate the promise return", function()
		local one = spy.new(function() return other; end)
		local two = spy.new(function() end)
		_fulfilled(sentinel):Always(thenable(one)):Always(thenable(two))
		assert.spy(one).was.called(1)
		assert.spy(one).was.called_with(sentinel)
		assert.spy(two).was.called(1)
		assert.spy(two).was.called_with(sentinel)
	end)
	it("is called for both resolved and rejected promises", function()
		local one = spy.new(function() end)
		local two = spy.new(function() end)
		_fulfilled(sentinel):Always(thenable(one))
		assert.spy(one).was.called(1)
		assert.spy(one).was.called_with(sentinel)
		_rejected(sentinel):Always(thenable(two))
		assert.spy(two).was.called(1)
		assert.spy(two).was.called_with(sentinel)
	end)
	it("silently absorbs errors", function()
		_fulfilled(sentinel):Always(function() error("Whoops!") end)
		_rejected(sentinel):Always(function() error("Whoops!") end)
	end)
end)

describe("Promise:Notify", function()
	it("is acts like a resolve/reject", function()
		local pending = _pending()
		local promise = pending.promise()
		local one = spy.new(function() return other end)
		local two = spy.new(function() end)
		promise:Then(nil, nil, thenable(one)):Progress(thenable(two))
		assert.spy(one).was_not.called()
		assert.spy(two).was_not.called()

		pending.notify(sentinel)

		assert.spy(one).was.called(1)
		assert.spy(one).was.called_with(sentinel)
		assert.spy(two).was.called(1)
		assert.spy(two).was.called_with(other)
	end)
	it("has no effect on the actual promise", function()
		local pending = _pending()
		local promise = pending.promise()

		local one = spy.new(function() end)
		local two = spy.new(function() end)
		local three = spy.new(function() return other end)

		promise:Then(thenable(one), thenable(two), thenable(three))

		pending.notify(other)
		assert.spy(one).was_not.called()
		assert.spy(two).was_not.called()
		assert.spy(three).was.called(1)
		assert.spy(three).was.called_with(other)

		pending.fulfill(sentinel)
		assert.spy(one).was.called(1)
		assert.spy(one).was.called_with(sentinel)
		assert.spy(two).was_not.called()
		assert.spy(three).was.called(1)
		assert.spy(three).was_not.called_with(sentinel)
	end)
	it("ignores errors", function()
		local pending = _pending()
		local promise = pending.promise()
		local one = spy.new(function() error("oh dear"); end)
		local two = spy.new(function() error("oh dear"); end)
		local three = spy.new(function() error("oh dear") end)

		promise:Then(nil, nil, thenable(one)):Then(nil, nil, thenable(two)):Progress(thenable(three))

		pending.notify(sentinel)

		assert.spy(one).was.called(1)
		assert.spy(one).was.called_with(sentinel)
		assert.spy(two).was.called(1)
		assert.spy(two).was.called_with(sentinel)
		assert.spy(three).was.called(1)
		assert.spy(three).was.called_with(sentinel)
	end)
	it("calls notify handlers for all notifications", function()
		local pending = _pending()
		local promise = pending.promise()
		local one = spy.new(function(...) return ...; end)
		local two = spy.new(function(...) return ...; end)
		local three = spy.new(function(...) return ...; end)
		local four = spy.new(function(...) return ...; end)

		promise:Then(nil, nil, thenable(one)):Progress(thenable(two))

		pending.notify(sentinel)

		assert.spy(one).was.called(1)
		assert.spy(two).was.called(1)
		assert.spy(one).was.called_with(sentinel)
		assert.spy(two).was.called_with(sentinel)

		promise:Then(nil, nil, thenable(three)):Progress(thenable(four))

		assert.spy(three).was.called(1)
		assert.spy(four).was.called(1)
		assert.spy(three).was.called_with(sentinel)
		assert.spy(four).was.called_with(sentinel)

		pending.notify(other)


		assert.spy(one).was.called(2)
		assert.spy(two).was.called(2)
		assert.spy(three).was.called(2)
		assert.spy(four).was.called(2)
		assert.spy(one).was.called_with(other)
		assert.spy(two).was.called_with(other)
		assert.spy(three).was.called_with(other)
		assert.spy(four).was.called_with(other)
	end)
	it("throws an error if a fulfilled promise is notified", function()
		local pending = _pending()
		pending.fulfill(sentinel)
		assert.has.error(function() pending.notify(other) end)
	end)
	it("throws an error if a rejected promise is notified", function()
		local pending = _pending()
		pending.reject(sentinel)
		assert.has.error(function() pending.notify(other) end)
	end)
end)

describe("Promise:Error", function()
	local _pending = _pending
	local pending, promise, cback, cback_spy
	local err, other = "Whoops!", "not my fault"
	local throw_error = function() error(err) end
	local cback_func = function(msg)
		local res = string.find(msg, err, 1, true)
		assert(res, "Expected the error message!")
	end
	before_each(function()
		pending = _pending()
		promise = pending.promise()
		cback = spy.new(cback_func)
	end)
	after_each(function()
		pending = nil
		promise = nil
	end)
	it("catches error() calls", function()
		promise
			:Then(throw_error)
			:Error(cback, true)
		pending.fulfill(other)
		assert.spy(cback).was.called(1)
	end)
	it("catches runtime errors", function()
		local cback = spy.new(function(msg)
			-- vaguely accurate error message pattern
			local res = string.find(msg, ".lua:%d+.*nil value")
			assert(res, "Expected the error message!")
		end)
		promise
			:Then(function() return nil + 1 end)
			:Error(cback, true)
		pending.fulfill(other)
		assert.spy(cback).was.called(1)
	end)
	it("does not catch rejections", function()
		promise:Error(cback, true)
		pending.reject(other)
		assert.spy(cback).was_not.called()
	end)
	it("does not catch resolves", function()
		promise:Error(cback, true)
		pending.fulfill(other)
		assert.spy(cback).was_not.called()
	end)
	it("returns the promise it was called on", function()
		local prom2 = promise:Error(spy.new(fail), true)
		assert.is.equal(promise, prom2)
	end)
	it("does not affect return values", function()
		local cback1 = spy.new(function(...)
			cback_func(...)
			return other
		end)
		local cback2 = spy.new(cback_func)
		local cback3 = spy.new(cback_func)
		promise
			:Then(throw_error)
			:Error(cback1, true)
			:Fail(cback2)
			:Then(nil, thenable(cback3))
		pending.fulfill("foobar")
		assert.spy(cback1).was.called(1)
		assert.spy(cback2).was.called(1)
		assert.spy(cback3).was.called(1)
	end)
	it("is called as if it was added with :Then (reject)", function()
		promise = promise:Then(throw_error)
		local cback1 = spy.new(cback_func)
		local cback2 = spy.new(cback_func)
		promise:Error(cback1, true)
		assert.spy(cback1).was_not.called()
		pending.fulfill(sentinel)
		assert.spy(cback1).was.called(1)
		promise:Error(cback2, true)
		assert.spy(cback2).was.called(1)
	end)
	it("silently absorbs errors", function()
		_fulfilled(other):Error(throw_error)
	end)
end)
