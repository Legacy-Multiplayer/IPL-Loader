-- San Andreas text IPL objects, optional vehicles/pickups and IDE registration.
local IPL = {}
local Map = {}
Map.__index = Map

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function integer(value)
    return finite(value) and value % 1 == 0
end

local function trim(text)
    return text:match("^%s*(.-)%s*$")
end

-- SA IPL stores the conjugate quaternion. Extract GTA's Z-X-Y Euler angles,
-- not the usual XYZ angles: createWorldObject ultimately uses SetRotate(x,y,z).
function IPL.rotation(qx, qy, qz, qw)
    for _, value in ipairs({qx, qy, qz, qw}) do
        assert(finite(value), "quaternion components must be finite numbers")
    end
    local length = math.sqrt(qx*qx + qy*qy + qz*qz + qw*qw)
    assert(finite(length) and length > 1e-12, "invalid zero/overflowed quaternion")
    local x, y, z, w = -qx/length, -qy/length, -qz/length, qw/length
    local r01, r11 = 2*(x*y-z*w), 1-2*(x*x+z*z)
    local r20, r21, r22 = 2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)
    local rx = math.asin(math.max(-1, math.min(1, r21)))
    local ry, rz
    if math.abs(math.cos(rx)) > 1e-6 then
        ry, rz = math.atan(-r20, r22), math.atan(-r01, r11)
    else
        ry, rz = 0, math.atan(2*(x*y+z*w), 1-2*(y*y+z*z))
    end
    return math.deg(rx), math.deg(ry), math.deg(rz)
end

-- Addon-Sscanf does the typed conversion. Keep exact record boundaries here:
-- scanf deliberately allows extra input because it is also a command parser.
local function scanRecord(line, format, count, commaRequired)
    local comma = line:find(",", 1, true) ~= nil
    if commaRequired or comma then
        local _, separators = line:gsub(",", "")
        if separators + 1 ~= count then return nil, "expected " .. count .. " comma-separated fields" end
    end
    if #line > 4096 then return nil, "record exceeds Addon-Sscanf's 4096-byte limit" end
    local values, problem = sscanfTable(line, (comma and "p<,>" or "") .. format .. " W")
    if not values then return nil, problem end
    if values[count + 1] ~= nil then return nil, "unexpected extra field" end
    return values
end

