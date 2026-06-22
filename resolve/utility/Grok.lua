dofile("/Users/tref/film/grok-public-folder/resolve/lua/grok_startup.lua")

local GROK_ROOT = "/Users/tref/film/grok-public-folder"
local TERMINAL_LAUNCHER = GROK_ROOT .. "/bin/grok-terminal"

local MENU_ITEMS = {
    "Bootstrap",
    "Scan Downloads",
    "Import",
    "Scan + Import",
    "Open Folder",
    "Start Bridge",
    "Generate Video",
}

local function alert(title, message)
    local t = title:gsub("\\", "\\\\"):gsub('"', '\\"')
    local m = message:gsub("\\", "\\\\"):gsub('"', '\\"')
    os.execute('osascript -e "display alert \\"' .. t .. '\\" message \\"' .. m .. '\\""')
end

local function notify(message)
    local m = message:gsub("\\", "\\\\"):gsub('"', '\\"')
    os.execute('osascript -e "display notification \\"' .. m .. '\\" with title \\"Grok\\""')
end

local function choose_action()
    local parts = {}
    for _, item in ipairs(MENU_ITEMS) do
        table.insert(parts, '"' .. item:gsub('"', '\\"') .. '"')
    end
    local list = table.concat(parts, ", ")
    local cmd = "osascript -e 'choose from list {" .. list .. "} with title \"Grok\"'"
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

local function prompt_text(title, default_text)
    local d = default_text:gsub("\\", "\\\\"):gsub('"', '\\"')
    local t = title:gsub("\\", "\\\\"):gsub('"', '\\"')
    local cmd = 'osascript -e \'text returned of (display dialog "' .. d ..
        '" default answer "' .. d .. '" with title "' .. t .. '")\''
    local handle = io.popen(cmd)
    if not handle then
        return default_text
    end
    local text = handle:read("*a")
    handle:close()
    if not text or text == "" then
        return nil
    end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return text
end

local function open_terminal(command)
    local launcher = TERMINAL_LAUNCHER
    local escaped = command:gsub("'", "'\\''")
    os.execute("'" .. launcher .. "' '" .. escaped .. "'")
end

local function run_python_background(subcmd)
    local log = GROK_ROOT .. "/bridge/menu-last.log"
    local cmd = "/usr/bin/env python3 " .. GROK_ROOT .. "/grok_menu_cli.py " .. subcmd ..
        " >> " .. log .. " 2>&1 &"
    os.execute(cmd)
end

local function action_generate()
    local slug = prompt_text("Grok slug", "neo-noir")
    if not slug then
        alert("Grok", "slug cancelled")
        return
    end
    local prompt = prompt_text("Grok prompt", "woman in rain on empty street at night")
    if not prompt then
        alert("Grok", "prompt cancelled")
        return
    end

    local gen_cmd = GROK_ROOT .. "/bin/generate --slug '" .. slug:gsub("'", "'\\''") ..
        "' --prompt '" .. prompt:gsub("'", "'\\''") .. "'"
    open_terminal(gen_cmd)
    notify("Terminal opened — set XAI_API_KEY if needed, watch progress there")
    alert("Grok", "Terminal opened for generate.\n\nIf nothing runs, open Terminal and run:\nexport XAI_API_KEY=your-key\n" .. gen_cmd)
end

local function action_bridge()
    open_terminal(GROK_ROOT .. "/bin/bridge")
    notify("Terminal opened for bridge — export XAI_API_KEY first")
end

local function dispatch(choice)
    if choice == "Bootstrap" then
        grok_bootstrap_startup()
        alert("Grok", "bootstrap done — check Resolve console output")
    elseif choice == "Scan Downloads" then
        run_python_background("scan")
        notify("scan started — check Downloads dialog")
    elseif choice == "Import" then
        grok_import_verbose()
    elseif choice == "Scan + Import" then
        run_python_background("scan")
        grok_import_verbose()
    elseif choice == "Open Folder" then
        os.execute("open " .. GROK_ROOT)
    elseif choice == "Start Bridge" then
        action_bridge()
    elseif choice == "Generate Video" then
        action_generate()
    else
        alert("Grok", "unknown choice: " .. tostring(choice))
    end
end

local choice = choose_action()
if choice then
    print("grok: " .. choice)
    dispatch(choice)
else
    print("grok menu cancelled")
end