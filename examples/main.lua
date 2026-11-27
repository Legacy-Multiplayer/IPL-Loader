local IPL = require("IPL")
local activeMap
local vehicles = {}
local sessions = {}
local serial = 0
local grove = {x=2490, y=-1668, z=13.4, heading=90}

local function message(playerId, text)
    if doesPlayerExist(playerId) then sendMessage(playerId, 0xFFFFFFFF, text) end
end

local function clearVehicle(playerId)
    local id = vehicles[playerId]
    if id and isVehicleValid(id) then removeVehicle(id) end
    vehicles[playerId] = nil
end

local function spawnAtGrove(playerId)
    clearVehicle(playerId)
    setPlayerInterior(playerId, 0)
    setPlayerDimension(playerId, 0)
    setPlayerControllable(playerId, true)
    setPlayerSpawnData(playerId, 23, grove.x, grove.y, grove.z, grove.heading, 0,0,0,0,0,0)
    spawnPlayer(playerId)
end

local function unload()
    if activeMap then activeMap:destroy(); activeMap=nil end
end

local function loadMap(playerId, filename, here)
    filename = filename == "" and "grove-demo.ipl" or filename
    -- Commands only read leaf filenames within resources/maps, never paths.
    if not filename:match("^[%w_ %-]+%.ipl$") then
        return message(playerId, "Use a .ipl filename with letters, numbers, spaces, _ or - (no folders).")
    end
    local map, problem = IPL.load("resources/maps/" .. filename, {interior=0, dimension=0})
    if not map then return message(playerId, "IPL: " .. tostring(problem)) end
    if here then
        local x,y,z = getPlayerCoordinates(playerId)
        local first = map.entries[1]
        -- Align the first selected object's origin eight metres east of you.
        map.offset = {x=x+8-first.x, y=y-first.y, z=z-first.z}
    end
    -- Parse the replacement before removing the current map.
    unload()
    activeMap = map
    local ownerSession = sessions[playerId]
    local ok, err = map:spawn(function(result, success, why)
        local status = success and string.format("Loaded %s: %d objects (%d filtered).", filename, #result.objects, result.filtered)
            or ("IPL failed: " .. tostring(why))
        print("[IPL Test] " .. status)
        if sessions[playerId] == ownerSession then message(playerId, status) end
    end)
    if not ok then activeMap=nil; return message(playerId, "IPL: " .. tostring(err)) end
    message(playerId, "Loading " .. filename .. " in batches...")
end

local function createCar(playerId, model)
    clearVehicle(playerId)
    local x,y,z = getPlayerCoordinates(playerId)
    local id = spawnVehicle(model,x+4,y,z+0.5,getPlayerHeading(playerId),1,1,-1,false)
    if not id or id <= 0 or id >= 65535 then return message(playerId,"Vehicle spawn failed.") end
    vehicles[playerId] = id
    setPlayerVehicle(playerId,id,0)
end

local commands = {
    help = function(playerId)
        message(playerId,"/ipl [filename.ipl] /iplhere <filename.ipl> /unloadipl /iplstatus")
        message(playerId,"/grove /infernus /nrg /delveh /pos /help")
    end,
    ipl = function(playerId, argument) loadMap(playerId,argument,false) end,
    iplhere = function(playerId, argument)
        if argument == "" then return message(playerId,"Usage: /iplhere filename.ipl") end
        loadMap(playerId,argument,true)
    end,
    unloadipl = function(playerId) unload(); message(playerId,"IPL objects removed for everyone.") end,
    iplstatus = function(playerId)
        if not activeMap then return message(playerId,"No IPL loaded. Use /ipl.") end
        message(playerId,string.format("%s: %s, %d/%d objects, offset %.1f %.1f %.1f",
            activeMap.path,activeMap.state,#activeMap.objects,#activeMap.entries,
            activeMap.offset.x,activeMap.offset.y,activeMap.offset.z))
    end,
    grove = spawnAtGrove,
    infernus = function(playerId) createCar(playerId,411) end,
    nrg = function(playerId) createCar(playerId,522) end,
    delveh = function(playerId) clearVehicle(playerId) end,
    pos = function(playerId)
        local x,y,z=getPlayerCoordinates(playerId)
        message(playerId,string.format("Position %.3f, %.3f, %.3f",x,y,z))
    end,
}

addEventHandler("onMainScriptInit",function()
    setServerDescription("Pure Lua IPL loader - Grove Street")
    setWorldTime(12)
    setWorldWeather(1)
    disableInteriorEntrances()
    print("[IPL Test] Ready. Spawn at Grove Street and use /ipl for the sample.")
end)

addEventHandler("onPlayerConnect",function(playerId)
    serial=serial+1
    sessions[playerId]=serial
    spawnAtGrove(playerId)
end)

addEventHandler("onPlayerSpawn",function(playerId)
    -- This also runs after death. Never call spawnPlayer recursively here.
    setPlayerControllable(playerId,true)
    resetPlayerCamera(playerId)
    message(playerId,"IPL Test - Grove Street. /ipl shows the sample. /help lists commands.")
end)

addEventHandler("onPlayerDisconnect",function(playerId)
    clearVehicle(playerId)
    sessions[playerId]=nil
end)

addEventHandler("onPlayerCommandText",function(playerId,text)
    local name, argument = text:match("^/(%S+)%s*(.-)%s*$")
    local handler = name and commands[name:lower()]
    if not handler then return 0 end
    handler(playerId,argument)
    return 1
end)

addEventHandler("onMainScriptExit",function()
    unload()
    for playerId in pairs(vehicles) do clearVehicle(playerId) end
end)
