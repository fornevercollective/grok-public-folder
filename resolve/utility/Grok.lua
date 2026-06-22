dofile("/Users/tref/film/grok-public-folder/resolve/lua/grok_startup.lua")

local GROK_ROOT = "/Users/tref/film/grok-public-folder"
local TERMINAL_LAUNCHER = GROK_ROOT .. "/bin/grok-terminal"
local MENU_UI = GROK_ROOT .. "/bin/grok-menu"

local MENU_ITEMS = {
    "Bootstrap",
    "Scan Downloads",
    "Import",
    "Scan + Import",
    "Open Folder",
    "Start Bridge",
    "Generate Video",
}

local function trim(text)
    if not text then
        return ""
    end
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function run_menu_ui(...)
    local parts = { shell_quote(MENU_UI) }
    for i = 1, select("#", ...) do
        table.insert(parts, shell_quote(select(i, ...)))
    end
    local cmd = table.concat(parts, " ")
    local handle = io.popen(cmd)
    if not handle then
        return nil
    end
    local output = handle:read("*a")
    handle:close()
    output = trim(output)
    if output == "" or output == "CANCELLED" then
        return nil
    end
    return output
end

local function alert(title, message)
    run_menu_ui("alert", title, message)
end

local function notify(message)
    local m = message:gsub("\\", "\\\\"):gsub('"', '\\"')
    os.execute('osascript -e "display notification \\"' .. m .. '\\" with title \\"Grok\\""')
end

local function choose_action()
    return run_menu_ui("choose")
end

local function parse_field(line, key)
    if line:sub(1, #key + 1) == key .. ":" then
        return trim(line:sub(#key + 2))
    end
    return nil
end

local function prompt_generate()
    local output = run_menu_ui("generate")
    if not output then
        return nil
    end
    local result = {}
    for line in output:gmatch("[^\r\n]+") do
        for _, key in ipairs({
            "SLUG", "PROMPT", "DURATION", "RESOLUTION", "ASPECT",
            "LUT", "PROMPT_ADD", "CONTINUITY",
        }) do
            local value = parse_field(line, key)
            if value then
                result[key] = value
            end
        end
    end
    if not result.SLUG or not result.PROMPT or result.SLUG == "" or result.PROMPT == "" then
        return nil
    end
    return result
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
    local opts = prompt_generate()
    if not opts then
        alert("Grok", "Generate cancelled")
        return
    end

    local parts = {
        GROK_ROOT .. "/bin/generate",
        "--slug", shell_quote(opts.SLUG),
        "--prompt", shell_quote(opts.PROMPT),
    }
    if opts.DURATION and opts.DURATION ~= "" then
        table.insert(parts, "--duration")
        table.insert(parts, shell_quote(opts.DURATION))
    end
    if opts.RESOLUTION and opts.RESOLUTION ~= "" then
        table.insert(parts, "--resolution")
        table.insert(parts, shell_quote(opts.RESOLUTION))
    end
    if opts.ASPECT and opts.ASPECT ~= "" then
        table.insert(parts, "--aspect")
        table.insert(parts, shell_quote(opts.ASPECT))
    end
    if opts.LUT and opts.LUT ~= "" then
        table.insert(parts, "--lut")
        table.insert(parts, shell_quote(opts.LUT))
    end
    if opts.PROMPT_ADD and opts.PROMPT_ADD ~= "" then
        table.insert(parts, "--prompt-add")
        table.insert(parts, shell_quote(opts.PROMPT_ADD))
    end
    if opts.CONTINUITY and opts.CONTINUITY ~= "" then
        table.insert(parts, "--continuity")
        table.insert(parts, shell_quote(opts.CONTINUITY))
    end
    local gen_cmd = table.concat(parts, " ")
    open_terminal(gen_cmd)
    notify("Terminal opened — set XAI_API_KEY if needed")
    alert("Grok", "Terminal opened for generate.\n\nIf nothing runs:\nexport XAI_API_KEY=your-key\n\n" .. gen_cmd)
end

local function action_bridge()
    open_terminal(GROK_ROOT .. "/bin/bridge")
    notify("Terminal opened for bridge — export XAI_API_KEY first")
end

local function dispatch(choice)
    if choice == "Bootstrap" then
        grok_bootstrap_startup()
        alert("Grok", "Bootstrap done — check Resolve console output")
    elseif choice == "Scan Downloads" then
        run_python_background("scan")
        notify("Scan started — watch for Downloads dialog")
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
        alert("Grok", "Unknown choice: " .. tostring(choice))
    end
end

local choice = choose_action()
if choice then
    print("grok: " .. choice)
    dispatch(choice)
else
    print("grok menu cancelled")
end