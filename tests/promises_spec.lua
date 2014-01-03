require "busted";

local Deferred = require 'promises';

-- for k,v in pairs(Deferred) do print(k,v); end
-- do return end


-- Tests stolen from https:--github.com/domenic/promise-tests
function fulfilled( value )
    local d = Deferred();
    d:Resolve( value );
    return d:Promise();
end
function rejected( reason )
    local d = Deferred();
    d:Reject( reason );
    return d:Promise();
end
function pending()
    local d = Deferred();
    return {
        promise = function() return d:Promise(); end;
        fulfill = function(value) return d:Resolve(value); end;
        reject = function(reason) return d:Reject(reason); end;
    };
end

local other = {}; -- a dummy value we don't want to be strict equal to
local sentinel = {}; -- a sentinel fulfillment value to test for with strict equality
function callbackAggregator(times, ultimateCallback)
    local soFar = 0;
    return function ()
        soFar = soFar + 1;
        if (soFar == times) then
            ultimateCallback();
        end
    end
end

describe("[Promises/A] Basic characteristics of `then`", function ()
    describe("for fulfilled promises", function ()
        it("must return a new promise", function ()
            local promise1 = fulfilled();
            local promise2 = promise1:Then();

            assert.are_not.equal(promise1, promise2);
        end);

        it("calls the fulfillment callback", function ()
            fulfilled(sentinel):Then(function (value)
                assert.are.equal(value, sentinel);
            end);
        end);
    end);

    describe("for rejected promises", function ()
        it("must return a new promise", function ()
            local promise1 = rejected();
            local promise2 = promise1:Then();

            assert.are_not.equal(promise1, promise2);
        end);

        it("calls the rejection callback", function ()
            rejected(sentinel):Then(null, function (reason)
                assert.are.equal(reason, sentinel);
            end);
        end);
    end);

    describe("for pending promises", function ()
        it("must return a new promise", function ()
            local promise1 = pending().promise();
            local promise2 = promise1:Then();

            assert.are_not.equal(promise1, promise2);
        end);
    end);
end);

describe("[Promises/A] State transitions", function ()
    -- NOTE: Promises/A does not specify that attempts to change state twice
    -- should be silently ignored, so we allow implementations to throw
    -- exceptions. See resolution-races.js for more info.
    it("cannot fulfill twice", function ()
        local tuple = pending();
        tuple.promise():Then(function (value)
            assert.are.equal(value, sentinel);
        end);

        tuple.fulfill(sentinel);
        pcall(function()
            tuple.fulfill(other);
        end)
    end);

    it("cannot reject twice", function ()
        local tuple = pending();
        tuple.promise():Then(null, function (reason)
            assert.are.equal(reason, sentinel);
        end);

        tuple.reject(sentinel);
        pcall(function()
            tuple.reject(other);
        end)
    end);

    it("cannot fulfill then reject", function ()
        local tuple = pending();
        tuple.promise():Then(function (value)
            assert.are.equal(value, sentinel);
        end);

        tuple.fulfill(sentinel);
        pcall(function()
            tuple.reject(other);
        end)
    end);

    it("cannot reject then fulfill", function ()
        local tuple = pending();
        tuple.promise():Then(null, function (reason)
            assert.are.equal(reason, sentinel);
        end);

        tuple.reject(sentinel);
        pcall(function()
            tuple.fulfill(other);
        end)
    end);
end);


describe("[Promises/A] Chaining off of a fulfilled promise", function ()
    describe("when the first fulfillment callback returns a new value", function ()
        it("should call the second fulfillment callback with that new value", function (done)
            fulfilled(other):Then(function ()
                return sentinel;
            end):Then(function (value)
                assert.are.equal(value, sentinel);
            end);
        end);
    end);

    describe("when the first fulfillment callback throws an error", function ()
        it("should call the second rejection callback with that error as the reason", function (done)
            fulfilled(other):Then(function ()
                error( sentinel );
            end):Then(null, function (reason)
                assert.are.equal(reason, sentinel);
            end);
        end);
    end);

    describe("with only a rejection callback", function ()
        it("should call the second fulfillment callback with the original value", function (done)
            fulfilled(sentinel):Then(null, function ()
                return other;
            end):Then(function (value)
                assert.are.equal(value, sentinel);
            end);
        end);
    end);
end);

describe("[Promises/A] Chaining off of a rejected promise", function ()
    describe("when the first rejection callback returns a new value", function ()
        it("should call the second fulfillment callback with that new value", function (done)
            rejected(other):Then(null, function ()
                return sentinel;
            end):Then(function (value)
                assert.are.equal(value, sentinel);
            end);
        end);
    end);

    describe("when the first rejection callback throws a new reason", function ()
        it("should call the second rejection callback with that new reason", function (done)
            rejected(other):Then(null, function ()
                error( sentinel );
            end):Then(null, function (reason)
                assert.are.equal(reason, sentinel);
            end);
        end);
    end);

    describe("when there is only a fulfillment callback", function ()
        it("should call the second rejection callback with the original reason", function (done)
            rejected(sentinel):Then(function ()
                return other;
            end):Then(null, function (reason)
                assert.are.equal(reason, sentinel);
            end);
        end);
    end);
end);
