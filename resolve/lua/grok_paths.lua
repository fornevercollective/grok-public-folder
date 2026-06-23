-- Single source of truth for grok-public-folder paths (Resolve Lua).

local function trim(text)
    if not text then
        return ""
    end
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function detect_root()
    local env = trim(os.getenv("GROK_PUBLIC_FOLDER") or "")
    if env ~= "" then
        return env
    end
    -- Installed Utility/Grok.lua lives under Fusion/Scripts; repo root is not inferable
    -- from that path alone — fall back to canonical checkout location.
    return "/Users/tref/film/grok-public-folder"
end

GROK_ROOT = detect_root()
GROK_BIN = GROK_ROOT .. "/bin"
GROK_VIDEO = GROK_ROOT .. "/video"
GROK_IMAGE = GROK_ROOT .. "/image"
GROK_BRIDGE = GROK_ROOT .. "/bridge"
GROK_BROWSER = GROK_ROOT .. "/browser"
GROK_IMDB = GROK_ROOT .. "/imdb"
GROK_STREAMING = GROK_ROOT .. "/streaming"
GROK_PROJECT = GROK_ROOT .. "/project"