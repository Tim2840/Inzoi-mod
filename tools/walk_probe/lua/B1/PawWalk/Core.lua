-- Walking-cat probe, B1 side. Commands arrive through uimod.cfg (section cmd, key next,
-- value "<seq>;<verb> <args>"); results go to section log, key b1.
local C = { cats = {}, seq = nil, t = 0, poll = 0, walks = {}, lines = {}, setVariant = nil }
local MOD = "PawWalkProbe"

local function clean(s)
    s = tostring(s):gsub('"', "'"):gsub("[\r\n]", " ")
    return s
end

function C.log(line)
    C.lines[#C.lines + 1] = string.format("%.1f %s", C.t, clean(line))
    if #C.lines > 150 then table.remove(C.lines, 1) end
    pcall(inzoi.cli.execute, "uimod.cfg_save mod_id=" .. MOD .. " section=log key=b1 value=\""
        .. table.concat(C.lines, " || ") .. "\"")
end

-- call a method by name; names are built at run time so the static analyzer cannot reject them
local function m(obj, name, ...)
    local f = obj[name]
    if f == nil then error("no method " .. name) end
    return f(obj, ...)
end
C.m = m

local function vecStr(v)
    if v == nil then return "nil" end
    local ok, s = pcall(function() return string.format("(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z) end)
    return ok and s or tostring(v)
end
C.vecStr = vecStr

local function eidOf(a)
    local ok, id = pcall(function() return a:GetEntityId() end)
    if ok and type(id) ~= "number" and id ~= nil then
        local ok2, v = pcall(function() return id.Value end)
        if ok2 then id = v end
    end
    return ok and tonumber(id) or nil
end
C.eidOf = eidOf

function C.addCat(actor, how)
    local eid = eidOf(actor)
    if not eid then C.log("addCat(" .. how .. "): no entity id for " .. tostring(actor)); return end
    local again = C.cats[eid] ~= nil
    C.cats[eid] = actor
    local okL, loc = pcall(m, actor, "K2_GetActorLocation")
    C.log("cat " .. eid .. " via " .. how .. (again and " (again)" or "") .. " " .. tostring(actor)
        .. " loc " .. (okL and vecStr(loc) or ("ERR " .. tostring(loc))))
end

function C.endCat(actor, how)
    local eid = eidOf(actor)
    C.log("cat end " .. tostring(eid) .. " via " .. how .. " " .. tostring(actor))
end

-- list the actor's components (class names)
function C.comps(eid)
    local a = C.cats[eid]
    if not a then C.log("comps: unknown cat " .. tostring(eid)); return end
    local out = {}
    local ok, err = pcall(function()
        local list = m(a, "K2_GetComponentsByClass", UE.UActorComponent)
        local n = list.Num and list:Num() or #list
        for i = 1, n do
            local c = list[i]
            local okN, name = pcall(m, c, "GetName")
            local okC, cls = pcall(function() return m(m(c, "GetClass"), "GetName") end)
            out[#out + 1] = tostring(okN and name or c) .. ":" .. tostring(okC and cls or "?")
        end
    end)
    C.log("comps " .. eid .. " " .. tostring(ok) .. " " .. tostring(err) .. " [" .. table.concat(out, ", ") .. "]")
    local okR, root = pcall(function() return a.RootComponent end)
    local okW, w = pcall(function() return vecStr(m(root, "K2_GetComponentLocation")) end)
    C.log("root " .. tostring(okR and root) .. " loc " .. tostring(okW and w or w))
end

local function animComp(a)
    local ok, comp = pcall(m, a, "GetComponentByClass", inzoi.UB1AnimToTexComponent)
    if ok then return comp end
    return nil, comp
end

function C.probe(eid)
    local a = C.cats[eid]
    if not a then C.log("probe: unknown cat " .. tostring(eid)); return end
    local out = { "probe " .. eid }
    local function try(label, fn)
        local ok, r = pcall(fn)
        out[#out + 1] = label .. "=" .. (ok and tostring(r) or ("ERR " .. tostring(r)))
    end
    try("class", function() return m(a, "GetName") end)
    try("dtid", function() return tostring(a.ObjectDataTableId) end)
    try("loc", function() return vecStr(m(a, "K2_GetActorLocation")) end)
    try("rot", function() local r = m(a, "K2_GetActorRotation"); return string.format("%.1f", r.Yaw) end)
    try("scale", function() return vecStr(m(a, "GetActorScale3D")) end)
    try("anim2tex", function() local c, e = animComp(a); return tostring(c) .. " " .. tostring(e) end)
    try("anim", function() local c = animComp(a); return tostring(c.Animation) end)
    try("animName", function() local c = animComp(a); return m(c.Animation, "GetName") end)
    try("skel", function() local c = animComp(a); return tostring(c.SkeletalMeshComponent) end)
    try("animPlayer", function() return tostring(m(a, "GetComponentByClass", inzoi.UB1AnimPlayerComponent)) end)
    try("UE", function() return type(UE) .. " FVector=" .. tostring(UE and UE.FVector) end)
    C.log(table.concat(out, " ; "))
end

function C.playAnim(eid, name, start)
    local a = C.cats[eid]
    if not a then C.log("anim: unknown cat " .. tostring(eid)); return end
    local c, e = animComp(a)
    if not c then C.log("anim: no AnimToTex " .. tostring(e)); return end
    local ok, err = pcall(m, c, "PlayAnimSequence", name, start or 0)
    local okN, now = pcall(function() return m(c.Animation, "GetName") end)
    C.log("anim " .. eid .. " " .. name .. " -> " .. tostring(ok) .. " " .. tostring(err) .. " now " .. tostring(okN and now))
end

-- set the actor's location; the working argument shape is found once and remembered
local variants = {
    { "loc,false,nil,true", function(a, v) return m(a, "K2_SetActorLocation", v, false, nil, true) end },
    { "loc,false,true", function(a, v) return m(a, "K2_SetActorLocation", v, false, true) end },
    { "loc", function(a, v) return m(a, "K2_SetActorLocation", v) end },
    { "SetActorLocation", function(a, v) return m(a, "SetActorLocation", v) end },
}

local function setLoc(a, v)
    if C.setVariant then return pcall(C.setVariant[2], a, v) end
    local notes = {}
    for _, var in ipairs(variants) do
        local ok, r = pcall(var[2], a, v)
        local okG, now = pcall(m, a, "K2_GetActorLocation")
        if ok and okG and math.abs(now.X - v.X) < 1 and math.abs(now.Y - v.Y) < 1 then
            C.setVariant = var
            C.log("setLoc works with " .. var[1])
            return true
        end
        notes[#notes + 1] = var[1] .. ": " .. tostring(ok) .. "/" .. tostring(r)
    end
    C.log("setLoc failed: " .. table.concat(notes, "; "))
    return false
end

function C.walk(eid, dx, dy, secs, anim, idle)
    local a = C.cats[eid]
    if not a then C.log("walk: unknown cat " .. tostring(eid)); return end
    local okL, start = pcall(m, a, "K2_GetActorLocation")
    if not okL then C.log("walk: no location " .. tostring(start)); return end
    local okR, rot = pcall(m, a, "K2_GetActorRotation")
    if okR then
        rot.Yaw = math.deg(math.atan(dy, dx))
        local ok, r = pcall(m, a, "K2_SetActorRotation", rot, true)
        C.log("rotate to " .. string.format("%.1f", rot.Yaw) .. ": " .. tostring(ok) .. " " .. tostring(r))
    end
    if anim and anim ~= "-" then C.playAnim(eid, anim, 0) end
    C.walks[eid] = { a = a, sx = start.X, sy = start.Y, sz = start.Z, dx = dx, dy = dy, secs = secs, t = 0,
        idle = idle, yaw = okR and rot.Yaw or 0 }
    C.log("walk " .. eid .. " from " .. vecStr(start) .. " by " .. dx .. "," .. dy .. " in " .. secs .. "s")
end

function C.tickWalks(dt)
    for eid, w in pairs(C.walks) do
        w.t = w.t + dt
        local f = math.min(1, w.t / w.secs)
        local okL, v = pcall(m, w.a, "K2_GetActorLocation")
        if okL then
            v.X, v.Y, v.Z = w.sx + w.dx * f, w.sy + w.dy * f, w.sz
            if not setLoc(w.a, v) then C.walks[eid] = nil end
        else
            C.walks[eid] = nil
        end
        if f >= 1 and C.walks[eid] then
            C.walks[eid] = nil
            if w.idle and w.idle ~= "-" then C.playAnim(eid, w.idle, 0) end
            local okE, e = pcall(m, w.a, "K2_GetActorLocation")
            C.log("walk done " .. eid .. " at " .. (okE and vecStr(e) or "?"))
            local payload = string.format("%.1f,%.1f,%.1f,%.1f", w.sx + w.dx, w.sy + w.dy, w.sz, w.yaw)
            local okS, err = pcall(inzoi.message.send_to_sim, eid, "pwp:setloc", payload)
            C.log("send_to_sim setloc " .. tostring(okS) .. " " .. tostring(err))
        end
    end
end

function C.scale(eid, s)
    local a = C.cats[eid]
    if not a then C.log("scale: unknown cat " .. tostring(eid)); return end
    local okS, v = pcall(m, a, "GetActorScale3D")
    if not okS then C.log("scale: get failed " .. tostring(v)); return end
    v.X, v.Y, v.Z = s, s, s
    local ok, err = pcall(m, a, "SetActorScale3D", v)
    local okN, now = pcall(m, a, "GetActorScale3D")
    C.log("scale " .. eid .. " " .. s .. ": " .. tostring(ok) .. " " .. tostring(err) .. " now " .. (okN and vecStr(now) or "?"))
end

-- ---- skeletal swap experiment ------------------------------------------------------
local function nameOf(o)
    if o == nil then return "nil" end
    local ok, n = pcall(m, o, "GetName")
    return ok and tostring(n) or tostring(o)
end

-- try several ways to load an asset by object path; returns object, how
function C.load(path)
    local notes = {}
    local tries = {
        { "UE.UObject.Load", function() return UE.UObject.Load(path) end },
        { "UE.LoadObject", function() return UE.LoadObject(path) end },
        { "KSL.LoadAsset_Blocking(path)", function()
            local K = UE.UKismetSystemLibrary
            return K.LoadAsset_Blocking(K.MakeSoftObjectPath(path))
        end },
        { "KSL.LoadAsset_Blocking(ref)", function()
            local K = UE.UKismetSystemLibrary
            return K.LoadAsset_Blocking(K.Conv_SoftObjPathToSoftObjRef(K.MakeSoftObjectPath(path)))
        end },
        { "KSL.Conv_SoftObjectReferenceToObject", function()
            local K = UE.UKismetSystemLibrary
            return K.Conv_SoftObjectReferenceToObject(K.Conv_SoftObjPathToSoftObjRef(K.MakeSoftObjectPath(path)))
        end },
    }
    for _, t in ipairs(tries) do
        local ok, r = pcall(t[2])
        if ok and r ~= nil then
            C.log("load " .. path .. " via " .. t[1] .. " -> " .. nameOf(r))
            return r, t[1]
        end
        notes[#notes + 1] = t[1] .. ": " .. tostring(r)
    end
    C.log("load failed " .. path .. " :: " .. table.concat(notes, " ; "))
    return nil
end

local function comp(a, name)
    local list = m(a, "K2_GetComponentsByClass", UE.UActorComponent)
    local n = list.Num and list:Num() or #list
    for i = 1, n do
        local c = list[i]
        local ok, cn = pcall(m, c, "GetName")
        if ok and cn == name then return c end
    end
    return nil
end

function C.skel(eid)
    local a = C.cats[eid]
    local out = { "skel " .. tostring(eid) }
    local function try(label, fn)
        local ok, r = pcall(fn)
        out[#out + 1] = label .. "=" .. (ok and tostring(r) or ("ERR " .. tostring(r)))
    end
    local sk = comp(a, "SkeletalMeshComponent_B1AnimToTex")
    try("mesh", function() return nameOf(m(sk, "GetSkeletalMeshAsset")) end)
    try("meshProp", function() return nameOf(sk.SkeletalMesh) end)
    try("visible", function() return tostring(m(sk, "IsVisible")) end)
    try("animMode", function() return tostring(m(sk, "GetAnimationMode")) end)
    try("nmat", function() return tostring(m(sk, "GetNumMaterials")) end)
    local st = comp(a, "StaticMesh")
    try("static", function() return nameOf(m(st, "GetStaticMesh" ) or st.StaticMesh) end)
    try("staticVisible", function() return tostring(m(st, "IsVisible")) end)
    try("staticMat0", function() return nameOf(m(st, "GetMaterial", 0)) end)
    C.log(table.concat(out, " ; "))
end

-- show the skeletal dummy with the given mesh, hide the VAT meshes, loop an animation on it
function C.skelPlay(eid, animPath, meshPath)
    local a = C.cats[eid]
    if not a then C.log("skelplay: unknown cat"); return end
    local sk = comp(a, "SkeletalMeshComponent_B1AnimToTex")
    local st, fur = comp(a, "StaticMesh"), comp(a, "StaticMeshFur")
    local function step(label, fn)
        local ok, r = pcall(fn)
        C.log("skelplay " .. label .. ": " .. tostring(ok) .. " " .. tostring(r))
        return ok, r
    end
    if meshPath and meshPath ~= "-" then
        local mesh = C.load(meshPath)
        if mesh then step("SetSkeletalMeshAsset", function() return m(sk, "SetSkeletalMeshAsset", mesh) end) end
    end
    local anim = C.load(animPath)
    if not anim then return end
    step("SetVisibility(sk)", function() return m(sk, "SetVisibility", true, false) end)
    step("SetHiddenInGame(sk)", function() return m(sk, "SetHiddenInGame", false, false) end)
    step("hide static", function() return m(st, "SetVisibility", false, false) end)
    step("hide fur", function() return m(fur, "SetVisibility", false, false) end)
    step("PlayAnimation", function() return m(sk, "PlayAnimation", anim, true) end)
    step("now visible", function() return m(sk, "IsVisible") end)
end

function C.vatBack(eid)
    local a = C.cats[eid]
    local sk = comp(a, "SkeletalMeshComponent_B1AnimToTex")
    local st, fur = comp(a, "StaticMesh"), comp(a, "StaticMeshFur")
    local r1 = pcall(m, sk, "SetVisibility", false, false)
    local r2 = pcall(m, st, "SetVisibility", true, false)
    local r3 = pcall(m, fur, "SetVisibility", true, false)
    C.log("vatback " .. tostring(r1) .. tostring(r2) .. tostring(r3))
end

local function words(s)
    local t = {}
    for w in s:gmatch("%S+") do t[#t + 1] = w end
    return t
end

function C.run(line)
    local w = words(line)
    local verb = w[1]
    local eid = tonumber(w[2])
    if verb == "list" then
        local ids = {}
        for id in pairs(C.cats) do ids[#ids + 1] = tostring(id) end
        C.log("cats: " .. table.concat(ids, ","))
    elseif verb == "probe" then C.probe(eid)
    elseif verb == "comps" then C.comps(eid)
    elseif verb == "watch" then C.watch(eid, tonumber(w[3]))
    elseif verb == "skel" then C.skel(eid)
    elseif verb == "load" then C.load(w[2])
    elseif verb == "skelplay" then C.skelPlay(eid, w[3], w[4])
    elseif verb == "vatback" then C.vatBack(eid)
    elseif verb == "stopanim" then
        local a = C.cats[eid]
        local c = a and animComp(a)
        local ok, err = pcall(m, c, "StopAnimSquence")
        C.log("stopanim " .. tostring(ok) .. " " .. tostring(err))
    elseif verb == "anim" then C.playAnim(eid, w[3], tonumber(w[4]) or 0)
    elseif verb == "walk" then C.walk(eid, tonumber(w[3]), tonumber(w[4]), tonumber(w[5]), w[6], w[7])
    elseif verb == "scale" then C.scale(eid, tonumber(w[3]))
    elseif verb == "b2" then
        local payload = table.concat(w, " ", 4)
        local ok, err = pcall(inzoi.message.send_to_sim, eid, "pwp:" .. w[3], payload)
        C.log("send_to_sim " .. w[3] .. " " .. payload .. ": " .. tostring(ok) .. " " .. tostring(err))
    else
        C.log("unknown command " .. tostring(line))
    end
end

-- watch: log the cat's current VAT animation name whenever it changes, for some seconds
C.watches = {}
function C.watch(eid, secs)
    C.watches[eid] = { left = secs or 20, last = "?" }
    C.log("watch " .. tostring(eid) .. " for " .. tostring(secs))
end

local function tickWatches(dt)
    for eid, w in pairs(C.watches) do
        w.left = w.left - dt
        local a = C.cats[eid]
        local name = "nil"
        if a then
            local ok, n = pcall(function()
                local c = animComp(a)
                if c == nil then return "nocomp" end
                local anim = c.Animation
                if anim == nil then return "nil" end
                return m(anim, "GetName")
            end)
            name = ok and tostring(n) or ("ERR " .. tostring(n))
        end
        if name ~= w.last then
            w.last = name
            local okL, loc = pcall(m, a, "K2_GetActorLocation")
            C.log("watch " .. eid .. " anim=" .. name .. " loc " .. (okL and vecStr(loc) or "?"))
        end
        if w.left <= 0 then C.watches[eid] = nil; C.log("watch " .. eid .. " done") end
    end
end

function C.tick(dt)
    C.t = C.t + dt
    C.tickWalks(dt)
    tickWatches(dt)
    C.poll = C.poll + dt
    if C.poll < 0.5 then return end
    C.poll = 0
    local ok, success, _, data = pcall(inzoi.cli.execute, "uimod.cfg_load mod_id=" .. MOD .. " section=cmd key=next")
    if not ok or not success or type(data) ~= "string" then return end
    local value = data:match('"value"%s*:%s*"(.-)"%s*[,}]')
    if not value then return end
    local seq, line = value:match("^(%d+);(.*)$")
    seq = tonumber(seq)
    if not seq then return end
    if C.seq == nil then C.seq = seq; C.log("first command seq " .. seq .. " skipped"); return end
    if seq == C.seq then return end
    C.seq = seq
    local okR, err = pcall(C.run, line)
    if not okR then C.log("command failed: " .. tostring(err)) end
end

return C
