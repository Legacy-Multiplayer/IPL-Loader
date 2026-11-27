-- Pure Lua reader for San Andreas text IPL inst placements. No IDE dependency.
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

-- Parse separately from spawning, so malformed input never leaves half a map.
function IPL.parse(text, source)
    source = source or "<IPL>"
    if type(text) ~= "string" then return nil, "IPL content must be a string" end
    if #text > 8*1024*1024 then return nil, source .. ": exceeds 8 MiB text limit" end
    if text:sub(1,4) == "bnry" or text:find("\0", 1, true) then
        return nil, source .. ": binary IPL is not supported; export a text IPL"
    end
    text = text:gsub("^\239\187\191", "")
    local entries, section, lineNumber = {}, nil, 0
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
                local fields = {}
                for field in (line .. ","):gmatch("(.-),") do fields[#fields+1] = trim(field) end
                if #fields ~= 11 then return failure("SA inst requires 11 comma-separated fields") end
                local model, flags, lod = tonumber(fields[1]), tonumber(fields[3]), tonumber(fields[11])
                if not integer(model) or model < 1 or model > 2147483647 then return failure("invalid model ID") end
                if fields[2] == "" then return failure("missing model name") end
                if not integer(flags) or flags < 0 or flags > 4294967295 then return failure("invalid instance flags") end
                if not integer(lod) or lod < -1 then return failure("invalid zero-based LOD index") end
                local values = {}
                for index=4,10 do
                    values[index] = tonumber(fields[index])
                    if not finite(values[index]) then return failure("invalid number in field " .. index) end
                end
                local ok, rx, ry, rz = pcall(IPL.rotation, values[7], values[8], values[9], values[10])
                if not ok then return failure("invalid quaternion") end
                entries[#entries+1] = {
                    model=model, name=fields[2], interior=flags % 256, flags=flags,
                    x=values[4], y=values[5], z=values[6], rx=rx, ry=ry, rz=rz,
                    lod=lod, line=lineNumber, index=#entries,
                }
                if #entries > 20000 then return failure("exceeds 20000 placement limit") end
            end -- Non-inst sections are intentionally ignored.
        end
    end
    if section then return failure("missing end for section " .. section) end
    if #entries == 0 then return failure("no inst placements found") end
    for _, entry in ipairs(entries) do
        if entry.lod >= #entries or entry.lod == entry.index then
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
    for index=#self.objects,1,-1 do removeWorldObject(self.objects[index]) end
    self.objects = {}
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
            local ok, id = pcall(createWorldObject, entry.model,
                entry.x+self.offset.x, entry.y+self.offset.y, entry.z+self.offset.z,
                entry.rx, entry.ry, entry.rz, self.drawDistance, self.dimension)
            if not ok or not integer(id) or id < 0 or id >= 65535 then
                fail(string.format("%s:%d: could not create model %d (%s)", self.path, entry.line, entry.model, tostring(id)))
                return
            end
            self.objects[#self.objects+1] = id -- Object ID zero is valid in Legacy.
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
    for _, entry in ipairs(entries) do if entry.lod >= 0 then lods[entry.lod]=true end end
    local selected, filtered = {}, 0
    for _, entry in ipairs(entries) do
        if (interior == nil or entry.interior == interior) and (options.skipLOD == false or not lods[entry.index]) then
            local mapped = entry.model
            if options.models then mapped = options.models[entry.model] or options.models[entry.name] end
            if not integer(mapped) or mapped < 1 or mapped > 2147483647 then
                return nil, string.format("%s:%d: no valid model mapping for %d (%s)", path, entry.line, entry.model, entry.name)
            end
            entry.model = mapped
            selected[#selected+1] = entry
        else filtered=filtered+1 end
    end
    if #selected == 0 then return nil, "no placements match the interior/LOD filters" end
    return setmetatable({path=path, entries=selected, total=#entries, filtered=filtered,
        objects={}, state="idle", next=1, offset={x=ox,y=oy,z=oz}, dimension=dimension,
        drawDistance=distance, batchSize=batchSize}, Map)
end

return IPL
