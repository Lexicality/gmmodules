require( "tmysql4" )

--[[
	tmysql.initialize( HOSTNAME, USERNAME, PASSWORD, DATABASE, PORT, OPTIONAL_UNIX_SOCKET_PATH ) - Returns Database object, error string
	tmysql.Connect - alias of tmysql.initialize
	tmysql.escape( str ) - Escape a possible unsafe string that can be used to query
	tmysql.GetTable() - Returns a table of all current database connections
	tmysql.PollAll() - Polls all active queries on all connections and calls their callbacks on completion
	
	-- There's really no need for these, but was from the original tmysql
	QUERY_SUCCESS = true
	QUERY_FAIL = false
	
	QUERY_FLAG_ASSOC = 1 -- Makes the result table use the colum names instead of numerical indices
	QUERY_FLAG_LASTID = 2 -- ?? Honestly don't know
	
	MYSQL_VERSION = current version of the mysql lib
	MYSQL_INFO = random mysql version info
]]

--[[
	Database:Query( String, function onComplete, return flags, random object to be used in callback )
	function onComplete( [Object random object from query thing], Table result, Bool status, String error )	
	Database:Disconnect() - Close the current database connection and finish any pending queries
	Database:SetCharset( String character set )
	Database:Poll() - Polls all active queries and calls their callbacks on completion
--]]
	
	local function onPlayerCompleted( ply, results, status, error )
		-- if status == true, the error will be the mysql_last_id if doing an insert into an AUTO INCREMENT'd table
		print( "Query for player completed", ply )
		if status == QUERY_SUCCESS then
			PrintTable( results )
		else
			ErrorNoHalt( error )
		end
	end
	
	Database:Query( "select * from some_table", onPlayerCompleted, QUERY_FLAG_ASSOC, Player(1) )
	
	local function onCompleted( results, status, error )
		-- if status == true, the error will be the mysql_last_id if doing an insert into an AUTO INCREMENT'd table
		print( "Query for completed" )
		if status == QUERY_SUCCESS then
			PrintTable( results )
		else
			ErrorNoHalt( error )
		end
	end
	
	Database:Query( "select * from some_table", onCompleted, QUERY_FLAG_ASSOC )
	
	function GM:OurMySQLCallback( results, status, error )
		print( result, status, error )
	end
	
	Database:Query( "select * from some_table", GAMEMODE.OurMySQLCallback, QUERY_FLAG_ASSOC, GAMEMODE ) -- Call the gamemode function

DB_DM, err = tmysql.initialize( HOSTNAME, USERNAME, PASSWORD, DATABASE, PORT, OPTIONAL_UNIX_SOCKET_PATH )

-- hook.Remove( "Tick", "TMysqlPoll" ) -- This hook is added when the module is started, it calles tmysql.PollAll() as shown below

--[[
-- THIS IS BASICALLY WHAT THE CPP MODULE IS DOING

function tmysql.PollAll()
	for k,db in pairs( tmysql.GetTable() ) do
		db:Poll()
	end
end

hook.Add( "Tick", "TMysqlPoll", function()
	tmysql.PollAll()
end )
]]

if DB_DM then
	ServerLog( "[MySQL] Connected to GMOD database!" )
	DB_DM:Query( string.format( "SELECT 1+2, %s", tmysql.escape( [[this is some "random' ass : string filled with !shit+135-32'"]] ) ), function( result, status, err )
		if status then
			PrintTable( result )
		else
			ServerLog( "[MySQL] GMOD Error: " .. err .. "\n" )
		end
	end, 1 )
	DB_DM:Poll() -- Runs any queries that were created and calls all the callback functions, normally done automatically by the Tick hook
elseif err then
	ServerLog( "[MySQL] Error connecting to GMOD database!\n" )
	ServerLog( "[MySQL] Error: " .. err .. "\n" )
end

DB_DM:Disconnect() -- Destroy/Disconnect the connection to the database, will also finish any pending queries that havn't been completed