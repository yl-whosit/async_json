local fmt = string.format

local NAMESPACE = "json_storage:"
local KEY_JOB_COUNTER = NAMESPACE .. "job_counter"

env = {}

-- local job_id
-- do
-- --    while true do
--         local job_count = core.ipc_get(KEY_JOB_COUNTER) or 0
--         job_id = job_count + 1
--         print("* trying to get job_id", job_id)
--         if core.ipc_cas(KEY_JOB_COUNTER, job_count, job_id) then
--             --break
--         end
-- --    end
-- end

-- this is just a stupid value to try to differentiate worker threads, since I can't use IPC during dofile()?
local env_seed = math.floor(os.clock())*100 + math.random(1,99)
local function tell(fmt, ...)
    print(string.format("* [ASYNC %s]" .. fmt, env_seed, ...))
end

tell("loaded")


function sleep(time)
    local end_time = os.clock() + time
    while (os.clock() < end_time) do
    end
end

-- FIXME: all of this is probably wrong since it may not be shared between workers!!!

-- FIXME: Add some sanity check while developing, like reading the version number before writing

-- FIXME this needs to be a "weak" table?
-- We need to somehow mirror GC
--local mirrors = {}




--local values_cache = {}

local counter = 0
function env.create(table_id)
    assert(type(table_id) == "number")
    local table_name = fmt("table_%d", table_id)
    tell("creating table_%s", table_id)
    local new_table = {
        version = 0,
        data = {},
    }
    --mirrors[table_id] = new_table
    counter = counter + 1
    assert(core.ipc_cas(NAMESPACE .. table_name, nil, new_table))
    --sleep(10)
    return fmt("number of tables created: %s", counter)
end


function env.update(table_id, version, key, value)
    tell("updating table_%s[%s] = %s (v%s)", table_id, key, value, version)
    while true do
        local table_name = NAMESPACE .. fmt("table_%d", table_id)
        local cur_table = core.ipc_get(table_name)
        if cur_table.version >= version then
            tell("OUTDATED table_%s[%s] = %s was (v%s) now (v%s)", table_id, key, value, version, cur_table.version)
            break
        end
        local new_table = table.copy(cur_table)
        new_table.data[key] = value
        if core.ipc_cas(table_name, cur_table, new_table) then
            tell("UPDATE SUCCESS %s", table_name)
            break
        end
    end
end


function env.delete(table_id)
    tell("removing table_%s", table_id)
    mirrors[table_id] = nil
end


function env.dump_table(table_id)
    for k,v in pairs(mirrors[table_id].data) do
        print("|", dump(k), dump(v), dump((getmetatable(v) or {})._type))
    end
end


local function reconstruct(table_id, reconstructed)
    local out = {}
    if not reconstructed then
        reconstructed = {}
    end
    local existing = reconstructed[table_id]
    if existing then
        return existing
    end
    for k,v in pairs(mirrors[table_id].data) do
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


