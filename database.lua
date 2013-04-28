--[[
    ~ Universal Database GLua Module ~
    Copyright (c) 2013 Lex Robinson

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
    associated documentation files (the "Software"), to deal in the Software without restriction,
    including without limitation the rights to use, copy, modify, merge, publish, distribute,
    sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or
    substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
    NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
    WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--]]

local _G = _G;
local sqlite = sql;
local mysqloo = mysqloo;
local tmysql = tmysql;

local error, type, unpack, ipairs, system = error, type, unpack, ipairs, system;
local string = string;

module("database");

local queryobj = {};
local dbobj = {};

local function new(tab, ...)
    local ret = setmetatable({}, tab);
    ret:Init(...);
    return ret;
end
local function contextcall(what, context, ...)
    if (context) then
        what(context, ...);
    else
        what(...);
    end
end

--
-- DBOBJ
--

setmetatable(dbobj, { __index = function(self, key)
    -- A bit messy but hey
    if (key == 'Connect') then
        return nil;
    -- Forward all the generic db methods down the line
    elseif (self._db and self._db[key]) then
        if (string.sub(key, 1,1) == '_' or type(self._db) ~= "function") then
            return nil;
        end
        return function(self, ...)
            return self._db[key](self._db, ...);
        end
    end
end});

function dbobj:Init(db, connectionargs)
    self._db = db;
    self._conargs = connectionargs;
    self._context = connectionargs.Context;
    self.OnConnected = connectionargs.OnConnected;
    self.OnConnectionFailed = connectionargs.OnConnectionFailed;
end

function dbobj:Reconnect()
    self._db:Connect(self._conargs, self);
end

function dbobj:_onConnected()
    if (self.OnConnected) then
        contextcall(self.OnConnected, self._context, self);
    end
end
function dbobj:_onConnectionFailed(errmsg)
    if (self.OnConnectionFailed) then
        contextcall(self.OnConnectionFailed, self._context, self, errmsg);
    else
        error("Could not connect to the database: " .. err, 0);
    end
end

--[[
dbobj:PrepareQuery({
    Text = "Query Text";
    SuccessCallback = function(resultset, ...) end;
    FailureCallback = function(err, ...) end;
    PerDataCallback = function(result, ...) end;
});
--]]
function dbobj:PrepareQuery(tab)
    if (not tab.Text) then
        error("No query text specified!", 2);
    elseif (not tab.NumArgs) then
        local args = 0;
        for _ in string.gmatch(tab.Text, '(%%[%%diouXxfFeEgGaAcsb])') do
            args = args + 1;
        end
        self.NumArgs = args;
    end
    tab._dbobj = self;
    return new(queryobj, tab);
end

function dbobj:Query(text, qargs)
    return self._db:Query(text, qargs or {});
end

--
-- QueryOBJ
--

function queryobj:Init(qargs)
    self._datablock = qargs;
    self._qmeta = {__index = qargs};
    self.Text = qargs.Text;
    self.NumArgs = qargs.NumArgs or 0;
end

function queryobj:Prepare(...)
    if (self.NumArgs == 0) then
        return;
    end
    self.Prepared = true;
    local nargs = #{...};
    if (nargs ~= self.NumArgs) then
        error("Argument count missmatch! Expected " .. self.NumArgs .. " received " .. nargs .. "!", 2);
    end
    self.PreparedText = string.format(self.Text, ...);
end

