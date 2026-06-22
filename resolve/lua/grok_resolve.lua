local ARTIFACTS = "/Users/tref/film/grok-public-folder"
local MEDIA_EXT = {
    [".mp4"] = true, [".mov"] = true, [".m4v"] = true,
    [".png"] = true, [".jpg"] = true, [".jpeg"] = true, [".webp"] = true,
}

function grok_get_resolve()
    local tries = {
        function() return Resolve() end,
        function() return fusion and fusion:GetResolve() end,
        function() return bmd and bmd.scriptapp("Resolve") end,
    }
    for _, fn in ipairs(tries) do
        local ok, result = pcall(fn)
        if ok and result then
            return result
        end
    end
    return nil
end

function grok_list_files()
    local files = {}
    for _, sub in ipairs({"video", "image"}) do
        local dir = ARTIFACTS .. "/" .. sub
        local handle = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
        if handle then
            for name in handle:lines() do
                if name ~= "" and name:sub(1, 1) ~= "." then
                    local path = dir .. "/" .. name
                    local ext = name:match("^.+(%.[^%.]+)$")
                    if ext and MEDIA_EXT[ext:lower()] then
                        table.insert(files, path)
                    end
                end
            end
            handle:close()
        end
    end
    table.sort(files)
    return files
end

function grok_active_folder_name(media_pool)
    local folder = media_pool:GetCurrentFolder()
    if folder and folder.GetName then
        return folder:GetName()
    end
    return "current bin"
end

function grok_import_active()
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

    local files = grok_list_files()
    if #files == 0 then
        print("no files yet")
        print('generate first  g("/video your prompt")')
        return nil
    end

    local media_pool = project:GetMediaPool()
    local bin_name = grok_active_folder_name(media_pool)
    local imported = media_pool:ImportMedia(files)

    local count = 0
    if imported then
        count = #imported
    end

    print("imported " .. count .. " into " .. bin_name)
    return imported
end