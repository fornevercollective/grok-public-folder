dofile("/Users/tref/film/grok-public-folder/resolve/lua/grok_startup.lua")

local GROK_ROOT = "/Users/tref/film/grok-public-folder"
local PYTHON = "/usr/bin/env python3"

local MENU_ITEMS = {
    "Bootstrap",
    "Scan Downloads",
    "Import",
    "Scan + Import",
    "Open Folder",
    "Start Bridge",
    "Generate (terminal)",
}

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function choose_action()
    local parts = {}
    for _, item in ipairs(MENU_ITEMS) do
        table.insert(parts, '"' .. item:gsub('"', '\\"') .. '"')
    end
    local list = table.concat(parts, ", ")
    local cmd = 'osascript -e ' .. shell_quote(
        'choose from list {' .. list .. '} with title "Grok" default items {"Bootstrap"}'
    )
    local handle = io.popen(cmd)
    if not handle then
        return nil
    end
    local choice = handle:read("*a")
    handle:close()
    if not choice then
        return nil
    end
    choice = choice:gsub("^%s+", ""):gsub("%s+$", "")
    if choice == "" or choice == "false" then
        return nil
    end
    return choice
end

local function run_python(subcmd)
    local cmd = PYTHON .. " " .. shell_quote(GROK_ROOT .. "/grok_menu_cli.py") .. " " .. subcmd
    os.execute(cmd)
end

local function prompt_text(title, default_text)
    local cmd = 'osascript -e ' .. shell_quote(
        'text returned of (display dialog ' .. shell_quote(default_text) ..
        ' default answer ' .. shell_quote(default_text) ..
        ' with title ' .. shell_quote(title) .. ')'
    )
    local handle = io.popen(cmd)
    if not handle then
        return default_text
    end
    local text = handle:read("*a")
    handle:close()
    if not text or text == "" then
        return default_text
    end
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function action_generate()
    local slug = prompt_text("Grok slug", "neo-noir")
    local prompt = prompt_text("Grok prompt", "woman in rain on empty street at night")
    local cmd = PYTHON .. " " .. shell_quote(GROK_ROOT .. "/grok_menu_cli.py") ..
        " generate --slug " .. shell_quote(slug) .. " --prompt " .. shell_quote(prompt)
    os.execute(cmd)
end

local function dispatch(choice)
    if choice == "Bootstrap" then
        grok_bootstrap_startup()
    elseif choice == "Scan Downloads" then
        run_python("scan")
    elseif choice == "Import" then
        grok_import_verbose()
    elseif choice == "Scan + Import" then
        run_python("scan")
        grok_import_verbose()
    elseif choice == "Open Folder" then
        run_python("open-folder")
    elseif choice == "Start Bridge" then
        run_python("bridge")
    elseif choice == "Generate (terminal)" then
        action_generate()
    else
        print("unknown choice: " .. tostring(choice))
    end
end

local choice = choose_action()
if choice then
    print("grok: " .. choice)
    dispatch(choice)
else
    print("grok menu cancelled")
end