package.path = "./includes/?.lua;./?.lua;" .. package.path
local IPL = require("IPL")
local IDE = require("IDE")
local count = 0
local function check(name, run)
    run()
    count = count + 1
    print("PASS " .. name)
end

check("missing Addon-Sscanf produces an explicit dependency error", function()
    local original = sscanfTable
    sscanfTable = nil
    local entries, problem = IPL.parse("inst\nend")
    local definitions, ideProblem = IDE.parse("objs\nend")
    sscanfTable = original
    assert(not entries and problem:find("Addon-Sscanf", 1, true))
    assert(not definitions and ideProblem:find("Addon-Sscanf", 1, true))
end)

check("native scanning rejects extra, empty, malformed and oversized fields", function()
    local line = "1238, cone, 0, 1, 2, 3, 0, 0, 0, 1, -1"
    for _, bad in ipairs({line .. ",", line .. ", extra", line:gsub("1, 2, 3", "1,,3"),
        line:gsub("1238", "1238.5"), line:gsub("cone", string.rep("x", 4097))}) do
        assert(not IPL.parse("inst\n" .. bad .. "\nend"))
    end
    assert(not IPL.parse("pick\n19 1 2 3 extra\nend"))
    assert(not IDE.parse("objs\n1, cube, tex, 100, 0, extra\nend"))
end)

local objects = "inst\n1238, cone, 0, 0, 0, 1, 0, 0, 0, 1, 1\n1422, barrier, 0, 1, 0, 1, 0, 0, 0, 1, -1\nend\n"
local cars = "cars\n1, 2, 3, 1.5707963267949, 520, 1, 2, 0, 0, 0, 0, 0\nend\n"
local pickups = "pick\n19, 4, 5, 6\nend\n"
local timer, removed, failPickup, failDimension, arguments
function createTimer(fn) timer = fn return 1 end
function removeTimer() timer = nil end
function createWorldObject(...) arguments.object = {...} return 0 end
function spawnVehicle(...) arguments.vehicle = {...} return 1 end
function setVehicleDimension(id, dimension) arguments.dimension = {id, dimension} return not failDimension end
function spawnPickup(...) arguments.pickup = {...} return failPickup and -1 or 0 end
function removeWorldObject() removed.object = removed.object + 1 end
function removeVehicle() removed.vehicle = removed.vehicle + 1 end
function removePickup() removed.pickup = removed.pickup + 1 end
local function fixture(text, run)
    local path = os.tmpname()
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
    arguments, removed = {}, {object=0, vehicle=0, pickup=0}
    failPickup, failDimension, timer = false, false, nil
    local ok, problem = pcall(run, path)
    os.remove(path)
    assert(ok, problem)
end

