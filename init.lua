local MODNAME = core.get_current_modname()
local MODPATH = core.get_modpath(MODNAME)

local mod = {}
js = mod -- FIXME: just for testing



_G[MODNAME] = mod

core.register_async_dofile(MODPATH .. DIR_DELIM .. "async_internal.lua")

local async = dofile(MODPATH .. DIR_DELIM .. "async_export.lua")

mod.create_table = async.create_table


function mod.do_stuff(id)
    print("* handle_async() about to be called", env)
    async.dump(id)
    print("* handle_async() returned")
    return "ok"
end

core.register_chatcommand(
    "json_dump",
    {
        func = function(name, param)
            return true, mod.do_stuff(tonumber(param))
        end
    }
)