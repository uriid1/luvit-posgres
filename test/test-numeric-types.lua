local p = require("pretty-print").prettyPrint
local posgres = require("../pgdriver")

local function onPsqlResponse(err, res)
    if err then
        print(err)
        return
    end

    p(res)
end

local psql = posgres:new {
    username = "your-username";
    database = "your-database";
    callback = onPsqlResponse;
    -- username = "your-username";
    -- database = "your-database";
    -- password = without?
    -- host = default;
    -- port = default;
    -- debug = true;
}

--
psql:query([[
    create table test_numeric_types(
        smallint smallint,
        integer integer,
        bigint bigint,
        decimal decimal,
        numeric numeric,
        real real,
        double double precision,
        smallserial smallserial,
        serial serial,
        bigserial bigserial
    );
]], function(err, result)
        if err then
            print('[error]', err)
            return
        end

        p(result)
end)

--
psql:query([[
    insert into test_numeric_types(smallint, integer, bigint, decimal, numeric, real, double) values(10, 11, 12, 13, 14, 15, 16.50505);
]], function(err, result)
        if err then
            print('[error]', err)
            return
        end

        p(result)
end)

--
psql:query("select * from test_numeric_types;", function(err, result)
    if err then
        print('[error]', err)
        return
    end

    for k, v in pairs(result.rows[1]) do
        p(k, v)
    end

    -- Close connection
    psql:close()
end)