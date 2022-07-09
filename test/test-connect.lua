local p = require("pretty-print").prettyPrint
local posgres = require("../pgdriver")

local function onPsqlResponse(err, res)
    if err then
        print(err)
        return
    end

    p(res)
end

local psql = posgres:new({
    username = "your-username";
    database = "your-database";
    -- host = default;
    -- port = default;
    -- password = without?
}, onPsqlResponse)

psql:query("SELECT 'Hello' AS greeting", function(err, result)
    if err then
        print(err)
        return
    end

    p(result)
    -- p(result.rows[1])
    -- p(result.rows[1].greeting)

    -- Close connection
    psql:close()
end)