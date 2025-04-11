local MODNAME = core.get_current_modname()
local MODPATH = core.get_modpath(MODNAME)

-- /eval t = js.create_table(); t.x = 1; t.blah = {'a','b','c',{"inside"},'d'}; t.blah_copy = t.blah; t.blah[2] = "B"
-- /eval js.save_json(function() print('saved') end, t, core.get_worldpath() .. "\\cool_table.json", true)

local mod = {}
js = mod -- FIXME: just for testing


_G[MODNAME] = mod

core.register_async_dofile(MODPATH .. DIR_DELIM .. "async_internal.lua")

local async = dofile(MODPATH .. DIR_DELIM .. "async_export.lua")

mod.create_table = async.create_table
mod.save_json = async.save_json
mod.load_json = async.load_json


-- function mod.do_stuff(id)
--     print("* handle_async() about to be called", env)
--     --async.dump(id)
--     async.get_json(id, function(data) print(dump(data)) end)
--     print("* handle_async() returned")
--     return "ok"
-- end

-- core.register_chatcommand(
--     "json_dump",
--     {
--         func = function(name, param)
--             return true, mod.do_stuff(tonumber(param))
--         end
--     }
-- )

-- core.register_chatcommand(
--     "json_save",
--     {
--         func = function(name, param)
--             local idx = param:find(' ', 1, true)
--             if not idx then
--                 return false, "/json_save <table_id> <filename>"
--             end
--             -- local table_id = param:sub(1,idx-1)
--             -- local filename = param:sub(idx+1)
--             -- local res = async.save_json()
--             return true, dump(res)
--         end
--     }
-- )