check("inst LOD indices remain independent of cars and pick records", function()
    local entries = assert(IPL.parse(cars .. pickups .. objects))
    assert(#entries == 4 and entries[3].index == 0 and entries[4].index == 1)
    fixture(cars .. pickups .. objects, function(path)
        local map = assert(IPL.load(path))
        assert(#map.entries == 1 and map.entries[1].model == 1238 and map.filtered == 3)
    end)
end)

check("mixed entities, radians, ID mapping, offsets, dimension and cleanup", function()
    fixture(objects .. cars .. pickups, function(path)
        local map = assert(IPL.load(path, {
            vehicles=true, vehicleModels={[520]=506}, pickups={[19]={model=348,type=1}},
            dimension=7, offset={x=10,y=20,z=30}, batchSize=20,
        }))
        assert(map:spawn())
        timer()
        assert(map.state == "spawned" and #map.objects == 1 and #map.vehicles == 1 and #map.pickups == 1)
        assert(arguments.vehicle[1] == 506 and math.abs(arguments.vehicle[5] - 90) < 0.0001)
        assert(arguments.vehicle[2] == 11 and arguments.vehicle[3] == 22 and arguments.vehicle[4] == 33)
        assert(arguments.dimension[2] == 7 and arguments.pickup[1] == 348 and arguments.pickup[6] == 7)
        map:destroy()
        map:destroy()
        assert(removed.object == 1 and removed.vehicle == 1 and removed.pickup == 1)
    end)
end)

check("failure rolls back objects and vehicles created before a pickup", function()
    fixture(objects .. cars .. pickups, function(path)
        local map = assert(IPL.load(path, {vehicles=true, pickups={[19]={model=348,type=1}}}))
        failPickup = true
        assert(map:spawn())
        timer()
        assert(map.state == "failed" and removed.object == 1 and removed.vehicle == 1 and removed.pickup == 0)
    end)
end)

check("failed vehicle dimension assignment leaves no orphan vehicle", function()
    fixture(cars, function(path)
        local map = assert(IPL.load(path, {vehicles=true}))
        failDimension = true
        assert(map:spawn())
        timer()
        assert(map.state == "failed" and removed.vehicle == 1)
    end)
end)

check("pick-only files need explicit mappings and work without inst", function()
    fixture(pickups, function(path)
        assert(not IPL.load(path))
        assert(not IPL.load(path, {pickups={}}))
        assert(IPL.load(path, {pickups={[19]={model=348,type=1}}}))
    end)
    assert(not IPL.parse("cars\n1 2 3 4 411 invalid 1 0 0 0 0 0 0\nend"))
end)

check("IDE parsing, optional mesh counts, CR newlines and unrelated sections", function()
    local rows = assert(IDE.parse("objs\r1, cube, shared, 200, 0\r2, house, shared, 2, 100, 300, 0\rend\r2dfx\rend\r"))
    assert(#rows == 2 and rows[2].drawDistance == 300)
    assert(not IDE.parse("objs\n1, cube, shared, 200, 1\nend"))
    assert(not IDE.parse("tobj\n1, timed, shared, 200, 0, 6, 18\nend"))
    assert(not IDE.parse("objs\n1, cube, shared, 200, 0\n1, other, shared, 200, 0\nend"))
end)

check("IDE preflights assets, skips occupied IDs and feeds IPL mapping/distances", function()
    local originalOpen = io.open
    local registered, missing = {}, false
    MODEL = {OBJECT=1}
    function doesCustomModelExist(id) return id == 220001 end
    function registerCustomModel(id, kind, files)
        assert(kind == MODEL.OBJECT and files.col == "demo/cube.col")
        registered[#registered + 1] = id
        return true, ""
    end
    fixture("objs\n1238, cube, shared, 200, 0\nend", function(path)
        io.open = function(name, mode)
            if name:sub(1, 7) == "assets/" then
                if missing then return nil, "missing" end
                return {seek=function() return 100 end, close=function() end}
            end
            return originalOpen(name, mode)
        end
        local ok, problem = pcall(function()
            missing = true
            assert(not IDE.register(path, {firstModelId=220001,assetPath="demo"}))
            assert(#registered == 0)
            missing = false
            local catalogue = assert(IPL.registerIDE(path, {firstModelId=220001,assetPath="demo"}))
            assert(catalogue.models[1238] == 220002 and catalogue.models.cube == 220002)
            assert(catalogue.drawDistances[1238] == 200)
            assert(not IDE.register(path, {firstModelId=220001,assetPath="../outside"}))
            local placement = os.tmpname()
            local file = assert(originalOpen(placement, "wb"))
            file:write("inst\n1238, cube, 0, 0, 0, 0, 0, 0, 0, 1, -1\nend")
            file:close()
            local map = assert(IPL.load(placement, {ide=catalogue}))
            os.remove(placement)
            assert(map.entries[1].model == 220002 and map.entries[1].drawDistance == 200)
        end)
        io.open = originalOpen
        assert(ok, problem)
    end)
end)

print(count .. " IDE and mixed-entity checks passed")
