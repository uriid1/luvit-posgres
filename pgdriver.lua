--[[
####--------------------------------####
#--# Author:   by uriid1            #--#
#--# License:  GNU GPL              #--#
#--# Telegram: @main_moderator      #--#
#--# Mail:     appdurov@gmail.com   #--#
####--------------------------------####
--]]

local net = require('net')
local md5 = require('./md5').sumhexa
local encode = require('./postgres-codec').encode
local decode = require('./postgres-codec').decode

-- Debug
local p = require('pretty-print').prettyPrint
local debug_mode = false

--
local function formatError(msg)
  return string.format(
    "%s: %s %s:%s (%s) - %s",
    msg.S or "?",
    msg.F or "?",
    msg.L or "?",
    msg.C or "?",
    msg.R or "?",
    msg.M or "?")
end

-- Returns the first element of the table
-- then deletes it by making an offset
local function shift(tbl)
    local tmp = {}
    table.insert(tmp, tbl[1])
    table.remove(tbl, 1)
    return tmp[1] or {}
end

--
local function pairs_parse_data(data, next_index)
    local index = next_index or 1
    return function()
        local item, next_index = decode(data, index)
        index = next_index
        return item
    end
end

-- 
local function get_authentication(data, socket, options)
    local item, next_index = decode(data, 1)

    if item[1] == 'AuthenticationOk' then
        return next_index, true

    elseif item[1] == 'AuthenticationMD5Password' then
        assert(options.password, "[error] Password is needed!")

        local salt = item[2]
        local inner = md5(options.password .. options.username)

        socket:write(encode({'PasswordMessage',
            'md5'.. md5(inner .. salt)
        }))

        return next_index, false

    elseif item[1] == 'AuthenticationCleartextPassword' then
        socket:write(encode({ 'PasswordMessage', options.password }))

    elseif item[1] == 'AuthenticationKerberosV5' then
        options.callback("TODO: Implement AuthenticationKerberosV5 authentication")

    elseif item[1] == 'AuthenticationSCMCredential' then
        -- only possible for local unix domain connections
        options.callback("TODO: Implement AuthenticationSCMCredential authentication")

    elseif item[1] == 'AuthenticationGSS' then
        -- frontend initiates GSSAPI negotiation
        options.callback("TODO: Implement AuthenticationGSS authentication")

    elseif item[1] == 'AuthenticationSSPI' then
        -- frontend has to initiate a SSPI negotiation
        options.callback("TODO: Implement AuthenticationSSPI authentication")

    elseif item[1] == 'AuthenticationGSSContinue' then
        -- continuation of SSPI and GSS or a previous GSSContinue...
        options.callback("TODO: Implement AuthenticationGSSContinue authentication")

    elseif item[1] == 'ErrorResponse' then
        options.callback(formatError(item[2]))

    else
        options.callback("Unexpected response type: " .. item[1])
    end

    return 1, false
end

-- Parse params
local function get_params(data, next_index, callback)
    local params = {}

    for item in pairs_parse_data(data, next_index) do
        if item[1] == 'ReadyForQuery' then
            return params

        elseif item[1] == 'ParameterStatus' then
            params[item[2][1]] = item[2][2]

        elseif item[1] == 'BackendKeyData' then
            params.backend_key_data = {
                pid    = item[2];
                secret = item[3];
            }

        else
            callback(('[%s] %s'):format(item[1], item[2].M))
            return nil
        end
    end
end

-- Parse responses
local function parse(data, socket, callback)
    local description
    local rows
    local summary
    local err

    for item in pairs_parse_data(data) do

        if item[1] == 'ErrorResponse' then
            description = item[2].M
            err = ('[%s] %s'):format(item[1], item[2].M)
            rows = {}

        elseif item[1] == 'RowDescription' then
            description = item[2]
            rows = {}

        elseif item[1] == 'DataRow' then
            local row = {}
            rows[#rows + 1] = row

            for i = 1, #description do
                local column = description[i]
                local field = column.field
                local value = item[2][i]
                local typeId = column.typeId

                if typeId == 16 then -- boolean
                    value = value == "t"
                elseif typeId == 20   -- bigint
                    or typeId == 21   -- smallint
                    or typeId == 23   -- int
                    or typeId == 700  -- real
                    or typeId == 701  -- double
                    or typeId == 1700 -- numeric and decimal
                then
                    value = tonumber(value)
                end

                row[field] = value
            end

        elseif item[1] == 'CommandComplete' then
            summary = item[2]

        elseif item[1] == 'ReadyForQuery' then
            if not debug_mode then
                callback(err, {
                    rows = rows;
                })
            else
                callback(err, {
                    rows = rows;
                    description = description;
                    summary = summary;
                })
            end
            
            --
            socket:emit('readyForQuery')

        else
            description = "Unexpected message from server: " .. item[1]
            err = item[1]
            rows = {}
        end
    end
end

--
local prototype = {}
prototype.__index = prototype

function prototype:new(options)
    assert(type(options) == "table")

    -- init
    local obj = setmetatable({}, self)

    local isAuth = false
    local port = options.port or 5432
    local host = options.host or '0.0.0.0'

    obj.parameters = nil
    obj.callback = nil
    obj.queryQueue = {}
    obj.isReadyForQuery = false

    local startup = encode({'StartupMessage', {
        user     = options.username;
        database = options.database;
    }})

    --
    if options.debug then
        debug_mode = options.debug or false
    end

    --
    obj.socket = net.Socket:new()

    --
    obj.socket:on('connect', function(err)
        if err then
            options.callback(err, "[error] Error in connect")
            return
        end

        -- Debug
        obj.callback = function() end
        options.callback(nil, ("[true] Opened connection %s:%s"):format(host, port))

        --
        obj.socket:write(startup)
    end)

    -- the custom event listener starts when the server is ready
    -- process the following request
    obj.socket:on('readyForQuery', function() 
        if (#obj.queryQueue > 0) then
            -- set the flag to false so that another request does not
            -- interrupt this request
            obj.isReadyForQuery = false

            local next = shift(obj.queryQueue)
            obj.socket:write(next.buffer)
            obj.callback = next.callback
        else
           obj.isReadyForQuery = true
        end
    end)

    --
    local function on_connect()

        obj.socket:on('error', function(err)
            options.callback(err, "[false] Error in connect")
        end)

        obj.socket:on('data', function(data)
            if not isAuth then
                local next_index
                next_index, isAuth = get_authentication(data, obj.socket, options)
                    
                if isAuth then
                    options.callback(nil, "[true] Authenticated")
                end

                if not obj.parameters and debug_mode then
                    obj.parameters = get_params(data, next_index, options.callback)

                    if obj.parameters then
                        options.callback(nil, "[true] Getting server parameters")
                    end
                end
            end

            parse(data, obj.socket, obj.callback)
            
        end)
    end

    obj.socket:connect(port, host, on_connect)
    obj.socket:nodelay(true)

    return obj
end

--
function prototype:query(text, user_cb)
    local buffer = encode({'Query', text})

    -- if the database server is ready for query and the queue is
    -- empty, send the query directly. Otherwise, add the stack and
    -- callback to the queryQueue
    if (self.isReadyForQuery and #self.queryQueue == 0) then
        -- set the 'isReadyForQuery' flag to false so that another 
        -- query won't interrupt this one

        self.isReadyForQuery = false
        self.callback = user_cb
        self.socket:write(buffer)
    else
        -- Add to stack
        table.insert(self.queryQueue, {
            buffer = buffer;
            callback = user_cb;
        })
    end
end

--
function prototype:close()
    self.socket:write(encode {'Terminate'} )
end

return prototype