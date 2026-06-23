if not GROK_ROOT or GROK_ROOT == "" then
    local env = os.getenv("GROK_PUBLIC_FOLDER") or ""
    if env ~= "" then
        dofile(env .. "/resolve/lua/grok_paths.lua")
    else
        local src = debug.getinfo(1, "S").source:gsub("^@", "")
        dofile((src:match("(.*/)") or "") .. "grok_paths.lua")
    end
end
dofile(GROK_ROOT .. "/resolve/lua/grok_resolve.lua")
grok_import_active()