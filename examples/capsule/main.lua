-- Standalone main script for the Capsule IDE/IPL example.
local Capsule = require("capsule")
local grove = { x = 2490, y = -1668, z = 13.4 }

addEventHandler("onMainScriptInit", function()
    setWorldTime(12)
    setWorldWeather(1)
    Capsule.initialize()
end)

addEventHandler("onPlayerConnect", function(playerId)
    setPlayerSpawnData(playerId, 23, grove.x, grove.y, grove.z, 90, 0, 0, 0, 0, 0, 0)
    spawnPlayer(playerId)
end)

addEventHandler("onPlayerSpawn", function(playerId)
    resetPlayerCamera(playerId)
    sendMessage(playerId, 0xFFFFFFFF, "/capsule visits the map. /grove returns here.")
end)

addEventHandler("onPlayerCommandText", function(playerId, text)
    if text:lower() == "/capsule" then
        Capsule.teleport(playerId)
        return 1
    elseif text:lower() == "/grove" then
        setPlayerCoordinates(playerId, grove.x, grove.y, grove.z)
        resetPlayerCamera(playerId)
        return 1
    end

    return 0
end)

addEventHandler("onMainScriptExit", Capsule.shutdown)
