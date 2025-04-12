## untested, unfinished, do not use.


# Provides a table structure that gets mirrored in an async environmet

This should speed up process of saving of large structures into JSON
(or lua), since actual serialization/write is done in a separate thread.

## Usage:

`t = create_table()` - returns new empty table.

Can be used like a normal table, except in lua 5.1 and luajit without
5.2 compat enabled, you *must* call the table itself to get the
iterator, normal `pairs(t)` *will not work*:

```lua
for k,v in t() do
  ...
end
```

`#t` is also won't work. It's just limitations of lua 5.1. Use luajit
with 5.2 compat enabled.

To write the table to json, use: `save_json(t, file_path, human_readable)`.
This call will just send a message to the async, so it won't
block/wait for the write to finish.

## TODO / Known issues:

`__gc` does not work for normal objects in lua 5.1 and luajit. 5.1 has
undocumented `newproxy()` function, which can be used to work around
that, but it's not exposed by MT API. Luajit has `ffi` but it's also
not available without insecure env, ugh.

Without `__gc` metamethod, we can't really know if user is holding
references to any of the tables or parts of them - so if you create
and throw away tables, memory usage will just keep growing.

Explicit `delete(t)` could help, but you'd still need to be careful if
you keep any references to subtables of the deleted table, ugh.

### Workarounds:
Instead of returning individual json tables for sub-tables, return a
proxy object that will remember it's parent and path relative to the
root. Provide explicit delete() and invalidate all child objects? The
proxy/children can keep only weak references to main structure, so
deleting the root should sooner or later invalidate all child
references - at least if user is not careful, it would likely crash,
instead of staying in some invalid state. This will allow us to
properly mirror the structure in the async too, and just rely on lua's
GC to collect the garbage on the async side.
