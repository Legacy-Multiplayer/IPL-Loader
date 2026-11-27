-- Optional object-definition registration for the IPL loader.
local IDE = {}

local recordFormats = {
    [5] = "p<,>d w w f d W",
    [6] = "p<,>d w w d f d W",
    [7] = "p<,>d w w d f f d W",
    [8] = "p<,>d w w d f f f d W",
}

local function finite(number)
    return type(number) == "number" and number == number and math.abs(number) < math.huge
end

local function integer(number)
    return finite(number) and number % 1 == 0
end

local function read(path)
    local file, problem = io.open(path, "rb")
    if not file then return nil, problem end
    local content = file:read(2 * 1024 * 1024 + 1)
    file:close()
    if not content or #content > 2 * 1024 * 1024 then return nil, "IDE exceeds 2 MiB or could not be read" end
    return content
end

function IDE.parse(text, source)
    source = source or "<IDE>"
    if type(sscanfTable) ~= "function" then
        return nil, source .. ": Addon-Sscanf is required; install its DLL/SO in addons/"
    end
    if type(text) ~= "string" or #text > 2 * 1024 * 1024 or text:find("\0", 1, true) then
        return nil, source .. ": expected a text IDE of at most 2 MiB"
    end
    text = text:gsub("^\239\187\191", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local entries, ids, names = {}, {}, {}
    local section, lineNumber
    lineNumber = 0
    local function failure(problem)
        return nil, string.format("%s:%d: %s", source, lineNumber, problem)
    end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lineNumber = lineNumber + 1
        line = line:gsub("#.*$", ""):gsub("//.*$", ""):gsub(";.*$", ""):match("^%s*(.-)%s*$")
        if line ~= "" then
            if not section then
                if not line:match("^[%w_]+$") or line:lower() == "end" then return failure("expected an IDE section") end
                section = line:lower()
            elseif line:lower() == "end" then
                section = nil
            elseif section == "objs" then
                local _, separators = line:gsub(",", "")
                local count = separators + 1
                if not recordFormats[count] then return failure("unsupported objs field count") end
                if #line > 4096 then return failure("record exceeds Addon-Sscanf's 4096-byte limit") end
                local fields, problem = sscanfTable(line, recordFormats[count])
                if not fields then return failure("invalid objs record: " .. tostring(problem)) end
                if fields[count + 1] ~= nil then return failure("unexpected extra field") end
                local id, name, txd = fields[1], fields[2], fields[3]
                if not integer(id) or id < 1 or id > 2147483647 then return failure("invalid source model ID") end
                if not name:match("^[%w_%-]+$") or not txd:match("^[%w_%-]+$") then return failure("model/texture names must be leaf names without extensions") end
                if ids[id] or names[name:lower()] then return failure("duplicate object ID or model name") end
                local firstDistance = 4
                if count ~= 5 then
                    local meshCount = fields[4]
                    if not integer(meshCount) or meshCount < 1 or meshCount > 3 or count ~= meshCount + 5 then return failure("invalid mesh-distance count") end
                    firstDistance = 5
                end
                local distance = 0
                for index = firstDistance, count - 1 do
                    local value = fields[index]
                    if not finite(value) or value <= 0 or value > 3000 then return failure("draw distances must be 0 < distance <= 3000") end
                    distance = math.max(distance, value)
                end
                local flags = fields[count]
                if not integer(flags) or flags < 0 or flags > 4294967295 then return failure("invalid object flags") end
                if flags ~= 0 then return failure("nonzero native IDE object flags require manual registration; they are not emulated") end
                entries[#entries + 1] = {id=id, name=name, txd=txd, drawDistance=distance, line=lineNumber}
                ids[id], names[name:lower()] = true, true
                if #entries > 4096 then return failure("exceeds 4096 definitions") end
            elseif section == "tobj" then
                return failure("timed IDE objects are not supported")
            end
        end
    end
    if section then return failure("missing end for " .. section) end
    if #entries == 0 then return failure("no objs definitions found") end
    return entries
end

function IDE.register(path, options)
    options = options or {}
    if type(path) ~= "string" or path == "" or type(options) ~= "table" then return nil, "IDE path and options table are required" end
    local firstId, base = options.firstModelId, options.baseModel or 1337
    if not integer(firstId) or firstId <= 20000 or firstId > 2147483647 then return nil, "firstModelId must be a custom model ID above 20000" end
    if not integer(base) or base < 1 or base > 19999 then return nil, "invalid baseModel" end
    local directory = options.assetPath
    if type(directory) ~= "string" or directory == "" then return nil, "assetPath is required" end
    if directory:find("[:%z]") or directory:match("^[\\/]") then return nil, "assetPath must be relative to assets/" end
    for part in directory:gmatch("[^/\\]+") do
        if part == ".." then return nil, "assetPath cannot contain parent traversal" end
    end
    if type(registerCustomModel) ~= "function" or type(MODEL) ~= "table" then return nil, "Model and Constants addons are required" end
    local content, problem = read(path)
    if not content then return nil, problem end
    local entries
    entries, problem = IDE.parse(content, path)
    if not entries then return nil, problem end
    directory = directory:gsub("[\\/]$", "")
    local planned, nextId = {}, firstId
    -- Validate all paths and reserve distinct IDs before starting registration.
    for _, entry in ipairs(entries) do
        while type(doesCustomModelExist) == "function" and doesCustomModelExist(nextId) do nextId = nextId + 1 end
        if nextId > 2147483647 then return nil, "custom model ID range exhausted" end
        local files = {
            baseModel=base,
            dff=directory .. "/" .. entry.name .. ".dff",
            txd=directory .. "/" .. entry.txd .. ".txd",
            col=directory .. "/" .. entry.name .. ".col",
        }
        for _, key in ipairs({"dff", "txd", "col"}) do
            local file = io.open("assets/" .. files[key], "rb")
            if not file then return nil, path .. ": missing assets/" .. files[key] end
            local size = file:seek("end")
            file:close()
            if not size or size == 0 then return nil, path .. ": empty assets/" .. files[key] end
        end
        planned[#planned + 1] = {id=nextId, definition=entry, files=files}
        nextId = nextId + 1
    end
    local catalogue = {models={}, drawDistances={}, definitions=entries}
    for index, entry in ipairs(planned) do
        local success, reason = registerCustomModel(entry.id, MODEL.OBJECT, entry.files)
        if not success then
            return nil, string.format("%s:%d: registration failed for %s after %d registrations: %s; reload the owning script to clean up", path,
                entry.definition.line, entry.definition.name, index - 1, tostring(reason))
        end
        catalogue.models[entry.definition.id] = entry.id
        catalogue.models[entry.definition.name] = entry.id
        catalogue.drawDistances[entry.definition.id] = entry.definition.drawDistance
    end
    return catalogue
end

return IDE
