dofile("/Users/tref/film/grok-public-folder/resolve/lua/grok_resolve.lua")

local TIMELINE_W = "3840"
local TIMELINE_H = "2160"
local TIMELINE_FPS = "23.976"
local IMPORT_BIN = "03_clips/grok_generated"

local BINS = {
    "01_inputs",
    "02_stills",
    "03_clips",
    "03_clips/grok_generated",
    "04_story_beats",
    "05_resolve_edit",
    "06_exports",
}

local function find_child_folder(parent, name)
    if not parent or not parent.GetSubFolderList then
        return nil
    end
    for _, sub in ipairs(parent:GetSubFolderList() or {}) do
        if sub:GetName() == name then
            return sub
        end
    end
    return nil
end

local function find_or_create_bin(media_pool, root, path)
    local current = root
    for part in string.gmatch(path, "[^/]+") do
        local found = find_child_folder(current, part)
        if not found then
            found = media_pool:AddSubFolder(current, part)
        end
        current = found
    end
    return current
end

function grok_bootstrap_startup()
    local resolve = grok_get_resolve()
    if not resolve then
        print("resolve not connected")
        return false
    end

    local project = resolve:GetProjectManager():GetCurrentProject()
    if not project then
        print("open a project first")
        return false
    end

    local media_pool = project:GetMediaPool()
    local root = media_pool:GetRootFolder()
    local created = {}

    for _, spec in ipairs(BINS) do
        find_or_create_bin(media_pool, root, spec)
        table.insert(created, spec)
    end

    local target = find_or_create_bin(media_pool, root, IMPORT_BIN)
    if target then
        media_pool:SetCurrentFolder(target)
    end

    local settings = {
        timelineResolutionWidth = TIMELINE_W,
        timelineResolutionHeight = TIMELINE_H,
        timelineFrameRate = TIMELINE_FPS,
    }

    print("grok bootstrap")
    print("folder " .. ARTIFACTS)
    print("timeline " .. TIMELINE_W .. "x" .. TIMELINE_H .. " @ " .. TIMELINE_FPS)
    for key, value in pairs(settings) do
        local ok = project:SetSetting(key, value)
        print("  " .. key .. "=" .. value .. (ok and "" or " (not applied)"))
    end
    print("bins " .. #created)
    print("active bin " .. IMPORT_BIN)
    print("done — run Grok.lua menu or bin/grok, then Import")
    return true
end