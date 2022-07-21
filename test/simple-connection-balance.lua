local p = require("pretty-print").prettyPrint
local timer = require('timer')
local posgres = require("../pgdriver")

local psql = {}
local options = {}

function onPsqlResponse(err, res)
    if err then
        print(err)
        return
    end

    p(res)
end

function onCloseConnection(index, info)
    psql[index] = posgres:new(options)
    psql[index].index = index
end

options = {
    username = "your-username";
    database = "your-database";
    callback = onPsqlResponse;
    callbackClose = onCloseConnection;
}

for i = 1, 10 do
    psql[i] = posgres:new(options)
    psql[i].index = i
end

local n_psql = #psql
local i_prev = 0
local function balancer()
    i_prev = i_prev + 1
    if (i_prev > n_psql) then
        i_prev = 1
    end

    return psql[i_prev]
end

local test = function()

    local iter = 100
    local start = os.clock()
    
    p('run test')

    for i = 1, iter do
        balancer():query("select 'Hello, World' as greeting;", function(err, result)
            if err then
                p(err)
                return
            end

            if i == iter then
                p(i, os.clock() - start)
            end
        end)
    end

end

timer.setInterval(1000, test)