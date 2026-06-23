GROK_ROOT = "__GROK_INSTALL_ROOT__"
if GROK_ROOT:sub(1, 2) == "__" then
    GROK_ROOT = os.getenv("GROK_PUBLIC_FOLDER") or ""
end
dofile(GROK_ROOT .. "/resolve/lua/grok_paths.lua")
dofile(GROK_ROOT .. "/resolve/lua/grok_startup.lua")

local TERMINAL_LAUNCHER = GROK_BIN .. "/grok-terminal"
local MENU_UI = GROK_BIN .. "/grok-menu"
local APP_NAME = "Grok for Resolve"
local APP_SOURCE = "DaVinci Resolve → Workspace → Scripts → Grok"

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
    local parts = { "GROK_PUBLIC_FOLDER=" .. shell_quote(GROK_ROOT), shell_quote(MENU_UI) }
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
    local t = APP_NAME:gsub("\\", "\\\\"):gsub('"', '\\"')
    os.execute('osascript -e "display notification \\"' .. m .. '\\" with title \\"' .. t .. '\\""')
end

local function trust_terminal_message(action, detail)
    return APP_NAME .. " is opening Terminal.app.\n\n" ..
        "Launched from:\n  " .. APP_SOURCE .. "\n\n" ..
        "Action:\n  " .. action .. "\n\n" ..
        detail .. "\n\n" ..
        "Project folder:\n  " .. GROK_ROOT .. "\n\n" ..
        "Safe workflow: local scripts in grok-public-folder + x.ai API (your XAI_API_KEY only)."
end

local function parse_field(line, key)
    if line:sub(1, #key + 1) == key .. ":" then
        return trim(line:sub(#key + 2))
    end
    return nil
end

local function parse_menu_output(output)
    local action = nil
    local opts = {}
    for line in output:gmatch("[^\r\n]+") do
        if line:sub(1, 7) == "ACTION:" then
            action = trim(line:sub(8))
        end
        for _, key in ipairs({
            "SLUG", "PROMPT", "DURATION", "RESOLUTION", "ASPECT",
            "LUT", "PROMPT_ADD", "CONTINUITY", "REFERENCE",
        }) do
            local value = parse_field(line, key)
            if value then
                opts[key] = value
            end
        end
    end
    return action, opts
end

local function open_terminal(command, label)
    local escaped_cmd = command:gsub("'", "'\\''")
    local escaped_label = (label or "Workflow"):gsub("'", "'\\''")
    os.execute("GROK_PUBLIC_FOLDER=" .. shell_quote(GROK_ROOT) .. " '" .. TERMINAL_LAUNCHER .. "' '" .. escaped_cmd .. "' '" .. escaped_label .. "'")
end

local function run_python_background(subcmd)
    local log = GROK_BRIDGE .. "/menu-last.log"
    local cmd = "GROK_PUBLIC_FOLDER=" .. shell_quote(GROK_ROOT) ..
        " /usr/bin/env python3 " .. GROK_ROOT .. "/grok_menu_cli.py " .. subcmd ..
        " >> " .. log .. " 2>&1 &"
    os.execute(cmd)
end

local function build_generate_cmd(opts)
    local parts = {
        GROK_BIN .. "/generate",
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
    return table.concat(parts, " ")
end

local function action_generate(opts)
    if not opts or not opts.SLUG or not opts.PROMPT then
        alert("Grok", "Generate cancelled")
        return
    end
    local gen_cmd = build_generate_cmd(opts)
    alert("Opening Terminal", trust_terminal_message(
        "Generate Video",
        "Terminal tab title: Grok · Generate Video\nRuns: bin/generate → x.ai video API → saves to video/"
    ))
    open_terminal(gen_cmd, "Generate Video")
    notify("Terminal opened for Generate Video — set XAI_API_KEY if needed")
end

local function action_bridge()
    alert("Opening Terminal", trust_terminal_message(
        "Start Bridge",
        "Terminal tab title: Grok · Start Bridge\nRuns: bin/bridge → local Grok chat/generate listener"
    ))
    open_terminal(GROK_BIN .. "/bridge", "Start Bridge")
    notify("Terminal opened for Bridge — export XAI_API_KEY first")
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
        os.execute("open " .. shell_quote(GROK_ROOT))
    elseif choice == "Start Bridge" then
        action_bridge()
    elseif choice == "Generate Video" then
        -- handled via canvas generate output
    else
        alert("Grok", "Unknown choice: " .. tostring(choice))
    end
end

local function handle_menu_output(output)
    if not output or output == "" or output == "CANCELLED" then
        print("grok menu cancelled")
        return
    end

    local action, opts = parse_menu_output(output)
    if action == "Generate Video" and opts.SLUG and opts.PROMPT then
        print("grok: Generate Video")
        action_generate(opts)
    elseif action == "Scan Timeline" then
        dofile(GROK_ROOT .. "/resolve/lua/grok_timeline.lua")
        local count = grok_scan_timeline()
        notify("Timeline scan: " .. tostring(count) .. " Grok clip(s)")
        handle_menu_output(run_menu_ui("choose", "timeline"))
    elseif action == "Batch Regenerate Timeline" then
        alert("Opening Terminal", trust_terminal_message(
            "Batch Regenerate Timeline",
            "Terminal tab title: Grok · Batch Regenerate\nRuns: bin/timeline batch-run for queued clips"
        ))
        open_terminal(GROK_BIN .. "/timeline batch-run", "Batch Regenerate")
        notify("Batch regenerate queued — check Terminal")
    elseif action then
        print("grok: " .. action)
        dispatch(action)
    else
        print("grok menu cancelled")
    end
end

handle_menu_output(run_menu_ui("choose"))