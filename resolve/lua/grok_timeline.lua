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

local SCAN_FILE = GROK_PROJECT .. "/timeline-grok-clips.json"
local MEDIA_EXT = {
    [".mp4"] = true, [".mov"] = true, [".m4v"] = true, [".webm"] = true,
    [".png"] = true, [".jpg"] = true, [".jpeg"] = true, [".webp"] = true, [".gif"] = true,
}

local function json_escape(value)
    if value == nil then
        return "null"
    end
    if type(value) == "number" then
        return tostring(value)
    end
    if type(value) == "boolean" then
        return value and "true" or "false"
    end
    local text = tostring(value)
    text = text:gsub("\\", "\\\\")
    text = text:gsub('"', '\\"')
    text = text:gsub("\n", "\\n")
    text = text:gsub("\r", "\\r")
    return '"' .. text .. '"'
end

local function read_sidecar_json(media_path)
    if not media_path or media_path == "" then
        return nil
    end
    local sidecar = media_path .. ".grok.json"
    local file = io.open(sidecar, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    if content and content ~= "" and content:match("^%s*{") then
        return content
    end
    return nil
end

local function safe_call(fn, default)
    local ok, result = pcall(fn)
    if ok and result ~= nil then
        return result
    end
    return default
end

local function item_frame(item, method, default)
    if not item then
        return default
    end
    local getter = item[method]
    if type(getter) ~= "function" then
        return default
    end
    return safe_call(function() return getter(item) end, default)
end

local function is_grok_media(file_path, file_name)
    if not file_path and not file_name then
        return false
    end
    local path = file_path or ""
    local name = (file_name or path:match("([^/]+)$") or ""):lower()
    if path:find(GROK_ROOT, 1, true) then
        return true
    end
    if name:sub(1, 5) == "grok_" then
        return true
    end
    if read_sidecar_json(file_path) then
        return true
    end
    return false
end

local function clip_property(media_item, key)
    if not media_item or not media_item.GetClipProperty then
        return ""
    end
    local ok, value = pcall(function() return media_item:GetClipProperty(key) end)
    if ok and value and value ~= "" then
        return tostring(value)
    end
    return ""
end

local function frames_to_timecode(frames, fps)
    if not fps or fps <= 0 then
        fps = 24
    end
    local total_seconds = math.floor(frames / fps)
    local f = math.floor(frames % fps)
    local s = total_seconds % 60
    local m = math.floor(total_seconds / 60) % 60
    local h = math.floor(total_seconds / 3600)
    return string.format("%02d:%02d:%02d:%02d", h, m, s, f)
end

local function resolve_timeline(project, timeline_index)
    if timeline_index and tonumber(timeline_index) then
        local idx = tonumber(timeline_index)
        local tl = safe_call(function() return project:GetTimelineByIndex(idx) end, nil)
        if tl then
            safe_call(function() project:SetCurrentTimeline(tl) end)
            return tl, idx
        end
        print("timeline index not found: " .. tostring(idx))
        return nil, idx
    end
    local tl = safe_call(function() return project:GetCurrentTimeline() end, nil)
    return tl, nil
end

function grok_list_timelines()
    local resolve = grok_get_resolve()
    if not resolve then
        print("resolve not connected")
        return nil
    end
    local project = resolve:GetProjectManager():GetCurrentProject()
    if not project then
        print("open a project first")
        return nil
    end
    local current = safe_call(function() return project:GetCurrentTimeline() end, nil)
    local current_name = current and safe_call(function() return current:GetName() end, "") or ""
    local count = safe_call(function() return project:GetTimelineCount() end, 0) or 0
    print('{"ok":true,"project_name":' .. json_escape(project:GetName() or "Project") .. ',"timeline_count":' .. count .. ',"timelines":[')
    for idx = 1, count do
        local tl = safe_call(function() return project:GetTimelineByIndex(idx) end, nil)
        if tl then
            local name = safe_call(function() return tl:GetName() end, "") or ("Timeline " .. idx)
            local is_current = (current_name ~= "" and name == current_name)
            local suffix = idx < count and "," or ""
            print(
                '{"index":' ..
                    idx ..
                    ',"name":' ..
                    json_escape(name) ..
                    ',"is_current":' ..
                    (is_current and "true" or "false") ..
                    "}" .. suffix
            )
        end
    end
    print("]}")
    return count
end

function grok_scan_timeline(timeline_index)
    local resolve = grok_get_resolve()
    if not resolve then
        print("resolve not connected")
        return 0
    end

    local project = resolve:GetProjectManager():GetCurrentProject()
    if not project then
        print("open a project first")
        return 0
    end

    local timeline, index_used = resolve_timeline(project, timeline_index)
    if not timeline then
        print("open a timeline first")
        return 0
    end

    local fps_text = project:GetSetting("timelineFrameRate") or "24"
    local fps = tonumber(fps_text) or 24
    local timeline_name = timeline:GetName() or "Timeline"
    local project_name = project:GetName() or "Project"
    local clips = {}
    local track_count = timeline:GetTrackCount("video") or 0

    for track_index = 1, track_count do
        local items = safe_call(function() return timeline:GetItemListInTrack("video", track_index) end, nil)
        if items then
            local item_count = #items
            if item_count == 0 then
                item_count = safe_call(function() return items.GetCount and items:GetCount() or 0 end, 0)
            end
            local indices = {}
            if item_count > 0 then
                for i = 1, item_count do
                    table.insert(indices, i)
                end
            else
                for i, _ in ipairs(items) do
                    table.insert(indices, i)
                end
            end
            for _, item_index in ipairs(indices) do
                local item = items[item_index]
                if item then
                    local ok_item, err_item = pcall(function()
                        local media_item = safe_call(function() return item:GetMediaPoolItem() end, nil)
                        if not media_item then
                            return
                        end
                        local file_path = clip_property(media_item, "File Path")
                        local file_name = clip_property(media_item, "File Name")
                        if file_name == "" then
                            file_name = safe_call(function() return media_item:GetName() end, "") or ""
                        end
                        if not is_grok_media(file_path, file_name) then
                            return
                        end
                        local start_frame = item_frame(item, "GetStart", 0)
                        local end_frame = item_frame(item, "GetEnd", 0)
                        if end_frame <= start_frame then
                            local duration_frames = item_frame(item, "GetDuration", 0)
                            if duration_frames > 0 then
                                end_frame = start_frame + duration_frames
                            end
                        end
                        local duration = end_frame - start_frame
                        if duration < 0 then
                            duration = 0
                        end
                        local sidecar_raw = read_sidecar_json(file_path)
                        table.insert(clips, {
                            id = "v" .. track_index .. "_" .. item_index,
                            track = track_index,
                            track_type = "video",
                            name = file_name,
                            file_path = file_path,
                            start_frame = start_frame,
                            end_frame = end_frame,
                            duration_frames = duration,
                            timeline_in = frames_to_timecode(start_frame, fps),
                            timeline_out = frames_to_timecode(end_frame, fps),
                            sidecar_raw = sidecar_raw,
                        })
                    end)
                    if not ok_item then
                        print("timeline scan: skipped item v" .. track_index .. "_" .. item_index .. ": " .. tostring(err_item))
                    end
                end
            end
        end
    end

    local stamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local file = io.open(SCAN_FILE, "w")
    if not file then
        print("could not write " .. SCAN_FILE)
        return 0
    end

    file:write("{\n")
    file:write('  "scanned_at": ' .. json_escape(stamp) .. ",\n")
    file:write('  "project_name": ' .. json_escape(project_name) .. ",\n")
    file:write('  "timeline_name": ' .. json_escape(timeline_name) .. ",\n")
    if index_used then
        file:write('  "timeline_index": ' .. index_used .. ",\n")
    else
        file:write('  "timeline_index": null,\n')
    end
    file:write('  "fps": ' .. json_escape(fps) .. ",\n")
    file:write('  "clip_count": ' .. #clips .. ",\n")
    file:write('  "clips": [\n')

    for index, clip in ipairs(clips) do
        file:write("    {\n")
        file:write('      "id": ' .. json_escape(clip.id) .. ",\n")
        file:write('      "track": ' .. clip.track .. ",\n")
        file:write('      "track_type": ' .. json_escape(clip.track_type) .. ",\n")
        file:write('      "name": ' .. json_escape(clip.name) .. ",\n")
        file:write('      "file_path": ' .. json_escape(clip.file_path) .. ",\n")
        file:write('      "start_frame": ' .. clip.start_frame .. ",\n")
        file:write('      "end_frame": ' .. clip.end_frame .. ",\n")
        file:write('      "duration_frames": ' .. clip.duration_frames .. ",\n")
        file:write('      "timeline_in": ' .. json_escape(clip.timeline_in) .. ",\n")
        file:write('      "timeline_out": ' .. json_escape(clip.timeline_out) .. ",\n")
        if clip.sidecar_raw then
            file:write('      "sidecar": ' .. clip.sidecar_raw .. ",\n")
        else
            file:write('      "sidecar": null,\n')
        end
        file:write('      "is_grok": true\n')
        file:write("    }")
        if index < #clips then
            file:write(",\n")
        else
            file:write("\n")
        end
    end

    file:write("  ]\n}\n")
    file:close()

    print("timeline scan: " .. #clips .. " grok clip(s) on " .. timeline_name)
    print("wrote " .. SCAN_FILE)
    return #clips
end