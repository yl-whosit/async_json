local fmt = string.format

local key = dofile(core.get_modpath(core.get_current_modname()) .. DIR_DELIM .. "ipc_keys.lua")

-- local ASYNC_FIFO_SIZE = 1024 -- TODO fix the size and wrap around indices?


local async = {} -- the module table



local UNIQUE_TABLE = { "json_table" } -- used to identify our tables as a special type

local function tell(fmt, ...)
    --print(string.format("* [ASYNC_INTERFACE] " .. fmt, ...))
end

-- TODO make everything local

local function log(...)
    local msg = fmt(...)
    core.chat_send_all(msg)
    print(msg)
end

function async.start_worker()
    local async_start_worker = function(key, running_key)
        -- because this function actually exists in async env, we mush shadow the `key` var
        core.ipc_set(key.FIFO_BACK, 0)
        core.ipc_set(key.FIFO_FRONT, 0)
        env.main_loop(running_key)
    end
    local async_finished = function()
        tell("FINISHED")
    end
    core.handle_async(async_start_worker, async_finished, key, key.THE_WORKER)
end

function async.stop_worker()
    core.ipc_set(key.THE_WORKER, nil) -- set the flag to stop the worker
    while true do
        -- wait for the worker to process all messages
        -- and send one last "job" to wake it up from the ipc_poll()
        if core.ipc_cas(key.MORE_TASKS, nil, true) then
            break
        end
    end
end

local id_counter = 1
local function new_table_id()
    local id = id_counter
    id_counter = id_counter + 1
    return id
end

local function increment_task_count()
    while true do
        local task_count = core.ipc_get(key.MORE_TASKS)
        local new_count = (task_count or 0) + 1
        if core.ipc_cas(key.MORE_TASKS, task_count, new_count) then
            break
        end
    end
end

function async.push_task(task)
    local async_fifo_back = core.ipc_get(key.FIFO_BACK)
    core.ipc_set(key.FIFO_PREFIX .. tostring(async_fifo_back), task)
    local new_idx = async_fifo_back + 1
    tell("PUSH BACK: %s -> %s", async_fifo_back, new_idx)
    assert(core.ipc_cas(key.FIFO_BACK, async_fifo_back, new_idx)) -- this is just for my sanity
    increment_task_count()
end

local function create(table_id)
    async.push_task(
        {
            message = "create",
            table_id = table_id,
        }
    )
end


local function update(table_id, table_version, key, value)
    if type(value) == "table" then
        local mt = getmetatable(value) or {}
        assert(mt._type == UNIQUE_TABLE)
        value = {
            id = mt._id,
            version = mt._version,
        }
    end
    -- TODO instead of actually pushing new message here, just collect them,
    -- then send a "batch" update message at the end of the server step.

    async.push_task(
        {
            message = "update",
            table_id = table_id,
            version = table_version,
            key = key,
            value = value,
        }
    )
end


local function delete(table_id)
    async.push_task(
        {
            message = "delete",
            table_id = table_id,
        }
    )
end


function async.get_table_id(t)
    local mt = getmetatable(t)
    assert(mt._type == UNIQUE_TABLE)
    return mt._id
end

local function _mk_table(data, is_root)
    -- TODO try changing this to store data in just a plain lua table,
    -- but creating and returning proxies on demand?
    -- It can be more complicated, but can save some loading time or something?
    -- maybe?

    -- I guess what create tabke can also do, I just use a different process for
    -- table creation: instead of inserting values recursively and sending each
    -- update to async, we could have `create` message take pre-populated table too.

    local id = new_table_id()
    create(id)
    local dummy
    local mt
    if newproxy then
        -- this should work in 5.1, but luanti does not whitelist newproxy() function!
        dummy = newproxy(true)
        mt = getmetatable(dummy)
    else
        -- This requires 5.2 or luajit with 5.2 compat to actually call __gc!
        dummy = {} -- this must be empty to redirect all access to metamethods!
        mt = {}
        setmetatable(dummy, mt)
        -- If you're running lua that does not call __gc metamethod, your async
        -- will just slowly eat your memory.
    end
    local actual

    mt._type = UNIQUE_TABLE
    mt._id = id
    mt._is_root = is_root -- this is pointless
    mt._version = 0

    mt.__index = function(t, key)
        log("* json_table_%s[%s]", id, key)
        return actual[key]
    end

    mt.__newindex = function(t, key, value)
        local typ = type(value)
        if typ == "table" then
            if (getmetatable(value) or {})._type == UNIQUE_TABLE then
                -- previously existing one, this is just a new reference
                actual[key] = value
            else
                -- new plain table, wrap it
                local wrapped_table = _mk_table(value)
                actual[key] = wrapped_table
            end
        elseif typ == "string" or typ == "number" or typ == "boolean" or typ == "nil" then
            -- simple value
            actual[key] = value
        else
            error(string.format("JSON can't store values of type %s", typ))
        end
        log("* json_table_%s[%s] = %s", id, key, actual[key])
        local ver = mt._version + 1
        mt._version = ver
        -- send update to async
        update(id, ver, key, actual[key])
    end

    mt.__pairs = function(t)
        -- this required luajit 5.2 compat!!!
        local k, v
        print("* __pairs called")
        return function()
            k, v = next(actual, k)
            return k, v
        end
    end

    mt.__call = function(t)
        -- use this for iteration instead, if you don't have pairs() support!
        local k, v
        print("* __call called")
        return function()
            k, v = next(actual, k)
            return k, v
        end
    end

    mt.__tostring = function()
        return fmt("<json_table_%s>", id)
    end

    --__metatable = UNIQUE_TABLE,
    mt.__gc = function()
        log("* deteling json_table_%s[%s]", id)
        delete(id)
    end

    local t = dummy -- ugh, it's already has metatable assigned.
    if data then
        if type(data) ~= "table" then
            error("Internal table must be a table")
        end
        if (getmetatable(data) or {})._type == UNIQUE_TABLE then
            actual = data
        else
            actual = {}
            for k, v in pairs(data) do
                -- use normal insertion metamethods that will do everything for us
                t[k] = v
            end
        end
    else
        actual = {}
    end

    return t
end


function async.create_table(data)
    -- this is not really async, since table is usable as soon as this returns
    local is_root = true
    return _mk_table(data, is_root)
end


-- function async.get_json(callback, json_table)
--     local table_id = async.get_table_id(json_table)
--     local function _get_json(id)
--         local json = env.get_json(id)
--         return json
--     end
--     core.handle_async(_get_json, callback, table_id)
-- end


function async.save_json(json_table, filepath, styled)
    local table_id = async.get_table_id(json_table)
    async.push_task(
        {
            message = "save",
            table_id = table_id,
            filepath = filepath,
            styled = styled,
        }
    )
end

function async.load_json(filepath)
    -- not actually async!

    -- this may be the slowest part of this storage system.
    -- see comments in _mk_table() for potential fixes.

    local file, file_err = io.open(filepath, 'r')
    if not file then
        error(file_err)
    end
    local filedata = file:read("*all")
    file:close()
    local data, parse_err = core.parse_json(filedata, nil, true)
    if not data then
        error(parse_err)
    end
    return async.create_table(data)
end

return async
