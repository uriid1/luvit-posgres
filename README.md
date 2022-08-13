# Info
<b>Current support for postgres 12. With MD5 authentication<br>
Postgres 14 requires SCRAM-SHA-256 authentication, which is not supported in this library.</b>
<br>
This driver is based on the codec from https://github.com/creationix/lua-postgres

# Example
```lua
local p = require("pretty-print").prettyPrint
local posgres = require("./pgdriver")

local function onPsqlResponse(err, res)
    if err then
        p(err)
        return
    end

    p(res)
end

local psql = posgres:new {
    username = "your-username";
    database = "your-database";
    callback = onPsqlResponse;
    -- password = without?
    -- host = default;
    -- port = default;
    -- debug = true;
}

psql:query("SELECT 'Hello' AS greeting", function(err, result)
    if err then
        print('[error]', err)
        return
    end

    p(result)
    -- p(result.rows[1])
    -- p(result.rows[1].greeting)

    -- Close connection
    psql:close()
end)
```