-- Parse separately from spawning, so malformed input never leaves half a map.
function IPL.parse(text, source)
    source = source or "<IPL>"
    if type(sscanfTable) ~= "function" then
        return nil, source .. ": Addon-Sscanf is required; install its DLL/SO in addons/"
    end
    if type(text) ~= "string" then return nil, "IPL content must be a string" end
    if #text > 8*1024*1024 then return nil, source .. ": exceeds 8 MiB text limit" end
    if text:sub(1,4) == "bnry" or text:find("\0", 1, true) then
        return nil, source .. ": binary IPL is not supported; export a text IPL"
    end
    text = text:gsub("^\239\187\191", "")
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local entries, objects, section, lineNumber = {}, {}, nil, 0
    local function failure(message)
        return nil, string.format("%s:%d: %s", source, lineNumber, message)
    end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lineNumber = lineNumber + 1
        line = trim(line:gsub("#.*$", ""):gsub("//.*$", ""):gsub(";.*$", ""))
        if line ~= "" then
            local keyword = line:lower()
            if not section then
                if not keyword:match("^[a-z][a-z0-9_]*$") or keyword == "end" then
                    return failure("expected a section name (for example inst)")
                end
                section = keyword
            elseif keyword == "end" then
                section = nil
            elseif section == "inst" then
                local fields, problem = scanRecord(line, "d w d f f f f f f f d", 11, true)
                if not fields then return failure("invalid inst record: " .. tostring(problem)) end
                local model, flags, lod = fields[1], fields[3], fields[11]
                if not integer(model) or model < 1 or model > 2147483647 then return failure("invalid model ID") end
                if fields[2] == "" then return failure("missing model name") end
                if not integer(flags) or flags < 0 or flags > 4294967295 then return failure("invalid instance flags") end
                if not integer(lod) or lod < -1 then return failure("invalid zero-based LOD index") end
                local values = fields
                local ok, rx, ry, rz = pcall(IPL.rotation, values[7], values[8], values[9], values[10])
                if not ok then return failure("invalid quaternion") end
                entries[#entries+1] = {
                    kind="object", model=model, name=fields[2], interior=flags % 256, flags=flags,
                    x=values[4], y=values[5], z=values[6], rx=rx, ry=ry, rz=rz,
                    lod=lod, line=lineNumber, index=#objects,
                }
                objects[#objects + 1] = entries[#entries]
            elseif section == "cars" or section == "pick" then
                local count = section == "cars" and 12 or 4
                local format = section == "cars" and "f f f f d d d d d d d d" or "d f f f"
                local values, problem = scanRecord(line, format, count, false)
                if not values then return failure("invalid " .. section .. " record: " .. tostring(problem)) end
                if section == "cars" then
                    if values[5] ~= -1 and (values[5] < 1 or values[5] > 2147483647) then return failure("invalid vehicle model") end
                    if values[6] < -1 or values[6] > 255 or values[7] < -1 or values[7] > 255 then return failure("invalid vehicle colours") end
                    if values[8] < 0 or values[8] > 255 or values[9] < 0 or values[9] > 100 or values[10] < 0 or values[10] > 100 then
                        return failure("invalid generator flags or chance")
                    end
                    if values[11] < 0 or values[12] < values[11] then return failure("invalid generator delay range") end
                    entries[#entries + 1] = {
                        kind="vehicle", x=values[1], y=values[2], z=values[3], heading=math.deg(values[4]),
                        model=values[5], color1=values[6], color2=values[7], flags=values[8],
                        alarmChance=values[9], lockChance=values[10], minDelay=values[11], maxDelay=values[12],
                        interior=0, line=lineNumber,
                    }
                else
                    if not integer(values[1]) or values[1] < 0 or values[1] > 2147483647 then return failure("invalid pickup code") end
                    entries[#entries + 1] = {kind="pickup", code=values[1], x=values[2], y=values[3], z=values[4], interior=0, line=lineNumber}
                end
            end
            if #entries > 20000 then return failure("exceeds 20000 placement limit") end
        end
    end
    if section then return failure("missing end for section " .. section) end
    if #entries == 0 then return failure("no supported placements found") end
    for _, entry in ipairs(objects) do
        if entry.lod >= #objects or entry.lod == entry.index then
            lineNumber = entry.line
            return failure("LOD index is outside the placement list or refers to itself")
        end
    end
    return entries
end

local function callback(map, success, problem)
    if map.onComplete then
        local ok, err = pcall(map.onComplete, map, success, problem)
        if not ok then print("[IPL] completion callback failed: " .. tostring(err)) end
    end
end

function Map:destroy()
    if self.timer then removeTimer(self.timer); self.timer=nil end
    for _, group in ipairs({{self.pickups, removePickup}, {self.vehicles, removeVehicle}, {self.objects, removeWorldObject}}) do
        for index = #group[1], 1, -1 do group[2](group[1][index]) end
    end
    self.objects, self.vehicles, self.pickups = {}, {}, {}
    self.state = "idle"
    self.next = 1
end

function Map:spawn(onComplete)
    if self.state == "loading" or self.state == "spawned" then return false, "map is already active" end
    if onComplete ~= nil and type(onComplete) ~= "function" then return false, "callback must be a function" end
    self.onComplete = onComplete
    self.state, self.next = "loading", 1
    local function fail(problem)
        self:destroy()
        self.state, self.error = "failed", problem
        callback(self, false, problem)
    end
    local function batch()
        for _=1,self.batchSize do
            local entry = self.entries[self.next]
            if not entry then
                if self.timer then removeTimer(self.timer); self.timer=nil end
                self.state = "spawned"
                callback(self, true)
                return
            end
            local x, y, z = entry.x+self.offset.x, entry.y+self.offset.y, entry.z+self.offset.z
            local ok, id
            local kind = entry.kind or "object"
            if kind == "vehicle" then
                ok, id = pcall(spawnVehicle, entry.model, x, y, z, entry.heading,
                    entry.color1, entry.color2, self.vehicleRespawnDelay, false)
            elseif kind == "pickup" then
                ok, id = pcall(spawnPickup, entry.model, entry.pickupType, x, y, z, self.dimension)
            else
                ok, id = pcall(createWorldObject, entry.model, x, y, z,
                    entry.rx, entry.ry, entry.rz, entry.drawDistance or self.drawDistance, self.dimension)
            end
            if not ok or not integer(id) or id < 0 or id >= 65535 or (kind == "vehicle" and id == 0) then
                fail(string.format("%s:%d: could not create %s model %d (%s)", self.path, entry.line, kind, entry.model, tostring(id)))
                return
            end
            local target = kind == "vehicle" and self.vehicles or kind == "pickup" and self.pickups or self.objects
            target[#target+1] = id
            if kind == "vehicle" then
                local configured, result = pcall(setVehicleDimension, id, self.dimension)
                if not configured or result == false then
                    fail("Could not set the IPL vehicle dimension")
                    return
                end
            end
            self.next = self.next+1
        end
    end
    local timer = createTimer(batch, 50, true)
    if not timer or timer == 0 then
        self.state = "failed"
        return false, "could not create IPL spawn timer"
    end
    self.timer = timer
    return true
end

function IPL.load(path, options)
    options = options or {}
    if type(path) ~= "string" or path == "" then return nil, "missing IPL path" end
    if type(options) ~= "table" then return nil, "options must be a table" end
    if options.offset ~= nil and type(options.offset) ~= "table" then return nil, "offset must be a table" end
    if options.models ~= nil and type(options.models) ~= "table" then return nil, "models must be an ID/name mapping table" end
    if options.ide ~= nil and (type(options.ide) ~= "table" or type(options.ide.models) ~= "table" or type(options.ide.drawDistances) ~= "table") then return nil, "ide must be a registered IDE catalogue" end
    if options.vehicles ~= nil and type(options.vehicles) ~= "boolean" then return nil, "vehicles must be boolean" end
    if options.vehicleModels ~= nil and type(options.vehicleModels) ~= "table" then return nil, "vehicleModels must be a mapping table" end
    if options.pickups ~= nil and type(options.pickups) ~= "table" then return nil, "pickups must map IPL codes to model/type tables" end
    local respawnDelay = options.vehicleRespawnDelay or 60
    if not integer(respawnDelay) or respawnDelay < -1 or respawnDelay > 2147483647 then return nil, "invalid vehicleRespawnDelay" end
    local offset = options.offset or {}
    local ox, oy, oz = offset.x or 0, offset.y or 0, offset.z or 0
    local dimension, interior = options.dimension or 0, options.interior
    local distance, batchSize = options.drawDistance or 400, options.batchSize or 32
    if not finite(ox) or not finite(oy) or not finite(oz) then return nil, "offset must be finite" end
    if not integer(dimension) or dimension < 0 or dimension > 65535 then return nil, "invalid dimension" end
    if interior ~= nil and (not integer(interior) or interior < 0 or interior > 255) then return nil, "invalid interior filter" end
    if not finite(distance) or distance <= 0 or distance > 3000 then return nil, "drawDistance must be 0 < distance <= 3000" end
    if not integer(batchSize) or batchSize < 1 or batchSize > 128 then return nil, "batchSize must be 1..128" end
    local file, problem = io.open(path, "rb")
    if not file then return nil, problem end
    local text, readError = file:read(8*1024*1024+1)
    file:close()
    if not text then return nil, readError or "empty IPL file" end
    local entries, parseError = IPL.parse(text, path)
    if not entries then return nil, parseError end
    local lods = {}
    for _, entry in ipairs(entries) do
        if entry.kind == "object" and entry.lod >= 0 then lods[entry.lod] = true end
    end
    local selected, filtered = {}, 0
    for _, entry in ipairs(entries) do
        local enabled = entry.kind == "object" or entry.kind == "vehicle" and options.vehicles == true
            or entry.kind == "pickup" and options.pickups ~= nil
        local matches = interior == nil or entry.interior == interior
        if enabled and matches and (entry.kind ~= "object" or options.skipLOD == false or not lods[entry.index]) then
            local mapped = entry.model
            if entry.kind == "object" then
                if options.ide then
                    mapped = options.ide.models[entry.model] or options.ide.models[entry.name] or entry.model
                    entry.drawDistance = not options.drawDistance and options.ide.drawDistances[entry.model] or nil
                end
                if options.models then mapped = options.models[entry.model] or options.models[entry.name] end
            elseif entry.kind == "vehicle" then
                mapped = options.vehicleModels and options.vehicleModels[entry.model] or entry.model
                if entry.flags ~= 0 or entry.alarmChance ~= 0 or entry.lockChance ~= 0 then
                    return nil, string.format("%s:%d: generator flags/alarm/lock behavior is unsupported; set these fields to zero", path, entry.line)
                end
            else
                local definition = options.pickups[entry.code]
                if type(definition) ~= "table" or not integer(definition.type) or definition.type < 0 or definition.type > 255 then
                    return nil, string.format("%s:%d: provide a pickup model/type mapping for IPL code %d", path, entry.line, entry.code)
                end
                mapped, entry.pickupType = definition.model, definition.type
            end
            if not integer(mapped) or mapped < 1 or mapped > 2147483647 then
                return nil, string.format("%s:%d: no valid model mapping for %s", path, entry.line, tostring(entry.model or entry.code))
            end
            entry.model = mapped
            selected[#selected+1] = entry
        else
            filtered = filtered + 1
        end
    end
    if options.vehicles and (type(spawnVehicle) ~= "function" or type(removeVehicle) ~= "function" or type(setVehicleDimension) ~= "function") then
        return nil, "Vehicle addon functions are required when vehicles are enabled"
    end
    if options.pickups and (type(spawnPickup) ~= "function" or type(removePickup) ~= "function") then
        return nil, "Pickup addon functions are required when pickups are enabled"
    end
    if #selected == 0 then return nil, "no placements match the interior/LOD filters" end
    return setmetatable({path=path, entries=selected, total=#entries, filtered=filtered,
        objects={}, vehicles={}, pickups={}, vehicleRespawnDelay=respawnDelay, state="idle", next=1, offset={x=ox,y=oy,z=oz}, dimension=dimension,
        drawDistance=distance, batchSize=batchSize}, Map)
end

function IPL.registerIDE(path, options)
    return require("ide").register(path, options)
end

return IPL