function queryobj:Run(...)
    local text;
    if (self.NumArgs == 0) then
        text = self.Text;
    elseif (not self.Prepared) then
        error("Tried to run an unprepared query!", 2);
    else
        text = self.PreparedText;
    end
    local args = {...};
    if (#args == 0) then
        args = nil;
    end
    self._dbobj:Query(text, setmetatable({
        CallbackArguments = args;
    }, self._qmeta));
end

function queryobj:PrepareAndRun(prepargs, runargs)
    if (self.NumArgs == 0) then
        self:Run(runargs and unpack(runargs));
        return;
    end
    local nargs = #prepargs;
    if (nargs ~= self.NumArgs) then
        error("Argument count missmatch! Expected " .. self.NumArgs .. " received " .. nargs .. "!", 2);
    end
    local text = string.format(Self.Text, unpack(prepargs));
    if (runargs and #runargs == 0) then
        runargs = nil;
    end
    self._dbobj:Query(text, setmetatable({
        CallbackArguments = runargs;
    }, self._qmeta));
end

local registeredQueries = {};
local registeredDatabaseMethods = {};

local db;

local connected = false;

local function req(tab, name)
    if (not tab[name]) then
        error("You're missing '" .. name .. "' from the connection parameters!", 3);
    end
end
local function onConnected(tab)
    connected = true;
    if (tab.ConnectCallback) then
        tab.ConnectCallback();
    end
end
local function onConnectionFailed(tab, err)
    connected = false;
    if (tab.FailureCallback) then
        tab.FailureCallback(err);
    else
        error("Could not connect to the database: " .. err, 0);
    end
end

--[[
database.Connect {
    Hostname = "foo";
    Username = "bar";
    Password = "baz";
    Database = "quux";
    Port = 1337;
    ConnectCallback = function(db) end;
    FailureCallback = function(err) error(err, 0); end;
    DBMethod = "mysqloo";
    EnableSQLite = false;
};
--]]
function Connect(tab)
    if (not type(tab) == "table") then
        error("Invalid connection data passed to database.Connect!", 2);
    end
    req(tab, "Hostname");
    req(tab, "Username");
    req(tab, "Password");
    req(tab, "Database");
    req(tab, "Port"    );
    local db;
    if (tab.DBMethod) then
        local success, errmsg = IsValidDBMethod(tab.DBMethod);
        if (not success) then
            error("Cannot use database method '" .. tab.DBMethod .. "': " .. errmsg, 2);
        end
        db = GetDBMethod(tab.DBMethod);
    else
        for name, method in pairs(registeredDatabaseMethods) do
            if (method.CanSelect() and tab.EnableSQLite or name ~= "sqlite") then
                db = method;
                break;
            end
        end
        if (not db) then
            error("No valid database methods available!", 2);
        end
    end



    return db.Connect(tab, onConnected, onConnectionFailed);
end

local function req(tab, name)
    if (not tab[name]) then
        error("You're missing '" .. name .. "' from the database methods!", 4);
    end
end
local function regdb(tab)
    if (not tab.Name) then
        error("No database method name specified!", 3);
    end
    req(tab, "Connect");
    req(tab, "Disconnect");
    req(tab, "IsConnected");
    req(tab, "Escape");
    req(tab, "Query");
    req(tab, "CanSelect");
    registeredDatabaseMethods[string.lower(tab.Name)] = tab;
    return true;
end

function RegisterDatabaseMethod(name, tab)
    local t = type(name);
    if (t == "table") then
        return regdb(name);
    elseif (t ~= "string") then
        error("Expected a string to database.RegisterDatabaseMethod!", 2);
    end
    tab.Name = name;
    return regdb(tab);
end

function IsValidDBMethod(name)
    local db = registeredDatabases[string.lower(name)];
    if (not db) then
        return false, "Database method '" .. name .. "' does not exist!";
    end
    return db.CanSelect();
end

function GetDBMethod(name)
    return registeredDatabases[string.lower(name)];
end

local function checkmodule(name)
    local prefix = (SERVER) and "gmsv" or "gmcl";
    local suffix;
    if (system.IsWindows()) then
        suffix = "win32";
    elseif (system.IsLinux()) then
        suffix = "linux";
    elseif (system.IsOSX()) then
        suffix = "osx";
    else
        error("The fuck kind of a system are you running me on?!");
    end
    if (file.Exists("lua/bin/" .. prefix .. "_" .. name .. "_" .. suffix .. ".dll", "GAME")) then
        return require(name);
    end
end
local function callback(datachunk, name, arg)
    if (not datachunk[name]) then return; end
    local args = datachunk.CallbackArguments;
    contextcall(datachunk[name], datachunk.Context, arg, args and unpack(args));
end
do -- TMySQL
    local function mcallback(datachunk, results, success, err)
        if (success) then
            if (datachunk.PerDataCallback) then
                for _, result in ipairs(results) do
                    callback(datachunk, "PerDataCallback", result);
                end
            end
            callback(datachunk, "SuccessCallback", results);
        else
            callback(datachunk, "FailureCallback", err);
        end
    end

    local db = {};
    local mdb;

    function db.Connect(tab, onConnected, onConnectionFailed)
        if (mdb) then
            db.Disconnect();
        end
        local err;
        mdb, err = tmysql.initialize(tab.Hostname, tab.Username, tab.Password, tab.Database, tab.Port);
        if (mdb) then
            onConnected(tab);
        else
            onConnectionFailed(tab, string.gsub(err, "^Error connecting to DB: ", ""));
        end
    end

    function db.Disconnect()
        if (mdb) then
            mdb:Disconnect();
        end
    end

    function db.Query(text, datachunk)
        if (mdb) then
            mdb:Query(text, mcallback, 1, datachunk);
        end
    end

    function db.Escape(text)
        return tmysql.escape(text);
    end

    function db.IsConnected()
        -- Probably true
        return true;
    end

    function db.CanSelect()
        tmysql = tmysql or checkmodule('tmysql4');
        if (not tmysql) then
            return false, "TMySQL4 is not available!";
        end
        return true;
    end

    RegisterDatabaseMethod("TMySQL", db);
end
do -- MySQLOO
    local mysqlooyes, mysqloono, mysqloodata;
    function mysqlooyes(query)
        callback(query.datachunk, "SuccessCallback", query:GetData());
    end

    function mysqloono(query, err)
        callback(query.datachunk, "FailureCallback", err);
    end

    function mysqloodata(query, result)
        callback(query.datachunk, "PerDataCallback", result);
    end

    local mdb;
    local db = {};

    function db.Connect(tab, onConnected, onConnectionFailed)
        if (mdb) then
            db.Disconnect();
        end
        mdb = mysqloo.connect(tab.Hostname, tab.Username, tab.Password, tab.Database, tab.Port);
        mdb.SuccessCallback = tab.SuccessCallback;
        mdb.FailureCallback = tab.FailureCallback;
        mdb.onConnected        = onConnected;
        mdb.onConnectionFailed = onConnectionFailed;
        mdb:Connect();
    end

    function db.Disconnect()
        if (mdb) then
            mdb:AbortAllQueries();
            mdb = nil;
        end
    end

    function db.Query(text, datachunk)
        local q = mdb:query(text);
        q.onFailure = mysqloono;
        q.onSuccess = mysqlooyes;
        q.onData    = mysqloodata;
        q.datachunk = datachunk;
        q:start();
        -- I can't remember if queries are light userdata or not.
        table.insert(activeQueries, q);
    end

    function db.Escape(text)
        if (not mdb) then
            error("There is no database open to perform this act!", 2);
        end
        return mdb:escape(text);
    end

    function db.IsConnected()
        if (not mdb) then
            return false;
        end
        local status = mdb:status();
        if (status == mysqloo.DATABASE_CONNECTED) then
            return true;
        end
        connected = false;
        if (status == mysqloo.DATABASE_INTERNAL_ERROR) then
            ErrorNoHalt("The MySQLOO database has encountered an internal error!\n");
        end
        return false;
    end

    function db.CanSelect()
        mysqloo = mysqloo or checkmodule('mysqloo');
        if (not mysqloo) then
            return false, "MySQLOO is not available!";
        end
        return true;
    end

    RegisterDatabaseMethod "MySQLOO" (db);
end
do -- SQLite
    local db = {};

    function db.Connect(tab, onConnected, onConnectionFailed)
        onConnected();
    end

    function db.Disconnect()
    end

    function db.Query(text, datachunk)
        local results = sqlite.Query(text);
        if (results) then
            if (datachunk.PerDataCallback) then
                for _, result in ipairs(results) do
                    callback(datachunk, "PerDataCallback", result);
                end
            end
            callback(datachunk, "SuccessCallback", results);
        else
            callback(datachunk, "FailureCallback", sqlite.LastError());
        end
    end

    function db.Escape(text)
        return sqlite.SQLStr(text);
    end

    function db.IsConnected()
        return true;
    end

    function db.CanSelect()
        return true;
    end

    RegisterDatabaseMethod "SQLite" (db);
end

-- Autoselect
if (mysqloo) then
    SelectDatabaseMethod "MySQLOO";
elseif (tmysql) then
    SelectDatabaseMethod "TMySQL";
end
