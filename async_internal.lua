env = {}

local function tell(fmt, ...)
    print(string.format("* [ASYNC] " .. fmt, ...))
end

tell("loaded")
-- FIXME: all of this is probably wrong since it may not be shared between workers!!!

-- FIXME: Add some sanity check while developing, like reading the version number before writing

-- FIXME this needs to be a weak table!
local mirrors = {

}

function env.create(table_id)
    assert(type(table_id) == "number")
    tell("creating table_%s", table_id)
    mirrors[table_id] = {}
end


function env.update(table_id, key, value)
    tell("updating table_%s[%s] = %s", table_id, key, value)
    mirrors[table_id][key] = value
end


function env.dump_table(table_id)
    for k,v in pairs(mirrors[table_id]) do
        print("|", dump(k), dump(v), dump((getmetatable(v) or {})._type))
    end
end

function sleep(time)
    local end_time = os.clock() + time
    while (os.clock() < end_time) do
    end
end
