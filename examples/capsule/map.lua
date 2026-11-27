local IPL = require("IPL")
local Capsule = {}
local map
local arrivalPad

-- The map includes a replacement terrain mesh. Move the complete layout
-- offshore so that it does not overlap GTA's original terrain.
local offset = { x = 8000, y = 0, z = 0 }
local arrival = { x = 10260, y = 600, z = 11.2, heading = 225 }

function Capsule.initialize()
    local catalogue, problem = IPL.registerIDE("resources/maps/capsule/capsule.ide", {
        assetPath = "maps/capsule",
        firstModelId = 220001,
        baseModel = 1337,
    })
    assert(catalogue, problem)

    map, problem = IPL.load("resources/maps/capsule/capsule.ipl", {
        ide = catalogue,
        offset = offset,
        interior = 0,
        dimension = 0,
        drawDistance = 900,
        vehicles = true,
        vehicleRespawnDelay = 60,
        pickups = {
            [19] = { model = 348, type = 1 },
        },
    })
    assert(map, problem)
    arrivalPad = createWorldObject(3095, arrival.x, arrival.y, 9.3, 0, 0, 0, 250, 0)
    assert(arrivalPad and arrivalPad >= 0 and arrivalPad < 65535, "Could not create arrival pad")
    assert(map:spawn(function(result, success, reason)
        assert(success, reason)
        print(string.format("[Capsule] Ready: %d custom objects, %d stock vehicles, %d pickup. Use /capsule.",
            #result.objects, #result.vehicles, #result.pickups))
    end))
end

function Capsule.teleport(playerId)
    if not map or map.state ~= "spawned" then
        return sendMessage(playerId, 0xFFFFFFFF, "Capsule Corp is still loading. Try /capsule again shortly.")
    end

    setPlayerInterior(playerId, 0)
    setPlayerDimension(playerId, 0)
    setPlayerCoordinates(playerId, arrival.x, arrival.y, arrival.z)
    setPlayerHeading(playerId, arrival.heading)
    resetPlayerCamera(playerId)
    sendMessage(playerId, 0xFFFFFFFF, "Capsule Corp. Stock Super GT and Sultan are parked nearby. /grove returns you.")
end

function Capsule.shutdown()
    if map then
        map:destroy()
        map = nil
    end
    if arrivalPad then
        removeWorldObject(arrivalPad)
        arrivalPad = nil
    end
end

return Capsule
