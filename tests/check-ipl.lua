-- Run from the repository root with Lua 5.3+: lua tests/check-ipl.lua
package.path = "./?.lua;" .. package.path
local IPL = require("ipl")
local passed = 0
local function check(name, fn)
    fn()
    passed=passed+1
    print("PASS " .. name)
end
local function close(a,b) assert(math.abs(a-b)<1e-6, tostring(a).." ~= "..tostring(b)) end
local row = "1238, cone, 0, 1, 2, 3, 0, 0, 0, 1, -1"
local function wrap(text) return "inst\n" .. text .. "\nend\n" end

check("comments, BOM, CRLF, unknown sections and placement metadata", function()
    local entries=assert(IPL.parse("\239\187\191# comment\r\n"..wrap(row).."cull\nignored\nend\n"))
    assert(#entries==1 and entries[1].model==1238 and entries[1].x==1 and entries[1].index==0)
end)

check("invalid records, non-finite numbers, binary input and section boundaries", function()
    local bad={"bnryxxx", "inst\0", wrap("1238, broken"), wrap(row:gsub(", 1, 2, 3,", ", 1e999, 2, 3,")),
        wrap(row:gsub("0, 0, 0, 1, %-1", "0, 0, 0, 0, -1")), "inst\n"..row,
        wrap(row:gsub(", %-1$", ", 20")), "end\n", wrap(row:gsub(", %-1$", ", 0"))}
    for _,text in ipairs(bad) do
        local result,err=IPL.parse(text,"bad.ipl")
        assert(not result and err:find("bad.ipl",1,true),tostring(err))
    end
end)

check("quaternion rotations reproduce the conjugated GTA matrix, including gimbal lock",function()
    local function verify(qx,qy,qz,qw)
        local length=math.sqrt(qx*qx+qy*qy+qz*qz+qw*qw)
        local x,y,z,w=-qx/length,-qy/length,-qz/length,qw/length
        local rx,ry,rz=IPL.rotation(qx,qy,qz,qw)
        rx,ry,rz=math.rad(rx),math.rad(ry),math.rad(rz)
        local sx,cx,sy,cy,sz,cz=math.sin(rx),math.cos(rx),math.sin(ry),math.cos(ry),math.sin(rz),math.cos(rz)
        local actual={cz*cy-sz*sx*sy, cz*sx*sy+sz*cy, -sy*cx,
            -sz*cx, cz*cx, sx, cz*sy+sz*sx*cy, sz*sy-cz*sx*cy, cy*cx}
        local expected={1-2*(z*z+y*y),2*(z*w+x*y),2*(z*x-y*w),
            2*(y*x-z*w),1-2*(z*z+x*x),2*(x*w+z*y),
            2*(y*w+z*x),2*(z*y-x*w),1-2*(y*y+x*x)}
        for i=1,9 do close(actual[i],expected[i]) end
    end
    verify(0,0,0,1)
    verify(0,0,-math.sqrt(0.5),math.sqrt(0.5))
    verify(-math.sqrt(0.5),0,0,math.sqrt(0.5))
    verify(math.sqrt(0.5),0,0,math.sqrt(0.5))
    math.randomseed(42)
    for _=1,100 do verify(math.random()-0.5,math.random()-0.5,math.random()-0.5,math.random()-0.5) end
end)

local timers, removed, nextId, failAt = {}, {}, 0, nil
local created = {}
function createTimer(fn) timers[#timers+1]=fn; return #timers end
function removeTimer(id) timers[id]=false end
function createWorldObject(...)
    local id=nextId
    if failAt==id then return 65535 end
    nextId=nextId+1
    created[#created+1]={...}
    return id
end
function removeWorldObject(id) removed[#removed+1]=id end
local function drain()
    for _=1,100 do
        local busy=false
        for _,fn in pairs(timers) do if fn then fn(); busy=true end end
        if not busy then return end
    end
    error("timer did not finish")
end
local fixture=os.tmpname()
local function withFixture(text,fn)
    local file=assert(io.open(fixture,"wb")); file:write(text); file:close()
    local ok,problem=pcall(fn)
    os.remove(fixture)
    assert(ok,problem)
end

check("LOD/interior filtering and model ID/name mapping",function()
    withFixture(wrap(row:gsub(", %-1$", ", 1").."\n"..row.."\n"..row:gsub("cone, 0,", "cone, 1,")),function()
        local map=assert(IPL.load(fixture,{interior=0,models={cone=160001}}))
        assert(#map.entries==1 and map.filtered==2 and map.entries[1].model==160001)
        local all=assert(IPL.load(fixture,{skipLOD=false}))
        assert(#all.entries==3)
        assert(not IPL.load(fixture,{models={}}))
    end)
end)

check("batched spawn, offsets, valid object ID zero, completion and destruction",function()
    nextId=0; created={}; removed={}
    withFixture(wrap(row.."\n"..row),function()
        local complete=0
        local map=assert(IPL.load(fixture,{offset={x=10,y=20,z=30},dimension=7,batchSize=1}))
        assert(map:spawn(function(_,ok) assert(ok);complete=complete+1 end))
        assert(#map.objects==0 and map.state=="loading")
        assert(not map:spawn())
        drain()
        assert(complete==1 and #map.objects==2 and map.objects[1]==0 and map.state=="spawned")
        assert(created[1][2]==11 and created[1][3]==22 and created[1][4]==33 and created[1][9]==7)
        map:destroy(); map:destroy()
        assert(#removed==2 and #map.objects==0)
    end)
end)

check("spawn failure rolls back previously created objects",function()
    nextId=0; failAt=1; removed={}
    withFixture(wrap(row.."\n"..row),function()
        local complete=0
        local map=assert(IPL.load(fixture))
        assert(map:spawn(function(_,ok,why) assert(not ok and why);complete=complete+1 end))
        drain()
        assert(complete==1 and map.state=="failed" and #map.objects==0 and removed[1]==0)
    end)
    failAt=nil
end)

check("unloading while loading cancels pending batches",function()
    nextId=0
    withFixture(wrap(row.."\n"..row),function()
        local map=assert(IPL.load(fixture,{batchSize=1}))
        assert(map:spawn(function() error("cancelled map completed") end))
        timers[map.timer]()
        assert(#map.objects==1)
        map:destroy(); drain()
        assert(nextId==1 and #map.objects==0)
    end)
end)

check("option validation and timer creation failure",function()
    withFixture(wrap(row),function()
        assert(not IPL.load(fixture,"invalid"))
        assert(not IPL.load(fixture,{offset="invalid"}))
        assert(not IPL.load(fixture,{models=true}))
        assert(not IPL.load(fixture,{offset={x=0/0}}))
        assert(not IPL.load(fixture,{batchSize=0}))
        assert(not IPL.load(fixture,{dimension=-1}))
        local original=createTimer
        createTimer=function() return 0 end
        local map=assert(IPL.load(fixture))
        assert(not map:spawn() and map.state=="failed")
        createTimer=original
    end)
end)
print(string.format("%d IPL checks passed",passed))
