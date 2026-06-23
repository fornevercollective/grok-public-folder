-- Single source of truth for grok-public-folder paths (Resolve Lua).

local function trim(text)
    if not text then
        return ""
    end
    return text:gsub("^%s+", ""):gsub("%s+$", "")
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

local function lua_dir()
    local info = debug.getinfo(1, "S")
    local src = info.source or ""
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    return src:match("(.*/)") or ""
end

local function detect_root()
    local env = trim(os.getenv("GROK_PUBLIC_FOLDER") or "")
    if env ~= "" then
        return env
    end

    if GROK_ROOT and trim(GROK_ROOT) ~= "" and GROK_ROOT:sub(1, 2) ~= "__" then
        return trim(GROK_ROOT)
    end

    local base = lua_dir()
    if base ~= "" then
        local marker = base .. "../../project/.grok-root"
        local marker_text = trim(read_file(marker) or "")
        if marker_text ~= "" then
            return marker_text
        end
        local handle = io.popen('cd "' .. base .. '../.." && pwd 2>/dev/null')
        if handle then
            local pwd = trim(handle:read("*a"))
            handle:close()
            if pwd ~= "" and read_file(pwd .. "/project/presets-manifest.json") then
                return pwd
            end
        end
    end

    return ""
end

if not GROK_ROOT or GROK_ROOT == "" or GROK_ROOT:sub(1, 2) == "__" then
    GROK_ROOT = detect_root()
end

if GROK_ROOT == "" then
    print("GROK_ROOT not set — run ./install-resolve.sh from your grok-public-folder clone")
end

GROK_BIN = GROK_ROOT .. "/bin"
GROK_VIDEO = GROK_ROOT .. "/video"
GROK_IMAGE = GROK_ROOT .. "/image"
GROK_BRIDGE = GROK_ROOT .. "/bridge"
GROK_BROWSER = GROK_ROOT .. "/browser"
GROK_IMDB = GROK_ROOT .. "/imdb"
GROK_STREAMING = GROK_ROOT .. "/streaming"
GROK_PROJECT = GROK_ROOT .. "/project"