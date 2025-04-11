local fmt = string.format

local async = {} -- the module table

local UNIQUE_TABLE = {"json_table"} -- used to identify our tables as a special type

local function tell(fmt, ...)
    print(string.format("* [ASYNC_INTERFACE] " .. fmt, ...))
end

local function async_done_callback(label)
    local f = function(args)
        tell("%s DONE: %s", label, args)
    end
    return f
end


local function log(...)
    local msg = fmt(...)
    core.chat_send_all(msg)
    print(msg)
end


local id_counter = 1
local function new_id()
    local id = id_counter
    id_counter = id_counter + 1
    return id
end


local function _create(table_id)
    env.create(table_id)
end


local function create(table_id)
    core.handle_async(_create, async_done_callback("create"), table_id)
end


local function _update(table_id, path, value)
    -- value here is already serialized and deserialized
    env.update(table_id, path, value)
end


local function update(table_id, path, value)
    if type(value) == "table" then
        --print("***", dump(value))
        local mt = getmetatable(value) or {}
        --print("***", dump(mt))
        assert(mt._type == UNIQUE_TABLE)
        value = {
            id = mt._id,
            is_root = mt._is_root, -- this is pointless
        }
    end
    core.handle_async(_update, async_done_callback("update"), table_id, path, value)
end


local function _delete(table_id)
    env._delete(table_id)
end


local function delete(table_id)
    core.handle_async(_delete, async_done_callback("delete"), table_id)
end


function async.get_table_id(t)
    local mt = getmetatable(t)
    assert(mt._type == UNIQUE_TABLE)
    return mt._id
end


local function _mk_table(data, is_root)
    local id = new_id()
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
    end
    local actual

    mt._type = UNIQUE_TABLE
    mt._id = id
    mt._is_root = is_root -- this is pointless

    mt.__index = function(t, key)
        log("* json_table_%s[%s]", id, key)
        return actual[key]
    end

    mt.__newindex = function(t, key, value)
        local typ = type(value)
        if typ == "table" then
            if (getmetatable(value) or {})._type == UNIQUE_TABLE then
                actual[key] = value
            else
                local wrapped_table = _mk_table(value)
                actual[key] = wrapped_table
            end
        elseif typ == "string" or typ == "number" or typ == "boolean" or typ == "nil" then
            --async.update(id, key, value)
            actual[key] = value
        else
            error(string.format("JSON can't store values of type %s", typ))
        end
        log("* json_table_%s[%s] = %s", id, key, actual[key])
        update(id, key, actual[key]) -- FIXME this is wrong??
    end

    mt.__pairs = function(t)
        local k,v
        print("* __pairs called")
        return function()
            k, v = next(actual, k)
            return k, v
        end
    end
    
    mt.__call = function(t)
        local k,v
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
            for k,v in pairs(data) do
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


function async.dump(table_id)
    local function _dump(id)
        env.dump_table(id)
    end
    core.handle_async(_dump, async_done_callback("dump"), table_id)
end


function async.get_json(callback, json_table)
    local table_id = async.get_table_id(json_table)
    local function _get_json(id)
        local json = env.get_json(id)
        return json
    end
    core.handle_async(_get_json, callback, table_id)
end


function async.save_json(callback, json_table, filepath, styled)
    local table_id = async.get_table_id(json_table)
    local function _save_json(id, filepath, styled)
        env.save_json(id, filepath, styled)
    end
    core.handle_async(_save_json, callback, table_id, filepath, styled)
end


function async.load_json(filepath)
    -- not actually async!
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