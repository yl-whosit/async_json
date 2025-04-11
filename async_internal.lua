local fmt = string.format

local NAMESPACE = "json_storage:"
local KEY_JOB_COUNTER = NAMESPACE .. "job_counter"
local KEY_ADDRESS_COUNTER = NAMESPACE .. "addr_counter"

env = {}

local job_id
do
   while true do
        local job_count = core.ipc_get(KEY_JOB_COUNTER)
        job_id = (job_count or 0) + 1
        print("* trying to get job_id", job_id)
        if core.ipc_cas(KEY_JOB_COUNTER, job_count, job_id) then
            break
        end
   end
end


local function tell(fmt, ...)
    print(string.format("* [ASYNC %s]" .. fmt, job_id, ...))
end

tell("loaded")


function sleep(time)
    local end_time = os.clock() + time
    while (os.clock() < end_time) do
    end
end

-- FIXME: all of this is probably wrong since it may not be shared between workers!!!

-- FIXME: Add some sanity check while developing, like reading the version number before writing

-- FIXME The mirrored tables needs to somehow be a "weak" table. We basically must mirror main thread GC.

--local values_cache = {}

local function table_name_from_id(table_id)
    return NAMESPACE .. fmt("table_%d", table_id)
end

local function get_new_address()
    local addr_new
    while true do
        local addr_cur = core.ipc_get(KEY_ADDRESS_COUNTER)
        addr_new = (addr_cur or 0) + 1
        tell("trying to get new address", addr_new)
        if core.ipc_cas(KEY_ADDRESS_COUNTER, addr_cur, addr_new) then
            break
        end
   end
   return fmt(NAMESPACE .. "addr%X", addr_new)
end


local counter = 0
function env.create(table_id)
    assert(type(table_id) == "number")
    local addr = get_new_address()
    local table_name = table_name_from_id(table_id)
    tell("creating table_%s", table_id)
    local new_table = {
        version = 0,
        data = {},
    }
    counter = counter + 1
    core.ipc_set(addr, new_table) -- actual data
    assert(core.ipc_cas(table_name, nil, addr)) -- this is just a pointer to data
    --sleep(math.random())
    return fmt("number of tables created: %s", counter)
end


function env.update(table_id, version, key, value)
    tell("updating table_%s[%s] = %s (v%s)", table_id, key, value, version)
    local new_table_addr = get_new_address()
    while true do
        local table_name = table_name_from_id(table_id)
        local cur_table_addr = core.ipc_get(table_name)
        if cur_table_addr then
            -- FIXME what if it's deleted? what if it's not created yet? How do we know?!?
            local cur_table = core.ipc_get(cur_table_addr)
            -- FIXME what if it's deleted at this point?
            if cur_table.version >= version then
                tell("OUTDATED table_%s[%s] = %s was (v%s) now (v%s)", table_id, key, value, version, cur_table_addr.version)
                break
            end
            local new_table = {
                 version = version,
                 data = table.copy(cur_table.data),
            }
            new_table.data[key] = value
            core.ipc_set(new_table_addr, new_table)
            if core.ipc_cas(table_name, cur_table_addr, new_table_addr) then
                tell("UPDATE SUCCESS %s", table_name)
                core.ipc_set(cur_table_addr, nil) -- remove old data
                break
            end
        end
        sleep(1)
    end
end


function env.delete(table_id)
    tell("removing table_%s", table_id)
    local table_name = table_name_from_id(table_id)
    local cur_table_addr = core.ipc_get(table_name)
    core.ipc_set(cur_table_addr, nil)
    core.ipc_set(table_name, nil)
end

local function get_table_data(table_id)
    local table_name = table_name_from_id(table_id)
    local cur_table_addr = core.ipc_get(table_name)
    local table_entry = core.ipc_get(cur_table_addr)
    return table_entry.data, table_entry.version
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
    for k,v in pairs(get_table_data(table_id)) do
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


