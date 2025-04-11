local MODNAME = core.get_current_modname()
local MODPATH = core.get_modpath(MODNAME)

-- /eval t = js.create_table(); t.x = 1; t.blah = {'a','b','c',{"inside"},'d'}; t.blah_copy = t.blah; t.blah[2] = "B"
-- /eval js.save_json(function() print('saved') end, t, core.get_worldpath() .. "\\cool_table3.json", true)

local mod = {}
js = mod -- FIXME: just for testing


_G[MODNAME] = mod

core.register_async_dofile(MODPATH .. DIR_DELIM .. "async_internal.lua")

local async = dofile(MODPATH .. DIR_DELIM .. "async_export.lua")

mod.create_table = async.create_table
mod.save_json = async.save_json
mod.load_json = async.load_json
