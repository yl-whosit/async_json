env = {}

local function tell(fmt, ...)
    print(string.format("* [ASYNC] " .. fmt, ...))
end

tell("loaded")
-- FIXME: all of this is probably wrong since it may not be shared between workers!!!

-- FIXME: Add some sanity check while developing, like reading the version number before writing

-- FIXME this needs to be a weak table?
local mirrors = {}

--local values_cache = {}

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


function reconstruct(table_id, reconstructed)
    local out = {}
    if not reconstructed then
        reconstructed = {}
    end
    local existing = reconstructed[table_id]
    if existing then
        return existing
    end
    for k,v in pairs(mirrors[table_id]) do
        if type(v) == "table" then
            out[k] = reconstruct(v.id, reconstructed)
        else
            out[k] = v
        end
    end
    reconstructed[table_id] = out
    return out
end


function env.get_json(table_id, styled)
    local json = core.write_json(reconstruct(table_id), styled)
    return json
end


function env.save_json(table_id, filepath, styled)
    local json = env.get_json(table_id, styled)
    core.safe_file_write(filepath, json)
end


function sleep(time)
    local end_time = os.clock() + time
    while (os.clock() < end_time) do
    end
end
