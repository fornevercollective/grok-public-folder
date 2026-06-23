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

local BRIDGE = GROK_BRIDGE
local REQUEST = BRIDGE .. "/request.json"
local RESPONSE = BRIDGE .. "/response.json"

local function sleep(seconds)
    local deadline = os.clock() + seconds
    while os.clock() < deadline do end
end

local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function write_file(path, content)
    local file = io.open(path, "w")
    if not file then
        return false
    end
    file:write(content)
    file:close()
    return true
end

local function json_escape(value)
    return (value or "")
        :gsub("\\", "\\\\")
        :gsub("\"", "\\\"")
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
end

local function parse_response(json_text, id)
    if not json_text or not json_text:find('"id"%s*:%s*"' .. id .. '"') then
        return nil
    end
    local ok = json_text:match('"ok"%s*:%s*(true|false)')
    local message = json_text:match('"message"%s*:%s*"(.-)"')
    if message then
        message = message:gsub("\\n", "\n"):gsub("\\\"", "\"")
    end
    return ok == "true", message or json_text
end

local function next_id()
    return tostring(os.time()) .. tostring(math.random(1000, 9999))
end

function grok_help()
    print("grok bridge ready")
    print("g()                     help")
    print("ping()                  test terminal bridge")
    print('g("your message")       chat')
    print('g("/image prompt")      still')
    print('g("/video prompt")      clip')
    print("import()                load into active bin")
    print("")
    print("start terminal bridge first")
    print("export XAI_API_KEY=your-key")
    print(GROK_BIN .. "/bridge")
end

function grok_send(action, text, options)
    options = options or {}
    local id = next_id()
    local payload = '{"id":"' .. id .. '","action":"' .. json_escape(action) .. '","text":"' .. json_escape(text or "") .. '"'
    if options.duration then
        payload = payload .. ',"duration":' .. tostring(options.duration)
    end
    if options.aspect_ratio then
        payload = payload .. ',"aspect_ratio":"' .. json_escape(options.aspect_ratio) .. '"'
    end
    if options.resolution then
        payload = payload .. ',"resolution":"' .. json_escape(options.resolution) .. '"'
    end
    payload = payload .. "}"

    os.remove(RESPONSE)
    if not write_file(REQUEST, payload) then
        print("could not write bridge request")
        return nil
    end

    local timeout = 30
    if action == "video" then
        timeout = options.timeout or 900
    elseif action == "image" then
        timeout = options.timeout or 120
    elseif action == "chat" then
        timeout = options.timeout or 180
    end

    print("waiting")

    local waited = 0
    while waited < timeout do
        local response_text = read_file(RESPONSE)
        local ok, message = parse_response(response_text, id)
        if ok ~= nil then
            if ok then
                print(message)
                return message
            end
            print(message)
            return nil
        end
        sleep(0.5)
        waited = waited + 0.5
    end

    print("bridge timeout")
    print("start " .. GROK_BIN .. "/bridge in terminal")
    return nil
end

function ping()
    return grok_send("ping", "", { timeout = 15 })
end

function grok_ping()
    return ping()
end

function grok_chat(text)
    return grok_send("chat", text, { timeout = 180 })
end

function grok_image(text)
    return grok_send("image", text, { timeout = 120 })
end

function grok_video(text, duration)
    return grok_send("video", text, { duration = duration or 8, timeout = 900 })
end

function import()
    return grok_import_active()
end

function grok_import()
    return import()
end

function grok_clear()
    return grok_send("clear", "", { timeout = 15 })
end

function grok(text)
    if not text or text == "" then
        grok_help()
        return nil
    end
    if text:sub(1, 6) == "/image" then
        return grok_image(text:sub(7):match("^%s*(.-)%s*$"))
    end
    if text:sub(1, 6) == "/video" then
        return grok_video(text:sub(7):match("^%s*(.-)%s*$"))
    end
    if text:sub(1, 7) == "/import" then
        return import()
    end
    if text:sub(1, 6) == "/clear" then
        return grok_clear()
    end
    return grok_chat(text)
end

function g(text)
    if text == nil or text == "" then
        grok_help()
        return nil
    end
    return grok(text)
end

grok_help()