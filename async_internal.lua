local fmt = string.format


local key = dofile(core.get_modpath(core.get_current_modname())  .. DIR_DELIM .. "ipc_keys.lua")


env = {}

assert(core.ipc_get(key.THE_WORKER) == nil, "there could be only one worker!")

local mirror = {}

local job_id
do
   while true do
        local job_count = core.ipc_get(key.JOB_COUNTER)
        job_id = (job_count or 0) + 1
        print("* trying to get job_id", job_id)
        if core.ipc_cas(key.JOB_COUNTER, job_count, job_id) then
            break
        end
   end
end



local function tell(fmt, ...)
    print(string.format("* [ASYNC %s] " .. fmt, job_id, ...))
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
        local addr_cur = core.ipc_get(key.ADDRESS_COUNTER)
        addr_new = (addr_cur or 0) + 1
        tell("trying to get new address", addr_new)
        if core.ipc_cas(key.ADDRESS_COUNTER, addr_cur, addr_new) then
            break
        end
   end
   return fmt(NAMESPACE .. "addr%X", addr_new)
end


local counter = 0
function env.create(table_id)
    assert(type(table_id) == "number")
    tell("creating table_%s", table_id)
    local new_table = {
        version = 0,
        data = {},
    }
    counter = counter + 1
    mirror[table_id] = new_table
    return fmt("number of tables created: %s", counter)
end


function env.update(table_id, version, key, value)
    tell("updating table_%s[%s] = %s (v%s)", table_id, key, value, version)
    mirror[table_id].data[key] = value
    mirror[table_id].version = version -- FIXME not needed
end


function env.delete(table_id)
    tell("removing table_%s", table_id)
    -- local table_name = table_name_from_id(table_id)
    -- local cur_table_addr = core.ipc_get(table_name)
    -- core.ipc_set(cur_table_addr, nil)
    -- core.ipc_set(table_name, nil)
end

local function get_table_data(table_id)
    -- local table_name = table_name_from_id(table_id)
    -- local cur_table_addr = core.ipc_get(table_name)
    -- local table_entry = core.ipc_get(cur_table_addr)
    -- return table_entry.data, table_entry.version
    local t = mirror[table_id]
    tell("get_data %s %s", table_id, t)
    return t and t.data or "ERROR!!!"
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

local function pop_task()
    local async_fifo_front = core.ipc_get(key.FIFO_FRONT)
    local async_fifo_back = core.ipc_get(key.FIFO_BACK)
    if async_fifo_back == async_fifo_front then
        return
    end
    local task = core.ipc_get(key.FIFO_PREFIX .. tostring(async_fifo_front))
    local new_idx = async_fifo_front + 1
    tell("POP FRONT: %s -> %s", async_fifo_front, new_idx)
    assert(core.ipc_cas(key.FIFO_FRONT, async_fifo_front, new_idx)) -- this is just for my sanity
    return task
end

local function process_fifo()
    local task = pop_task()
    if not task then
        return
    end
    local message = task.message
    if message == "create" then
        tell("GOT_TASK * %s %s", task.message, task.table_id)
        env.create(task.table_id)
    elseif message == "update" then
        tell("GOT_TASK * %s %s[%s] = %s", task.message, task.table_id, task.key, task.value)
        env.update(task.table_id, task.version, task.key, task.value)
    elseif message == "delete" then
        tell("GOT_TASK * %s %s", task.message, task.table_id)
        error("not implemented")
    elseif message == "dump" then
        for k,v in pairs(mirror) do
            tell("DUMP %s %s", dump(k), dump(v))
        end
    elseif message == "save" then
        env.save_json(task.table_id, task.filepath, task.styled)
    else
        tell("GOT_TASK * %s????", task.message)
        error(fmt("unknown message %s", message))
    end
end


local running = true
function env.main_loop(key_running)
    assert(core.ipc_cas(key_running, nil, "whatever"))
    while running do
        if core.ipc_poll(key.MORE_TASKS, 1000) then -- FIXME!!!!!!!!
            -- local front = core.ipc_get(key.FIFO_FRONT)
            -- local back = core.ipc_get(key.FIFO_BACK)
            if true or back > front then
                process_fifo()
            else
                core.ipc_cas(key.MORE_TASKS, true, nil)  -- FIXME this is blegh
            end
        else
            tell("POLL timed out...")
        end


        running = core.ipc_get(key_running)
    end
end