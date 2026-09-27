loadstring([=====[
-- AutoSkills / Void bootstrap (compact build)
local __AUTOSKILLS_SOURCE = [====[

local Settings = {
    BossAutoSave = true, BossFirstDiscovery = false, BossGridSearch = true,
    BossDwell = 1.5, BossGridRadius = 2048,
    AutoBoss = false, BossAutoRange = 500000, BossLocalScanRadius = 2500, BossNoAttackTimeout = 5,
    GuardianDamageTimeout = 0.75, GuardianStuckTimeout = 6, GuardianCombatStallTimeout = 25,
    GuardianVerifyInterval = 1.0, GuardianMaxRecoveries = 1,
    StaticMapScan = true, StaticScanRange = 500000,
    AutoRejoin = true, AutoExecute = true,
    PrivateServerMap = "Ouwigahara", PrivateJoinHold = 1.35,
    NoClip = true, FlyEnabled = false, FlySpeed = 85,
    SpeedEnabled = false, WalkSpeed = 32,
    ToggleKey = Enum.KeyCode.F6,
    StopKey = Enum.KeyCode.F7,
    VisibilityKey = Enum.KeyCode.RightShift,
    ESPToggleKey = Enum.KeyCode.F8,
    HealthToggleKey = Enum.KeyCode.F9,
    HoldTime = 0.05, KeyGap = 0.15,
    PauseWhileTyping = true, PauseWhenUnfocused = true,
    ESPEnabled = false, ESPShowNames = true, ESPShowDistance = true,
    ESPShowHealth = true, ESPThroughWalls = true, ESPHideTeammates = false,
    ESPMaxDistance = 2500,
    HealthLock = true, FarmEnabled = false, FarmDepth = 7, FarmHealthOnly = true,
    FarmMinHP = 3000, FarmMaxHP = 3200,
    FarmM1 = true, FarmAutoLoot = true,
    FarmUseSkills = true, FarmExpandHitbox = false, FarmHitboxSize = 16,
    HealthEscapeEnabled = false, HealthThreshold = 30, HealthSource = "Auto",
    UICompact = false, UIOpacity = 1, UIScale = 1, NotificationsEnabled = true,
    SafetyEnabled = true, SafetyStuckTimeout = 8, SafetyAutoRecover = true,
    SafetyPauseOnUnexpected = true, StatsEnabled = true,
}

local CustomHealthReader = false
local Skills = {
    {name = "Z", key = Enum.KeyCode.Z, enabled = true},
    {name = "X", key = Enum.KeyCode.X, enabled = true},
    {name = "C", key = Enum.KeyCode.C, enabled = true},
    {name = "V", key = Enum.KeyCode.V, enabled = true},
}
local Input = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local World = game:GetService("Workspace")
local Player = Players.LocalPlayer
local virtualUserOK, VirtualUser = pcall(function()
    return game:GetService("VirtualUser")
end)
local serviceOK, VirtualInput = pcall(function()
    return game:GetService("VirtualInputManager")
end)
if not serviceOK or not Player then
    warn("AutoSkills: the required Roblox client input service is unavailable.")
    return
end
local playerGui = Player:WaitForChild("PlayerGui")

local environment = type(getgenv) == "function" and getgenv() or _G
local slot = "__AutoSkills_ZXCVB"
local previous = environment[slot]
if type(previous) == "table" and type(previous.Stop) == "function" then previous.Stop() end

local State = {
    alive = true, enabled = false, focused = true, minimized = false,
    heldKey = nil, lastKey = nil, fault = nil, gesture = nil,
    tab = "Skills", espCount = 0, espFault = nil,
    uiScaleTarget = 1.0,
    visibilityTween = nil, visibilityX = nil, visibilityY = nil,
    miniMode = false, miniTween = nil, miniX = nil, miniY = nil,
}
local connections, tweens = {}, setmetatable({}, {__mode = "k"})
local controller, UI = {}, {}
local MiniMode = {}
local render = function() end
local clearESP = function() end
local stopHealthGuard = function() end
local stopFarm = function() end
local stopMovement = function() end
local pauseFarmForEscape = function() end
local root
local loaderRoot

environment[slot] = controller
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    connections[#connections + 1] = connection
    return connection
end

if virtualUserOK and VirtualUser then
    connect(Player.Idled, function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end)
end

local function notify(message)
    print("AutoSkills: " .. message)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "AutoSkills / Void", Text = message, Duration = 3,
        })
    end)
end
local function releaseKey()
    local key = State.heldKey
    State.heldKey = nil
    if key then
        return pcall(function() VirtualInput:SendKeyEvent(false, key, false, game) end)
    end
    return true
end
function controller.Stop()
    if not State.alive then return end
    if MiniMode and MiniMode.hide then pcall(MiniMode.hide) end
    -- IMPORTANT: do not persist the theme from Stop().
    -- Re-execution calls the OLD instance's Stop() before the NEW bootstrap
    -- resolves the saved theme. If the old instance is stale (for example
    -- Blackhole), saving here can overwrite a newer EMPYREAN selection.
    -- Theme persistence happens immediately inside UI.setTheme/System.savePrefs.
    State.alive, State.enabled = false, false
    State.gesture = nil
    stopFarm()
    stopHealthGuard()
    stopMovement()
    clearESP()
    local released, err = releaseKey()
    if not released then warn("AutoSkills: key release failed: " .. tostring(err)) end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for _, tween in pairs(tweens) do tween:Cancel() end
    if root then root:Destroy() end
    if loaderRoot then loaderRoot:Destroy() end
    if environment[slot] == controller then environment[slot] = nil end
end
local function inputFault(err)
    State.enabled = false
    State.fault = "Virtual input unavailable. Check your Lua runner."
    local released, releaseError = releaseKey()
    if not released then warn("AutoSkills: " .. tostring(releaseError)) end
    warn("AutoSkills: " .. tostring(err))
    render()
    notify("Input stopped. Check your runner; then toggle on to retry.")
end
local function releaseOrPause()
    local released, err = releaseKey()
    if not released then inputFault(err) end
    render()
end
local function selectedCount()
    local count = 0
    for _, skill in ipairs(Skills) do
        if skill.enabled then count = count + 1 end
    end
    return count
end

local function isChatTextBox(box)
    if not box then return false end
    local node = box
    for _ = 1, 10 do
        if not node then break end
        local name = string.lower(tostring(node.Name or ""))
        if name:find("chat", 1, true)
            or name:find("message", 1, true)
            or name:find("textchat", 1, true)
            or name:find("chatbar", 1, true)
            or name:find("chatinput", 1, true) then
            return true
        end
        node = node.Parent
    end
    return false
end

local function shouldPauseForTextEntry()
    return Settings.PauseWhileTyping and isChatTextBox(Input:GetFocusedTextBox())
end

local function availability()
    if State.discovering then return false, "DISCOVERING", "Skills paused during location discovery." end
    if State.fault then return false, "INPUT ERROR", State.fault end
    if not State.enabled and not (State.farming and Settings.FarmUseSkills) then return false, "STANDBY", "Choose your keys, then turn Auto skills on." end
    if selectedCount() == 0 then return false, "NO KEYS", "Enable at least one skill to begin." end
    if shouldPauseForTextEntry() then
        return false, "PAUSED", "Chat typing detected. Resumes when chat closes."
    end

    if State.gesture then return false, "PAUSED", "Adjusting controls. Resumes when released." end
    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false, "WAITING", "Waiting for your character to spawn."
    end
    return true, "RUNNING", "Repeating selected keys. Last input: " .. (State.lastKey or "--")
end
local function setEnabled(value)
    if not State.alive then return end
    State.enabled = value
    if value then State.fault = nil else releaseOrPause() end
    render()
end

local Guard = {
    sources = {}, source = nil, character = nil, nextScan = 0,
    current = nil, maximum = nil, percent = nil, latched = false,
    lastTeleport = -math.huge, count = 0, busy = false, fault = nil,
    status = "OFF", detail = "Choose a health source, then enable Health escape.",
    sourceLabel = "Auto", sourceDetail = "Waiting for health data.",
}
do
    function Guard.release()
        local held = Guard.held
        Guard.held = nil
        if held then pcall(function() held.root.Anchored = held.anchored end) end
    end
    function Guard.setLock(value)
        Settings.HealthLock = value
        if not value then Guard.release() end
        Guard.step()
    end
    local sourceConnections, bound = {}, nil
    local pairsToCheck = {
        {"health", "maxhealth"}, {"currenthealth", "maxhealth"},
        {"health", "maximumhealth"}, {"currenthealth", "maximumhealth"},
        {"hp", "maxhp"}, {"currenthp", "maxhp"},
        {"hitpoints", "maxhitpoints"}, {"currenthitpoints", "maxhitpoints"},
    }
    local containers = {
        stats = true, data = true, playerdata = true, playerstats = true,
        characterstats = true, vitals = true, health = true, combat = true,
        status = true, values = true, leaderstats = true, attributes = true,
        resources = true,
    }
    local function normalized(name) return string.lower(name):gsub("[%s_]", "") end
    local function finite(value)
        return type(value) == "number" and value == value and math.abs(value) < math.huge
    end
    local function valid(current, maximum)
        return finite(current) and finite(maximum) and current >= 0 and maximum > 0
    end
    local function disconnectSource()
        for _, connection in ipairs(sourceConnections) do connection:Disconnect() end
        sourceConnections, bound = {}, nil
    end
    local function bindSource(source)
        if bound and source and bound.id == source.id and bound.owner == source.owner
            and bound.currentObject == source.currentObject and bound.maxObject == source.maxObject then
            return
        end
        disconnectSource()
        if not source then return end
        bound = source
        local function watch(signal)
            sourceConnections[#sourceConnections + 1] = signal:Connect(function()
                Guard.step()
            end)
        end
        if source.kind == "humanoid" then
            watch(source.owner.HealthChanged)
            watch(source.owner:GetPropertyChangedSignal("MaxHealth"))
        elseif source.kind == "attributes" then
            watch(source.owner:GetAttributeChangedSignal(source.currentKey))
            watch(source.owner:GetAttributeChangedSignal(source.maxKey))
        elseif source.kind == "values" then
            watch(source.currentObject:GetPropertyChangedSignal("Value"))
            watch(source.maxObject:GetPropertyChangedSignal("Value"))
        end
    end
    local function readSource(source)
        if not source then return nil, nil end
        if source.kind == "adapter" then
            local character = Player.Character
            return CustomHealthReader(Player, character,
                character and character:FindFirstChildOfClass("Humanoid"))
        end
        local owner = source.owner
        if not owner or (owner ~= Player and not owner.Parent) then return nil, nil end
        if source.kind == "humanoid" then return owner.Health, owner.MaxHealth end
        if source.kind == "attributes" then
            return owner:GetAttribute(source.currentKey), owner:GetAttribute(source.maxKey)
        end
        if source.currentObject.Parent ~= owner or source.maxObject.Parent ~= owner then return nil, nil end
        return source.currentObject.Value, source.maxObject.Value
    end
    function Guard.refreshSources(force)
        local character = Player.Character
        if Guard.character ~= character then
            Guard.release()
            Guard.character, Guard.latched = character, false
            Guard.lastTeleport, Guard.nextScan = -math.huge, 0
            disconnectSource()
        end
        if not force and os.clock() < Guard.nextScan then return end
        Guard.nextScan = os.clock() + 1
        local found, visited, visitedCount = {}, {}, 0
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            found[#found + 1] = {id = "Humanoid", label = "Humanoid", kind = "humanoid",
                owner = humanoid, detail = "Live Humanoid.Health / MaxHealth"}
        end
        local function scan(owner, path, depth)
            if not owner or visited[owner] or visitedCount >= 32 then return end
            visited[owner], visitedCount = true, visitedCount + 1
            local attributes, values = {}, {}
            for name, value in pairs(owner:GetAttributes()) do
                if finite(value) then attributes[normalized(name)] = name end
            end
            local children = owner:GetChildren()
            for _, child in ipairs(children) do
                if child:IsA("NumberValue") or child:IsA("IntValue") then
                    values[normalized(child.Name)] = child
                end
            end
            for _, pair in ipairs(pairsToCheck) do
                local currentKey, maxKey = attributes[pair[1]], attributes[pair[2]]
                if currentKey and maxKey then
                    found[#found + 1] = {
                        id = path .. ":attributes:" .. currentKey .. "/" .. maxKey,
                        label = path .. " (attributes)", detail = currentKey .. " / " .. maxKey,
                        kind = "attributes", owner = owner, currentKey = currentKey, maxKey = maxKey,
                    }
                end
                local currentObject, maxObject = values[pair[1]], values[pair[2]]
                if currentObject and maxObject then
                    found[#found + 1] = {
                        id = path .. ":values:" .. currentObject.Name .. "/" .. maxObject.Name,
                        label = path .. " (values)", detail = currentObject.Name .. " / " .. maxObject.Name,
                        kind = "values", owner = owner, currentObject = currentObject, maxObject = maxObject,
                    }
                end
            end

            if depth < 3 then
                for _, child in ipairs(children) do
                    if containers[normalized(child.Name)] and (child:IsA("Folder")
                        or child:IsA("Configuration") or child:IsA("Model")) then
                        scan(child, path .. "." .. child.Name, depth + 1)
                    end
                end
            end
        end
        scan(character, "Character", 0)
        scan(humanoid, "Humanoid", 0)
        scan(Player, "Player", 0)
        if type(CustomHealthReader) == "function" then
            found[#found + 1] = {id = "Adapter", label = "Game adapter", kind = "adapter",
                detail = "CustomHealthReader: current / maximum health"}
        end
        table.sort(found, function(a, b)
            if a.id == "Humanoid" then return b.id ~= "Humanoid" end
            if b.id == "Humanoid" then return false end
            return a.id < b.id
        end)
        Guard.sources = found
        local selected
        if Settings.HealthSource == "Auto" then

            if found[1] and found[1].id == "Humanoid" then selected = found[1]
            elseif #found == 1 then selected = found[1] end
        else
            for _, source in ipairs(found) do
                if source.id == Settings.HealthSource then selected = source; break end
            end
        end
        Guard.source = selected
        Guard.sourceLabel = Settings.HealthSource == "Auto" and (selected and "Auto - " .. selected.label or "Auto")
            or (selected and selected.label or "Selected source unavailable")
        Guard.sourceDetail = selected and selected.detail
            or (#found > 1 and Settings.HealthSource == "Auto" and "Multiple custom sources. Select one with the arrows."
                or "No matching source. Rescan or supply a game adapter.")
        bindSource(selected)
    end
    local function update()
        Guard.refreshSources(false)
        local ok, current, maximum = pcall(readSource, Guard.source)
        local hasHealth = ok and valid(current, maximum)
        Guard.current, Guard.maximum, Guard.percent = nil, nil, nil
        if hasHealth then
            Guard.current, Guard.maximum = current, maximum
            Guard.percent = math.clamp(current / maximum * 100, 0, 100)
        end
        if Guard.fault then
            Guard.status, Guard.detail = "ERROR", Guard.fault
            return
        end
        if not Settings.HealthEscapeEnabled then
            Guard.status, Guard.detail = "OFF", "Check the live health, then enable Health escape."
            return
        end
        if not hasHealth then
            Guard.release()
            Guard.status, Guard.detail = "NO DATA", "No valid current / maximum health. Check the source."
            return
        end
        local character = Player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local rootPart = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
        if not character or not character.Parent or not rootPart or not rootPart:IsA("BasePart") then
            Guard.release()
            Guard.status, Guard.detail = "WAITING", "Waiting for your character and root part."
            return
        end
        if current <= 0 or (humanoid and humanoid.Health <= 0) then
            Guard.release()
            Guard.status, Guard.detail = "DEAD", "Waiting for a living character."
            return
        end
        if Guard.held then
            if Guard.held.root ~= rootPart then Guard.release()
            else
                rootPart.Anchored = true
                character:PivotTo(Guard.held.pivot)
                Guard.status, Guard.detail = "LOCKED", "Holding escape position. Release or turn escape off to move."
                return
            end
        end
        if rootPart.Anchored or (humanoid and (humanoid.SeatPart or humanoid.Sit)) then
            Guard.status, Guard.detail = "WAITING", "Stand up and wait for your character to move freely."
            return
        end
        local threshold = math.clamp(Settings.HealthThreshold, 1, 95)
        local rearmAt = threshold + 5
        if Guard.latched and Guard.percent >= rearmAt then Guard.latched = false end
        if Guard.latched then
            Guard.status, Guard.detail = "RECOVER", string.format("Escaped. Heal to %.0f%% to re-arm.", rearmAt)
            return
        end
        local remaining = 5 - (os.clock() - Guard.lastTeleport)
        if remaining > 0 then
            Guard.status, Guard.detail = "COOLDOWN", string.format("Next escape available in %.1f seconds.", remaining)
            return
        end
        Guard.status, Guard.detail = "ARMED", string.format("Teleports +70 studs at or below %.0f%% health.", threshold)
        if Guard.percent > threshold then return end

        if not State.alive or not Settings.HealthEscapeEnabled or character ~= Guard.character then return end
        Guard.latched, Guard.lastTeleport = true, os.clock()

        character:PivotTo(character:GetPivot() + Vector3.new(0, 70, 0))
        if System and type(System.recordTeleport) == "function" then
            pcall(function() System.recordTeleport("Health Escape", 70, true) end)
        end
        pauseFarmForEscape()
        if Settings.HealthLock then
            Guard.held = {root = rootPart, anchored = rootPart.Anchored, pivot = character:GetPivot()}
            rootPart.Anchored = true
        end

        pcall(function()
            local velocity = rootPart.AssemblyLinearVelocity
            rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
        end)
        Guard.count = Guard.count + 1
        Guard.status, Guard.detail = Settings.HealthLock and "LOCKED" or "ESCAPED", string.format("Moved up 70 studs. Heal to %.0f%% to re-arm.", rearmAt)
    end
    function Guard.step()
        if not State.alive or Guard.busy then return end
        Guard.busy = true
        local ok, err = pcall(update)
        Guard.busy = false
        if not ok then
            Guard.release()
            Settings.HealthEscapeEnabled = false
            Guard.fault = "Health escape stopped. Toggle on to retry."
            Guard.status, Guard.detail = "ERROR", Guard.fault
            warn("AutoSkills Health Escape: " .. tostring(err))
        end
        render()
    end
    function Guard.setEnabled(value)
        if not State.alive then return end
        if not value then Guard.release() end
        Settings.HealthEscapeEnabled, Guard.fault = value, nil
        if value then Guard.latched = false end
        Guard.nextScan = 0
        Guard.step()
    end
    function Guard.cycleSource(direction)
        Guard.refreshSources(true)
        local index = 0
        for i, source in ipairs(Guard.sources) do
            if source.id == Settings.HealthSource then index = i; break end
        end
        index = (index + direction) % (#Guard.sources + 1)
        Settings.HealthSource = index == 0 and "Auto" or Guard.sources[index].id

        Guard.setEnabled(false)
    end
    stopHealthGuard = function()
        Guard.release()
        Settings.HealthEscapeEnabled = false
        disconnectSource()
        Guard.sources, Guard.source, Guard.character = {}, nil, nil
    end
end

local System
local CoreUI
local showPage
local BUILT_IN_BOSS_SEED_CODE = "__AUTOSKILLS_BOSS_SEED_PLACEHOLDER__"
local Farm = {catalog = {}, remembered = {}, pinned = nil, records = {}, selected = nil, nextScan = 0, status = "OFF",
    detail = "Select a target, then enable Auto farm.", count = 0, aliveCount = 0,
    autoVisited = {}, autoCurrent = nil, autoLastPath = nil, autoArrivedAt = 0,
    autoCombatAt = 0, autoLastProgressAt = 0, autoLastHP = nil, autoDefeated = false,
    autoRespawnResume = false, autoResumePath = nil,
    autoCycles = 0, autoSkipped = 0, travelHealth = nil,
    guardian = {lastHealth = nil, damageSince = 0, damageBase = nil, lastPosition = nil,
        lastPositionAt = 0, stuckSince = 0, lostSince = 0, verifyAt = 0, recoveries = 0,
        lastAction = "STANDBY", lastActionAt = 0, dangerPaths = {}}
}
local function attackHealthAllowed(maximum)
    return type(maximum) == "number"
        and maximum == maximum
        and maximum >= Settings.FarmMinHP
        and maximum <= Settings.FarmMaxHP
end

do
    local place = tostring(game.PlaceId or 0)
    Farm.configPath = "AutoSkills_BossLocations_" .. place .. "_v1.json"
    Farm.markers = {}
    Farm.configStatus, Farm.discoveryStatus = "Session only", "Not started"
    local reader = type(readfile)=="function" and readfile or environment.readfile
    local writer = type(writefile)=="function" and writefile or environment.writefile
    local exists = type(isfile)=="function" and isfile or environment.isfile
    local okHTTP, HTTP = pcall(function() return game:GetService("HttpService") end)
    Farm.canSave = okHTTP and type(reader)=="function" and type(writer)=="function" and type(exists)=="function"
    local dirty, nextSave, validBytes, revision = false, 0, nil, 0
    local function finite(n) return type(n)=="number" and n==n and math.abs(n)<10000000 end
    local function pack(v) return v and {v.X,v.Y,v.Z} or nil end
    local function unpackPosition(v)
        if type(v)=="table" and finite(v[1]) and finite(v[2]) and finite(v[3]) then
            return Vector3.new(v[1],v[2],v[3])
        end
    end
    local function short(s,n) return type(s)=="string" and #s>0 and #s<=(n or 200) end
    function Farm.markDirty() dirty=true; revision=revision+1 end
    local aliases={"enru","akazo","datai","gyorei","gyutai","nezura","nezurai","tengai","zentaro","rengu","giyen"}
    function Farm.bossKey(name)
        name=string.lower(tostring(name or ""))
        for _, alias in ipairs(aliases) do
            if name:find("%f[%a]"..alias.."%f[%A]") then return alias=="nezurai" and "nezura" or alias end
        end
        return (name:gsub("[^%w]",""))
    end
    local function decode(bytes)
        if type(bytes)~="string" or #bytes>2000000 then error("Config is too large or unreadable") end
        local data=HTTP:JSONDecode(bytes)
        if type(data)~="table" or data.schema~=1 or tostring(data.placeId)~=place
            or type(data.bosses)~="table" or type(data.options)~="table" then error("Invalid config or different place") end
        return data
    end
    if Farm.canSave then
        local hadFile, data = false, nil
        for _, file in ipairs({Farm.configPath,Farm.configPath..".bak"}) do
            local ok, present=pcall(exists,file)
            if ok and present then
                hadFile=true
                local loaded, parsed, bytes=pcall(function() local b=reader(file);return decode(b),b end)
                if loaded then
                    data,validBytes=parsed,bytes
                    Farm.configStatus=file==Farm.configPath and "Loaded saved locations" or "Recovered backup"
                    break
                end
            end
        end
        if data then
            Farm.hadConfig=true
            for _, key in ipairs({"BossAutoSave","BossFirstDiscovery","BossGridSearch"}) do
                if type(data.options[key])=="boolean" then Settings[key]=data.options[key] end
            end
            if finite(data.options.BossDwell) then Settings.BossDwell=math.clamp(data.options.BossDwell,1,5) end
            if finite(data.options.BossGridRadius) then Settings.BossGridRadius=math.clamp(data.options.BossGridRadius,512,8192) end
            for i, entry in ipairs(data.bosses) do
                if i>512 then break end
                if type(entry)=="table" and short(entry.path,512) and short(entry.name)
                    and (entry.maximum==nil or (finite(entry.maximum) and entry.maximum>0)) then
                    local spawn=unpackPosition(entry.spawn)
                    if spawn then
                        Farm.catalog[entry.path]={path=entry.path,name=entry.name,id="Saved location",spawn=spawn,
                            position=unpackPosition(entry.position) or spawn,maximum=entry.maximum,
                            rigPath=short(entry.rigPath,512) and entry.rigPath or nil}
                    end
                end
            end
            for i, entry in ipairs(type(data.markers)=="table" and data.markers or {}) do
                if i>512 then break end
                if type(entry)=="table" and short(entry.key,160) then
                    local position=unpackPosition(entry.position)
                    if position then Farm.markers[entry.key]={key=entry.key,position=position,
                        name=short(entry.name) and entry.name or nil} end
                end
            end
        elseif hadFile then
            Farm.saveBlocked=true; Farm.hadConfig=true
            Farm.configStatus="Invalid save; preserved. Session only."
        else Farm.configStatus="Ready to autosave" end
    else Farm.configStatus="File access unavailable; session only" end
    function Farm.saveConfig(force, optionsOnly, manual)
        if not Farm.canSave or Farm.saveBlocked or Farm.saving then return end
        if not optionsOnly and not manual and (not Settings.BossAutoSave or not dirty) then return end
        if not force and os.clock()<nextSave then return end
        nextSave=os.clock()+5
        local bosses,markers={},{}
        for _, entry in pairs(Farm.catalog) do
            if entry.spawn and #bosses<512 then
                bosses[#bosses+1]={path=entry.path,name=entry.name,maximum=entry.maximum,
                    spawn=pack(entry.spawn),position=pack(entry.position),rigPath=entry.rigPath}
            end
        end
        for _, entry in pairs(Farm.markers) do
            if #markers<512 then markers[#markers+1]={key=entry.key,name=entry.name,position=pack(entry.position)} end
        end

        if optionsOnly and not Settings.BossAutoSave then
            if validBytes then local previous=decode(validBytes);bosses,markers=previous.bosses,previous.markers or {}
            else bosses,markers={},{} end
        end
        local savedRevision=revision
        Farm.saving=true
        local ok,err=pcall(function()
            local bytes=HTTP:JSONEncode({schema=1,placeId=place,bosses=bosses,markers=markers,
                options={BossAutoSave=Settings.BossAutoSave,BossFirstDiscovery=Settings.BossFirstDiscovery,
                    BossGridSearch=Settings.BossGridSearch,BossDwell=Settings.BossDwell,BossGridRadius=Settings.BossGridRadius}})
            if validBytes then writer(Farm.configPath..".bak",validBytes) end
            writer(Farm.configPath,bytes)
            validBytes=bytes
        end)
        Farm.saving=false
        if ok then
            if (Settings.BossAutoSave or manual) and revision==savedRevision then dirty=false end
            Farm.configStatus=(Settings.BossAutoSave or manual) and ("Saved "..#bosses.." bosses / "..#markers.." markers") or "Autosave OFF; existing save retained"
        else
            Farm.configStatus="Save failed; locations remain in this session"
            warn("AutoSkills config: "..tostring(err))
        end
    end
    function Farm.setConfig(key,value)
        Settings[key]=value
        if key=="BossFirstDiscovery" and not value then Farm.pendingDiscovery=false end
        Farm.markDirty(); Farm.saveConfig(true,true); render()
    end

    local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local values={};for i=1,#alphabet do values[alphabet:sub(i,i)]=i-1 end
    local function encode64(bytes)
        local out={}
        for i=1,#bytes,3 do
            local a,b,c=bytes:byte(i,i+2);b=b or 0;c=c or 0
            local n=a*65536+b*256+c
            local x=math.floor(n/262144)%64;local y=math.floor(n/4096)%64
            local z=math.floor(n/64)%64;local w=n%64
            out[#out+1]=alphabet:sub(x+1,x+1)..alphabet:sub(y+1,y+1)
                ..(i+1<=#bytes and alphabet:sub(z+1,z+1) or "=")
                ..(i+2<=#bytes and alphabet:sub(w+1,w+1) or "=")
        end
        return table.concat(out)
    end
    local function decode64(text)
        if #text==0 or #text%4~=0 or text:find("[^%w+/=]") then error("Invalid or incomplete code") end
        local out={}
        for i=1,#text,4 do
            local a,b,c,d=text:sub(i,i),text:sub(i+1,i+1),text:sub(i+2,i+2),text:sub(i+3,i+3)
            if not values[a] or not values[b] or (c~="=" and not values[c]) or (d~="=" and not values[d])
                or (c=="=" and d~="=") or ((c=="=" or d=="=") and i+3~=#text) then error("Invalid code padding") end
            local n=values[a]*262144+values[b]*4096+(values[c] or 0)*64+(values[d] or 0)
            out[#out+1]=string.char(math.floor(n/65536)%256)
            if c~="=" then out[#out+1]=string.char(math.floor(n/256)%256) end
            if d~="=" then out[#out+1]=string.char(n%256) end
        end
        return table.concat(out)
    end
    local function checksum(text)
        local a,b=1,0
        for i=1,#text do a=(a+text:byte(i))%65521;b=(b+a)%65521 end
        return string.format("%08x",b*65536+a)
    end
    local function array(value)
        if type(value)~="table" or #value>512 then error("Invalid location list (maximum 512)") end
        local count=0
        for key in pairs(value) do
            if type(key)~="number" or key%1~=0 or key<1 or key>#value then error("Invalid list entry") end
            count=count+1
        end
        if count~=#value then error("Incomplete location list") end
        return value
    end
    local function safeText(value,limit)
        return short(value,limit) and not value:find("[%z\1-\31\127]")
    end
    function Farm.exportCode()
        if not okHTTP then return nil,"JSON service unavailable" end
        Farm.scan(true)
        local bosses,markers={},{}
        for _,entry in pairs(Farm.catalog) do
            if entry.spawn then bosses[#bosses+1]={path=entry.path,name=entry.name,maximum=entry.maximum,
                spawn=pack(entry.spawn),position=pack(entry.spawn)} end
        end
        for _,entry in pairs(Farm.markers) do
            markers[#markers+1]={key=entry.key,name=entry.name,position=pack(entry.position)}
        end
        if #bosses+#markers==0 then return nil,"No locations to export yet" end
        if #bosses>512 or #markers>512 then return nil,"Too many locations to export (512 per list)" end
        table.sort(bosses,function(a,b) return a.path<b.path end)
        table.sort(markers,function(a,b) return a.key<b.key end)
        local ok,bytes=pcall(function() return HTTP:JSONEncode({format="AutoSkillsLocations",schema=1,
            placeId=place,bosses=bosses,markers=markers}) end)
        if not ok then return nil,"Could not encode locations" end
        if #bytes>500000 then return nil,"Location code exceeds size limit" end
        return "ASLOC1:"..checksum(bytes)..":"..encode64(bytes),"Exported "..#bosses.." bosses and "..#markers.." markers"
    end
    function Farm.importCode(code)
        if not okHTTP then return false,"JSON service unavailable" end
        local ok,result=pcall(function()
            if type(code)~="string" or #code>800000 then error("Code is missing or too large") end
            code=code:gsub("%s","")
            local digest,payload=code:match("^ASLOC1:([%da-fA-F]+):(.+)$")
            if not digest or #digest~=8 then error("Paste the complete ASLOC1 code") end
            local bytes=decode64(payload)
            if #bytes>500000 or checksum(bytes)~=digest:lower() then error("Code damaged or incomplete; copy it again") end
            local data=HTTP:JSONDecode(bytes)
            if type(data)~="table" or data.format~="AutoSkillsLocations" or data.schema~=1 then error("Unsupported location code") end
            if tostring(data.placeId)~=place then error("This code belongs to a different Roblox place") end
            local bosses,markers={},{}
            for _,entry in ipairs(array(data.bosses)) do
                if type(entry)~="table" or not safeText(entry.path,512) or not safeText(entry.name,200)
                    or (entry.maximum~=nil and (not finite(entry.maximum) or entry.maximum<=0)) then error("Invalid boss data") end
                local position=unpackPosition(entry.spawn)
                if not position then error("Invalid boss coordinates") end
                bosses[#bosses+1]={path=entry.path,name=entry.name,maximum=entry.maximum,spawn=position,
                    position=position,id="Imported location"}
            end
            for _,entry in ipairs(array(data.markers)) do
                if type(entry)~="table" or not safeText(entry.key,160)
                    or (entry.name~=nil and not safeText(entry.name,200)) then error("Invalid marker data") end
                local position=unpackPosition(entry.position)
                if not position then error("Invalid marker coordinates") end
                markers[#markers+1]={key=entry.key,name=entry.name,position=position}
            end
            if #bosses+#markers==0 then error("This code contains no locations") end

            local merged,mergedMarkers={},{}
            for key,entry in pairs(Farm.catalog) do merged[key]=entry end
            for key,entry in pairs(Farm.markers) do mergedMarkers[key]=entry end
            local added=0
            for _,entry in ipairs(bosses) do
                local duplicate=false
                for _,current in pairs(merged) do
                    if current.spawn and Farm.bossKey(current.name)==Farm.bossKey(entry.name)
                        and (current.spawn-entry.spawn).Magnitude<384 then duplicate=true;break end
                end
                if not duplicate then
                    local key=entry.path;local suffix=0
                    while merged[key] do suffix=suffix+1;key="@import:"..suffix..":"..entry.name end
                    entry.path=key;merged[key]=entry;added=added+1
                end
            end
            for _,entry in ipairs(markers) do

                local p=entry.position
                local key=string.format("%d_%d_%d",math.floor(p.X/32),math.floor(p.Y/32),math.floor(p.Z/32))
                entry.key=key
                if not mergedMarkers[key] then mergedMarkers[key]=entry end
            end
            local count,markerCount=0,0
            for _ in pairs(merged) do count=count+1 end
            for _ in pairs(mergedMarkers) do markerCount=markerCount+1 end
            if count>512 or markerCount>512 then error("Merged config exceeds 512 locations per list") end
            return {catalog=merged,markers=mergedMarkers,added=added}
        end)
        if not ok then return false,tostring(result):gsub("^.-:%d+: ","") end
        Farm.setEnabled(false)
        Farm.catalog,Farm.markers=result.catalog,result.markers
        Farm.hadConfig=true
        Farm.markDirty(); Farm.scan(true); Farm.saveConfig(true)
        render()
        return true,"Imported "..result.added.." new bosses. Choose a boss, then enable Farm."
    end
    function Farm.remember(found)
        for _, entry in pairs(Farm.catalog) do entry.live=nil end
        for _, record in ipairs(found) do
            local hp,maximum,_,part=Farm.read(record)
            local entry=Farm.catalog[record.path]
            if not entry and part then
                local best=Settings.BossLocalScanRadius
                for _, candidate in pairs(Farm.catalog) do
                    if not candidate.live and candidate.spawn and Farm.bossKey(candidate.name)==Farm.bossKey(record.name) then
                        local distance=(part.Position-candidate.spawn).Magnitude
                        if distance<best then entry,best=candidate,distance end
                    end
                end
            end
            if not entry then
                entry={path=record.path,name=record.name,id=record.id}
                Farm.catalog[entry.path]=entry; Farm.markDirty()
            end
            if entry.maximum~=maximum or entry.name~=record.name or entry.rigPath~=record.path then Farm.markDirty() end
            entry.name,entry.maximum,entry.rigPath,entry.live=record.name,maximum,record.path,record
            if part and hp and hp>0 then
                if not entry.position or (part.Position-entry.position).Magnitude>16 then Farm.markDirty() end
                entry.position=part.Position
                if not entry.spawn then entry.spawn=part.Position;Farm.markDirty() end
            end
        end
        Farm.remembered={}
        for _, entry in pairs(Farm.catalog) do
            if entry.maximum == nil or attackHealthAllowed(entry.maximum) then
                Farm.remembered[#Farm.remembered+1]=entry
            end
        end
        table.sort(Farm.remembered,function(a,b) return a.path<b.path end)
        Farm.saveConfig(false)
    end
end

do
    local ids, nextID = setmetatable({}, {__mode = "k"}), 0
    local collisionState, farmCharacter, origin = {}, nil, nil
    local rotationState, expanded
    local combatPose = nil

    local function makeCombatPose(character, humanoid, rootPart, targetRoot)
        if not character or not humanoid or not rootPart or not targetRoot then return end
        if not character.Parent or not targetRoot.Parent then return end
        humanoid.AutoRotate = false
        local depth = math.clamp(Settings.FarmDepth, 6, 7)
        local destination = targetRoot.Position - Vector3.new(0, depth, 0)
        local flat = Vector3.new(targetRoot.Position.X - destination.X, 0, targetRoot.Position.Z - destination.Z)
        local yaw = 0
        if flat.Magnitude > 0.05 then
            yaw = math.atan2(-flat.X, -flat.Z)
        end

        local desired = CFrame.new(destination) * CFrame.Angles(math.rad(90), yaw, 0)
        rootPart.CFrame = desired
        rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end

    local function prepareFarmCollision(character)
        if not character then return end
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") and collisionState[part] == nil then
                collisionState[part] = part.CanCollide
                part.CanCollide = false
            end
        end
    end
    function Farm.restoreHitbox()
        local saved = expanded
        expanded = nil
        if saved then
            pcall(function() saved.part.Size = saved.size end)
            pcall(function() saved.part.CanCollide = saved.collide end)
        end
    end
    local function expandHitbox(part)
        if expanded and (expanded.part ~= part or not Settings.FarmExpandHitbox) then Farm.restoreHitbox() end
        if not Settings.FarmExpandHitbox then return end
        if not expanded then expanded = {part = part, size = part.Size, collide = part.CanCollide} end
        local size = math.clamp(Settings.FarmHitboxSize, 2, 30)
        part.Size = Vector3.new(math.max(size, expanded.size.X), math.max(size, expanded.size.Y), math.max(size, expanded.size.Z))
        part.CanCollide = false
    end
    local function within(object, ancestor)
        while object do
            if object == ancestor then return true end
            object = object.Parent
        end
        return false
    end
    local function rigModel(humanoid)
        local node = humanoid.Parent
        while node and node ~= World do
            if node:IsA("Model") then return node end
            node = node.Parent
        end
    end
    local function rigRoot(model, humanoid)
        local rootPart = humanoid.RootPart or model:FindFirstChild("HumanoidRootPart", true) or model.PrimaryPart
            or model:FindFirstChild("Torso", true) or model:FindFirstChild("UpperTorso", true)
        return rootPart and rootPart:IsA("BasePart") and within(rootPart, model) and rootPart or nil
    end
    local function inWorld(object)
        while object do
            if object == World then return true end
            object = object.Parent
        end
        return false
    end
    local function isPlayer(model)
        for _, player in ipairs(Players:GetPlayers()) do
            local node = model
            while node and node ~= World do
                if node == player.Character then return true end
                node = node.Parent
            end
        end
        return false
    end
    local function path(model)
        local names, node = {}, model
        while node and node ~= World do table.insert(names, 1, node.Name); node = node.Parent end
        return table.concat(names, ".")
    end
    function Farm.read(record)
        if not record or not inWorld(record.model) or isPlayer(record.model) then return nil end
        local humanoid = record.humanoid
        if not humanoid or not within(humanoid, record.model) then return nil end
        local rootPart = record.root
        if not rootPart or not within(rootPart, record.model) then
            rootPart = rigRoot(record.model, humanoid); record.root = rootPart
        end
        local hp, maximum = humanoid.Health, humanoid.MaxHealth
        if type(hp) ~= "number" or type(maximum) ~= "number" or hp ~= hp or maximum ~= maximum
            or math.abs(hp) == math.huge or maximum <= 0 or maximum == math.huge then return nil end
        return hp, maximum, humanoid, rootPart and rootPart:IsA("BasePart") and rootPart or nil
    end
    function Farm.scan(force)
        if not force and os.clock() < Farm.nextScan then return end
        Farm.nextScan = os.clock() + 2
        local found, seen = {}, {}
        Farm.scanned = 0
        for _, object in ipairs(World:GetDescendants()) do
            if object:IsA("Humanoid") then
                local model = rigModel(object)
                if model and not seen[model] and not isPlayer(model) then
                    seen[model] = true
                    Farm.scanned = Farm.scanned + 1
                    local record = {model = model, humanoid = object, root = rigRoot(model, object), path = path(model)}
                    local hp, maximum = Farm.read(record)
                    if hp and attackHealthAllowed(maximum) then
                        if not ids[model] then nextID = nextID + 1; ids[model] = nextID end
                        local gameID = model:GetAttribute("BossId") or model:GetAttribute("BossID")
                            or model:GetAttribute("NPCId") or model:GetAttribute("Id")
                        local display = model:GetAttribute("NPCName") or model:GetAttribute("BossName")
                            or model:GetAttribute("DisplayName") or object.DisplayName
                        record.name = type(display) == "string" and display ~= "" and display ~= "Humanoid" and display or model.Name
                        record.id = gameID ~= nil and ("Game ID: " .. tostring(gameID)) or ("Session ID: " .. ids[model])
                        found[#found + 1] = record
                    end
                end
            end
        end
        if Farm.scanMarkers then Farm.scanMarkers() end
        Farm.remember(found)
        table.sort(found, function(a,b) return a.path < b.path end)
        if Farm.pinned then
            local entry = Farm.catalog[Farm.pinned]
            Farm.selected = entry and entry.live or nil
        elseif Farm.selected then
            for _, record in ipairs(found) do
                if record.path == Farm.selected.path then Farm.selected = record; break end
            end
        end
        Farm.records, Farm.count = found, #found
    end
    local mouseDown, toolDown, nextM1, releaseM1At = nil, nil, 0, 0
    local uiBlockCache, nextUIBlockScan = false, 0
    local Mouse = Player:GetMouse()
    local coreGuiOK, CoreGui = pcall(function() return game:GetService("CoreGui") end)
    Farm.m1Status = "M1 ready"

    local function guiVisible(object)
        local node = object
        while node and node ~= playerGui do
            if node:IsA("GuiObject") and not node.Visible then return false end
            if node:IsA("ScreenGui") and not node.Enabled then return false end
            node = node.Parent
        end
        return true
    end

    local inventoryWords = {
        "inventory", "backpack", "storage", "equipment",
        "itemmenu", "items", "bag", "hotbarinventory",
    }

    local function nameLooksInventory(name)
        name = string.lower(tostring(name or ""))
        for _, word in ipairs(inventoryWords) do
            if name:find(word, 1, true) then return true end
        end
        return false
    end

    local function looksLikeInventory(object)
        local node = object
        for _ = 1, 9 do
            if not node or node == playerGui then break end
            if nameLooksInventory(node.Name) then return true end
            node = node.Parent
        end
        return false
    end

    local function centerCoveredByGameUI()
        local camera = World.CurrentCamera
        local viewport = camera and camera.ViewportSize
        if not viewport or viewport.X < 2 or viewport.Y < 2 then return false end

        local point = Vector2.new(math.floor(viewport.X / 2), math.floor(viewport.Y / 2))
        local ok, hits = pcall(function()
            return playerGui:GetGuiObjectsAtPosition(point.X, point.Y)
        end)
        if not ok then return true end

        for _, object in ipairs(hits) do
            if (not root or not object:IsDescendantOf(root)) and guiVisible(object) then
                if object:IsA("TextButton") or object:IsA("ImageButton") or object:IsA("TextBox")
                    or ((object:IsA("Frame") or object:IsA("ScrollingFrame")) and object.Active) then
                    return true
                end
            end
        end
        return false
    end

    function Farm.inventoryOrBlockingUIOpen(force)
        local focused = Input:GetFocusedTextBox()
        if focused and not isChatTextBox(focused) then return true end

        local now = os.clock()
        if not force and now < nextUIBlockScan then return uiBlockCache end
        nextUIBlockScan = now + 0.12

        local blocked = centerCoveredByGameUI()

        if not blocked then
            for _, object in ipairs(playerGui:GetDescendants()) do
                if object:IsA("GuiObject")
                    and guiVisible(object)
                    and looksLikeInventory(object)
                    and object.AbsoluteSize.X >= 80
                    and object.AbsoluteSize.Y >= 50 then
                    blocked = true
                    break
                end
            end
        end

        uiBlockCache = blocked
        return blocked
    end

    local function getConnections(signal)
        local getter = type(getconnections) == "function" and getconnections
            or (type(environment.getconnections) == "function" and environment.getconnections or nil)
        if type(getter) ~= "function" then return nil end
        local ok, list = pcall(getter, signal)
        return ok and type(list) == "table" and list or nil
    end

    local function callConnections(signal, ...)
        local list = getConnections(signal)
        if not list or #list == 0 then return false end

        local args = table.pack(...)
        local attempted = false

        for _, connection in ipairs(list) do
            local enabled = connection.Enabled
            if enabled == nil or enabled == true then
                if type(connection.Fire) == "function" then
                    attempted = true
                    pcall(connection.Fire, connection, table.unpack(args, 1, args.n))
                elseif type(connection.Function) == "function" then
                    attempted = true
                    pcall(connection.Function, table.unpack(args, 1, args.n))
                end
            end
        end

        return attempted
    end

    local function syntheticInput(keyCode, inputType, state)
        return {
            KeyCode = keyCode or Enum.KeyCode.Unknown,
            UserInputType = inputType,
            UserInputState = state,
            Position = Vector3.new(0, 0, 0),
            Delta = Vector3.new(0, 0, 0),
        }
    end

    local function inventoryRoots()
        local roots, seen = {}, {}

        local function inspect(container)
            if not container then return end
            for _, object in ipairs(container:GetDescendants()) do
                if (object:IsA("GuiObject") or object:IsA("ScreenGui"))
                    and (not root or not object:IsDescendantOf(root))
                    and nameLooksInventory(object.Name) then

                    local candidate = object
                    local node = object.Parent

                    while node and node ~= container do
                        if (node:IsA("GuiObject") or node:IsA("ScreenGui"))
                            and nameLooksInventory(node.Name) then
                            candidate = node
                        end
                        node = node.Parent
                    end

                    if not seen[candidate] then
                        seen[candidate] = true
                        roots[#roots + 1] = candidate
                    end
                end
            end
        end

        inspect(playerGui)
        if coreGuiOK then inspect(CoreGui) end
        return roots
    end

    local function suspendInventoryVisual()
        local saved = {}
        local focused = Input:GetFocusedTextBox()

        if focused and not isChatTextBox(focused) then
            pcall(function() focused:ReleaseFocus(false) end)
        end

        for _, object in ipairs(inventoryRoots()) do
            local record = {object = object}

            if object:IsA("ScreenGui") then
                record.enabled = object.Enabled
                object.Enabled = false
            elseif object:IsA("GuiObject") then
                record.visible = object.Visible
                object.Visible = false
            end

            saved[#saved + 1] = record
        end

        local oldSelected = GuiService.SelectedObject
        pcall(function() GuiService.SelectedObject = nil end)

        return function()
            pcall(function() GuiService.SelectedObject = oldSelected end)
            for i = #saved, 1, -1 do
                local record = saved[i]
                local object = record.object
                if object and object.Parent then
                    if record.enabled ~= nil then
                        pcall(function() object.Enabled = record.enabled end)
                    elseif record.visible ~= nil then
                        pcall(function() object.Visible = record.visible end)
                    end
                end
            end
        end, #saved
    end

    local function hardInventoryPulse(downCallback, upCallback, holdTime)
        local restore, rootCount = suspendInventoryVisual()

        task.wait(0.015)

        local okDown, downResult = pcall(downCallback)

        if okDown and upCallback then
            task.wait(math.max(0.025, holdTime or 0.03))
            pcall(upCallback)
        end

        task.wait(0.015)
        restore()

        return okDown, downResult, rootCount
    end

    local function neutralizeInventoryInput()
        local saved = {}
        local focused = Input:GetFocusedTextBox()

        if focused and not isChatTextBox(focused) then
            pcall(function() focused:ReleaseFocus(false) end)
        end

        for _, object in ipairs(playerGui:GetDescendants()) do
            if object:IsA("GuiObject")
                and (not root or not object:IsDescendantOf(root))
                and guiVisible(object)
                and looksLikeInventory(object) then

                local record = {object = object}

                local okActive, active = pcall(function() return object.Active end)
                if okActive then
                    record.active = active
                    pcall(function() object.Active = false end)
                end

                if object:IsA("GuiButton") then
                    local okModal, modal = pcall(function() return object.Modal end)
                    if okModal then
                        record.modal = modal
                        pcall(function() object.Modal = false end)
                    end

                    local okSelectable, selectable = pcall(function() return object.Selectable end)
                    if okSelectable then
                        record.selectable = selectable
                        pcall(function() object.Selectable = false end)
                    end
                end

                saved[#saved + 1] = record
            end
        end

        local oldSelected = GuiService.SelectedObject
        pcall(function() GuiService.SelectedObject = nil end)

        return function()
            pcall(function() GuiService.SelectedObject = oldSelected end)
            for i = #saved, 1, -1 do
                local record = saved[i]
                local object = record.object
                if object and object.Parent then
                    if record.active ~= nil then pcall(function() object.Active = record.active end) end
                    if record.modal ~= nil then pcall(function() object.Modal = record.modal end) end
                    if record.selectable ~= nil then pcall(function() object.Selectable = record.selectable end) end
                end
            end
        end
    end

    local function withInventoryBypass(callback)
        local restore = neutralizeInventoryInput()
        local ok, a, b = pcall(callback)
        restore()
        return ok, a, b
    end

    function Farm.directSkillKey(key, down)
        local signal = down and Input.InputBegan or Input.InputEnded
        local state = down and Enum.UserInputState.Begin or Enum.UserInputState.End
        local inputObject = syntheticInput(key, Enum.UserInputType.Keyboard, state)

        local ok, attempted = withInventoryBypass(function()
            return callConnections(signal, inputObject, false)
        end)

        return ok and attempted == true
    end

    function Farm.inventorySkillPulse(key)
        local ok, _, roots = hardInventoryPulse(
            function()
                VirtualInput:SendKeyEvent(true, key, false, game)
                return true
            end,
            function()
                VirtualInput:SendKeyEvent(false, key, false, game)
            end,
            Settings.HoldTime
        )

        if roots == 0 and type(Farm.directSkillKey) == "function" then
            Farm.directSkillKey(key, true)
            task.wait(math.max(0.025, Settings.HoldTime))
            Farm.directSkillKey(key, false)
        end

        return ok
    end

    local function directMouseM1(down)
        local mouseSignal = down and Mouse.Button1Down or Mouse.Button1Up
        local uiSignal = down and Input.InputBegan or Input.InputEnded
        local state = down and Enum.UserInputState.Begin or Enum.UserInputState.End
        local inputObject = syntheticInput(Enum.KeyCode.Unknown, Enum.UserInputType.MouseButton1, state)

        local ok, attempted = withInventoryBypass(function()

            local usedMouse = callConnections(mouseSignal)
            if usedMouse then return true end
            return callConnections(uiSignal, inputObject, false)
        end)

        return ok and attempted == true
    end

    function Farm.stopM1()
        local point, tool = mouseDown, toolDown
        mouseDown, toolDown = nil, nil

        if point == "DIRECT" then
            pcall(function() directMouseM1(false) end)
        elseif point then
            pcall(function()
                VirtualInput:SendMouseButtonEvent(point.X, point.Y, 0, false, game, 0)
            end)
        end

        if tool then
            pcall(function() tool:Deactivate() end)
        end
    end

    function Farm.setM1(value)
        Farm.stopM1()
        Settings.FarmM1 = value
        nextM1 = 0
        Farm.m1Status = value and "M1 ready" or "M1 off"
    end

    local function stepM1()
        if (mouseDown or toolDown) and (os.clock() >= releaseM1At
            or (toolDown and toolDown.Parent ~= Player.Character)) then
            Farm.stopM1()
        end

        if not Settings.FarmM1 then
            Farm.stopM1()
            return
        end

        if shouldPauseForTextEntry() or State.gesture then
            Farm.stopM1()
            Farm.m1Status = "M1 paused for chat / script controls"
            return
        end

        if mouseDown or toolDown or os.clock() < nextM1 then return end

        local camera = World.CurrentCamera
        local viewport = camera and camera.ViewportSize
        if not viewport or viewport.X < 2 or viewport.Y < 2 then
            Farm.m1Status = "M1 waiting for camera"
            return
        end

        local point = Vector2.new(
            math.floor(viewport.X * (1600 / 1920)),
            math.floor(viewport.Y * 0.5)
        )
        local blocked = Farm.inventoryOrBlockingUIOpen(false)

        if blocked then

            local ok, _, roots = hardInventoryPulse(
                function()
                    VirtualInput:SendMouseButtonEvent(point.X, point.Y, 0, true, game, 0)
                    return true
                end,
                function()
                    VirtualInput:SendMouseButtonEvent(point.X, point.Y, 0, false, game, 0)
                end,
                0.035
            )

            if ok and roots > 0 then
                nextM1 = os.clock() + 0.16
                Farm.m1Status = "M1: inventory pulse bypass"
                return
            end

            if directMouseM1(true) then
                mouseDown = "DIRECT"
                nextM1, releaseM1At = os.clock() + 0.16, os.clock() + 0.035
                Farm.m1Status = "M1: local inventory bypass"
                return
            end

            local character = Player.Character
            local tool = character and character:FindFirstChildOfClass("Tool")
            if tool and (not tool.RequiresHandle or tool:FindFirstChild("Handle")) then
                nextM1, releaseM1At = os.clock() + 0.16, os.clock() + 0.04
                toolDown = tool
                local toolOK, err = pcall(function() tool:Activate() end)
                if toolOK then
                    Farm.m1Status = "M1: Tool inventory bypass"
                else
                    toolDown = nil
                    Farm.m1Status = "M1 Tool bypass failed: " .. tostring(err)
                end
                return
            end

            Farm.m1Status = "M1 inventory bypass unavailable"
            nextM1 = os.clock() + 0.20
            return
        end

        if State.focused and (Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            or Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)) then
            Farm.m1Status = "M1 paused for your mouse"
            return
        end

        nextM1, releaseM1At = os.clock() + 0.16, os.clock() + 0.035
        mouseDown = point

        local ok, err = pcall(function()
            VirtualInput:SendMouseButtonEvent(point.X, point.Y, 0, true, game, 0)
        end)

        if not ok then
            mouseDown = nil
            Farm.m1Status = "M1 input failed: " .. tostring(err)
        else
            Farm.m1Status = "M1 active"
        end
    end

    local loot, watched, deathConnection, lastTargetPosition
    local LOOT_OLD_HORIZONTAL_RADIUS = 60
    local LOOT_NEW_HORIZONTAL_RADIUS = 250
    local LOOT_VERTICAL_RADIUS = 400
    local function endPrompt()
        if loot and loot.holding then
            local prompt = loot.holding; loot.holding = nil
            pcall(function() prompt:InputHoldEnd() end)
        end
    end
    function Farm.clearLoot()
        endPrompt()
        if loot and loot.spawnConnection then
            loot.spawnConnection:Disconnect()
            loot.spawnConnection = nil
        end
        loot = nil
        if deathConnection then deathConnection:Disconnect(); deathConnection = nil end
        watched, lastTargetPosition = nil, nil
    end
    function Farm.setLoot(value)
        Settings.FarmAutoLoot = value
        if not value then Farm.clearLoot() end
    end
    local function beginLoot(position)
        if not Settings.FarmEnabled or not Settings.FarmAutoLoot or not State.alive or loot then return end
        Farm.stopM1(); Farm.restoreHitbox(); State.farming = false; combatPose = nil; releaseOrPause()

        loot = {
            center = position,
            destination = position + Vector3.new(0, 2, 0),
            deadline = os.clock() + 10,
            nextScan = 0,
            tries = {},
            count = 0,
            fresh = setmetatable({}, {__mode = "k"}),
            index = {},
            cache = setmetatable({}, {__mode = "k"}),
            indexed = setmetatable({}, {__mode = "k"}),
            indexReady = false,
            message = "Waiting for boss drops near the kill.",
        }

        local lootSession = loot
        local function indexObject(object, isFresh)
            if not lootSession or lootSession ~= loot or not object then return end
            if not lootSession.indexed[object] and (object:IsA("ProximityPrompt") or object:IsA("ClickDetector")) then
                lootSession.indexed[object] = true
                lootSession.index[#lootSession.index + 1] = object
            elseif not lootSession.indexed[object] and object:IsA("BasePart") and object.CanTouch then
                local delta = object.Position - lootSession.center
                local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
                if horizontal <= LOOT_NEW_HORIZONTAL_RADIUS and math.abs(delta.Y) <= LOOT_VERTICAL_RADIUS then
                    lootSession.indexed[object] = true
                    lootSession.index[#lootSession.index + 1] = object
                end
            end
            if isFresh then
                local node = object
                for _ = 1, 8 do
                    if not node or node == World then break end
                    lootSession.fresh[node] = true
                    node = node.Parent
                end
            end
        end

        loot.spawnConnection = World.DescendantAdded:Connect(function(object)
            indexObject(object, true)
        end)

        task.spawn(function()
            local initial = World:GetDescendants()
            local batch = 0
            for _, object in ipairs(initial) do
                if not lootSession or lootSession ~= loot or os.clock() >= lootSession.deadline then return end
                indexObject(object, false)
                batch = batch + 1
                if batch >= 1200 then
                    batch = 0
                    task.wait()
                end
            end
            if lootSession and lootSession == loot then
                lootSession.indexReady = true
            end
        end)

        if deathConnection then deathConnection:Disconnect(); deathConnection = nil end
        watched, lastTargetPosition = nil, nil
    end
    local function watchTarget(record, part)
        lastTargetPosition = part.Position
        if watched == record.humanoid then return end
        if deathConnection then deathConnection:Disconnect() end
        watched = record.humanoid

        -- Analytics target counting happens at the actual attack/engagement
        -- point below, not merely when the health watcher is attached.
        deathConnection = watched.HealthChanged:Connect(function(hp)
            if hp <= 0 then
                -- Count each humanoid exactly once. HealthChanged can fire more
                -- than once at 0 and must never inflate kill/boss statistics.
                if System and type(System.recordKill) == "function" then
                    pcall(function() System.recordKill(record) end)
                end
                if Settings.AutoBoss then Farm.autoDefeated = true end
                if lastTargetPosition then beginLoot(lastTargetPosition) end
            end
        end)
    end
    local function lootPart(object)
        if not object then return nil end
        if object:IsA("BasePart") then return object end
        if object:IsA("Attachment") then return lootPart(object.Parent) end
        if object:IsA("Model") and object.PrimaryPart then return object.PrimaryPart end
        for _, child in ipairs(object:GetDescendants()) do if child:IsA("BasePart") then return child end end
    end
    local function lootIdentity(object)
        local node, entity, part, marked = object, nil, nil, false
        while node and node ~= World do
            if isPlayer(node) then return nil end
            if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then return nil end
            for _, record in ipairs(Farm.records) do if node == record.model then return nil end end
            if not entity and (node:IsA("Model") or node:IsA("Tool")) then entity = node end
            if not part and node:IsA("BasePart") then part = node end
            local name = string.lower(node.Name)
            marked = marked or node:IsA("Tool") or node:GetAttribute("IsLoot") == true
                or node:GetAttribute("Collectible") == true or name:find("chest", 1, true)
                or name:find("loot", 1, true) or name:find("drop", 1, true)
                or name:find("pickup", 1, true) or name:find("collect", 1, true)
            node = node.Parent
        end
        return entity or part, marked
    end
    local function allowedPrompt(prompt)
        local action = string.lower(prompt.ActionText or "")
        for _, word in ipairs({"buy", "purchase", "trade", "sell", "quest", "talk", "teleport", "travel", "upgrade"}) do
            if action:find(word, 1, true) then return false, false end
        end
        local pickup = action:find("collect", 1, true) or action:find("pick", 1, true)
            or action:find("loot", 1, true) or action:find("claim", 1, true)
        return action == "" or action:find("open", 1, true) or pickup, pickup
    end
    local function lootDistanceOK(part, entity)
        if not loot or not part then return false, false, math.huge end

        local delta = part.Position - loot.center
        local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
        local vertical = math.abs(delta.Y)

        if vertical > LOOT_VERTICAL_RADIUS then
            return false, false, horizontal
        end

        local fresh = (loot.fresh and (
            loot.fresh[part] or
            (entity and loot.fresh[entity]) or
            loot.fresh[part.Parent]
        )) and true or false

        local radius = fresh and LOOT_NEW_HORIZONTAL_RADIUS or LOOT_OLD_HORIZONTAL_RADIUS
        return horizontal <= radius, fresh, horizontal
    end

    local function findLoot()
        local candidates, interactive, seen = {}, {}, {}
        local function available(object)
            local attempt = loot.tries[object]
            return not attempt or (attempt.count < 3 and os.clock() >= attempt.nextTry)
        end
        if not loot.index then return nil end

        for _, object in ipairs(loot.index) do
            if object and object.Parent and (object:IsA("ProximityPrompt") or object:IsA("ClickDetector")) then
                local cached = loot.cache[object]
                if not cached or not cached.entity or not cached.part then
                    local entity, marked = lootIdentity(object)
                    local part = lootPart(object.Parent)
                    cached = {entity=entity, marked=marked, part=part}
                    loot.cache[object] = cached
                end
                local entity, marked, part = cached.entity, cached.marked, cached.part
                local allowed = true
                if object:IsA("ProximityPrompt") then
                    local pickup, isPickup
                    allowed, isPickup = allowedPrompt(object)
                    marked = marked or isPickup
                    allowed = allowed and object.Enabled

                end
                if entity and marked then
                    interactive[entity] = true
                    if allowed and part and available(object) then
                        local inRange, fresh, horizontal = lootDistanceOK(part, entity)
                        if inRange then
                            candidates[#candidates + 1] = {
                                object=object, part=part, entity=entity,
                                fresh=fresh, horizontal=horizontal
                            }
                        end
                    end
                end
            end
        end

        for _, object in ipairs(loot.index) do
            if object and object.Parent and object:IsA("BasePart") and object.CanTouch then
                local cached = loot.cache[object]
                if not cached then
                    local entity, marked = lootIdentity(object)
                    cached = {entity=entity, marked=marked, part=object}
                    loot.cache[object] = cached
                end
                local entity, marked, part = cached.entity, cached.marked, cached.part
                if entity and marked and not interactive[entity] and not seen[entity]
                    and available(entity) then
                    local inRange, fresh, horizontal = lootDistanceOK(part, entity)
                    if inRange then
                        seen[entity] = true
                        candidates[#candidates + 1] = {
                            object=entity, part=part, entity=entity, touch=true,
                            fresh=fresh, horizontal=horizontal
                        }
                    end
                end
            end
        end
        table.sort(candidates, function(a,b)
            if a.fresh ~= b.fresh then return a.fresh == true end
            return (a.horizontal or math.huge) < (b.horizontal or math.huge)
        end)
        return candidates[1]
    end
    local function stepLoot(character, rootPart)
        if not loot then return false end
        State.farming = false; Farm.stopM1(); releaseOrPause()
        if os.clock() >= loot.deadline then Farm.clearLoot(); return false end
        Farm.status, Farm.detail = "LOOT", loot.message
        if loot.touchUntil then
            if os.clock() < loot.touchUntil then return true end
            loot.touchUntil = nil; loot.destination = loot.center + Vector3.new(0,2,0)
        end
        if loot.destination then
            character:PivotTo(character:GetPivot() + (loot.destination - rootPart.Position))
            rootPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
            rootPart.AssemblyAngularVelocity = Vector3.new(0,0,0)
        end
        if loot.holding then
            if not inWorld(loot.holding) or os.clock() >= loot.holdUntil then endPrompt() else return true end
        end
        local item = loot.pending
        if item then
            if os.clock() < loot.readyAt then return true end
            loot.pending = nil
            if not inWorld(item.object) or not inWorld(item.part) then return true end
        else
            if os.clock() < loot.nextScan then return true end
            loot.nextScan = os.clock() + 0.12
            item = findLoot()
            if not item then return true end
            local old = loot.tries[item.object]
            loot.tries[item.object] = {count=old and old.count+1 or 1, nextTry=os.clock()+2}
            loot.pending, loot.readyAt = item, os.clock()+0.15
            loot.destination = item.part.Position + Vector3.new(0,item.touch and 2 or 1,0)
            return true
        end
        loot.count = loot.count+1; loot.message = "Pickup requested: " .. item.entity.Name
        local ok, err = pcall(function()
            if item.object:IsA("ProximityPrompt") then
                local duration = math.max(0,item.object.HoldDuration)
                if os.clock()+duration+0.1 > loot.deadline then return end
                if type(fireproximityprompt) == "function" then fireproximityprompt(item.object,duration)
                else
                    loot.holding, loot.holdUntil = item.object, os.clock()+duration+0.1
                    item.object:InputHoldBegin()
                end
            elseif item.object:IsA("ClickDetector") then
                if type(fireclickdetector) ~= "function" then error("Click-detector support unavailable") end
                fireclickdetector(item.object)
            elseif type(firetouchinterest) == "function" then
                firetouchinterest(rootPart,item.part,0); firetouchinterest(rootPart,item.part,1)
            else
                loot.destination = nil; loot.touchUntil = os.clock()+0.2
                rootPart.AssemblyLinearVelocity = Vector3.new(0,-8,0)
            end
        end)
        if not ok and loot then
            endPrompt(); loot.message = "Pickup failed: " .. tostring(err)
        elseif ok and System and type(System.recordLoot) == "function" then
            pcall(function() System.recordLoot(item) end)
        end
        return true
    end
    local function resetAutoBossRoute(clearLast)
        Farm.autoVisited = {}
        Farm.autoCurrent = nil
        Farm.autoArrivedAt = 0
        Farm.autoCombatAt = 0
        Farm.autoLastProgressAt = 0
        Farm.autoLastHP = nil
        Farm.autoEngaged = false
        Farm.autoDefeated = false
        Farm.autoRespawnResume = false
        Farm.autoResumePath = nil
        local g = Farm.guardian
        g.lastHealth, g.damageSince, g.damageBase = nil, 0, nil
        g.lastPosition, g.lastPositionAt, g.stuckSince, g.lostSince = nil, 0, 0, 0
        g.verifyAt, g.recoveries, g.lastAction, g.lastActionAt = 0, 0, "STANDBY", 0
        g.dangerPaths = {}
        if clearLast then Farm.autoLastPath = nil end
    end
    local function autoBossLocation(entry)
        return entry and (entry.spawn or entry.position) or nil
    end
    local function autoBossEligible(entry)
        if not entry or not autoBossLocation(entry) then return false end
        if entry.maximum and not attackHealthAllowed(entry.maximum) then return false end
        return true
    end
    local function findBossNearSavedLocation(entry)
        if not entry then return nil end
        local location = autoBossLocation(entry)
        if not location then return nil end

        Farm.scan(true)

        local wantedKey = Farm.bossKey(entry.name)
        local bestSame, bestSameDistance
        local bestAny, bestAnyDistance

        for _, record in ipairs(Farm.records) do
            local hp, maximum, _, candidateRoot = Farm.read(record)
            if hp and hp > 0 and candidateRoot and attackHealthAllowed(maximum) then
                local distance = (candidateRoot.Position - location).Magnitude
                if distance <= Settings.BossLocalScanRadius then
                    local sameBoss = wantedKey ~= "" and Farm.bossKey(record.name) == wantedKey

                    if sameBoss and (not bestSameDistance or distance < bestSameDistance) then
                        bestSame, bestSameDistance = record, distance
                    end

                    if not bestAnyDistance or distance < bestAnyDistance then
                        bestAny, bestAnyDistance = record, distance
                    end
                end
            end
        end

        return bestSame or bestAny
    end
    local function pickAutoBoss(rootPart)
        Farm.scan(true)
        local position = rootPart and rootPart.Position
        if not position then return nil end
        local function collect(excludeLast)
            local best, bestDistance
            for _, entry in ipairs(Farm.remembered) do
                local location = autoBossLocation(entry)
                local dangerUntil = Farm.guardian.dangerPaths and Farm.guardian.dangerPaths[entry.path]
                local environmentallyUnsafe = dangerUntil and dangerUntil > os.clock()
                if environmentallyUnsafe and dangerUntil <= os.clock() then
                    Farm.guardian.dangerPaths[entry.path] = nil
                    environmentallyUnsafe = false
                end
                if autoBossEligible(entry) and not environmentallyUnsafe and not Farm.autoVisited[entry.path]
                    and (not excludeLast or entry.path ~= Farm.autoLastPath) then
                    local distance = (location - position).Magnitude
                    if distance <= Settings.BossAutoRange and (not bestDistance or distance < bestDistance) then
                        best, bestDistance = entry, distance
                    end
                end
            end
            return best, bestDistance
        end
        local entry, distance = collect(false)
        if not entry then
            local hadVisited = next(Farm.autoVisited) ~= nil
            Farm.autoVisited = {}
            if hadVisited then Farm.autoCycles = Farm.autoCycles + 1 end
            entry, distance = collect(true)
            if not entry then entry, distance = collect(false) end
        end
        if not entry then return nil end
        Farm.autoVisited[entry.path] = true
        Farm.autoCurrent = entry.path
        Farm.autoLastPath = entry.path
        Farm.autoArrivedAt = os.clock()
        Farm.autoCombatAt = 0
        Farm.autoLastProgressAt = 0
        Farm.autoLastHP = nil
        Farm.autoEngaged = false
        Farm.autoDefeated = false
        Farm.pinned = entry.path
        Farm.selected = entry.live
        Farm.travelKey, Farm.travelAt = nil, nil
        local g = Farm.guardian
        g.lastHealth, g.damageSince, g.damageBase = nil, 0, nil
        g.lastPosition, g.lastPositionAt, g.stuckSince = rootPart.Position, os.clock(), 0
        g.verifyAt, g.recoveries, g.lastAction, g.lastActionAt = 0, 0, "TARGET SELECTED", os.clock()
        Farm.status = "AUTO BOSS"
        Farm.detail = string.format("Next: %s | %.0f studs away", entry.name, distance or 0)
        return entry
    end
    local function advanceAutoBoss(reason, rootPart, skipped)
        local previous = Farm.autoCurrent and Farm.catalog[Farm.autoCurrent]
        if previous and type(reason) == "string" and (reason:find("environmental damage", 1, true) or reason:find("taking damage", 1, true)) then
            Farm.guardian.dangerPaths[previous.path] = os.clock() + 120
        end
        if skipped then Farm.autoSkipped = Farm.autoSkipped + 1 end
        Farm.stopM1()
        Farm.restoreHitbox()
        Farm.clearLoot()
        Farm.selected = nil
        Farm.pinned = nil
        Farm.autoCurrent = nil
        Farm.autoArrivedAt = 0
        Farm.autoCombatAt = 0
        Farm.autoLastProgressAt = 0
        Farm.autoLastHP = nil
        Farm.autoEngaged = false
        Farm.autoDefeated = false
        Farm.travelKey, Farm.travelAt = nil, nil
        Farm.travelHealth = nil
        local g = Farm.guardian
        g.lastHealth, g.damageSince, g.damageBase = nil, 0, nil
        g.lastPosition, g.lastPositionAt, g.stuckSince, g.lostSince = rootPart and rootPart.Position or nil, os.clock(), 0, 0
        g.verifyAt, g.recoveries, g.lastAction, g.lastActionAt = 0, 0, reason or "MOVING", os.clock()
        Farm.nextScan = 0
        Farm.status = "AUTO BOSS"
        Farm.detail = (reason or "Moving to next boss") .. (previous and (" | " .. previous.name) or "")
        return pickAutoBoss(rootPart)
    end

    local function guardianResetObservation(rootPart, humanoid)
        local g = Farm.guardian
        local now = os.clock()
        g.lastHealth = humanoid and humanoid.Health or nil
        g.damageSince, g.damageBase = 0, nil
        g.lastPosition, g.lastPositionAt = rootPart and rootPart.Position or nil, now
        g.stuckSince, g.lostSince = 0, 0
        g.verifyAt = 0
    end

    local function guardianObservePlayer(humanoid, rootPart, engaged)
        if not Settings.AutoBoss or not humanoid or not rootPart then return false end
        local g, now = Farm.guardian, os.clock()
        local hp = humanoid.Health

        if g.lastHealth == nil then
            guardianResetObservation(rootPart, humanoid)
            return false
        end

        local drop = g.lastHealth - hp
        if not engaged and drop > 0.01 then
            if g.damageSince == 0 then
                g.damageSince = now
                g.damageBase = g.lastHealth
            end
            local cumulative = (g.damageBase or g.lastHealth) - hp
            if cumulative >= 1 or now - g.damageSince >= Settings.GuardianDamageTimeout then
                g.lastHealth = hp
                g.damageSince, g.damageBase = 0, nil
                return true
            end
        elseif not engaged and g.damageSince ~= 0 then
            local cumulative = (g.damageBase or g.lastHealth) - hp
            if now - g.damageSince >= Settings.GuardianDamageTimeout then
                g.damageSince, g.damageBase = 0, nil
                if cumulative >= 0.25 then return true end
            end
        end

        g.lastHealth = hp
        return false
    end

    local function guardianObserveTravel(rootPart, entry, targetRoot, engaged)
        if not Settings.AutoBoss or not rootPart or not entry or engaged then return false end
        local g, now = Farm.guardian, os.clock()
        if not g.lastPosition then
            g.lastPosition, g.lastPositionAt = rootPart.Position, now
            return false
        end

        local moved = (rootPart.Position - g.lastPosition).Magnitude
        if moved >= 1 then
            g.lastPosition, g.lastPositionAt, g.stuckSince = rootPart.Position, now, 0
        elseif Farm.travelDestination and Farm.travelAt and now - Farm.travelAt >= 1.25 then
            local distance = (rootPart.Position - Farm.travelDestination).Magnitude
            if distance > 10 then
                if g.stuckSince == 0 then g.stuckSince = now end
                if now - g.stuckSince >= Settings.GuardianStuckTimeout then
                    g.lastAction, g.lastActionAt = "TRAVEL STUCK", now
                    return true
                end
            else
                g.stuckSince = 0
            end
        end

        return false
    end

    local function guardianVerifyTarget(entry, targetRoot)
        if not Settings.AutoBoss or not entry or not targetRoot then return false end
        local location = autoBossLocation(entry)
        if not location then return false end
        return (targetRoot.Position - location).Magnitude <= Settings.BossLocalScanRadius
    end

    local function guardianCombatStalled(hp, targetRoot)
        if not Settings.AutoBoss or not Farm.autoEngaged or not targetRoot or not hp or hp <= 0 then return false end
        local g, now = Farm.guardian, os.clock()
        if Farm.autoLastProgressAt == 0 then Farm.autoLastProgressAt = now end
        if now - Farm.autoLastProgressAt < Settings.GuardianCombatStallTimeout then return false end

        if g.recoveries < Settings.GuardianMaxRecoveries then
            g.recoveries = g.recoveries + 1
            g.lastAction, g.lastActionAt = "REACQUIRING BOSS", now
            Farm.stopM1()
            Farm.restoreHitbox()
            combatPose = nil
            Farm.selected = nil
            Farm.nextScan = 0
            Farm.scan(true)
            local entry = Farm.catalog[Farm.autoCurrent]
            local nearby = entry and findBossNearSavedLocation(entry) or nil
            if nearby then
                Farm.selected = nearby
                if entry then entry.live = nearby end
                if System and type(System.recordTarget) == "function" then
                    pcall(function() System.recordTarget(nearby) end)
                end
                Farm.autoCombatAt = now
                Farm.autoLastProgressAt = now
                Farm.autoLastHP = nearby.humanoid and nearby.humanoid.Health or hp
                Farm.autoEngaged = false
                Farm.travelKey, Farm.travelAt, Farm.travelHealth = nil, nil, nil
                Farm.status = "AUTO BOSS RECOVERING"
                Farm.detail = string.format("Guardian reacquired %s after %.0fs without HP progress.", nearby.name, Settings.GuardianCombatStallTimeout)
                guardianResetObservation(Player.Character and (Player.Character:FindFirstChild("HumanoidRootPart") or Player.Character.PrimaryPart), Player.Character and Player.Character:FindFirstChildOfClass("Humanoid"))
                return "recovered"
            end
        end

        return "skip"
    end

    function Farm.guardianStatus()
        local g = Farm.guardian
        return g.lastAction or "STANDBY"
    end

    function Farm.setAutoBoss(value)
        if not State.alive then return end

        local enable = value == true
        if not enable and Farm.stopDiscovery then Farm.stopDiscovery() end

        -- Auto Boss is its own automation mode.  It may internally require
        -- FarmEnabled, but an Auto Boss startup error must never immediately
        -- flip the user's toggle back off.  The old implementation treated
        -- any first-frame farm error as a hard Farm failure, which made the
        -- Auto Boss switch visually disable the instant it was activated.
        Settings.AutoBoss = enable
        Farm.fault = nil
        Farm.autoBossError = nil
        Farm.autoBossErrorAt = 0
        Farm.nextScan = 0

        if enable then
            Settings.BossAutoSave = true
            Settings.FarmEnabled = true
            Farm.markDirty(); Farm.saveConfig(true)
            Farm.stopM1(); Farm.clearLoot(); Farm.restoreHitbox()
            Farm.pinned, Farm.selected = nil, nil
            Farm.autoCycles, Farm.autoSkipped = 0, 0
            resetAutoBossRoute(true)
            Farm.status = "AUTO BOSS STARTING"
            Farm.detail = "Selecting the nearest remembered boss..."
        else
            Settings.FarmEnabled = false
            resetAutoBossRoute(true)
            Farm.release(false)
            Farm.status = "OFF"
            Farm.detail = "Auto Boss disabled."
        end

        -- Run startup through the same guarded path as the heartbeat.
        -- This prevents one bad saved location / transient scanner state from
        -- turning the feature back off.
        Farm.step()
        render()
    end
    function Farm.release(returnToStart)
        State.farming = false
        combatPose = nil
        Farm.travelKey, Farm.travelAt = nil, nil
        Farm.travelHealth = nil
        Farm.stopM1(); Farm.clearLoot()
        Farm.restoreHitbox()
        if rotationState then
            local saved = rotationState; rotationState = nil
            pcall(function() saved.humanoid.AutoRotate = saved.autoRotate end)
        end
        if returnToStart and origin and farmCharacter and farmCharacter.Parent
            and farmCharacter == Player.Character then
            local returnDistance = 0
            pcall(function() returnDistance = (farmCharacter:GetPivot().Position - origin.Position).Magnitude end)
            local ok, err = pcall(function() farmCharacter:PivotTo(origin) end)
            if ok and System and type(System.recordTeleport) == "function" then
                pcall(function() System.recordTeleport("Farm Return", returnDistance) end)
            end
            if not ok then warn("AutoSkills: could not return from farming: " .. tostring(err)) end
        end
        for part, original in pairs(collisionState) do
            pcall(function() part.CanCollide = original end)
        end
        collisionState, farmCharacter, origin = {}, nil, nil
        releaseOrPause()
    end
    pauseFarmForEscape = function()
        if Farm.stopDiscovery then Farm.stopDiscovery("Stopped for health escape") end
        Farm.release(false)
    end
    function Farm.setEnabled(value)
        if Farm.stopDiscovery then Farm.stopDiscovery() end
        Settings.FarmEnabled, Farm.fault = value, nil
        if not value then
            Settings.AutoBoss = false
            resetAutoBossRoute(true)
            Farm.release(false)
        end
        Farm.nextScan = 0
        Farm.step()
    end
    function Farm.choose(pathKey)
        Farm.setEnabled(false)
        Farm.pinned = pathKey
        Farm.scan(true)
        Farm.selected = pathKey and Farm.catalog[pathKey] and Farm.catalog[pathKey].live or nil
        render()
    end
    function Farm.cycle(direction)
        Farm.scan(true)
        if #Farm.remembered == 0 then return end
        local index = direction > 0 and 0 or 1
        for i, entry in ipairs(Farm.remembered) do
            if entry.path == Farm.pinned then index = i; break end
        end
        Farm.choose(Farm.remembered[(index - 1 + direction) % #Farm.remembered + 1].path)
    end
    local function update()
        if Farm.discoveryStep and Farm.discoveryStep() then return end
        if Settings.FarmEnabled or Settings.AutoBoss or Settings.BossAutoSave or State.tab == "Farm" then Farm.scan(false) end
        Farm.saveConfig(false)
        Farm.aliveCount = 0
        for _, record in ipairs(Farm.records) do
            local hp = Farm.read(record)
            if hp and hp > 0 then Farm.aliveCount = Farm.aliveCount + 1 end
        end
        local function pause(status, detail)
            if farmCharacter then Farm.release(true) end
            Farm.status, Farm.detail = status, detail
        end
        if Farm.fault then pause("ERROR", Farm.fault); return end
        if not Settings.FarmEnabled then pause("OFF", "Choose a remembered boss, Auto nearest, or enable Auto Boss."); return end
        if Guard.held or (Settings.HealthEscapeEnabled and (Guard.latched
            or os.clock() - Guard.lastTeleport < 5)) then
            pause("ESCAPE PAUSE", "Release the health lock and recover before farming resumes."); return
        end
        local character = Player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local rootPart = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
        if not character or not character.Parent or not humanoid or humanoid.Health <= 0
            or not rootPart or not rootPart:IsA("BasePart") or rootPart.Anchored or humanoid.Sit or humanoid.SeatPart then
            pause("WAITING", "Waiting for your living, unseated character."); return
        end
        if Settings.AutoBoss then
            local entry

            if Farm.autoRespawnResume and Farm.autoResumePath then
                entry = Farm.catalog[Farm.autoResumePath]
                if entry and autoBossEligible(entry) then
                    Farm.autoCurrent = entry.path
                    Farm.pinned = entry.path
                else
                    Farm.autoRespawnResume = false
                    Farm.autoResumePath = nil
                    entry = nil
                end
            else
                entry = Farm.autoCurrent and Farm.catalog[Farm.autoCurrent] or nil
            end

            if not entry or not autoBossEligible(entry) then entry = pickAutoBoss(rootPart) end
            if not entry then
                Farm.stopM1(); Farm.restoreHitbox()
                Farm.status = "AUTO BOSS WAITING"
                Farm.detail = string.format("No saved boss location within %.0f studs. Discover or import locations first.", Settings.BossAutoRange)
                return
            end
            Farm.pinned = entry.path
            Farm.selected = entry.live

            if Farm.autoCurrent == entry.path and Farm.guardian.verifyAt <= os.clock() then
                Farm.guardian.verifyAt = os.clock() + Settings.GuardianVerifyInterval
                local currentHP, currentMax, _, currentRoot = Farm.read(Farm.selected)
                if currentHP and currentHP > 0 and currentRoot and attackHealthAllowed(currentMax)
                    and not guardianVerifyTarget(entry, currentRoot) then
                    local nearby = findBossNearSavedLocation(entry)
                    if nearby then
                        Farm.selected, entry.live = nearby, nearby
                    else
                        Farm.selected = nil
                        Farm.guardian.lastAction, Farm.guardian.lastActionAt = "NO VALID BOSS", os.clock()
                    end
                end
            end
        end
        if stepLoot(character, rootPart) then return end
        if Settings.AutoBoss and Farm.autoDefeated then
            advanceAutoBoss("Killed + loot pass complete; moving on", rootPart, false)
            return
        end
        local hp, maximum, _, targetRoot = Farm.read(Farm.selected)
        if hp and hp <= 0 and lastTargetPosition then
            beginLoot(lastTargetPosition)
            if stepLoot(character, rootPart) then return end
        end
        if Farm.pinned then
            local entry = Farm.catalog[Farm.pinned]
            if not entry or (entry.maximum and not attackHealthAllowed(entry.maximum)) then
                pause("FILTERED", "Only 3,000-3,200 MaxHealth targets are attackable."); return
            end
            if not hp or hp <= 0 or not targetRoot then
                if Settings.AutoBoss then
                    local nearby = findBossNearSavedLocation(entry)
                    if nearby then
                        Farm.selected = nearby
                        entry.live = nearby
                        hp, maximum, _, targetRoot = Farm.read(nearby)
                    end
                end

                if hp and hp > 0 and targetRoot and attackHealthAllowed(maximum) then

                    Farm.travelKey, Farm.travelAt, Farm.travelHealth = nil, nil, nil
                else
                    State.farming = false; Farm.stopM1(); Farm.restoreHitbox(); releaseOrPause()
                    local location = hp and hp <= 0 and entry.spawn or entry.position or entry.spawn
                if not location then
                    pause("UNKNOWN LOCATION", "Visit this boss once to learn its location."); return
                end
                if farmCharacter and farmCharacter ~= character then Farm.release(false) end
                if not farmCharacter then
                    farmCharacter, origin = character, character:GetPivot()
                    rotationState = {humanoid = humanoid, autoRotate = humanoid.AutoRotate}
                end
                humanoid.AutoRotate = false
                prepareFarmCollision(character)

                if Farm.travelHealth and humanoid.Health < Farm.travelHealth - 0.01 then
                    local damagedHealth = humanoid.Health
                    Farm.travelHealth = nil
                    if Settings.AutoBoss then
                        advanceAutoBoss("No boss loaded; environmental damage detected, moving on", rootPart, false)
                    else
                        pause("DANGER", string.format("No boss loaded; damage detected (%.0f HP). Returning to safety.", damagedHealth))
                    end
                    return
                end

                if Farm.travelKey ~= entry.path then
                    Farm.travelKey, Farm.travelAt = entry.path, os.clock()
                    Farm.travelHealth = humanoid.Health
                    Farm.travelDestination = location - Vector3.new(0, math.clamp(Settings.FarmDepth,6,7),0)
                    Farm.nextScan = 0
                    if Settings.AutoBoss then
                        Farm.autoArrivedAt = os.clock()
                        Farm.autoCombatAt, Farm.autoLastProgressAt, Farm.autoLastHP = 0, 0, nil
                        Farm.autoEngaged = false
                    end
                    -- One count per actual route teleport. Do not count the
                    -- repeated PivotTo calls that follow while holding position.
                    if System and type(System.recordTeleport) == "function" then
                        local travelDistance = (Farm.travelDestination - rootPart.Position).Magnitude
                        pcall(function() System.recordTeleport(entry.name, travelDistance) end)
                    end
                end
                character:PivotTo(character:GetPivot() + (Farm.travelDestination - rootPart.Position))
                rootPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
                rootPart.AssemblyAngularVelocity = Vector3.new(0,0,0)
                if Settings.AutoBoss and not Farm.autoRespawnResume
                    and os.clock() - Farm.autoArrivedAt >= Settings.BossNoAttackTimeout then
                    advanceAutoBoss("No live attack target after 5s; skipped", rootPart, true)
                    return
                end
                Farm.status = Settings.AutoBoss
                    and (Farm.autoRespawnResume and "AUTO BOSS RESUME" or "AUTO BOSS LOADING")
                    or (hp and hp <= 0 and "WAITING FOR RESPAWN" or "LOADING BOSS")
                Farm.detail = Settings.AutoBoss
                    and (Farm.autoRespawnResume
                        and string.format("Waiting for SAME boss %s after respawn | %.0f-stud scan", entry.name, Settings.BossLocalScanRadius)
                        or string.format("At %s | scanning %.0f studs for a live boss", entry.name, Settings.BossLocalScanRadius))
                    or (os.clock() - Farm.travelAt > 15
                        and "Not loaded yet; waiting at saved location. OFF returns you."
                        or ("At saved location: " .. entry.name .. ". Waiting for a live rig."))
                    return
                end
            end
            if Settings.AutoBoss and Farm.autoRespawnResume and hp and hp > 0 and targetRoot then
                Farm.autoRespawnResume = false
                Farm.autoResumePath = nil
                Farm.autoCombatAt = 0
                Farm.autoLastProgressAt = 0
                Farm.autoLastHP = nil
                Farm.autoEngaged = false
                Farm.autoDefeated = false
                Farm.status = "AUTO BOSS RESUMED"
                Farm.detail = "Same boss reacquired after respawn."
            end
            if Settings.AutoBoss and Farm.autoCombatAt == 0 then
                Farm.autoCombatAt = os.clock()
                Farm.autoLastProgressAt = Farm.autoCombatAt
                Farm.autoLastHP = hp
            end
            Farm.travelKey, Farm.travelAt, Farm.travelHealth = nil, nil, nil
        end

        if Settings.AutoBoss then
            local engaged = Farm.autoEngaged == true
            if guardianObservePlayer(humanoid, rootPart, engaged) then
                Farm.guardian.lastAction, Farm.guardian.lastActionAt = "DAMAGE WITHOUT COMBAT", os.clock()
                advanceAutoBoss("Guardian: player taking damage with no boss being damaged", rootPart, true)
                return
            end

            local entry = Farm.autoCurrent and Farm.catalog[Farm.autoCurrent] or nil
            if entry and guardianObserveTravel(rootPart, entry, targetRoot, engaged) then
                Farm.guardian.lastAction, Farm.guardian.lastActionAt = "TRAVEL STUCK", os.clock()
                advanceAutoBoss("Guardian: travel position stuck, moving to next boss", rootPart, true)
                return
            end

            if engaged then
                if not hp or hp <= 0 or not targetRoot then
                    local now = os.clock()
                    local g = Farm.guardian
                    if g.lostSince == 0 then g.lostSince = now end
                    if now - g.lostSince >= Settings.GuardianCombatStallTimeout then
                        g.lastAction, g.lastActionAt, g.lostSince = "BOSS LOST", now, 0
                        advanceAutoBoss("Guardian: engaged boss disappeared without a kill", rootPart, true)
                        return
                    end
                elseif hp and hp > 0 and targetRoot then
                    Farm.guardian.lostSince = 0
                    local combatResult = guardianCombatStalled(hp, targetRoot)
                    if combatResult == "skip" then
                        Farm.guardian.lastAction, Farm.guardian.lastActionAt = "COMBAT STALLED", os.clock()
                        advanceAutoBoss("Guardian: boss made no HP progress for too long", rootPart, true)
                        return
                    elseif combatResult == "recovered" then
                        return
                    end
                end
            end
        end

        if Settings.AutoBoss and (not hp or hp <= 0 or not targetRoot or not attackHealthAllowed(maximum)) then
            if hp and hp <= 0 and Farm.selected and watched == Farm.selected.humanoid
                and System and type(System.recordKill) == "function" then
                pcall(function() System.recordKill(Farm.selected) end)
            end
            if Farm.autoDefeated or (hp and hp <= 0) then
                Farm.autoDefeated = true
                beginLoot(lastTargetPosition or (targetRoot and targetRoot.Position) or rootPart.Position)
                if stepLoot(character, rootPart) then return end
                advanceAutoBoss("Killed + loot pass complete; moving on", rootPart, false)
            elseif Farm.autoEngaged then

                Farm.stopM1()
                Farm.restoreHitbox()
                combatPose = nil
                Farm.status = "AUTO BOSS ENGAGED"
                Farm.detail = "Boss already took damage; skip timer disabled until it dies."
            elseif not Farm.autoRespawnResume
                and os.clock() - Farm.autoArrivedAt >= Settings.BossNoAttackTimeout then
                advanceAutoBoss("Target unavailable before first damage; skipped", rootPart, true)
            elseif Farm.autoRespawnResume then
                Farm.status = "AUTO BOSS RESUME"
                Farm.detail = "Waiting for the same boss to respawn. Auto Boss remains enabled."
            end
            return
        end
        if not hp or hp <= 0 or not targetRoot or not attackHealthAllowed(maximum) then
            Farm.stopM1()
            Farm.restoreHitbox()
            combatPose = nil
            Farm.selected = nil
            local nearest = math.huge
            for _, record in ipairs(Farm.records) do
                local current, maxHealth, _, candidateRoot = Farm.read(record)
                if current and current > 0 and candidateRoot and attackHealthAllowed(maxHealth) then
                    local distance = (candidateRoot.Position - rootPart.Position).Magnitude
                    if distance < nearest then
                        nearest, Farm.selected, targetRoot = distance, record, candidateRoot
                    end
                end
            end
            if not Farm.selected then
                pause("WAITING", "No living qualifying NPC loaded. Move near one and Rescan."); return
            end
        end
        if farmCharacter and farmCharacter ~= character then Farm.release(false) end
        if not farmCharacter then
            farmCharacter, origin = character, character:GetPivot()
            rotationState = {humanoid = humanoid, autoRotate = humanoid.AutoRotate}
            prepareFarmCollision(character)
        end
        humanoid.AutoRotate = false
        expandHitbox(targetRoot)
        combatPose = {character = character, humanoid = humanoid, rootPart = rootPart, targetRoot = targetRoot}
        makeCombatPose(character, humanoid, rootPart, targetRoot)
        State.farming = true
        watchTarget(Farm.selected, targetRoot)
        if Settings.AutoBoss then
            local now = os.clock()
            if Farm.autoCombatAt == 0 then

                Farm.autoCombatAt = now
                Farm.autoLastProgressAt = now
                Farm.autoLastHP = hp
                Farm.autoEngaged = false
            else
                local previousHP = Farm.autoLastHP
                if previousHP ~= nil and hp < previousHP - 0.01 then

                    Farm.autoEngaged = true
                    Farm.autoLastProgressAt = now
                    Farm.guardian.recoveries = 0
                    Farm.guardian.lastAction, Farm.guardian.lastActionAt = "BOSS DAMAGED", now
                end
                Farm.autoLastHP = hp
            end

            if not Farm.autoEngaged and now - Farm.autoCombatAt >= Settings.BossNoAttackTimeout then
                advanceAutoBoss("No first damage within 5s; skipped", rootPart, true)
                return
            end
        end
        if System and type(System.recordTarget) == "function" then
            pcall(function() System.recordTarget(Farm.selected) end)
        end
        stepM1()
        Farm.status = Settings.AutoBoss and "AUTO BOSS FARMING" or "FARMING"
        Farm.detail = Settings.AutoBoss
            and string.format("%s | %s | Guardian: %s | route %d visited, %d skipped", Farm.m1Status, Farm.selected.name,
                Farm.guardianStatus(),
                (function() local n=0 for _ in pairs(Farm.autoVisited) do n=n+1 end return n end)(), Farm.autoSkipped)
            or (Farm.m1Status .. " | " .. Farm.selected.name)
    end
    function Farm.step()
        if not State.alive or Farm.updating then return end
        -- Give Auto Boss a short recovery window after a runtime fault instead
        -- of immediately re-entering the exact failing path every frame.
        if Settings.AutoBoss and Farm.autoBossErrorAt and Farm.autoBossErrorAt > 0
            and os.clock() - Farm.autoBossErrorAt < 0.75 then
            return
        end
        Farm.updating = true
        local ok, err = pcall(update)
        Farm.updating = false
        if not ok then
            -- A transient Auto Boss error must not disable Auto Boss.  The
            -- previous handler hard-disabled both FarmEnabled and AutoBoss,
            -- which is exactly why the toggle snapped off on activation.
            if Settings.AutoBoss then
                Farm.autoBossError = tostring(err)
                Farm.autoBossErrorAt = os.clock()
                Farm.fault = nil
                Settings.FarmEnabled = true
                Settings.AutoBoss = true
                Farm.stopM1()
                Farm.restoreHitbox()
                Farm.clearLoot()
                Farm.selected = nil
                Farm.pinned = nil
                Farm.travelKey, Farm.travelAt, Farm.travelHealth = nil, nil, nil
                Farm.autoEngaged = false
                Farm.autoDefeated = false
                Farm.nextScan = os.clock() + 0.75
                Farm.status = "AUTO BOSS RETRYING"
                Farm.detail = "Recovered from a startup/runtime error; retrying boss scan: " .. tostring(err)
                warn("AutoSkills Auto Boss recovered: " .. tostring(err))
            else
                if Farm.stopDiscovery then Farm.stopDiscovery("Discovery stopped after an error") end
                Settings.FarmEnabled = false
                Settings.AutoBoss = false
                resetAutoBossRoute(true)
                Farm.fault = "Farming stopped. Toggle on to retry."
                Farm.release(false)
                Farm.status, Farm.detail = "ERROR", Farm.fault
                warn("AutoSkills Farm: " .. tostring(err))
            end
        end
    end
    stopFarm = function()
        if Farm.stopDiscovery then Farm.stopDiscovery() end
        Farm.saveConfig(true)
        Settings.FarmEnabled = false
        Settings.AutoBoss = false
        resetAutoBossRoute(true)
        Farm.release(false)
    end
    local runOK, Run = pcall(function() return game:GetService("RunService") end)
    if runOK then

        connect(Run.Stepped, function()
            local pose = combatPose
            if not State.alive or not State.farming or not pose then return end
            if pose.character and pose.character.Parent and pose.rootPart and pose.rootPart.Parent
                and pose.targetRoot and pose.targetRoot.Parent then

                local depth = math.clamp(Settings.FarmDepth, 6, 7)
                local desiredPosition = pose.targetRoot.Position - Vector3.new(0, depth, 0)
                local upright = math.abs(pose.rootPart.CFrame.UpVector.Y) > 0.55
                local displaced = (pose.rootPart.Position - desiredPosition).Magnitude > 0.45
                if upright or displaced then
                    makeCombatPose(pose.character, pose.humanoid, pose.rootPart, pose.targetRoot)
                end
            else
                combatPose = nil
            end
        end)

        local nextFarmStep = 0
        connect(Run.Stepped, function()
            local now = os.clock()
            if now < nextFarmStep then return end
            nextFarmStep = now + 0.05
            Farm.step()
        end)
    else
        task.spawn(function()
            while State.alive do Farm.step(); task.wait(0.05) end
        end)
    end
end

do
    local function finite(n) return type(n)=="number" and n==n and math.abs(n)<10000000 end
    local function valid(v) return v and finite(v.X) and finite(v.Y) and finite(v.Z) end
    local function location(object)
        if not object then return end
        if object:IsA("BasePart") then return object.Position end
        if object:IsA("Attachment") then return object.WorldPosition end
        if object:IsA("Model") then
            local part=object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart",true)
            return part and part.Position
        end
    end
    local function isCharacter(object)
        while object and object~=World and object~=playerGui do
            for _,player in ipairs(Players:GetPlayers()) do if object==player.Character then return true end end
            if object:IsA("Model") and object:FindFirstChildOfClass("Humanoid") then return true end
            object=object.Parent
        end
        return false
    end
    local known={"Enru","Akazo","Datai","Gyorei","Gyutai","Nezura","Nezurai","Tengai","Zentaro","Rengu","Giyen"}
    function Farm.scanMarkers()
        local function inspect(gui)
            if not gui:IsA("BillboardGui") and not gui:IsA("SurfaceGui") then return end
            local anchor=gui.Adornee or gui.Parent
            if not anchor or isCharacter(anchor) then return end
            local position=location(anchor)
            if not valid(position) then return end
            local texts,timer={},nil
            for _, child in ipairs(gui:GetDescendants()) do
                if child:IsA("TextLabel") or child:IsA("TextButton") then
                    local text=tostring(child.Text or ""):gsub("<[^>]+>","")
                    texts[#texts+1]=text
                    local lower=string.lower(text)
                    if lower:find("%d+:%d%d") or lower:find("%d+%s*[smh]%f[%A]")
                        or lower:find("respawn",1,true) or lower:find("spawns in",1,true) then timer=text end
                end
            end
            if not timer then return end
            local combined=string.lower(table.concat(texts," ").." "..anchor.Name.." "..gui.Name)
            local name=anchor:GetAttribute("BossName") or gui:GetAttribute("BossName")
            if type(name)~="string" or #name==0 or #name>200 then
                name=nil
                for _, candidate in ipairs(known) do
                    if combined:find("%f[%a]"..string.lower(candidate).."%f[%A]") then name=candidate;break end
                end
            end
            local key=string.format("%d_%d_%d",math.floor(position.X/32),math.floor(position.Y/32),math.floor(position.Z/32))
            local marker=Farm.markers[key]
            if not marker then
                marker={key=key,position=position,name=name}; Farm.markers[key]=marker;Farm.markDirty()
            elseif name and name~=marker.name then marker.name=name;Farm.markDirty() end
            marker.timerText,marker.timerAt=timer:sub(1,100),os.clock()
            local entry,best=nil,200
            for _, candidate in pairs(Farm.catalog) do
                if candidate.spawn and (not name or Farm.bossKey(candidate.name)==Farm.bossKey(name)) then
                    local distance=(candidate.spawn-position).Magnitude
                    if distance<best then entry,best=candidate,distance end
                end
            end
            if not entry and name then
                local path="@timer:"..key..":"..Farm.bossKey(name)
                entry={path=path,name=name,id="Timer marker; HP unverified",spawn=position,position=position}
                Farm.catalog[path]=entry;Farm.markDirty()
            end
            if entry then entry.timerText,entry.timerAt=marker.timerText,marker.timerAt end
        end
        for _, parent in ipairs({World,playerGui}) do
            for _, object in ipairs(parent:GetDescendants()) do
                if object:IsA("BillboardGui") or object:IsA("SurfaceGui") then

                    pcall(inspect,object)
                end
            end
        end
    end

    Farm.staticScanBusy = false
    Farm.staticScanCount = 0
    Farm.staticScanStatus = "Not scanned yet"
    Farm.staticScanOrigin = nil

    local function normalizedWords(object)
        local parts = {tostring(object.Name or "")}
        for key, value in pairs(object:GetAttributes()) do
            parts[#parts+1] = tostring(key)
            if type(value) == "string" or type(value) == "number" then
                parts[#parts+1] = tostring(value)
            end
        end
        local node = object.Parent
        for _ = 1, 5 do
            if not node or node == World then break end
            parts[#parts+1] = tostring(node.Name or "")
            node = node.Parent
        end
        return string.lower(table.concat(parts, " "))
    end

    local function bossNameFromObject(object, blob)
        local direct = object:GetAttribute("BossName")
            or object:GetAttribute("NPCName")
            or object:GetAttribute("Boss")
            or object:GetAttribute("EnemyName")
        if type(direct) == "string" and #direct > 0 and #direct <= 200 then
            return direct
        end

        for _, candidate in ipairs(known) do
            local lower = string.lower(candidate)
            if blob:find("%f[%a]" .. lower .. "%f[%A]") then
                return candidate
            end
        end
    end

    local function staticPosition(object)
        local current = object
        for _ = 1, 5 do
            if not current or current == World then break end
            local p = location(current)
            if valid(p) then return p end
            current = current.Parent
        end
    end

    local function staticSignal(blob, object)
        if object:GetAttribute("BossName") ~= nil
            or object:GetAttribute("BossId") ~= nil
            or object:GetAttribute("BossID") ~= nil
            or object:GetAttribute("NPCName") ~= nil then
            return true
        end

        for _, word in ipairs({
            "boss", "spawn", "spawner", "location", "marker",
            "respawn", "timer", "npcspawn", "bossspawn",
        }) do
            if blob:find(word, 1, true) then return true end
        end
        return false
    end

    local function addStaticLocation(name, position, source)
        if not name or not valid(position) then return false end

        local bossKey = Farm.bossKey(name)
        if bossKey == "" then return false end

        local nearest, nearestDistance
        for _, entry in pairs(Farm.catalog) do
            if entry.spawn and Farm.bossKey(entry.name) == bossKey then
                local distance = (entry.spawn - position).Magnitude
                if not nearestDistance or distance < nearestDistance then
                    nearest, nearestDistance = entry, distance
                end
            end
        end

        if nearest and nearestDistance <= 350 then
            if nearest.id == nil or nearest.id == "Saved location" then
                nearest.id = source or "Static map scan"
            end
            return false
        end

        local key = string.format(
            "%s:%d_%d_%d",
            bossKey,
            math.floor(position.X / 32),
            math.floor(position.Y / 32),
            math.floor(position.Z / 32)
        )
        local path = "@mapscan:" .. key

        if not Farm.catalog[path] then
            Farm.catalog[path] = {
                path = path,
                name = name,
                id = source or "Static map scan; HP verified on arrival",
                spawn = position,
                position = position,
                maximum = nil,
            }
            Farm.markDirty()
            return true
        end
        return false
    end

    function Farm.staticMapScan(force)
        if Farm.staticScanBusy then return false end
        if not force and not Settings.StaticMapScan then return false end

        Farm.staticScanBusy = true
        Farm.staticScanStatus = "Scanning replicated map from spawn..."
        render()

        task.spawn(function()
            local character = Player.Character
            local rootPart = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
            local origin = rootPart and rootPart:IsA("BasePart") and rootPart.Position
                or (World.CurrentCamera and World.CurrentCamera.CFrame.Position)
                or Vector3.new(0, 0, 0)

            Farm.staticScanOrigin = Farm.staticScanOrigin or origin
            origin = Farm.staticScanOrigin

            Farm.scan(true)
            Farm.scanMarkers()

            local found = 0
            local inspected = 0
            local descendants = World:GetDescendants()

            for _, object in ipairs(descendants) do
                inspected = inspected + 1

                if object:IsA("BasePart")
                    or object:IsA("Attachment")
                    or object:IsA("Model")
                    or object:IsA("BillboardGui")
                    or object:IsA("SurfaceGui") then

                    if not isCharacter(object) then
                        local blob = normalizedWords(object)
                        local name = bossNameFromObject(object, blob)

                        if name and staticSignal(blob, object) then
                            local position = staticPosition(object)

                            if position and (position - origin).Magnitude <= Settings.StaticScanRange then
                                if addStaticLocation(name, position, "Static map scan") then
                                    found = found + 1
                                end
                            end
                        end
                    end
                end

                if inspected % 2500 == 0 then
                    Farm.staticScanStatus = string.format(
                        "Static scan: %d objects checked / %d new boss locations",
                        inspected, found
                    )
                    render()
                    task.wait()
                end
            end

            local requested, requestLimit = 0, 128
            for _, entry in pairs(Farm.catalog) do
                if requested >= requestLimit then break end
                if entry.spawn and (entry.spawn - origin).Magnitude <= Settings.StaticScanRange then
                    requested = requested + 1
                    pcall(function()
                        Player:RequestStreamAroundAsync(entry.spawn, 0.25)
                    end)
                    task.wait(0.02)
                end
            end

            Farm.scan(true)
            Farm.scanMarkers()

            Farm.staticScanCount = 0
            for _, entry in pairs(Farm.catalog) do
                if entry.spawn and (entry.spawn - origin).Magnitude <= Settings.StaticScanRange then
                    Farm.staticScanCount = Farm.staticScanCount + 1
                end
            end

            Farm.markDirty()
            Farm.saveConfig(true)
            Farm.staticScanStatus = string.format(
                "Done: %d saved boss locations in %.0f-stud range | character never moved",
                Farm.staticScanCount, Settings.StaticScanRange
            )
            Farm.staticScanBusy = false
            if System and System.writeFriendReady then
                System.writeFriendReady()
            end
            render()
        end)

        return true
    end

    local discovery
    local sessionKey="__AutoSkills_Discovery_"..tostring(game.PlaceId or 0)
    Farm.pendingDiscovery=Settings.BossFirstDiscovery and not Farm.hadConfig and not environment[sessionKey]
    function Farm.stopDiscovery(message)
        Farm.pendingDiscovery=false
        if not discovery then return end
        local stopped=discovery;discovery=nil;State.discovering=false
        for part,collide in pairs(stopped.collisions) do pcall(function() part.CanCollide=collide end) end
        pcall(function() stopped.humanoid.AutoRotate=stopped.rotation end)
        if stopped.character==Player.Character and stopped.character.Parent and stopped.humanoid.Health>0 then
            pcall(function() stopped.character:PivotTo(stopped.origin) end)
        end
        Farm.discoveryStatus=message or "Stopped; returned to start"
        Farm.markDirty(); Farm.saveConfig(true); releaseOrPause()
    end
    local function queuePoint(run,position,label,priority)
        if not valid(position) or #run.queue>=512 then return end
        local key=string.format("%d_%d_%d",math.floor(position.X/96),math.floor(position.Y/96),math.floor(position.Z/96))
        if run.seen[key] then return end
        run.seen[key]=true
        run.queue[#run.queue+1]={position=position,label=label,priority=priority or 0}
    end
    local function addKnown(run)
        for _,marker in pairs(Farm.markers) do queuePoint(run,marker.position,marker.name or "Timer marker",2) end
        for _,entry in pairs(Farm.catalog) do
            if entry.spawn then queuePoint(run,entry.spawn,entry.name,1) end
        end
    end
    function Farm.startDiscovery()
        if discovery then Farm.stopDiscovery();return end
        Farm.pendingDiscovery=false
        local character=Player.Character
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        local part=character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
        if not humanoid or humanoid.Health<=0 or not part or part.Anchored or humanoid.Sit or humanoid.SeatPart then
            Farm.discoveryStatus="Waiting for a living, unseated character"; return false
        end
        if Guard.held or (Settings.HealthEscapeEnabled and Guard.latched) then
            Farm.discoveryStatus="Release health escape before discovery"; return false
        end
        Farm.setEnabled(false)
        State.enabled=false; releaseOrPause()
        local run={character=character,humanoid=humanoid,root=part,origin=character:GetPivot(),rotation=humanoid.AutoRotate,
            collisions={},queue={},seen={},completed=0,started=os.clock(),nextStep=0,center=part.Position}
        discovery=run;State.discovering=true;environment[sessionKey]=true
        Farm.scan(true);addKnown(run)
        if Settings.BossGridSearch then

            local radius=Settings.BossGridRadius
            local step=math.max(512,math.ceil(radius*2/20))
            for x=-radius,radius,step do
                for z=-radius,radius,step do
                    queuePoint(run,run.center+Vector3.new(x,0,z),"Grid survey",0)
                end
            end
        end
        Farm.discoveryStatus="Discovery started; M1 and skills paused"
        render(); return true
    end
    function Farm.discoveryStep()
        local run=discovery
        if not run then return false end
        if run.character~=Player.Character or not run.character.Parent or run.humanoid.Health<=0 or run.root.Anchored
            or run.humanoid.Sit or run.humanoid.SeatPart then
            Farm.stopDiscovery("Stopped: character changed or unavailable");return true
        end
        if Guard.held or (Settings.HealthEscapeEnabled and (Guard.latched or os.clock()-Guard.lastTeleport<5)) then
            Farm.stopDiscovery("Stopped for health escape");return true
        end
        if os.clock()-run.started>900 then Farm.stopDiscovery("Stopped at 15-minute discovery limit");return true end
        Farm.stopM1();State.farming=false
        run.humanoid.AutoRotate=false
        for _,part in ipairs(run.character:GetDescendants()) do
            if part:IsA("BasePart") then
                if run.collisions[part]==nil then run.collisions[part]=part.CanCollide end
                part.CanCollide=false
            end
        end
        if os.clock()>=run.nextStep then
            Farm.scan(true);addKnown(run)
            if run.destination then run.completed=run.completed+1 end
            if #run.queue==0 then
                Farm.stopDiscovery("Route complete: "..run.completed.." stops; "..#Farm.remembered.." remembered");return true
            end
            local best=1
            for i=2,#run.queue do
                local a,b=run.queue[i],run.queue[best]
                if a.priority>b.priority or (a.priority==b.priority
                    and (a.position-run.root.Position).Magnitude<(b.position-run.root.Position).Magnitude) then best=i end
            end
            local point=table.remove(run.queue,best)
            run.destination=point.position+Vector3.new(0,12,0)
            run.nextStep=os.clock()+Settings.BossDwell
            if System and type(System.recordTeleport) == "function" then
                local discoveryDistance = (run.destination - run.root.Position).Magnitude
                pcall(function() System.recordTeleport("Discovery: " .. tostring(point.label), discoveryDistance) end)
            end
            Farm.discoveryStatus=string.format("%d visited / %d queued | %s",run.completed,#run.queue+1,point.label)

            if not run.requestBusy then
                run.requestBusy=true
                task.spawn(function()
                    pcall(function() Player:RequestStreamAroundAsync(point.position,Settings.BossDwell) end)
                    run.requestBusy=false
                end)
            end
        end
        run.character:PivotTo(run.character:GetPivot()+(run.destination-run.root.Position))
        run.root.AssemblyLinearVelocity=Vector3.new(0,0,0)
        run.root.AssemblyAngularVelocity=Vector3.new(0,0,0)
        Farm.status,Farm.detail="DISCOVERING",Farm.discoveryStatus
        return true
    end
    function Farm.bootDiscovery()
        if not Farm.pendingDiscovery then return end
        task.spawn(function()

            for _=1,30 do
                task.wait(0.1)
                if not State.alive or not Farm.pendingDiscovery then return end
            end
            if State.alive and Farm.pendingDiscovery then
                local started=Farm.startDiscovery()
                if not started then notify(Farm.discoveryStatus.."; start discovery from Boss config.") end
            end
        end)
    end
end

local Movement = {
    character = nil, humanoid = nil, rootPart = nil,
    collisions = setmetatable({}, {__mode = "k"}),
    speedHumanoid = nil, speedOriginal = nil,
    flyHumanoid = nil, flyAutoRotate = nil,
    tBlocked = false,
    status = "NOCLIP ON",
    detail = "No-clip is active automatically. T is blocked while No Clip is on.",
}

local function movementCharacter()
    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local rootPart = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
    if rootPart and not rootPart:IsA("BasePart") then rootPart = nil end
    return character, humanoid, rootPart
end

function Movement.updateTBlock()
    if Settings.NoClip and not Movement.tBlocked then
        ContextActionService:BindActionAtPriority(
            "AutoSkills_BlockTWhileNoClip",
            function()
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.ContextActionPriority.High.Value + 2000,
            Enum.KeyCode.T
        )
        Movement.tBlocked = true
    elseif not Settings.NoClip and Movement.tBlocked then
        ContextActionService:UnbindAction("AutoSkills_BlockTWhileNoClip")
        Movement.tBlocked = false
    end
end

function Movement.restoreNoClip(force)
    if not force and (Settings.FarmEnabled or State.farming or State.discovering or Settings.FlyEnabled) then return end
    for part, original in pairs(Movement.collisions) do
        if part and part.Parent then
            pcall(function() part.CanCollide = original end)
        end
        Movement.collisions[part] = nil
    end
end

local function applyNoClip(character)
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if Movement.collisions[part] == nil then
                Movement.collisions[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end
end

function Movement.restoreSpeed()
    if Movement.speedHumanoid and Movement.speedHumanoid.Parent and Movement.speedOriginal then
        pcall(function() Movement.speedHumanoid.WalkSpeed = Movement.speedOriginal end)
    end
    Movement.speedHumanoid, Movement.speedOriginal = nil, nil
end

function Movement.restoreFly()
    if Movement.flyHumanoid and Movement.flyHumanoid.Parent and Movement.flyAutoRotate ~= nil then
        pcall(function() Movement.flyHumanoid.AutoRotate = Movement.flyAutoRotate end)
    end
    Movement.flyHumanoid, Movement.flyAutoRotate = nil, nil
end

local function refreshMovementCharacter()
    local character, humanoid, rootPart = movementCharacter()
    if character ~= Movement.character then
        Movement.restoreNoClip(true)
        Movement.restoreSpeed()
        Movement.restoreFly()
        Movement.character, Movement.humanoid, Movement.rootPart = character, humanoid, rootPart
    else
        Movement.humanoid, Movement.rootPart = humanoid, rootPart
    end
    return character, humanoid, rootPart
end

function Movement.setNoClip(value)
    Settings.NoClip = value
    Movement.updateTBlock()
    if not value and not Settings.FlyEnabled then Movement.restoreNoClip(false) end
    Movement.status = value and "NOCLIP ON" or "NOCLIP OFF"
    Movement.detail = value
        and "Collision disabled. T is blocked while No Clip is active."
        or "Collision restored when Auto Farm/Fly is not using it."
    render()
end

function Movement.setFly(value)
    Settings.FlyEnabled = value
    if value then

        Settings.NoClip = true
        Movement.updateTBlock()
    else
        Movement.restoreFly()
    end
    Movement.status = value and "FLY ON" or (Settings.NoClip and "NOCLIP ON" or "MOVEMENT")
    Movement.detail = value
        and "3D camera flight: WASD / Space or E up / Ctrl or Q down."
        or "Fly disabled."
    render()
end

function Movement.setSpeed(value)
    Settings.SpeedEnabled = value
    if not value then Movement.restoreSpeed() end
    Movement.status = value and "SPEED ON" or (Settings.FlyEnabled and "FLY ON" or (Settings.NoClip and "NOCLIP ON" or "MOVEMENT"))
    Movement.detail = value and ("WalkSpeed locked to " .. tostring(Settings.WalkSpeed) .. ".") or "Speed override disabled."
    render()
end

function Movement.step(dt)
    if not State.alive then return end

    Movement.updateTBlock()

    local character, humanoid, rootPart = refreshMovementCharacter()
    if not character or not character.Parent or not humanoid or humanoid.Health <= 0 or not rootPart then
        Movement.status, Movement.detail = "WAITING", "Waiting for your character."
        return
    end

    if Settings.NoClip or Settings.FlyEnabled then
        applyNoClip(character)
    else
        Movement.restoreNoClip(false)
    end

    local farmBusy = Settings.FarmEnabled or State.farming or State.discovering

    if Settings.SpeedEnabled and not farmBusy and not Settings.FlyEnabled then
        if Movement.speedHumanoid ~= humanoid then
            Movement.restoreSpeed()
            Movement.speedHumanoid, Movement.speedOriginal = humanoid, humanoid.WalkSpeed
        end
        humanoid.WalkSpeed = Settings.WalkSpeed
    else
        Movement.restoreSpeed()
    end

    if Settings.FlyEnabled and not farmBusy and not rootPart.Anchored then
        if Movement.flyHumanoid ~= humanoid then
            Movement.restoreFly()
            Movement.flyHumanoid, Movement.flyAutoRotate = humanoid, humanoid.AutoRotate
        end
        humanoid.AutoRotate = false

        local camera = World.CurrentCamera
        local cf = camera and camera.CFrame or rootPart.CFrame

        local forward = cf.LookVector
        local right = cf.RightVector
        local worldUp = Vector3.new(0, 1, 0)

        local direction = Vector3.new(0, 0, 0)

        if Input:IsKeyDown(Enum.KeyCode.W) then direction = direction + forward end
        if Input:IsKeyDown(Enum.KeyCode.S) then direction = direction - forward end
        if Input:IsKeyDown(Enum.KeyCode.D) then direction = direction + right end
        if Input:IsKeyDown(Enum.KeyCode.A) then direction = direction - right end

        if Input:IsKeyDown(Enum.KeyCode.Space) or Input:IsKeyDown(Enum.KeyCode.E) then
            direction = direction + worldUp
        end
        if Input:IsKeyDown(Enum.KeyCode.LeftControl) or Input:IsKeyDown(Enum.KeyCode.Q) then
            direction = direction - worldUp
        end

        if direction.Magnitude > 1 then direction = direction.Unit end

        local frameDelta = math.clamp(dt or 0, 0, 0.05)
        local delta = direction * Settings.FlySpeed * frameDelta

        if delta.Magnitude > 0 then
            character:PivotTo(character:GetPivot() + delta)
        end

        rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

        Movement.status = "FLY ON"
        Movement.detail = string.format(
            "Fly %.0f | WASD + camera pitch | Space/E up | Ctrl/Q down | No Clip ON",
            Settings.FlySpeed
        )
    else
        Movement.restoreFly()

        if Settings.FlyEnabled and farmBusy then
            Movement.status, Movement.detail = "FLY PAUSED", "Auto Farm / discovery has movement priority."
        elseif Settings.SpeedEnabled then
            Movement.status, Movement.detail = "SPEED ON", string.format("WalkSpeed %.0f", Settings.WalkSpeed)
        elseif Settings.NoClip then
            Movement.status, Movement.detail = "NOCLIP ON", "Collision disabled. T is blocked."
        else
            Movement.status, Movement.detail = "MOVEMENT", "All movement overrides are off."
        end
    end
end

stopMovement = function()
    Settings.FlyEnabled = false
    Settings.SpeedEnabled = false
    Settings.NoClip = false
    Movement.updateTBlock()
    Movement.restoreFly()
    Movement.restoreSpeed()
    Movement.restoreNoClip(true)
end

Movement.updateTBlock()

do
    local okRun, Run = pcall(function() return game:GetService("RunService") end)
    if okRun and Run then
        connect(Run.Stepped, function(_, dt) Movement.step(dt) end)
    else
        task.spawn(function()
            local previous = os.clock()
            while State.alive do
                local now = os.clock()
                Movement.step(now - previous)
                previous = now
                task.wait(0.03)
            end
        end)
    end
end

System = {
    configPath = "AutoSkills_System_v1.json",
    themeConfigPath = "AutoSkills_Theme_v1.txt",
    themeStatePath = "AutoSkills_Theme_v2.state",
    bodyPath = "AutoSkills_Void_AutoRun.lua",
    autoexecPath = "autoexec/AutoSkills_Void.lua",
    targetGameId = tostring(game.GameId or 0),
    status = "READY",
    detail = "Static map scan and recovery services ready.",
    persistStatus = "Checking executor persistence...",
    rejoinStatus = "Watching private-server state.",
    friendReadyPath = "AutoSkills_FriendReady.lua",
    friendReadyStatus = "Friend seed bundle not built yet.",
    lastPrivatePlace = nil,
    lastPrivateJob = nil,
    rejoinRequested = false,
    directTriedAt = 0,
    menuNextAt = 0,
    menuStage = "idle",
    theme = "Default",
    startupTheme = "Default",
    bootstrapTheme = nil,
    _themeFileLoaded = false,
    _sessionThemeLoaded = false,
    profilePath = "AutoSkills_Profiles_v1.json",
    profiles = {},
    activeProfile = "Default",
    notificationLog = {},
    commandOpen = false,
    safetyStatus = "SAFE",
    safetyDetail = "Recovery monitor armed.",
    stats = {runtime=0, kills=0, targets=0, loots=0, teleports=0, bosses=0, lastTarget="--", startedAt=time()},
    statsLastCycles = 0,
    statsLastTarget = nil,
    statsKillSeen = setmetatable({}, {__mode="k"}),
    statsTargetSeen = setmetatable({}, {__mode="k"}),
    statsLootSeen = setmetatable({}, {__mode="k"}),
    -- Realtime analytics observer state.  These tables let analytics detect
    -- target acquisition and deaths even when a HealthChanged event is missed
    -- or the farm switches targets between heartbeat ticks.
    statsHealthSeen = setmetatable({}, {__mode="k"}),
    statsBossTargetSeen = setmetatable({}, {__mode="k"}),
    statsLastObservedTarget = nil,
    locationsFilter = "",
    keybinds = {
        ToggleAutomation = Enum.KeyCode.F6, StopAutomation = Enum.KeyCode.F7, ToggleUI = Enum.KeyCode.RightShift,
        ToggleESP = Enum.KeyCode.F8, ToggleHealth = Enum.KeyCode.F9, CommandPalette = Enum.KeyCode.K,
        EmergencyStop = Enum.KeyCode.End,
    },
    keybindCapture = nil,
    themeRegistry = {
        Default={name="Default", loader="VOID NEXUS", effects=true},
        Blackhole={name="Blackhole", loader="BLACKHOLE V1", effects=true},
        Empyrean={name="Empyrean", loader="EMPYREAN", effects=true},
        Frost={name="Frost", loader="FROSTBOUND", effects=true},
    },
}

-- The outer bootstrap resolves the theme BEFORE this body is executed.
-- Treat that value as the authoritative startup theme for this execution.
local function getBootstrapTheme()
    local ok, value = pcall(function()
        return environment.__AutoSkills_StartupTheme or environment.__AutoSkills_LastTheme
    end)
    return ok and value or nil
end

-- Roblox-session persistence: this survives script destruction/re-execution even
-- when the executor does not preserve getgenv() or writefile state.
local function getSessionTheme()
    local value
    pcall(function()
        value = Player:GetAttribute("AutoSkills_Theme")
            or Player:GetAttribute("AutoSkills_StartupTheme")
            or Player:GetAttribute("AutoSkills_LastTheme")
    end)
    if value then return value end
    pcall(function()
        value = playerGui:GetAttribute("AutoSkills_StartupTheme")
            or playerGui:GetAttribute("AutoSkills_LastTheme")
    end)
    return value
end

local function setSessionTheme(value)
    -- Player attributes survive PlayerGui replacement/respawn and are therefore
    -- the primary same-session persistence layer.
    pcall(function()
        Player:SetAttribute("AutoSkills_Theme", value)
        Player:SetAttribute("AutoSkills_StartupTheme", value)
        Player:SetAttribute("AutoSkills_LastTheme", value)
    end)
    pcall(function()
        playerGui:SetAttribute("AutoSkills_StartupTheme", value)
        playerGui:SetAttribute("AutoSkills_LastTheme", value)
    end)
    pcall(function()
        environment.__AutoSkills_StartupTheme = value
        environment.__AutoSkills_LastTheme = value
    end)
end

do
    local reader = type(readfile) == "function" and readfile or environment.readfile
    local writer = type(writefile) == "function" and writefile or environment.writefile
    local exists = type(isfile) == "function" and isfile or environment.isfile
    local deleter = type(delfile) == "function" and delfile or environment.delfile
    local mkdir = type(makefolder) == "function" and makefolder or environment.makefolder

    System.reader, System.writer, System.exists, System.deleter, System.mkdir =
        reader, writer, exists, deleter, mkdir

    local function finiteText(value, limit)
        return type(value) == "string" and #value > 0 and #value <= (limit or 200)
    end

    local function normalizeTheme(value)
        if type(value) ~= "string" then return nil end
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
        if value == "Default" or value == "Blackhole" or value == "Empyrean" or value == "Frost" then
            return value
        end
        return nil
    end

    function System.loadPrefs()
        -- Theme startup is deliberately isolated from the general JSON settings.
        -- The dedicated theme state is authoritative; the old JSON Theme field
        -- is NEVER allowed to select the startup loader/UI.
        System._themeFileLoaded = false
        System._sessionThemeLoaded = false
        local bootstrap = getBootstrapTheme()
        System.bootstrapTheme = bootstrap
        -- The dedicated theme files are authoritative when available. This
        -- prevents an old PlayerGui attribute from pinning the UI to Blackhole.
        -- Same-session Player/executor state is the fallback when file APIs are
        -- unavailable.
        local candidates = {}
        -- Current Roblox session is authoritative. Old disk state is fallback only.
        candidates[#candidates + 1] = bootstrap
        candidates[#candidates + 1] = getSessionTheme()
        candidates[#candidates + 1] = environment.__AutoSkills_StartupTheme
        candidates[#candidates + 1] = environment.__AutoSkills_LastTheme
        if type(reader) == "function" then
            local ok1, raw1 = pcall(reader, System.themeStatePath)
            if ok1 then candidates[#candidates + 1] = raw1 end
            local ok2, raw2 = pcall(reader, System.themeConfigPath)
            if ok2 then candidates[#candidates + 1] = raw2 end
        end
        for _, candidate in ipairs(candidates) do
            local restored = normalizeTheme(candidate)
            if restored then
                System.theme = restored
                System.startupTheme = restored
                System._themeFileLoaded = true
                break
            end
        end

        -- Load the rest of the settings independently. The old JSON Theme field
        -- is intentionally ignored so stale Blackhole data cannot override the
        -- dedicated theme state.
        if type(reader) ~= "function" then return end
        local raw
        local okRead, result = pcall(reader, System.configPath)
        if okRead and type(result) == "string" and #result > 0 then
            raw = result
        end

        if raw then
            local ok, data = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            if ok and type(data) == "table" then
                if type(data.StaticMapScan) == "boolean" then Settings.StaticMapScan = data.StaticMapScan end
                if type(data.AutoRejoin) == "boolean" then Settings.AutoRejoin = data.AutoRejoin end
                if type(data.AutoExecute) == "boolean" then Settings.AutoExecute = data.AutoExecute end
                if finiteText(data.PrivateServerMap, 80) then Settings.PrivateServerMap = data.PrivateServerMap end
                if finiteText(data.TargetGameId, 40) then System.targetGameId = data.TargetGameId end
                if finiteText(data.LastPrivateJob, 120) then System.lastPrivateJob = data.LastPrivateJob end
                if type(data.LastPrivatePlace) == "number" then System.lastPrivatePlace = data.LastPrivatePlace end
            end
        end
    end

    function System.savePrefs()
        local themeSaved = false
        local jsonSaved = false
        local themeToSave = normalizeTheme(System.theme) or "Default"
        -- Roblox-session persistence is authoritative for re-execution.
        -- This succeeds independently of writefile/readfile.
        setSessionTheme(themeToSave)
        themeSaved = true
        -- Always persist to the shared executor environment as well. This is
        -- available immediately on the next re-execution even if writefile is
        -- unavailable or rejects the persistence path.
        pcall(function()
            environment.__AutoSkills_LastTheme = themeToSave
            environment.__AutoSkills_StartupTheme = themeToSave
        end)

        -- Theme persistence is independent from the large JSON file. Write the
        -- same authoritative value to two dedicated files so a stale/failed
        -- legacy preference cannot determine the next loader.
        if type(writer) == "function" then
            local paths = {System.themeStatePath, System.themeConfigPath}
            for _, path in ipairs(paths) do
                local okWrite = pcall(writer, path, themeToSave)
                if okWrite and type(reader) == "function" then
                    -- Verification is useful diagnostically, but failure here
                    -- must never invalidate the already-successful session save.
                    local okRead, savedRaw = pcall(reader, path)
                    if not okRead or normalizeTheme(savedRaw) ~= themeToSave then
                        System.persistStatus = "Theme saved to session; file backup could not be verified."
                    end
                end
            end
        end

        if type(writer) == "function" then
            local ok, err = pcall(function()
                writer(System.configPath, HttpService:JSONEncode({
                    schema = 1,
                    StaticMapScan = Settings.StaticMapScan,
                    AutoRejoin = Settings.AutoRejoin,
                    AutoExecute = Settings.AutoExecute,
                    Theme = themeToSave,
                    PrivateMap = Settings.PrivateServerMap,
                    PrivateServerMap = Settings.PrivateServerMap,
                    TargetGameId = System.targetGameId,
                    LastPrivatePlace = System.lastPrivatePlace,
                    LastPrivateJob = System.lastPrivateJob,
                }))
            end)
            jsonSaved = ok
            if not ok then
                System.persistStatus = "Theme saved separately; settings JSON write failed: " .. tostring(err)
            end
        end

        if themeSaved then
            System.persistStatus = jsonSaved
                and ("Preferences saved | Theme: " .. themeToSave)
                or "Theme saved | Settings JSON unavailable"
            return true
        end

        if jsonSaved then
            System.persistStatus = "Settings saved, but theme-file verification failed."
            return false
        end

        System.persistStatus = "Theme persistence failed: writefile/readfile unavailable or rejected the file."
        return false
    end

    -- ========================= CONTROL SERVICES =========================
    local function profileSnapshot()
        local snapshot = {schema=2, theme=System.theme, settings={}, skills={}, keybinds={}, ui={width=windowWidth or 420, height=windowHeight or 560, scale=Settings.UIScale, opacity=Settings.UIOpacity}}
        for k,v in pairs(Settings) do
            if type(v)=="boolean" or type(v)=="number" or type(v)=="string" then snapshot.settings[k]=v end
        end
        for i,skill in ipairs(Skills) do snapshot.skills[i]={name=skill.name, enabled=skill.enabled, key=skill.key.Name} end
        for k,v in pairs(System.keybinds) do snapshot.keybinds[k]=v.Name end
        return snapshot
    end
    local function applyProfileSnapshot(data)
        if type(data)~="table" then return false end
        if type(data.settings)=="table" then
            for k,v in pairs(data.settings) do
                if Settings[k]~=nil and (type(v)==type(Settings[k])) then Settings[k]=v end
            end
        end
        if type(data.skills)=="table" then
            for i,entry in ipairs(data.skills) do
                if Skills[i] and type(entry)=="table" then
                    if type(entry.enabled)=="boolean" then Skills[i].enabled=entry.enabled end
                    if type(entry.key)=="string" and Enum.KeyCode[entry.key] then Skills[i].key=Enum.KeyCode[entry.key] end
                end
            end
        end
        if type(data.keybinds)=="table" then
            for k,v in pairs(data.keybinds) do if type(v)=="string" and Enum.KeyCode[v] then System.keybinds[k]=Enum.KeyCode[v] end end
        end
        if type(data.ui)=="table" then
            if type(data.ui.scale)=="number" then Settings.UIScale=math.clamp(data.ui.scale,.75,1.25) end
            if type(data.ui.opacity)=="number" then Settings.UIOpacity=math.clamp(data.ui.opacity,.35,1) end
        end
        return true
    end
    function System.saveProfile(name)
        name=tostring(name or "Default"):gsub("[^%w _%-]",""):sub(1,32); if name=="" then name="Default" end
        System.profiles[name]=profileSnapshot(); System.activeProfile=name
        if System.writer then pcall(System.writer,System.profilePath,HttpService:JSONEncode(System.profiles)) end
        System.notify("Profile saved: "..name); render(); return true
    end
    function System.loadProfile(name)
        name=tostring(name or System.activeProfile or "Default"); local data=System.profiles[name]
        if not data and System.reader and System.exists and pcall(System.exists,System.profilePath) then
            local ok,raw=pcall(System.reader,System.profilePath); if ok then local good,parsed=pcall(HttpService.JSONDecode,HttpService,raw); if good and type(parsed)=="table" then System.profiles=parsed; data=System.profiles[name] end end
        end
        if not data then System.notify("Profile not found: "..name); return false end
        applyProfileSnapshot(data); System.activeProfile=name
        if data.theme and UI and UI.setTheme then task.defer(function() UI.setTheme(data.theme) end) end
        System.notify("Profile loaded: "..name); render(); return true
    end
    function System.duplicateProfile(name)
        local base=System.profiles[name] or profileSnapshot(); local target=(name=="Default" and "Custom 01" or name.." Copy"):sub(1,32); local i=1
        while System.profiles[target] do i=i+1; target=(name.." Copy "..i):sub(1,32) end
        System.profiles[target]=base; System.activeProfile=target
        if CoreUI and CoreUI.profileInput then CoreUI.profileInput.Text=target end
        if System.writer then pcall(System.writer,System.profilePath,HttpService:JSONEncode(System.profiles)) end
        System.notify("Profile duplicated: "..target); render(); return true
    end
    function System.deleteProfile(name)
        if name=="Default" then System.notify("Default profile is protected."); return false end
        System.profiles[name]=nil; if System.activeProfile==name then System.activeProfile="Default" end
        if System.writer then pcall(System.writer,System.profilePath,HttpService:JSONEncode(System.profiles)) end
        System.notify("Profile deleted: "..name); render(); return true
    end
    function System.notify(message)
        if not Settings.NotificationsEnabled then return end
        message=tostring(message or ""); table.insert(System.notificationLog,1,{time=os.date("%H:%M:%S"),message=message})
        while #System.notificationLog>100 do table.remove(System.notificationLog) end
        pcall(notify,message)
    end
    function System.registerTheme(name, metadata)
        name=tostring(name or ""):gsub("^%s+",""):gsub("%s+$",""); if name=="" then return false end
        if type(metadata)~="table" then metadata={} end
        metadata.name=name; System.themeRegistry[name]=metadata; return true
    end
    function System.getThemes() local out={}; for name,data in pairs(System.themeRegistry) do out[#out+1]={name=name,metadata=data} end; table.sort(out,function(a,b) return a.name<b.name end); return out end
    -- Session Analytics event API.
    --
    -- Analytics are deliberately driven by actual farm state transitions rather
    -- than by Farm's route loop.  A route can scan many times without being a
    -- new target, and a target can die between two Farm.step() calls.  The
    -- observer below therefore owns the session event state and Farm calls only
    -- provide authoritative hints (target acquired / kill / loot / teleport).
    function System.refreshStatsUI()
        if not CoreUI or not CoreUI.statsLabel or not CoreUI.statsLabel.Parent then return end
        local now = time()
        local started = tonumber(System.stats.startedAt) or now
        local runtime = math.max(0, now - started)
        System.stats.runtime = runtime
        local sec=math.max(0, math.floor(runtime))
        local h=math.floor(sec/3600); local m=math.floor((sec%3600)/60); local ss=sec%60
        local hours = math.max(runtime / 3600, 1 / 3600)
        local targetsPerHour = System.stats.targets / hours
        local killsPerHour = System.stats.kills / hours
        local bossesPerHour = System.stats.bosses / hours
        local lootsPerHour = System.stats.loots / hours
        local teleportsPerHour = System.stats.teleports / hours
        local killRate = System.stats.targets > 0 and (System.stats.kills / System.stats.targets) * 100 or 0

        CoreUI.statsLabel.Text=string.format(
            "Runtime %02d:%02d:%02d  |  Targets %d  |  Kills %d\nLoots %d  |  Bosses %d  |  Teleports %d",
            h,m,ss,System.stats.targets,System.stats.kills,System.stats.loots,System.stats.bosses,System.stats.teleports)

        if CoreUI.efficiencyLabel then
            CoreUI.efficiencyLabel.Text = string.format(
                "RATE / HOUR   Targets %.1f   Kills %.1f   Bosses %.1f\n" ..
                "Loots %.1f   Teleports %.1f   Kill Rate %.1f%%",
                targetsPerHour, killsPerHour, bossesPerHour, lootsPerHour, teleportsPerHour, killRate)
        end

        local target = Farm and Farm.selected or nil
        local hp, maxHp = nil, nil
        if target and Farm and Farm.read then
            local ok, a, b = pcall(Farm.read, target)
            if ok then hp, maxHp = a, b end
        end
        local distanceText = "--"
        if target and target.humanoid and target.humanoid.Parent and Player and Player.Character then
            local hrp = Player.Character:FindFirstChild("HumanoidRootPart") or Player.Character.PrimaryPart
            local tr = target.root or target.part or (target.humanoid.Parent and (target.humanoid.Parent:FindFirstChild("HumanoidRootPart") or target.humanoid.Parent.PrimaryPart))
            if hrp and tr and tr:IsA("BasePart") then
                distanceText = string.format("%.0f", (hrp.Position - tr.Position).Magnitude)
            end
        end
        if CoreUI.liveLabel then
            local targetName = tostring((target and target.name) or System.stats.lastTarget or "--")
            local hpText = (hp and maxHp) and string.format("%.0f / %.0f HP", hp, maxHp) or "-- / -- HP"
            local action = tostring((Farm and Farm.status) or "IDLE")
            CoreUI.liveLabel.Text = string.format("LIVE   %s\nHP %s   |   %s studs   |   %s", targetName, hpText, distanceText, action)
        end
        if CoreUI.targetLabel then CoreUI.targetLabel.Text="Last Target: "..tostring(System.stats.lastTarget or "--") end
        if CoreUI.safetyLabel then
            CoreUI.safetyLabel.Text="Safety: "..tostring(System.safetyStatus)
            CoreUI.safetyLabel.TextColor3=(System.safetyStatus=="SAFE" and C.green or C.amber)
        end

        -- Mini Mode has a dedicated updater so it cannot become stale when
        -- the main Control Center is hidden or not rendered.
        pcall(function() MiniMode.updateLive() end)
    end

    local function statsRecordIsBoss(record)
        if not record then return false end
        if record.isBoss == true then return true end
        if not Farm then return false end
        local path = record.path
        if path and Farm.catalog and Farm.catalog[path] then
            return Settings.AutoBoss == true or Farm.pinned == path or Farm.autoCurrent == path
        end
        return false
    end

    function System.recordTarget(record)
        if not record or not record.humanoid then return false end
        local humanoid = record.humanoid
        if not humanoid.Parent then return false end
        if System.statsTargetSeen[humanoid] then
            System.stats.lastTarget = tostring(record.name or System.stats.lastTarget or "--")
            return false
        end
        System.statsTargetSeen[humanoid] = true
        System.statsHealthSeen[humanoid] = tonumber(humanoid.Health) or 0
        System.statsBossTargetSeen[humanoid] = statsRecordIsBoss(record)
        System.stats.targets = System.stats.targets + 1
        System.stats.lastTarget = tostring(record.name or "Unknown target")
        System.refreshStatsUI()
        return true
    end

    function System.recordKill(record)
        if not record or not record.humanoid then return false end
        local humanoid = record.humanoid
        if System.statsKillSeen[humanoid] then return false end
        local hp = tonumber(humanoid.Health)
        if hp and hp > 0 then return false end

        -- A kill must always have been a tracked engagement.  If the kill was
        -- observed before the target-acquisition tick, register the target first.
        if not System.statsTargetSeen[humanoid] then
            System.recordTarget(record)
        end

        System.statsKillSeen[humanoid] = true
        System.stats.kills = System.stats.kills + 1
        System.stats.lastTarget = tostring(record.name or System.stats.lastTarget or "--")
        if System.statsBossTargetSeen[humanoid] or statsRecordIsBoss(record) then
            System.stats.bosses = System.stats.bosses + 1
        end
        System.refreshStatsUI()
        return true
    end

    function System.recordLoot(item)
        if not item then return false end
        local key = item.entity or item.object or item.part
        if key and System.statsLootSeen[key] then return false end
        if key then System.statsLootSeen[key] = true end
        System.stats.loots = System.stats.loots + 1
        System.refreshStatsUI()
        return true
    end

    -- Teleport analytics use a two-stage model.  Farm code calls recordTeleport
    -- immediately before/after a PivotTo, so the call itself is only a hint.
    -- The realtime movement observer below confirms the actual displacement.
    System.statsTeleportPending = nil
    System.statsLastTeleportAt = 0
    System.statsLastTeleportPosition = nil

    function System.recordTeleport(reason, distance, alreadyMoved)
        distance = tonumber(distance) or 0
        if distance < 5 then return false end

        -- Some paths (Health Escape) call this after PivotTo has already happened.
        -- Those are explicitly confirmed by the caller and can be counted now.
        if alreadyMoved == true then
            System.stats.teleports = System.stats.teleports + 1
            System.statsLastTeleportAt = time()
            System.statsTeleportPending = nil
            System.refreshStatsUI()
            return true
        end

        -- Otherwise remember the expected movement and let the observer confirm
        -- that the character actually changed position.
        local char = Player and Player.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
        System.statsTeleportPending = {
            reason = tostring(reason or "Automation"),
            distance = distance,
            at = time(),
            origin = root and root.Position or nil,
        }
        return true
    end

    function System.confirmTeleport(reason, distance)
        distance = tonumber(distance) or 0
        if distance < 5 then return false end
        System.stats.teleports = System.stats.teleports + 1
        System.statsLastTeleportAt = time()
        System.statsTeleportPending = nil
        System.refreshStatsUI()
        return true
    end

    function System.resetStats()
        System.stats={runtime=0,kills=0,targets=0,loots=0,teleports=0,bosses=0,lastTarget="--",startedAt=time()}
        System.statsLastCycles=0
        System.statsLastTarget=nil
        System.statsLastObservedTarget=nil
        System.statsTargetSeen=setmetatable({}, {__mode="k"})
        System.statsKillSeen=setmetatable({}, {__mode="k"})
        System.statsLootSeen=setmetatable({}, {__mode="k"})
        System.statsHealthSeen=setmetatable({}, {__mode="k"})
        System.statsBossTargetSeen=setmetatable({}, {__mode="k"})
        System.statsTeleportPending=nil
        System.statsLastTeleportAt=0
        System.statsLastTeleportPosition=nil
        System.refreshStatsUI()
        System.notify("Session statistics reset")
        render()
    end
    function System.emergencyStop()
        pcall(setEnabled,false); pcall(Farm.setEnabled,false); pcall(Farm.setAutoBoss,false); pcall(stopMovement); pcall(stopHealthGuard); System.safetyStatus="EMERGENCY STOP"; System.safetyDetail="All automation modules were stopped."; System.notify("EMERGENCY STOP"); render()
    end
    function System.toggleSafety() Settings.SafetyEnabled=not Settings.SafetyEnabled; System.safetyStatus=Settings.SafetyEnabled and "SAFE" or "DISABLED"; System.notify("Safety system "..(Settings.SafetyEnabled and "enabled" or "disabled")); System.savePrefs(); render() end
    function System.showLocations() State.tab="Farm"; render(); System.notify("Opening location database") end
    function System.showKeybinds() System.notify("Opening keybind manager") end
    function System.showNotifications() System.notify("Opening notification center") end
    function System.toggleCommandPalette() System.commandOpen=not System.commandOpen; if UI and UI.commandOverlay then UI.commandOverlay.Visible=System.commandOpen; if System.commandOpen then UI.commandInput:CaptureFocus() end end end
    function System.executeCommand(q)
        q=tostring(q or ""):lower():gsub("^%s+",""):gsub("%s+$","")
        if q=="" then return end
        local commands={
            ["boss"]=function() State.tab="Farm"; Settings.AutoBoss=true; Farm.setAutoBoss(true) end,
            ["auto boss"]=function() State.tab="Farm"; Farm.setAutoBoss(not Settings.AutoBoss) end,
            ["esp players"]=function() State.tab="ESP"; setESPEnabled(not Settings.ESPEnabled) end,
            ["stop"]=System.emergencyStop,
            ["emergency stop"]=System.emergencyStop,
            ["theme empyrean"]=function() if UI.setTheme then UI.setTheme("Empyrean") end end,
            ["theme blackhole"]=function() if UI.setTheme then UI.setTheme("Blackhole") end end,
            ["theme default"]=function() if UI.setTheme then UI.setTheme("Default") end end,
            ["theme frost"]=function() if UI.setTheme then UI.setTheme("Frost") end end,
            ["core"]=function() State.tab="Core"; render() end,
            ["stats"]=function() State.tab="Core"; render() end,
        }
        local fn=commands[q]
        if fn then fn(); System.commandOpen=false; if UI.commandOverlay then UI.commandOverlay.Visible=false end; System.notify("Command executed: "..q); render(); return true end
        System.notify("Unknown command: "..q); return false
    end
    function System.initProfiles()
        if System.reader and System.exists then
            local ok,exists=pcall(System.exists,System.profilePath)
            if ok and exists then local good,raw=pcall(System.reader,System.profilePath); if good then local parsedOK,parsed=pcall(HttpService.JSONDecode,HttpService,raw); if parsedOK and type(parsed)=="table" then System.profiles=parsed end end end
        end
        System.profiles.Default=System.profiles.Default or profileSnapshot(); System.activeProfile="Default"
        local gameProfile="Game_"..tostring(game.PlaceId or 0)
        if System.profiles[gameProfile] then
            System.activeProfile=gameProfile; applyProfileSnapshot(System.profiles[gameProfile])
        end
    end

    -- Realtime Session Analytics observer.
    -- This observes the automation state itself, not only HealthChanged.  The
    -- important transition is: not farming -> farming with a concrete target.
    -- This makes target acquisition deterministic even when Roblox fires no
    -- HealthChanged event for the target.
    task.spawn(function()
        local previousFarming = false
        local previousHumanoid = nil
        local lastRenderAt = time()
        local lastPosition = nil
        local lastPositionAt = time()
        while State.alive do
            task.wait(0.05)
            if not State.alive then break end

            local now = time()
            local farming = State.farming == true
            local selected = Farm and Farm.selected or nil
            local humanoid = selected and selected.humanoid or nil

            if farming and humanoid and humanoid.Parent then
                if humanoid ~= previousHumanoid or not previousFarming then
                    pcall(function() System.recordTarget(selected) end)
                    previousHumanoid = humanoid
                end

                local hp = tonumber(humanoid.Health) or 0
                System.statsHealthSeen[humanoid] = hp
                if hp <= 0 and not System.statsKillSeen[humanoid] then
                    pcall(function() System.recordKill(selected) end)
                end
            elseif not farming then
                previousHumanoid = nil
            end

            -- Confirm actual automation teleports from real root-part displacement.
            -- This catches PivotTo paths that do not go through recordTeleport and
            -- prevents counting the repeated PivotTo calls while holding position.
            local char = Player and Player.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
            if root and root:IsA("BasePart") then
                local pos = root.Position
                if lastPosition then
                    local delta = (pos - lastPosition).Magnitude
                    local dt = math.max(0.001, now - lastPositionAt)
                    local pending = System.statsTeleportPending
                    local automationMovement = Settings.AutoBoss == true or Settings.FarmEnabled == true or State.farming == true or State.discovering == true

                    -- A displacement of 15+ studs in a single observer interval is
                    -- treated as an automation teleport only when automation is active.
                    -- Normal walking cannot realistically satisfy this threshold.
                    if automationMovement then
                        -- Pending automation movement can be small (for example a
                        -- saved boss point that is only a few studs away), while an
                        -- unhinted jump must be large enough to distinguish it from
                        -- normal movement.
                        if pending and now - pending.at <= 1.5 and delta >= 5 then
                            System.confirmTeleport(pending.reason, math.max(delta, pending.distance or 0))
                        elseif (not pending or now - pending.at > 1.5)
                            and delta >= 15 and now - (System.statsLastTeleportAt or 0) > 0.75 then
                            System.confirmTeleport("Detected automation teleport", delta)
                        end
                    end
                    if pending and now - pending.at > 1.5 then
                        -- The hint expired without actual movement; never count it.
                        System.statsTeleportPending = nil
                    end
                end
                lastPosition = pos
                lastPositionAt = now
            else
                lastPosition = nil
            end

            previousFarming = farming

            if now - lastRenderAt >= 0.20 then
                System.refreshStatsUI()
                lastRenderAt = now
            end
        end
    end)

    -- Safety monitor: watches movement/target progress and can pause automation when stuck.
    task.spawn(function()
        local lastPos=nil; local lastMove=os.clock(); local lastCycles=0
        while State.alive do
            task.wait(1)
            if not State.alive then break end
            -- Runtime is always maintained; StatsEnabled should only control
            -- whether optional statistics collection is desired, not whether the
            -- visible session clock freezes.
            System.stats.runtime=math.max(0,time()-(System.stats.startedAt or time()))
            if Settings.SafetyEnabled and Settings.SafetyAutoRecover and State.enabled then
                local char=Player.Character; local hrp=char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local pos=hrp.Position
                    if lastPos and (pos-lastPos).Magnitude>3 then lastMove=os.clock() end
                    lastPos=pos
                    if os.clock()-lastMove>=Settings.SafetyStuckTimeout then
                        System.safetyStatus="RECOVERY"; System.safetyDetail="Movement appears stuck; attempting safe pause."
                        -- A stuck detection is not itself a teleport. Only actual
                        -- PivotTo reposition events increment Teleports.
                        if Settings.SafetyPauseOnUnexpected then pcall(setEnabled,false) end
                        lastMove=os.clock(); System.notify("Safety recovery triggered")
                    else System.safetyStatus="SAFE"; System.safetyDetail="Recovery monitor armed." end
                end
            end
            System.refreshStatsUI()
        end
    end)
    System.initProfiles()

    System.loadPrefs()
    -- Freeze the theme selected by persisted preferences for this execution.
    -- The loader and initial UI must use the same startup theme.
    if System.theme ~= "Blackhole" and System.theme ~= "Empyrean" and System.theme ~= "Frost" and System.theme ~= "Default" then
        System.theme = "Default"
    end
    System.startupTheme = System.theme

    if not finiteText(System.targetGameId, 40) or System.targetGameId == "0" then
        System.targetGameId = tostring(game.GameId or 0)
    end

    local loader = string.format([[
pcall(function()
    if tostring(game.GameId or 0) ~= %q then return end
    local rf = type(readfile) == "function" and readfile
    local ff = type(isfile) == "function" and isfile
    if rf and ff and ff(%q) then
        local source = rf(%q)
        local fn = loadstring(source)
        if fn then fn() end
    end
end)
]], System.targetGameId, System.bodyPath, System.bodyPath)

    function System.applyAutoExecute()
        local queue = type(queue_on_teleport) == "function" and queue_on_teleport
            or (type(environment.queue_on_teleport) == "function" and environment.queue_on_teleport)
            or (type(syn) == "table" and type(syn.queue_on_teleport) == "function" and syn.queue_on_teleport)
            or nil

        local queued = false
        if Settings.AutoExecute and type(queue) == "function" then
            local ok = pcall(queue, loader)
            queued = ok
        end

        if Settings.AutoExecute and type(writer) == "function" then
            local folderOK = true
            if type(mkdir) == "function" then
                folderOK = pcall(mkdir, "autoexec")
            end

            local ok = pcall(writer, System.autoexecPath, loader)
            if ok then
                System.persistStatus = queued
                    and "Auto-execute ON | teleport queue + autoexec installed"
                    or "Auto-execute ON | autoexec installed"
            else
                System.persistStatus = queued
                    and "Auto-execute ON | teleport queue active"
                    or "Auto-execute requested; executor autoexec path unavailable"
            end
        elseif Settings.AutoExecute then
            System.persistStatus = queued
                and "Auto-execute ON | teleport queue active"
                or "Auto-execute unavailable in this runner"
        else
            if type(deleter) == "function" and type(exists) == "function" then
                pcall(function()
                    if exists(System.autoexecPath) then deleter(System.autoexecPath) end
                end)
            end
            System.persistStatus = "Auto-execute OFF"
        end

        System.savePrefs()
        render()
    end

    function System.setAutoExecute(value)
        Settings.AutoExecute = value and true or false
        System.applyAutoExecute()
    end

    function System.setAutoRejoin(value)
        Settings.AutoRejoin = value and true or false
        if not Settings.AutoRejoin then
            System.rejoinRequested = false
            System.rejoinStatus = "Auto-rejoin OFF"
        else
            System.rejoinStatus = "Auto-rejoin armed"
        end
        System.savePrefs()
        render()
    end

    function System.setStaticScan(value)
        Settings.StaticMapScan = value and true or false
        System.savePrefs()
        if Settings.StaticMapScan and Farm and Farm.staticMapScan then
            Farm.staticMapScan(true)
        end
        render()
    end

    function System.setPrivateMap(value)
        value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if value == "" then value = "Ouwigahara" end
        Settings.PrivateServerMap = value:sub(1, 80)
        System.savePrefs()
        render()
    end

    function System.writeFriendReady()
        if type(writer) ~= "function" then
            System.friendReadyStatus = "Friend-ready file unavailable: writefile missing."
            return false
        end

        local source = environment.__AUTOSKILLS_SOURCE
        if type(source) ~= "string" or #source < 1000 then
            System.friendReadyStatus = "Friend-ready source unavailable in this launch."
            return false
        end

        local code, message = Farm.exportCode()
        if not code then
            System.friendReadyStatus = "Friend-ready file waiting for boss locations."
            return false
        end

        local marker = 'local BUILT_IN_BOSS_SEED_CODE = "'
        local startAt = source:find(marker, 1, true)
        if not startAt then
            System.friendReadyStatus = "Friend-ready template marker missing."
            return false
        end

        local valueStart = startAt + #marker
        local valueEnd = source:find('"', valueStart, true)
        if not valueEnd then
            System.friendReadyStatus = "Friend-ready template malformed."
            return false
        end

        local baked = source:sub(1, valueStart - 1) .. code .. source:sub(valueEnd)

        local ok, err = pcall(writer, System.friendReadyPath, baked)
        if ok then
            System.friendReadyStatus = message .. " -> " .. System.friendReadyPath
            return true
        end

        System.friendReadyStatus = "Friend-ready write failed: " .. tostring(err)
        return false
    end

    function System.rememberPrivateServer()
        if tostring(game.PrivateServerId or "") ~= "" and tostring(game.JobId or "") ~= "" then
            local changed = System.lastPrivatePlace ~= game.PlaceId or System.lastPrivateJob ~= game.JobId
            System.lastPrivatePlace = game.PlaceId
            System.lastPrivateJob = game.JobId
            System.rejoinRequested = false
            System.rejoinStatus = "Private server active; recovery point saved."
            if changed then System.savePrefs() end
            return true
        end
        return false
    end

    local function buttonText(button)
        local pieces = {button.Name}
        if button:IsA("TextButton") then pieces[#pieces+1] = button.Text end
        for _, child in ipairs(button:GetDescendants()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                pieces[#pieces+1] = child.Text
            end
        end
        return string.lower(table.concat(pieces, " "))
    end

    local function guiVisible(object)
        local node = object
        while node and node ~= playerGui do
            if node:IsA("GuiObject") and not node.Visible then return false end
            if node:IsA("ScreenGui") and not node.Enabled then return false end
            node = node.Parent
        end
        return true
    end

    local function normalize(value)
        return string.lower(tostring(value or "")):gsub("[^%w]", "")
    end

    local function findButton(predicate)
        for _, object in ipairs(playerGui:GetDescendants()) do
            if object:IsA("GuiButton")
                and (not root or not object:IsDescendantOf(root))
                and guiVisible(object) then
                local text = buttonText(object)
                if predicate(text, normalize(text), object) then return object end
            end
        end
    end

    local function pressButton(button, hold)
        if not button or not button.Parent then return false end
        local center = button.AbsolutePosition + button.AbsoluteSize / 2

        local ok = pcall(function()
            VirtualInput:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
            task.wait(hold or 0.04)
            VirtualInput:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
        end)
        return ok
    end

    function System.tryDirectRejoin(reason)
        if not Settings.AutoRejoin then return false end
        if not System.lastPrivatePlace or not System.lastPrivateJob then return false end
        if os.clock() - System.directTriedAt < 15 then return false end

        System.directTriedAt = os.clock()
        System.rejoinRequested = true
        System.rejoinStatus = "Direct private-instance rejoin requested..."
        render()

        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(
                System.lastPrivatePlace,
                System.lastPrivateJob,
                Player
            )
        end)

        if not ok then
            System.rejoinStatus = "Direct rejoin failed; using menu recovery."
            warn("AutoSkills direct rejoin: " .. tostring(err))
        end
        return ok
    end

    function System.menuStep()
        if not Settings.AutoRejoin or not System.rejoinRequested then return end
        if os.clock() < System.menuNextAt then return end
        if tostring(game.PrivateServerId or "") ~= "" then
            System.rememberPrivateServer()
            return
        end

        local play = findButton(function(text, compact)
            return compact == "play" or compact == "playgame" or compact == "playbutton"
        end)
        if play then
            System.menuStage = "play"
            System.rejoinStatus = "Main menu found -> Play"
            System.menuNextAt = os.clock() + 0.8
            pressButton(play, 0.05)
            render()
            return
        end

        local target = normalize(Settings.PrivateServerMap)
        local prefix = target:sub(1, math.min(#target, 6))
        local mapButton = findButton(function(text, compact)
            if target == "" then return false end
            return compact:find(target, 1, true) ~= nil
                or (prefix ~= "" and compact:find(prefix, 1, true) ~= nil)
        end)
        if mapButton then
            System.menuStage = "map"
            System.rejoinStatus = "Selecting " .. Settings.PrivateServerMap
            System.menuNextAt = os.clock() + 0.8
            pressButton(mapButton, 0.05)
            render()
            return
        end

        local privateButton = findButton(function(text, compact)
            return compact == "private"
                or compact:find("privateserver", 1, true) ~= nil
                or compact:find("private", 1, true) ~= nil
        end)
        if privateButton then
            System.menuStage = "private"
            System.rejoinStatus = "Selecting Private Server"
            System.menuNextAt = os.clock() + 0.8
            pressButton(privateButton, 0.05)
            render()
            return
        end

        local join = findButton(function(text, compact)
            return compact == "join"
                or compact == "joinserver"
                or compact == "enter"
                or compact == "enterprivate"
        end)
        if join then
            System.menuStage = "join"
            System.rejoinStatus = string.format(
                "Holding Join for %.2fs...",
                Settings.PrivateJoinHold
            )
            System.menuNextAt = os.clock() + 6
            pressButton(join, Settings.PrivateJoinHold)
            render()
            return
        end

        System.rejoinStatus = "Waiting for Play / map / Private Server / Join UI..."
    end

    connect(TeleportService.TeleportInitFailed, function(player, result, message)
        if player ~= Player or not Settings.AutoRejoin then return end
        System.rejoinRequested = true
        System.rejoinStatus = "Teleport failed; menu recovery active."
        System.menuNextAt = 0
        render()
    end)

    pcall(function()
        connect(GuiService.ErrorMessageChanged, function(message)
            if not Settings.AutoRejoin or tostring(message or "") == "" then return end
            System.rejoinRequested = true
            System.rejoinStatus = "Disconnect detected; recovering private server..."
            System.menuNextAt = 0
            System.tryDirectRejoin("disconnect")
            render()
        end)
    end)

    if not System.rememberPrivateServer() and Settings.AutoRejoin then
        System.rejoinRequested = true
    end

    System.applyAutoExecute()

    task.spawn(function()
        while State.alive do
            if Settings.AutoRejoin then
                System.rememberPrivateServer()
                if System.rejoinRequested then
                    if not System.tryDirectRejoin("menu") then
                        System.menuStep()
                    end
                end
            end
            task.wait(0.45)
        end
    end)
end

local C = {

    panel = Color3.fromRGB(8, 4, 15),
    surface = Color3.fromRGB(16, 8, 29),
    raised = Color3.fromRGB(27, 13, 45),
    line = Color3.fromRGB(82, 49, 121),
    text = Color3.fromRGB(233, 226, 247),
    muted = Color3.fromRGB(155, 143, 184),
    dim = Color3.fromRGB(92, 82, 122),
    accent = Color3.fromRGB(168, 85, 247),
    bright = Color3.fromRGB(143, 227, 255),
    green = Color3.fromRGB(125, 255, 176),
    amber = Color3.fromRGB(255, 199, 96),
    red = Color3.fromRGB(255, 103, 127),
    magenta = Color3.fromRGB(217, 70, 199),
    voidDeep = Color3.fromRGB(11, 6, 22),
}
local W, H = 720, 760
local function make(className, parent, properties)
    local object = Instance.new(className)
    for name, value in pairs(properties or {}) do object[name] = value end
    object.Parent = parent
    return object
end
local function corner(object, radius)
    return make("UICorner", object, {CornerRadius = UDim.new(0, radius)})
end
local function stroke(object, color, transparency, thickness)
    return make("UIStroke", object, {
        Color = color, Transparency = transparency or 0, Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end
local function frame(parent, name, x, y, width, height, color, radius)
    local object = make("Frame", parent, {
        Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = color or C.surface, BorderSizePixel = 0,
    })
    if radius then corner(object, radius) end
    return object
end
local function label(parent, name, text, x, y, width, height, size, color, font)
    return make("TextLabel", parent, {
        Name = name, Text = text, Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(width, height), BackgroundTransparency = 1,
        TextColor3 = color or C.text, TextSize = size or 12,
        Font = font or Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center, BorderSizePixel = 0,
    })
end
local function button(parent, name, text, x, y, width, height, color, size)
    local object = make("TextButton", parent, {
        Name = name, Text = text, Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(width, height), BackgroundColor3 = color or C.surface,
        BorderSizePixel = 0, AutoButtonColor = false, TextColor3 = C.muted,
        TextSize = size or 12, Font = Enum.Font.GothamMedium, Active = true,
    })
    corner(object, 8)
    return object
end
local function animate(object, properties, instant)
    if tweens[object] then tweens[object]:Cancel() end
    if instant then
        for property, value in pairs(properties) do object[property] = value end
        tweens[object] = nil
    else
        local tween = TweenService:Create(object,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
        tweens[object] = tween
        tween:Play()
    end
end
local function hover(object, normal, highlighted)
    connect(object.MouseEnter, function() animate(object, {TextColor3 = highlighted}) end)
    connect(object.MouseLeave, function() animate(object, {TextColor3 = normal}) end)
end

local espRecords, espFolder = {}, nil
local function removeESPRecord(other)
    local record = espRecords[other]
    if not record then return end
    if record.highlight then record.highlight:Destroy() end
    if record.billboard then record.billboard:Destroy() end
    espRecords[other] = nil
end
clearESP = function()
    for other in pairs(espRecords) do removeESPRecord(other) end
    if espFolder then espFolder:Destroy(); espFolder = nil end
    State.espCount = 0
end
local function sameTeam(other)
    return Player.Team ~= nil and other.Team == Player.Team
        and not Player.Neutral and not other.Neutral
end
local function createESPRecord(other, character, anchor)
    local record = {character = character}

    espRecords[other] = record
    record.highlight = make("Highlight", espFolder, {
        Name = "Player_" .. tostring(other.UserId), Adornee = character,
        FillColor = C.accent, OutlineColor = C.bright,
        FillTransparency = 0.8, OutlineTransparency = 0.08,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    })
    record.billboard = make("BillboardGui", playerGui, {
        Name = "VoidESP_" .. tostring(other.UserId), Adornee = anchor,
        Size = UDim2.fromOffset(210, 56), StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0),
        AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 100000,
        ResetOnSpawn = false, Active = false,
    })
    record.card = frame(record.billboard, "Tag", 0, 0, 210, 56, C.panel, 8)
    record.card.BackgroundTransparency = 0.18
    stroke(record.card, C.accent, 0.42)
    record.nameLabel = label(record.card, "Name", "", 10, 5, 190, 18, 12, C.text, Enum.Font.GothamBold)
    record.nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    record.nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    record.infoLabel = label(record.card, "Info", "", 10, 23, 190, 16, 10, C.bright, Enum.Font.GothamMedium)
    record.infoLabel.TextXAlignment = Enum.TextXAlignment.Center
    record.healthTrack = frame(record.card, "HealthTrack", 10, 46, 190, 3, C.line, 2)
    record.healthFill = frame(record.healthTrack, "Health", 0, 0, 190, 3, C.green, 2)
    return record
end
local function updateESP()
    if not State.alive or not Settings.ESPEnabled then return end
    local localCharacter = Player.Character
    local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
    local camera = World.CurrentCamera
    local origin = localRoot and localRoot:IsA("BasePart") and localRoot.Position
        or (camera and camera.CFrame.Position)
    if not origin then clearESP(); return end
    if not espFolder or espFolder.Parent ~= World then
        clearESP()
        espFolder = make("Folder", World, {Name = "AutoSkillsVoidESP"})
    end
    local seen, count = {}, 0
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= Player and not (Settings.ESPHideTeammates and sameTeam(other)) then
            local character = other.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local targetRoot = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
            if character and character.Parent and humanoid and humanoid.Health > 0
                and targetRoot and targetRoot:IsA("BasePart") then
                local distance = (targetRoot.Position - origin).Magnitude
                if distance <= Settings.ESPMaxDistance then
                    local head = character:FindFirstChild("Head")
                    local anchor = head and head:IsA("BasePart") and head or targetRoot
                    local record = espRecords[other]
                    if record and (record.character ~= character or record.highlight.Parent ~= espFolder
                        or record.billboard.Parent ~= playerGui) then
                        removeESPRecord(other)
                        record = nil
                    end
                    record = record or createESPRecord(other, character, anchor)
                    seen[other], count = true, count + 1
                    record.highlight.DepthMode = Settings.ESPThroughWalls
                        and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
                    record.highlight.OutlineColor = sameTeam(other) and C.green or C.bright
                    record.billboard.Adornee = anchor
                    record.billboard.AlwaysOnTop = Settings.ESPThroughWalls
                    record.billboard.Enabled = Settings.ESPShowNames or Settings.ESPShowDistance or Settings.ESPShowHealth
                    record.nameLabel.Visible = Settings.ESPShowNames
                    record.nameLabel.Text = other.DisplayName == other.Name and other.Name
                        or other.DisplayName .. "  @" .. other.Name
                    local y, info = 5, {}
                    if Settings.ESPShowNames then y = y + 18 end
                    if Settings.ESPShowDistance then info[#info + 1] = string.format("%d studs", math.floor(distance + 0.5)) end
                    if Settings.ESPShowHealth then info[#info + 1] = string.format("%d HP", math.ceil(humanoid.Health)) end
                    record.infoLabel.Visible = #info > 0
                    record.infoLabel.Text = table.concat(info, "   /   ")
                    record.infoLabel.Position = UDim2.fromOffset(10, y)
                    if #info > 0 then y = y + 16 end
                    record.healthTrack.Visible = Settings.ESPShowHealth
                    record.healthTrack.Position = UDim2.fromOffset(10, y + 5)
                    if Settings.ESPShowHealth then y = y + 11 end
                    local health = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
                    record.healthFill.Size = UDim2.new(health, 0, 1, 0)
                    record.healthFill.BackgroundColor3 = health > 0.5 and C.green or (health > 0.25 and C.amber or C.red)
                    record.card.Size = UDim2.fromOffset(210, y + 6)
                    record.billboard.Size = UDim2.fromOffset(210, y + 6)
                end
            end
        end
    end
    for other in pairs(espRecords) do if not seen[other] then removeESPRecord(other) end end
    State.espCount = count
end
local function refreshESP()
    if not State.alive or not Settings.ESPEnabled then return end
    local ok, err = pcall(updateESP)
    if not ok then
        Settings.ESPEnabled = false
        State.espFault = "ESP stopped. Toggle on to retry."
        clearESP()
        warn("AutoSkills ESP: " .. tostring(err))
        notify("ESP stopped. Check the runner output for details.")
    end
end
local function setESPEnabled(value)
    if not State.alive then return end
    Settings.ESPEnabled, State.espFault = value, nil
    if value then refreshESP() else clearESP() end
    render()
end

root = make("ScreenGui", playerGui, {
    Name = "AutoSkillsVoidUI", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 100, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Enabled = false,
})
local canvas = make("Frame", root, {
    Name = "Canvas", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
    BorderSizePixel = 0, Active = false,
})
local loaderCanvas
loaderRoot = make("ScreenGui", playerGui, {
    Name = "AutoSkillsVoidLoader", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 101, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Enabled = true,
})
loaderCanvas = make("Frame", loaderRoot, {
    Name = "LoaderCanvas", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
    BorderSizePixel = 0, Active = false,
})

local W, H = 420, 560
local windowWidth = W
local C = {
    black = Color3.fromRGB(2, 1, 5),
    deep = Color3.fromRGB(11, 6, 22),
    panel = Color3.fromRGB(14, 8, 26),
    panel2 = Color3.fromRGB(20, 10, 36),
    violet = Color3.fromRGB(123, 47, 247),
    violet2 = Color3.fromRGB(168, 85, 247),
    magenta = Color3.fromRGB(217, 70, 199),
    cyan = Color3.fromRGB(143, 227, 255),
    ink = Color3.fromRGB(233, 226, 247),
    dim = Color3.fromRGB(155, 143, 184),
    faint = Color3.fromRGB(92, 82, 122),
    line = Color3.fromRGB(82, 55, 122),
    green = Color3.fromRGB(125, 255, 176),
    amber = Color3.fromRGB(255, 199, 96),
    red = Color3.fromRGB(255, 103, 127),
    white = Color3.fromRGB(255, 255, 255),

    accent = Color3.fromRGB(168, 85, 247),
    bright = Color3.fromRGB(143, 227, 255),
    muted = Color3.fromRGB(155, 143, 184),
    surface = Color3.fromRGB(16, 8, 29),
    text = Color3.fromRGB(233, 226, 247),
    voidDeep = Color3.fromRGB(11, 6, 22),
    toggleOn = Color3.fromRGB(88, 48, 124),
    toggleOff = Color3.fromRGB(32, 24, 43),
}
local uiScale = make("UIScale", canvas, {Scale = 1})
local holder = make("Frame", canvas, {
    Name = "Window", Size = UDim2.fromOffset(W, H), Position = UDim2.fromOffset(0, 0),
    BackgroundTransparency = 1, BorderSizePixel = 0, Active = true, Visible = false,
})
local shadow = frame(holder, "Shadow", -6, 8, W + 12, H + 12, Color3.new(0, 0, 0), 15)
shadow.BackgroundTransparency = 0.58
shadow.ZIndex = 0
local panel = frame(holder, "Panel", 0, 0, W, H, C.panel, 14)
panel.ZIndex = 2
panel.Active = true
panel.ClipsDescendants = true
stroke(panel, Color3.fromRGB(168, 120, 255), 0.28, 1)
make("UIGradient", panel, {
    Rotation = 90,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(23, 12, 39)),
        ColorSequenceKeypoint.new(0.45, Color3.fromRGB(14, 7, 26)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 2, 12)),
    }),
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.18),
        NumberSequenceKeypoint.new(0.48, 0.28),
        NumberSequenceKeypoint.new(1, 0.12),
    }),
})

panel.BackgroundTransparency = 0.40
local panelBackdrop = make("Frame", panel, {
    Name = "VoidBackdrop", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(W, H),
    BackgroundColor3 = C.black, BackgroundTransparency = 0.56, BorderSizePixel = 0,
    Active = false, ZIndex = 1,
})

local voidFX = make("Frame", panel, {
    Name = "VoidFX", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(W, H),
    BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, ZIndex = 3,
})
local voidRings, voidStars, voidDust, voidShots = {}, {}, {}, {}

local voidCore = frame(voidFX, "Core", 166, 214, 88, 88, C.black, 44)
voidCore.BackgroundTransparency = 0.18
voidCore.ZIndex = 2
stroke(voidCore, C.violet2, 0.68, 1)
local coreGlow = frame(voidFX, "CoreGlow", 145, 193, 130, 130, C.violet, 65)
coreGlow.BackgroundTransparency = 0.92
coreGlow.ZIndex = 2
stroke(coreGlow, C.violet2, 0.90, 1)
local coreGlow2 = frame(voidFX, "CoreGlow2", 125, 173, 170, 170, C.magenta, 85)
coreGlow2.BackgroundTransparency = 0.96
coreGlow2.ZIndex = 2
stroke(coreGlow2, C.magenta, 0.96, 1)

local nebulaA = frame(voidFX, "NebulaA", -90, 155, 300, 90, C.violet, 45)
nebulaA.BackgroundTransparency = 0.985
nebulaA.Rotation = -18
nebulaA.ZIndex = 2
make("UIGradient", nebulaA, {
    Rotation = 0,
    Color = ColorSequence.new(C.violet, C.magenta),
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.48, 0.88),
        NumberSequenceKeypoint.new(1, 1),
    }),
})
local nebulaB = frame(voidFX, "NebulaB", 230, 300, 300, 75, C.cyan, 38)
nebulaB.BackgroundTransparency = 0.988
nebulaB.Rotation = 16
nebulaB.ZIndex = 2
make("UIGradient", nebulaB, {
    Rotation = 180,
    Color = ColorSequence.new(C.cyan, C.violet2),
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 0.92),
        NumberSequenceKeypoint.new(1, 1),
    }),
})

for i, size in ipairs({180, 290, 390}) do
    local ring = frame(voidFX, "Ring" .. i,
        math.floor(W * 0.5 - size / 2), math.floor(H * 0.49 - size / 2),
        size, size, C.black, size / 2)
    ring.BackgroundTransparency = 1
    ring.ZIndex = 2
    stroke(ring, i == 1 and C.violet2 or (i == 2 and C.magenta or C.cyan),
        i == 1 and 0.80 or (i == 2 and 0.91 or 0.96), 1)
    voidRings[#voidRings + 1] = {
        object = ring,
        speed = i == 1 and 7 or (i == 2 and -4 or 2.2),
        phase = i * 0.9,
        size = size,
    }
end

for i = 1, 34 do
    local size = math.random(1, 2)
    local dust = frame(voidFX, "Dust" .. i,
        math.random(5, math.max(6, W - 8)), math.random(70, math.max(71, H - 8)),
        size, size, (i % 3 == 0) and C.magenta or C.violet2, size / 2)
    dust.BackgroundTransparency = math.random(82, 95) / 100
    dust.ZIndex = 2
    voidDust[#voidDust + 1] = {
        object = dust,
        x = dust.Position.X.Offset,
        y = dust.Position.Y.Offset,
        speed = 3 + math.random() * 8,
        phase = math.random() * math.pi * 2,
    }
end

for i = 1, 42 do
    local size = (i % 7 == 0) and 2.4 or (i % 3 == 0 and 1.8 or 1.35)
    local x = math.random(10, math.max(11, W - 12))
    local y = math.random(72, math.max(73, H - 12))
    local color = (i % 6 == 0) and C.magenta or ((i % 4 == 0) and C.violet2 or C.cyan)
    local groupSize = math.floor(18 * size)
    local group = frame(voidFX, "Star" .. i, math.floor(x), math.floor(y), groupSize, groupSize, C.black, math.floor(groupSize / 2))
    group.BackgroundTransparency = 1
    group.ZIndex = 4

    local coreSize = math.max(2, math.floor(3.2 * size))
    local cx = math.floor(groupSize / 2 - coreSize / 2)
    local cy = math.floor(groupSize / 2 - coreSize / 2)
    local core = frame(group, "Core", cx, cy, coreSize, coreSize, color, math.floor(coreSize / 2))
    core.BackgroundTransparency = 0.03
    core.ZIndex = 8

    local hotSize = math.max(1, math.floor(coreSize * 0.45))
    local hot = frame(group, "HotCore",
        math.floor(groupSize / 2 - hotSize / 2), math.floor(groupSize / 2 - hotSize / 2),
        hotSize, hotSize, C.white, math.floor(hotSize / 2))
    hot.BackgroundTransparency = 0.02
    hot.ZIndex = 9

    local rayLen = math.max(5, math.floor(7 * size))
    local outerW = math.max(2, math.floor(size * 0.95))
    local innerW = math.max(1, math.floor(size * 0.48))

    local function makeRay(name, rotation, length, width, rayColor, transparency, z)
        local ray = frame(group, name,
            math.floor(groupSize / 2 - width / 2),
            math.floor(groupSize / 2 - length / 2),
            width, length, rayColor, math.floor(width / 2))
        ray.Rotation = rotation
        ray.BackgroundTransparency = transparency
        ray.ZIndex = z
        return ray
    end

    local outerRays = {
        makeRay("OuterV", 0, rayLen + 4, outerW, color, 0.55, 5),
        makeRay("OuterH", 90, rayLen + 4, outerW, color, 0.55, 5),
        makeRay("OuterD1", 45, rayLen + 3, outerW, color, 0.64, 5),
        makeRay("OuterD2", -45, rayLen + 3, outerW, color, 0.64, 5),
    }
    local innerRays = {
        makeRay("InnerV", 0, rayLen, innerW, C.white, 0.08, 7),
        makeRay("InnerH", 90, rayLen, innerW, C.white, 0.08, 7),
    }

    local tailLen = math.floor(8 + size * 7)
    local tail = frame(group, "Tail",
        math.floor(groupSize / 2 - 0.5), math.floor(groupSize / 2 + 2),
        1, tailLen, color, 1)
    tail.BackgroundTransparency = 0.58
    tail.Rotation = -18
    tail.ZIndex = 4

    voidStars[#voidStars + 1] = {
        object = group,
        core = core,
        hot = hot,
        outerRays = outerRays,
        innerRays = innerRays,
        tail = tail,
        x = x, y = y,
        speed = 24 + math.random() * 64,
        drift = -10 + math.random() * 20,
        phase = math.random() * math.pi * 2,
        twinkle = 1.5 + math.random() * 3.8,
        spin = -18 + math.random() * 36,
        size = size,
        widthAtSpawn = W,
    }
end

for i = 1, 10 do
    local streak = frame(voidFX, "VoidStreak" .. i, 0, 0, 2, 34,
        i % 2 == 0 and C.cyan or C.magenta, 1)
    streak.BackgroundTransparency = 1
    streak.ZIndex = 2
    local streakGlow = frame(voidFX, "VoidStreakGlow" .. i, 0, 0, 5, 44,
        i % 2 == 0 and C.cyan or C.magenta, 2)
    streakGlow.BackgroundTransparency = 0.93
    streakGlow.ZIndex = 2
    voidShots[#voidShots + 1] = {
        object = streak, glow = streakGlow,
        x = math.random(20, W - 20), y = math.random(70, H),
        speed = 115 + math.random() * 75,
        wait = math.random() * 4,
        phase = math.random() * math.pi * 2,
    }
end

local voidWisps = {}
for i = 1, 7 do
    local length = 70 + math.random(30, 120)
    local wisp = frame(voidFX, "VoidWisp" .. i, math.random(-length, W), math.random(75, math.max(80, H - 30)), length, 1,
        i % 2 == 0 and C.cyan or C.magenta, 1)
    wisp.BackgroundTransparency = 0.82
    wisp.ZIndex = 3
    voidWisps[#voidWisps + 1] = {
        object = wisp, x = wisp.Position.X.Offset, y = wisp.Position.Y.Offset,
        length = length, speed = 7 + math.random() * 13,
        phase = math.random() * math.pi * 2, pulse = 0.7 + math.random() * 1.5,
    }
end

local voidFXClock = os.clock()
local voidLast = voidFXClock
connect(RunService.RenderStepped, function()
    if not State.alive or not voidFX.Parent then return end
    local now = os.clock()
    local dt = math.min(now - voidLast, 0.05)
    voidLast = now
    local t = now - voidFXClock

    for _, star in ipairs(voidStars) do
        if star.object.Parent then
            star.y = star.y + star.speed * dt
            star.x = star.x + star.drift * dt + math.sin(t * 0.72 + star.phase) * 0.16
            local fxWidth = math.max(W, windowWidth or W)
            if star.y > H + 22 then
                star.y = math.random(68, 82)
                star.x = math.random(8, math.max(9, math.floor(fxWidth - 18)))
            end
            if star.x < -18 then star.x = fxWidth + 10 elseif star.x > fxWidth + 18 then star.x = -10 end
            local pulse = (math.sin(t * star.twinkle + star.phase) + 1) * 0.5
            local rayFade = math.clamp(0.72 - pulse * 0.60, 0.05, 0.72)
            local innerFade = math.clamp(0.18 - pulse * 0.14, 0.025, 0.18)
            star.object.Position = UDim2.fromOffset(math.floor(star.x), math.floor(star.y))
            star.object.Rotation = math.sin(t * 0.45 + star.phase) * 8 + t * star.spin * 0.015
            star.object.BackgroundTransparency = 1

            if star.core then
                star.core.BackgroundTransparency = math.clamp(0.16 - pulse * 0.14, 0.01, 0.16)
                star.core.Size = UDim2.fromOffset(
                    math.max(2, math.floor(3.2 * star.size + pulse * 1.3)),
                    math.max(2, math.floor(3.2 * star.size + pulse * 1.3))
                )
            end
            if star.hot then
                star.hot.BackgroundTransparency = math.clamp(0.10 - pulse * 0.08, 0.01, 0.10)
            end
            if star.outerRays then
                for _, ray in ipairs(star.outerRays) do
                    ray.BackgroundTransparency = rayFade
                end
            end
            if star.innerRays then
                for _, ray in ipairs(star.innerRays) do
                    ray.BackgroundTransparency = innerFade
                end
            end
            if star.tail then
                star.tail.BackgroundTransparency = math.clamp(0.66 - pulse * 0.38, 0.24, 0.66)
                star.tail.Size = UDim2.fromOffset(1, math.floor(7 + pulse * 13 * star.size))
            end
        end
    end

    for _, dust in ipairs(voidDust) do
        if dust.object.Parent then
            dust.y = dust.y + dust.speed * dt
            dust.x = dust.x + math.sin(t * 0.35 + dust.phase) * dt * 2
            local fxWidth = math.max(W, windowWidth or W)
            if dust.y > H + 5 then dust.y = 68 end
            if dust.x < 3 then dust.x = fxWidth - 3 elseif dust.x > fxWidth - 3 then dust.x = 3 end
            local pulse = (math.sin(t * 0.9 + dust.phase) + 1) * 0.5
            dust.object.Position = UDim2.fromOffset(math.floor(dust.x), math.floor(dust.y))
            dust.object.BackgroundTransparency = 0.90 + pulse * 0.08
        end
    end

    for _, shot in ipairs(voidShots) do
        if shot.object.Parent then
            local cycle = (t + shot.wait) % 3.4
            local active = cycle < 1.05
            if active then
                shot.y = shot.y + shot.speed * dt
                local fxWidth = math.max(W, windowWidth or W)
                if shot.y > H + 60 then
                    shot.y = math.random(72, 150)
                    shot.x = math.random(20, math.max(21, math.floor(fxWidth - 20)))
                end
                local fade = cycle < 0.16 and cycle / 0.16 or (cycle > 0.78 and (1.05 - cycle) / 0.27 or 1)
                shot.object.Position = UDim2.fromOffset(math.floor(shot.x), math.floor(shot.y))
                shot.glow.Position = UDim2.fromOffset(math.floor(shot.x - 1), math.floor(shot.y - 4))
                shot.object.BackgroundTransparency = 1 - math.clamp(fade, 0, 1) * 0.94
                shot.glow.BackgroundTransparency = 0.90 - math.clamp(fade, 0, 1) * 0.38
            else
                shot.object.BackgroundTransparency = 1
                shot.glow.BackgroundTransparency = 1
            end
        end
    end

    for _, wisp in ipairs(voidWisps or {}) do
        if wisp.object.Parent then
            wisp.x = wisp.x + wisp.speed * dt
            local fxWidth = math.max(W, windowWidth or W)
            if wisp.x > fxWidth + wisp.length then
                wisp.x = -wisp.length
                wisp.y = math.random(72, math.max(74, H - 30))
            end
            local wp = (math.sin(t * wisp.pulse + wisp.phase) + 1) * 0.5
            wisp.object.Position = UDim2.fromOffset(math.floor(wisp.x), math.floor(wisp.y))
            wisp.object.BackgroundTransparency = 0.78 - wp * 0.22
        end
    end

    nebulaA.Rotation = -18 + math.sin(t * 0.18) * 7
    nebulaA.Position = UDim2.fromOffset(math.floor((windowWidth * 0.16) + math.sin(t * 0.22) * 24 - 90), math.floor(155 + math.cos(t * 0.31) * 18))
    nebulaB.Rotation = 16 + math.cos(t * 0.16) * 6
    nebulaB.Position = UDim2.fromOffset(math.floor((windowWidth * 0.56) + math.cos(t * 0.19) * 28), math.floor(300 + math.sin(t * 0.27) * 20))
    nebulaA.BackgroundTransparency = 0.982 + math.sin(t * 0.65) * 0.008
    nebulaB.BackgroundTransparency = 0.985 + math.cos(t * 0.52) * 0.008

    local pulse = 0.5 + math.sin(t * 1.2) * 0.5
    voidCore.BackgroundTransparency = 0.06 + pulse * 0.16
    coreGlow.BackgroundTransparency = 0.985 - pulse * 0.045
    coreGlow2.BackgroundTransparency = 0.995 - pulse * 0.025
    for _, ring in ipairs(voidRings) do
        if ring.object.Parent then
            ring.object.Rotation = (t * ring.speed + ring.phase * 57) % 360
            local ringPulse = (math.sin(t * 0.6 + ring.phase) + 1) * 0.5
            ring.object:FindFirstChildOfClass("UIStroke").Transparency = math.clamp(
                (ring.size == 180 and 0.76 or ring.size == 290 and 0.88 or 0.94) - ringPulse * 0.08, 0.45, 0.98)
        end
    end
end)

local lastVoidFXWidth = W
local function resizeVoidEffects(newWidth)
    newWidth = math.max(W, math.floor(newWidth + 0.5))
    local oldWidth = math.max(W, lastVoidFXWidth or W)
    local ratio = newWidth / oldWidth
    if math.abs(ratio - 1) > 0.001 then
        for _, star in ipairs(voidStars) do
            star.x = star.x * ratio
            star.object.Position = UDim2.fromOffset(math.floor(star.x), math.floor(star.y))
        end
        for _, dust in ipairs(voidDust) do
            dust.x = dust.x * ratio
            dust.object.Position = UDim2.fromOffset(math.floor(dust.x), math.floor(dust.y))
        end
        for _, shot in ipairs(voidShots) do
            shot.x = shot.x * ratio
            shot.object.Position = UDim2.fromOffset(math.floor(shot.x), math.floor(shot.y))
            shot.glow.Position = UDim2.fromOffset(math.floor(shot.x - 1), math.floor(shot.y - 4))
        end
        for _, wisp in ipairs(voidWisps or {}) do
            wisp.x = wisp.x * ratio
            wisp.object.Position = UDim2.fromOffset(math.floor(wisp.x), math.floor(wisp.y))
        end
    end
    voidFX.Size = UDim2.fromOffset(newWidth, H)
    panelBackdrop.Size = UDim2.fromOffset(newWidth, H)
    lastVoidFXWidth = newWidth

    voidCore.Position = UDim2.fromOffset(math.floor(newWidth * 0.5 - 44), math.floor(H * 0.49 - 44))
    coreGlow.Position = UDim2.fromOffset(math.floor(newWidth * 0.5 - 65), math.floor(H * 0.49 - 65))
    coreGlow2.Position = UDim2.fromOffset(math.floor(newWidth * 0.5 - 85), math.floor(H * 0.49 - 85))
    for _, data in ipairs(voidRings) do
        data.object.Position = UDim2.fromOffset(math.floor(newWidth * 0.5 - data.size / 2), math.floor(H * 0.49 - data.size / 2))
    end
end

local function safeText(parent, name, text, x, y, w, h, size, color, font)
    return label(parent, name, text, x, y, w, h, size, color, font)
end

local function navIcon(parent, kind, x, y, color)
    local box = frame(parent, "Icon", x, y, 19, 19, Color3.new(1, 1, 1), 0)
    box.BackgroundTransparency = 1
    local function bar(name, bx, by, bw, bh, rot, col, rad)
        local b = frame(box, name, bx, by, bw, bh, col or color, rad or 1)
        b.Rotation = rot or 0
        return b
    end
    if kind == "skills" then
        bar("A", 2, 2, 10, 2, 45); bar("B", 7, 2, 10, 2, -45)
        bar("C", 2, 15, 10, 2, -45); bar("D", 7, 15, 10, 2, 45)
        frame(box, "Core", 8, 8, 3, 3, color, 3)
    elseif kind == "esp" then
        local eye = frame(box, "Eye", 1, 6, 17, 7, Color3.new(1,1,1), 7)
        eye.BackgroundTransparency = 1; stroke(eye, color, 0, 1)
        frame(box, "Pupil", 8, 8, 3, 3, color, 3)
    elseif kind == "health" then
        bar("H", 8, 2, 3, 15, 0); bar("V", 2, 8, 15, 3, 0)
    elseif kind == "farm" then
        local diamond = frame(box, "Diamond", 4, 4, 11, 11, Color3.new(1,1,1), 1)
        diamond.BackgroundTransparency = 1; diamond.Rotation = 45; stroke(diamond, color, 0, 1)
        local core = frame(box, "Core", 8, 8, 3, 3, color, 3)
    elseif kind == "move" then
        bar("Stem", 9, 3, 2, 12, 0)
        bar("Left", 5, 4, 7, 2, 45); bar("Right", 8, 4, 7, 2, -45)
        bar("Base", 3, 16, 13, 2, 0)
    elseif kind == "theme" then
        local orbit = frame(box, "Orbit", 2, 6, 15, 7, Color3.new(1,1,1), 7)
        orbit.BackgroundTransparency = 1
        orbit.Rotation = -18
        stroke(orbit, color, 0, 1)
        frame(box, "Void", 7, 7, 5, 5, color, 5)
    else
        local shell = frame(box, "Shell", 3, 3, 13, 13, Color3.new(1,1,1), 2)
        shell.BackgroundTransparency = 1; stroke(shell, color, 0, 1)
        frame(box, "Center", 8, 8, 3, 3, color, 3)
    end
    return box
end

local header = make("Frame", panel, {
    Name = "Header", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(W, 64),
    BackgroundColor3 = C.panel, BackgroundTransparency = 0.08, BorderSizePixel = 0,
    Active = true, ZIndex = 5,
})
make("UIGradient", header, {
    Rotation = 90,
    Color = ColorSequence.new(C.violet, C.panel),
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.82), NumberSequenceKeypoint.new(1, 1),
    }),
})
local headerLine = frame(header, "Line", 0, 63, W, 1, C.violet, 0)
headerLine.BackgroundTransparency = 0.48
local brandmark = frame(header, "BrandMark", 18, 18, 26, 26, C.panel2, 13)
stroke(brandmark, C.violet2, 0.12, 1)
local markCore = frame(brandmark, "Core", 9, 9, 8, 8, C.violet2, 8)
local markH = frame(brandmark, "H", 3, 12, 20, 1, C.violet2, 1)
local markV = frame(brandmark, "V", 12, 3, 1, 20, C.cyan, 1)
local brandTitle = safeText(header, "Title", "VOID NEXUS", 55, 14, 210, 20, 15, C.ink, Enum.Font.GothamBlack)
brandTitle.TextStrokeTransparency = 0.85
safeText(header, "Sub", "CORE LINK STABLE", 55, 35, 190, 13, 9, C.faint, Enum.Font.GothamBold)
local statusDot = frame(header, "StatusDot", W - 84, 27, 6, 6, C.green, 6)
local statusGlow = stroke(statusDot, C.green, 0.45, 1)
UI.badge = make("TextButton", header, {
    Name = "Status", Text = "SYNCED", Position = UDim2.fromOffset(W - 72, 18),
    Size = UDim2.fromOffset(58, 24), BackgroundTransparency = 1, BorderSizePixel = 0,
    TextColor3 = C.dim, TextSize = 10, Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Right, AutoButtonColor = false, Active = true,
})

local ticker = frame(panel, "Ticker", 0, 64, W, 24, C.black, 0)
ticker.BackgroundTransparency = 0.38
ticker.ZIndex = 5
local tickerClip = make("Frame", ticker, {
    Name = "Clip", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true, Active = false, ZIndex = 6,
})
local tickerText = safeText(tickerClip, "Text",
    "◆ CORE TEMP NOMINAL     ◆ FIELD INTEGRITY 98.4%     ◆ SIGNAL LOCK ACQUIRED     ◆ RIFT PRESSURE STABLE     ◆ NO ANOMALIES DETECTED     ",
    0, 0, W * 2, 24, 10, C.faint, Enum.Font.Code)
tickerText.ZIndex = 7
local tickerStart = os.clock()
local uiAnimStart = os.clock()
local panelStroke = panel:FindFirstChildOfClass("UIStroke")
local edgeSheen = frame(panel, "EdgeSheen", -120, 0, 120, H, C.cyan, 0)
edgeSheen.BackgroundTransparency = 0.96
edgeSheen.ZIndex = 4
local edgeSheenGradient = make("UIGradient", edgeSheen, {
    Rotation = 90,
    Color = ColorSequence.new(C.cyan, C.magenta),
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.15), NumberSequenceKeypoint.new(1, 1),
    }),
})
connect(RunService.RenderStepped, function()
    if not State.alive or not tickerText.Parent then return end
    local now = os.clock()
    local phase = ((now - tickerStart) * 34) % math.max(windowWidth, W)
    tickerText.Position = UDim2.fromOffset(windowWidth - phase, 0)

    local t = now - uiAnimStart
    brandmark.Rotation = (t * 7) % 360
    edgeSheen.Position = UDim2.fromOffset(((t * 42) % (windowWidth + 240)) - 120, 0)
    edgeSheen.BackgroundTransparency = 0.94 + math.sin(t * 1.1) * 0.02
    edgeSheenGradient.Offset = Vector2.new(0, ((t * 0.12) % 2) - 1)
    local beat = (math.sin(t * 2.2) + 1) * 0.5
    statusDot.Size = UDim2.fromOffset(5 + math.floor(beat * 3), 5 + math.floor(beat * 3))
    statusDot.Position = UDim2.fromOffset(windowWidth - 84 - math.floor(beat * 1.5), 27 - math.floor(beat * 1.5))
    statusDot.BackgroundTransparency = 0.08 + beat * 0.30
    if panelStroke then panelStroke.Transparency = 0.18 + beat * 0.20 end
    headerLine.BackgroundTransparency = 0.28 + beat * 0.30
    local selectedBar = UI.navBars and UI.navBars[State.tab]
    if selectedBar then
        selectedBar.BackgroundTransparency = 0.10 + (1 - beat) * 0.30
        selectedBar.Size = UDim2.fromOffset(math.max(12, selectedBar.AbsoluteSize.X), 2)
    end
end)


-- BLACKHOLE V1 visual preset hero. Hidden unless the saved Theme is Blackhole.
local BH = {}
BH.hero = frame(panel, "BlackholeHero", 0, 64, W, 152, C.black, 0)
BH.hero.ZIndex = 4
BH.hero.ClipsDescendants = true
BH.hero.Visible = false
BH.heroStroke = stroke(BH.hero, Color3.fromRGB(150, 120, 230), 0.84, 1)
BH.atmosphere = frame(BH.hero, "Atmosphere", 0, 0, W, 152, Color3.fromRGB(18, 8, 35), 0)
BH.atmosphere.BackgroundTransparency = 0.30
BH.atmosphere.ZIndex = 1

BH.stars = {}
for i = 1, 20 do
    local size = (i % 5 == 0) and 2 or 1
    local star = frame(
        BH.hero, "Star" .. i,
        math.random(8, math.max(9, W - 10)),
        math.random(6, 146),
        size, size,
        (i % 4 == 0) and Color3.fromRGB(238,241,251) or Color3.fromRGB(130,110,175),
        size
    )
    star.BackgroundTransparency = 0.25 + math.random() * 0.55
    star.ZIndex = 2
    BH.stars[#BH.stars + 1] = {
        object = star,
        x = star.Position.X.Offset,
        y = star.Position.Y.Offset,
        phase = math.random() * math.pi * 2,
        twinkle = 0.7 + math.random() * 2.2,
        baseX = star.Position.X.Offset,
    }
end

BH.backA = frame(BH.hero, "BackOrbitA", 0, 0, W, 152, Color3.new(1,1,1), 0)
BH.backA.BackgroundTransparency = 1
BH.backA.AnchorPoint = Vector2.new(0.5, 0.5)
BH.backA.Position = UDim2.fromOffset(W * 0.5, 76)
BH.backA.ZIndex = 3
BH.backB = frame(BH.hero, "BackOrbitB", 0, 0, W, 152, Color3.new(1,1,1), 0)
BH.backB.BackgroundTransparency = 1
BH.backB.AnchorPoint = Vector2.new(0.5, 0.5)
BH.backB.Position = UDim2.fromOffset(W * 0.5, 76)
BH.backB.ZIndex = 3

BH.coreGlow = frame(BH.hero, "CoreGlow", 0, 0, 90, 90, Color3.fromRGB(72,38,150), 45)
BH.coreGlow.AnchorPoint = Vector2.new(0.5, 0.5)
BH.coreGlow.Position = UDim2.fromOffset(W * 0.5, 76)
BH.coreGlow.BackgroundTransparency = 0.90
BH.coreGlow.ZIndex = 4

BH.core = frame(BH.hero, "EventHorizon", 0, 0, 56, 56, Color3.new(0,0,0), 28)
BH.core.AnchorPoint = Vector2.new(0.5, 0.5)
BH.core.Position = UDim2.fromOffset(W * 0.5, 76)
BH.core.BackgroundTransparency = 0
BH.core.ZIndex = 6

BH.horizonSilver = frame(BH.hero, "HorizonSilver", 0, 0, 58, 58, Color3.new(1,1,1), 29)
BH.horizonSilver.AnchorPoint = Vector2.new(0.5, 0.5)
BH.horizonSilver.Position = UDim2.fromOffset(W * 0.5, 76)
BH.horizonSilver.BackgroundTransparency = 1
BH.horizonSilver.ZIndex = 5
BH.silverStroke = stroke(BH.horizonSilver, Color3.fromRGB(238,241,251), 0.18, 1.4)

BH.horizonPurple = frame(BH.hero, "HorizonPurple", 0, 0, 58, 58, Color3.new(1,1,1), 29)
BH.horizonPurple.AnchorPoint = Vector2.new(0.5, 0.5)
BH.horizonPurple.Position = UDim2.fromOffset(W * 0.5, 76)
BH.horizonPurple.BackgroundTransparency = 1
BH.horizonPurple.ZIndex = 5
BH.purpleStroke = stroke(BH.horizonPurple, Color3.fromRGB(122,63,242), 0.28, 1.2)

BH.front = frame(BH.hero, "FrontOrbit", 0, 0, W, 152, Color3.new(1,1,1), 0)
BH.front.BackgroundTransparency = 1
BH.front.AnchorPoint = Vector2.new(0.5, 0.5)
BH.front.Position = UDim2.fromOffset(W * 0.5, 76)
BH.front.ZIndex = 7

function BH.makeOrbit(group, rx, ry, count, width, z, palette, phaseOffset, speed)
    local data = {group = group, rx = rx, ry = ry, speed = speed or 0, segments = {}}
    for i = 1, count do
        local angle = ((i - 1) / count) * math.pi * 2 + (phaseOffset or 0)
        local segmentLength = math.floor(math.max(20, rx * (0.20 + ((i % 3) * 0.035))))
        local color = palette[((i - 1) % #palette) + 1]
        local glow = frame(group, "Glow" .. i, 0, 0, segmentLength + 8, width + 6, color, math.floor((width + 6) / 2))
        glow.AnchorPoint = Vector2.new(0.5, 0.5)
        glow.BackgroundTransparency = 0.90
        glow.ZIndex = z
        local seg = frame(group, "Segment" .. i, 0, 0, segmentLength, width, color, math.floor(width / 2))
        seg.AnchorPoint = Vector2.new(0.5, 0.5)
        seg.BackgroundTransparency = 0.08
        seg.ZIndex = z + 1
        data.segments[#data.segments + 1] = {seg = seg, glow = glow, angle = angle, length = segmentLength, width = width}
    end
    return data
end

BH.backRing1 = BH.makeOrbit(
    BH.backA, 216, 28, 9, 5, 3,
    {Color3.fromRGB(238,241,251), Color3.fromRGB(160,140,205), Color3.fromRGB(122,63,242), Color3.fromRGB(72,38,130)}, 0.18, math.rad(6)
)
BH.backRing2 = BH.makeOrbit(
    BH.backB, 166, 20, 7, 3, 3,
    {Color3.fromRGB(122,63,242), Color3.fromRGB(155,130,215), Color3.fromRGB(238,241,251)}, -0.35, math.rad(-4.4)
)
BH.frontRing = BH.makeOrbit(
    BH.front, 226, 34, 8, 4, 7,
    {Color3.fromRGB(42,20,88), Color3.fromRGB(238,241,251), Color3.fromRGB(190,176,230), Color3.fromRGB(122,63,242)}, 0.55, math.rad(-7.5)
)

BH.scan = frame(BH.hero, "Scan", 0, -58, W, 54, Color3.fromRGB(238,241,251), 0)
BH.scan.BackgroundTransparency = 0.965
BH.scan.ZIndex = 9
BH.scanGradient = make("UIGradient", BH.scan, {
    Rotation = 90,
    Color = ColorSequence.new(Color3.fromRGB(238,241,251), Color3.fromRGB(122,63,242)),
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 0.18),
        NumberSequenceKeypoint.new(1, 1),
    }),
})

BH.clock = os.clock()
BH.last = BH.clock
connect(RunService.RenderStepped, function()
    if not State.alive or not BH.hero.Parent or not BH.hero.Visible then return end
    local now = os.clock()
    local dt = math.min(now - BH.last, 0.05)
    BH.last = now
    local t = now - BH.clock
    local heroWidth = math.max(420, BH.hero.AbsoluteSize.X)
    -- Keep every Blackhole layer tied to the live hero width so the visual field
    -- grows with the window instead of leaving a fixed-width effect behind.
    local scale = heroWidth / 420
    local cx = heroWidth * 0.5
    local cy = 76
    BH.atmosphere.Size = UDim2.fromOffset(heroWidth, 152)
    local coreScale = math.clamp(0.92 + (heroWidth / 420) * 0.28, 0.92, 1.65)
    BH.core.Position = UDim2.fromOffset(cx, cy)
    BH.coreGlow.Position = UDim2.fromOffset(cx, cy)
    BH.horizonSilver.Position = UDim2.fromOffset(cx, cy)
    BH.horizonPurple.Position = UDim2.fromOffset(cx, cy)

    for _, star in ipairs(BH.stars) do
        star.y = star.y + dt * 1.5
        if star.y > 148 then star.y = 4 end
        star.object.Position = UDim2.fromOffset(star.x, star.y)
        star.object.BackgroundTransparency = 0.25 + (math.sin(t * star.twinkle + star.phase) + 1) * 0.28
    end

    -- Animate the orbit segments themselves instead of rotating their parent
    -- frames. This keeps their center locked to the resized hero and prevents
    -- the orbit geometry from drifting/clipping when the window is widened.
    BH.backA.Rotation = 0
    BH.backB.Rotation = 0
    BH.front.Rotation = 0

    local pulse = (math.sin(t * 1.25) + 1) * 0.5
    local glowSize = (82 + math.floor(pulse * 18)) * coreScale
    BH.coreGlow.Size = UDim2.fromOffset(math.floor(glowSize), math.floor(glowSize))
    BH.coreGlow.BackgroundTransparency = 0.94 - pulse * 0.08
    local horizonSize = math.floor(58 * coreScale)
    local coreSize = math.floor(56 * coreScale)
    BH.core.Size = UDim2.fromOffset(coreSize, coreSize)
    BH.horizonSilver.Size = UDim2.fromOffset(horizonSize, horizonSize)
    BH.horizonPurple.Size = UDim2.fromOffset(horizonSize, horizonSize)
    for _, circular in ipairs({BH.coreGlow, BH.core, BH.horizonSilver, BH.horizonPurple}) do
        local circularCorner = circular:FindFirstChildOfClass("UICorner")
        if circularCorner then circularCorner.CornerRadius = UDim.new(1, 0) end
    end
    BH.silverStroke.Transparency = 0.16 + pulse * 0.18
    BH.purpleStroke.Transparency = 0.28 + (1 - pulse) * 0.20

    for _, orbit in ipairs({BH.backA, BH.backB, BH.front}) do
        orbit.Size = UDim2.fromOffset(heroWidth, 152)
        orbit.Position = UDim2.fromOffset(cx, cy)
    end

    for _, ring in ipairs({BH.backRing1, BH.backRing2, BH.frontRing}) do
        local rx, ry = ring.rx * scale, ring.ry
        for _, seg in ipairs(ring.segments) do
            local angle = seg.angle + t * ring.speed
            local x = cx + math.cos(angle) * rx
            local y = cy + math.sin(angle) * ry
            local tx, ty = -rx * math.sin(angle), ry * math.cos(angle)
            local rotation = math.deg(math.atan2(ty, tx))
            seg.seg.Size = UDim2.fromOffset(math.floor(seg.length * scale), seg.width)
            seg.glow.Size = UDim2.fromOffset(math.floor(seg.length * scale) + 8, seg.width + 6)
            seg.seg.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
            seg.seg.Rotation = rotation
            seg.glow.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
            seg.glow.Rotation = rotation
            seg.glow.BackgroundTransparency = 0.86 + (math.sin(t * 1.6 + angle * 2) + 1) * 0.05
        end
    end

    BH.scan.Size = UDim2.fromOffset(heroWidth, 54)
    BH.scan.Position = UDim2.fromOffset(0, -58 + ((t * 34) % 268))
    BH.scanGradient.Offset = Vector2.new(0, ((t * 0.14) % 2) - 1)
end)

local tabs = frame(panel, "Nav", 0, 88, W, 64, C.black, 0)
tabs.BackgroundTransparency = 0.35
tabs.ZIndex = 5
stroke(tabs, C.line, 0.55, 1)
local navNames = {"Skills", "ESP", "Health", "Farm", "Move", "System", "Theme", "Core"}
local navKinds = {"skills", "esp", "health", "farm", "move", "system", "theme", "system"}
local navButtons = {}
UI.navStrokes, UI.navBars = {}, {}
local navX, navW, navGap = 12, 61, 6
for i, key in ipairs(navNames) do
    local b = button(tabs, key .. "Tab", string.upper(key), navX + (i - 1) * (navW + navGap), 10, navW, 44, Color3.fromRGB(8, 4, 16), 9)
    b.ZIndex = 6
    b.TextTransparency = 0
    b.TextColor3 = C.faint
    b.TextSize = 8.6
    b.Font = Enum.Font.GothamBold
    b.TextYAlignment = Enum.TextYAlignment.Bottom
    b.TextXAlignment = Enum.TextXAlignment.Center
    b.Text = string.upper(key)
    navIcon(b, navKinds[i], 20, 5, C.faint)
    UI.navStrokes[key] = stroke(b, C.line, 0.88, 1)
    UI.navBars[key] = frame(b, "ActiveBar", 8, 40, 43, 2, C.violet2, 2)
    UI.navBars[key].Visible = false
    navButtons[key] = b
end
UI.skillsTab = navButtons.Skills
UI.espTab = navButtons.ESP
UI.healthTab = navButtons.Health
UI.farmTab = navButtons.Farm
UI.moveTab = navButtons.Move
UI.systemTab = navButtons.System
UI.themeTab = navButtons.Theme
UI.coreTab = navButtons.Core

local content = make("Frame", panel, {
    Name = "Content", Position = UDim2.fromOffset(0, 152), Size = UDim2.fromOffset(W, H - 152),
    BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, ZIndex = 3,
})

local function newPage(name)
    local page = make("ScrollingFrame", content, {
        Name = name .. "Page", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.violet2, ScrollBarImageTransparency = 0.55,
        CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false, Active = true, ZIndex = 4,
    })
    return page
end
local function pageHead(parent, iconKind, title, moduleText)
    local head = frame(parent, "PaneHead", 16, 14, W - 32, 28, Color3.new(1,1,1), 0)
    head.BackgroundTransparency = 1
    navIcon(head, iconKind, 0, 4, C.violet2)
    safeText(head, "Title", title, 27, 1, 220, 20, 12, C.ink, Enum.Font.GothamBold)
    local m = safeText(head, "Modules", moduleText, 230, 1, 160, 20, 9, C.faint, Enum.Font.GothamBold)
    m.TextXAlignment = Enum.TextXAlignment.Right
    return head
end
local toggleViews = {}
local sliders = {}

local function makeRow(parent, y, name, desc, getter, setter)
    local row = frame(parent, "Row_" .. tostring(y), 16, y, W - 32, 52, Color3.fromRGB(18, 10, 30), 10)
    stroke(row, C.line, 0.72, 1)
    safeText(row, "Name", name, 12, 7, 270, 18, 13, C.ink, Enum.Font.GothamMedium)
    safeText(row, "Desc", desc, 12, 27, 270, 15, 10, C.faint, Enum.Font.GothamMedium)
    local track = button(row, "Toggle", "", W - 32 - 54, 14, 42, 23, Color3.fromRGB(32, 24, 43), 12)
    track.ZIndex = 7
    local knob = frame(track, "Knob", 3, 3, 17, 17, C.faint, 17)
    knob.ZIndex = 8
    local view = {track = track, knob = knob, getter = getter, last = nil}
    toggleViews[#toggleViews + 1] = view
    connect(track.Activated, function()
        setter(not getter())
        render()
    end)
    return row, view
end
local function makeSlider(parent, y, name, getter, setter, min, max, format)
    local row = frame(parent, "Slider_" .. tostring(y), 16, y, W - 32, 72, Color3.fromRGB(18, 10, 30), 10)
    stroke(row, C.line, 0.72, 1)
    safeText(row, "Name", name, 12, 8, 240, 18, 13, C.ink, Enum.Font.GothamMedium)
    local val = safeText(row, "Value", "", W - 120, 8, 104, 18, 11, C.cyan, Enum.Font.GothamBold)
    val.TextXAlignment = Enum.TextXAlignment.Right
    local hit = button(row, "Slider", "", 12, 35, W - 56, 24, Color3.new(1,1,1), 1)
    hit.BackgroundTransparency = 1
    local rail = frame(hit, "Rail", 0, 10, W - 56, 4, Color3.fromRGB(47, 32, 65), 3)
    local fill = frame(rail, "Fill", 0, 0, 0, 4, C.violet2, 3)
    local knob = frame(hit, "Knob", 0, 6, 14, 14, C.cyan, 14)
    stroke(knob, C.deep, 0.15, 2)
    local view = {property = name, hit = hit, fill = fill, knob = knob, valueLabel = val,
        minimum = min, maximum = max, getter = getter, setter = setter, format = format or "%.0f"}
    sliders[#sliders + 1] = view
    local function updateFromX(x)
        local width = hit.AbsoluteSize.X
        if width <= 0 then return end
        local f = math.clamp((x - hit.AbsolutePosition.X) / width, 0, 1)
        local value = min + (max - min) * f
        setter(value)
        render()
    end
    view.updateFromX = updateFromX
    connect(hit.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            State.gesture = {kind = "slider", input = input, view = view}
            updateFromX(input.Position.X)
        end
    end)
    return row
end

local function addKeyLoadout(parent, y)
    local box = frame(parent, "KeyLoadout", 16, y, W - 32, 56, Color3.fromRGB(18, 10, 30), 10)
    stroke(box, C.line, 0.72, 1)
    safeText(box, "Label", "SKILL LOADOUT", 12, 6, 120, 15, 9, C.faint, Enum.Font.GothamBold)
    for i, skill in ipairs(Skills) do
        local s = skill
        local b = button(box, "Key" .. s.name, s.name, 132 + (i - 1) * 54, 9, 46, 34, C.panel2, 8)
        b.TextSize = 14; b.Font = Enum.Font.GothamBold
        connect(b.Activated, function()
            s.enabled = not s.enabled
            if not s.enabled and State.heldKey == s.key then releaseOrPause() end
            render()
        end)
    end
    return box
end

local skillsPage = newPage("Skills")
body = skillsPage
pageHead(skillsPage, "skills", "SKILLS", "4 MODULES")
makeRow(skillsPage, 48, "Auto Cast", "Queues abilities on repeat", function() return State.enabled end, setEnabled)
makeRow(skillsPage, 108, "Cooldown Sync", "Keeps the selected key cycle aligned", function() return Settings.FarmUseSkills end, function(v) Settings.FarmUseSkills = v; releaseOrPause() end)
makeRow(skillsPage, 168, "Combo Assist", "Uses the reliable inventory-safe input path", function() return Settings.FarmM1 end, function(v) Settings.FarmM1 = v; releaseOrPause() end)
makeSlider(skillsPage, 228, "Cast Priority", function() return Settings.KeyGap end, function(v) Settings.KeyGap = math.clamp(v, 0.03, 1.0) end, 0.03, 1.0, "%.2fs")
addKeyLoadout(skillsPage, 308)
local skillHint = safeText(skillsPage, "Hint", "F6 toggles skills  /  F7 unloads  /  R-SHIFT hides the panel", 16, 376, W - 32, 18, 9, C.faint, Enum.Font.GothamMedium)
skillHint.TextXAlignment = Enum.TextXAlignment.Center

local espPage = newPage("ESP")
espBody = espPage
pageHead(espPage, "esp", "ESP OVERLAY", "5 LAYERS")
makeRow(espPage, 48, "Distance Markers", "Shows live range on tracked players", function() return Settings.ESPShowDistance end, function(v) Settings.ESPShowDistance = v; refreshESP() end)
makeRow(espPage, 108, "Outline Layer", "Highlights players through geometry", function() return Settings.ESPEnabled end, setESPEnabled)
makeRow(espPage, 168, "Info Tags", "Shows name and health information", function() return Settings.ESPShowNames end, function(v) Settings.ESPShowNames = v; refreshESP() end)
makeRow(espPage, 228, "Health Bars", "Shows current player health", function() return Settings.ESPShowHealth end, function(v) Settings.ESPShowHealth = v; refreshESP() end)
makeSlider(espPage, 288, "Render Range", function() return Settings.ESPMaxDistance end, function(v) Settings.ESPMaxDistance = math.floor(v / 50 + 0.5) * 50; refreshESP() end, 100, 10000, "%.0f studs")

local healthPage = newPage("Health")
healthBody = healthPage
pageHead(healthPage, "health", "HEALTH CORE", "3 MODULES")
makeRow(healthPage, 48, "Health Escape", "Moves 70 studs upward at the threshold", function() return Settings.HealthEscapeEnabled end, Guard.setEnabled)
makeRow(healthPage, 108, "Escape Lock", "Holds position until released", function() return Settings.HealthLock end, function(v) Settings.HealthLock = v; Guard.step() end)
makeRow(healthPage, 168, "Automatic Source", "Uses the client-visible health reader", function() return Settings.HealthSource == "Auto" end, function(v) Settings.HealthSource = v and "Auto" or "Custom"; Guard.step() end)
makeSlider(healthPage, 228, "Alert Threshold", function() return Settings.HealthThreshold end, function(v) Settings.HealthThreshold = math.floor(v + 0.5); Guard.step() end, 5, 80, "%.0f%%")
local healthHint = safeText(healthPage, "Hint", "Re-arms 5 percentage points above the threshold.", 16, 312, W - 32, 18, 9, C.faint, Enum.Font.GothamMedium)
healthHint.TextXAlignment = Enum.TextXAlignment.Center
UI.healthStatus = safeText(healthPage, "CompatStatus", "", -100, -100, 1, 1, 1, C.dim)
UI.healthStatus.Visible = false
UI.healthDetail = safeText(healthPage, "CompatDetail", "", -100, -100, 1, 1, 1, C.dim)
UI.healthDetail.Visible = false

local farmPage = newPage("Farm")
farmBody = farmPage
pageHead(farmPage, "farm", "FARM ROUTE", "5 NODES")
makeRow(farmPage, 48, "Auto Farm", "Selects eligible 3000-3200 HP targets", function() return Settings.FarmEnabled end, Farm.setEnabled)
makeRow(farmPage, 108, "Auto Boss", "Routes through saved boss locations", function() return Settings.AutoBoss end, Farm.setAutoBoss)
makeRow(farmPage, 168, "Auto Collect", "Loots boss drops and world rewards", function() return Settings.FarmAutoLoot end, Farm.setLoot)
makeRow(farmPage, 228, "Auto M1", "Uses the inventory-safe M1 path", function() return Settings.FarmM1 end, function(v) Settings.FarmM1 = v; Farm.step() end)
makeSlider(farmPage, 288, "Boss Delay", function() return Settings.BossNoAttackTimeout end, function(v) Settings.BossNoAttackTimeout = math.max(1, v) end, 1, 10, "%.1fs")
local farmHint = safeText(farmPage, "Hint", "Auto Boss keeps the same-boss respawn route when possible.", 16, 372, W - 32, 18, 9, C.faint, Enum.Font.GothamMedium)
farmHint.TextXAlignment = Enum.TextXAlignment.Center
UI.farmHint = farmHint
UI.farmCount = safeText(farmPage, "Count", "0", 0, 0, 1, 1, 1, C.dim)
UI.farmName = safeText(farmPage, "Target", "None", 0, 0, 1, 1, 1, C.dim)
UI.farmID = safeText(farmPage, "ID", "--", 0, 0, 1, 1, 1, C.dim)
UI.farmPath = safeText(farmPage, "Path", "", 0, 0, 1, 1, 1, C.dim)
UI.farmHP = safeText(farmPage, "HP", "", 0, 0, 1, 1, 1, C.dim)
UI.farmParts = safeText(farmPage, "Parts", "", 0, 0, 1, 1, 1, C.dim)
UI.farmStatus = safeText(farmPage, "Status", "", 0, 0, 1, 1, 1, C.dim)
UI.farmDetail = safeText(farmPage, "Detail", "", 0, 0, 1, 1, 1, C.dim)
UI.refTargetName = safeText(farmPage, "RefTarget", "", 0, 0, 1, 1, 1, C.dim)
UI.refBossDelay = safeText(farmPage, "RefDelay", "", 0, 0, 1, 1, 1, C.dim)
UI.refRunDot = frame(farmPage, "RunDot", 0, 0, 1, 1, C.dim, 1)
UI.refElapsed = safeText(farmPage, "Elapsed", "", 0, 0, 1, 1, 1, C.dim)

local movePage = newPage("Move")
moveBody = movePage
pageHead(movePage, "move", "MOVEMENT", "3 MODULES")
makeRow(movePage, 48, "NoClip", "Prevents collision while moving", function() return Settings.NoClip end, function(v) Settings.NoClip = v; Movement.step(0) end)
makeRow(movePage, 108, "Fly", "Camera-relative full-direction flight", function() return Settings.FlyEnabled end, Movement.setFly)
makeRow(movePage, 168, "Speed", "Adjusts local walk speed", function() return Settings.SpeedEnabled end, function(v) Settings.SpeedEnabled = v; Movement.step(0) end)
makeSlider(movePage, 228, "Speed Multiplier", function() return Settings.FlySpeed end, function(v) Settings.FlySpeed = math.floor(v + 0.5); Movement.step(0) end, 20, 200, "%.0f")
local moveHint = safeText(movePage, "Hint", "T is blocked while NoClip is active.", 16, 312, W - 32, 18, 9, C.faint, Enum.Font.GothamMedium)
moveHint.TextXAlignment = Enum.TextXAlignment.Center
UI.moveStatus = safeText(movePage, "CompatStatus", "", -100, -100, 1, 1, 1, C.dim)
UI.moveStatus.Visible = false
UI.moveDetail = safeText(movePage, "CompatDetail", "", -100, -100, 1, 1, 1, C.dim)
UI.moveDetail.Visible = false
UI.moveStatusDot = frame(movePage, "MoveDot", 0, 0, 1, 1, C.dim, 1)
UI.moveMasterStroke = stroke(movePage, C.line, 1, 1)

local systemPage = newPage("System")
systemBody = systemPage
pageHead(systemPage, "system", "SYSTEM CORE", "STATUS")
makeRow(systemPage, 48, "Overlay Lock", "Pins the panel after dragging", function() return false end, function(_) end)
makeRow(systemPage, 108, "Auto Rejoin", "Retries the configured recovery path", function() return Settings.AutoRejoin end, System.setAutoRejoin)
makeRow(systemPage, 168, "Auto Execute", "Queues the script after teleport", function() return Settings.AutoExecute end, function(v) Settings.AutoExecute = v end)
makeRow(systemPage, 228, "Static Map Scan", "Discovers replicated boss locations", function() return Settings.StaticMapScan end, function(v) Settings.StaticMapScan = v end)
local scanButton = button(systemPage, "Scan", "SCAN MAP NOW", 16, 288, 128, 30, C.panel2, 9)
scanButton.TextColor3 = C.cyan
stroke(scanButton, C.violet2, 0.55, 1)
UI.staticScanButton = scanButton
UI.staticScanStatus = safeText(systemPage, "ScanStatus", "", 154, 286, 244, 34, 9, C.faint, Enum.Font.GothamMedium)
UI.staticScanStatus.TextWrapped = true
connect(scanButton.Activated, function()
    if Farm.staticMapScan then Farm.staticMapScan(true) end
    render()
end)
local systemHint = safeText(systemPage, "Hint", "VOID NEXUS  /  LINK STABLE", 16, 336, W - 32, 18, 9, C.faint, Enum.Font.GothamMedium)
systemHint.TextXAlignment = Enum.TextXAlignment.Center
UI.systemStatus = safeText(systemPage, "CompatStatus", "", -100, -100, 1, 1, 1, C.dim)
UI.systemStatus.Visible = false
UI.systemDetail = safeText(systemPage, "CompatDetail", "", -100, -100, 1, 1, 1, C.dim)
UI.systemDetail.Visible = false
UI.systemStatusDot = frame(systemPage, "SystemDot", 0, 0, 1, 1, C.dim, 1)
UI.systemMasterStroke = stroke(systemPage, C.line, 1, 1)
UI.rejoinStatus = safeText(systemPage, "RejoinStatus", "", 0, 0, 1, 1, 1, C.dim)
UI.privateMapBox = make("TextBox", systemPage, {
    Name = "PrivateMap", Text = Settings.PrivateServerMap, Position = UDim2.fromOffset(16, 360),
    Size = UDim2.fromOffset(180, 28), BackgroundColor3 = Color3.fromRGB(18,10,30),
    BorderSizePixel = 0, TextColor3 = C.ink, TextSize = 10, Font = Enum.Font.GothamMedium,
    PlaceholderText = "Map", ClearTextOnFocus = false, ZIndex = 5,
})
corner(UI.privateMapBox, 8); stroke(UI.privateMapBox, C.line, 0.72, 1)
connect(UI.privateMapBox.FocusLost, function()
    Settings.PrivateServerMap = UI.privateMapBox.Text ~= "" and UI.privateMapBox.Text or Settings.PrivateServerMap
    render()
end)

-- ========================= CONTROL CENTER =========================
-- The Control Center intentionally contains only the two requested modules:
-- Automation Profiles and Session Analytics.  UI scale/opacity and the old
-- Core Services toolbox are not part of this page.
CoreUI = {page = newPage("Core")}
pageHead(CoreUI.page, "system", "CONTROL CENTER", "2 MODULES")

local function coreButton(parent, name, text, x, y, width, callback)
    local b = button(parent, name, text, x, y, width, 34, C.panel2, 8)
    b.TextColor3 = C.ink
    b.TextSize = 9
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = false
    stroke(b, C.line, .55, 1)
    if callback then connect(b.Activated, callback) end
    return b
end

-- Automation Profiles
local coreProfile = frame(CoreUI.page, "Profiles", 16, 50, W - 32, 126, C.panel2, 10)
stroke(coreProfile, C.line, .7, 1)
safeText(coreProfile, "Title", "AUTOMATION PROFILES", 12, 9, 200, 18, 11, C.ink, Enum.Font.GothamBold)
local profileName = safeText(coreProfile, "Active", "Default", 12, 31, 180, 18, 10, C.faint, Enum.Font.GothamMedium)
CoreUI.profileName = profileName
CoreUI.profileButtons = {}
CoreUI.profileBox = coreProfile
CoreUI.profileInput = make("TextBox", coreProfile, {
    Name="ProfileInput",
    Position=UDim2.fromOffset(202,30),
    Size=UDim2.fromOffset(170,24),
    BackgroundColor3=C.panel,
    BorderSizePixel=0,
    TextColor3=C.ink,
    PlaceholderText="Profile name",
    PlaceholderColor3=C.faint,
    Text="",
    TextSize=10,
    Font=Enum.Font.GothamMedium,
    ClearTextOnFocus=false,
    ZIndex=20,
})
stroke(CoreUI.profileInput, C.line, .6, 1)
coreButton(coreProfile,"SaveProfile","SAVE",12,70,78,function()
    if System.saveProfile then
        System.saveProfile(CoreUI.profileInput.Text~="" and CoreUI.profileInput.Text or System.activeProfile)
    end
end)
coreButton(coreProfile,"LoadProfile","LOAD",96,70,78,function()
    if System.loadProfile then
        System.loadProfile(CoreUI.profileInput.Text~="" and CoreUI.profileInput.Text or System.activeProfile)
    end
end)
coreButton(coreProfile,"NewProfile","DUPLICATE",180,70,88,function()
    if System.duplicateProfile then
        System.duplicateProfile(CoreUI.profileInput.Text~="" and CoreUI.profileInput.Text or System.activeProfile)
    end
end)
coreButton(coreProfile,"DeleteProfile","DELETE",274,70,78,function()
    if System.deleteProfile then
        System.deleteProfile(CoreUI.profileInput.Text~="" and CoreUI.profileInput.Text or System.activeProfile)
    end
end)

-- Session Analytics
local coreStats = frame(CoreUI.page, "Analytics", 16, 190, W - 32, 246, C.panel2, 10)
stroke(coreStats, C.line, .7, 1)
safeText(coreStats,"Title","SESSION ANALYTICS",12,9,180,18,11,C.ink,Enum.Font.GothamBold)
CoreUI.statsLabel = safeText(coreStats,"Stats", "Runtime 00:00:00  |  Targets 0  |  Kills 0\nLoots 0  |  Bosses 0  |  Teleports 0", 12,34,W-56,38,10,C.faint,Enum.Font.GothamMedium)
CoreUI.statsLabel.TextWrapped=true
CoreUI.efficiencyLabel = safeText(coreStats,"Efficiency","RATE / HOUR   Targets 0.0   Kills 0.0   Bosses 0.0\nLoots 0.0   Teleports 0.0   Kill Rate 0.0%",12,73,W-56,34,9,C.faint,Enum.Font.GothamMedium)
CoreUI.efficiencyLabel.TextWrapped=true
CoreUI.liveLabel = safeText(coreStats,"Live","LIVE   No target\nHP -- / -- HP   |   -- studs   |   IDLE",12,109,W-56,36,9.5,C.ink,Enum.Font.GothamMedium)
CoreUI.liveLabel.TextWrapped=true
CoreUI.targetLabel = safeText(coreStats,"Target","Last Target: --",12,147,W-56,18,10,C.ink,Enum.Font.GothamMedium)
CoreUI.safetyLabel = safeText(coreStats,"Safety","Safety: SAFE",12,169,W-56,18,10,C.green,Enum.Font.GothamBold)
coreButton(coreStats,"ResetStats","RESET STATS",W-150,201,120,function()
    if System.resetStats then System.resetStats() end
end)
coreButton(coreStats,"MiniMode","MINI MODE",W-276,201,116,function()
    if MiniMode and MiniMode.toggle then MiniMode.toggle() end
end)

local ThemeUI = {page = newPage("Theme")}
pageHead(ThemeUI.page, "theme", "THEME", "DISPLAY")
local themeInfo = frame(ThemeUI.page, "ThemeInfo", 16, 48, W - 32, 54, Color3.fromRGB(18,10,30), 10)
ThemeUI.themeInfo = themeInfo
stroke(themeInfo, C.line, 0.72, 1)
safeText(themeInfo, "Name", "ACTIVE PRESET", 12, 7, 130, 16, 9, C.faint, Enum.Font.GothamBold)
ThemeUI.activeLabel = safeText(themeInfo, "Active", "DEFAULT", 12, 25, 180, 20, 13, C.ink, Enum.Font.GothamBold)
ThemeUI.activeLabel.TextStrokeTransparency = 0.88
safeText(themeInfo, "Desc", "Saved automatically for the next execution.", 160, 17, W - 188, 30, 9, C.faint, Enum.Font.GothamMedium)

function ThemeUI.makePreset(y, title, desc, themeName)
    local row = frame(ThemeUI.page, "Preset_" .. themeName, 16, y, W - 32, 62, Color3.fromRGB(18,10,30), 10)
    local rowStroke = stroke(row, C.line, 0.72, 1)
    local icon = frame(row, "Icon", 12, 13, 36, 36, C.black, 18)
    icon.BackgroundTransparency = 0.18
    stroke(icon, C.violet2, 0.48, 1)
    if themeName == "Blackhole" then
        local orb = frame(icon, "Orb", 9, 9, 18, 18, Color3.new(0,0,0), 9)
        orb.BackgroundTransparency = 0
        stroke(orb, Color3.fromRGB(238,241,251), 0.32, 1)
        local orbit = frame(icon, "Orbit", 4, 15, 28, 8, Color3.new(1,1,1), 4)
        orbit.BackgroundTransparency = 1
        orbit.Rotation = -16
        stroke(orbit, C.violet2, 0.30, 1)
    elseif themeName == "Empyrean" then
        local halo = frame(icon, "Halo", 7, 7, 22, 22, Color3.new(1,1,1), 11)
        halo.BackgroundTransparency = 1; stroke(halo, Color3.fromRGB(217,169,78), 0.18, 2)
        local core = frame(icon, "Core", 12, 12, 12, 12, Color3.fromRGB(255,243,200), 6)
        core.BackgroundTransparency = 0.05; stroke(core, Color3.fromRGB(156,116,32), 0.42, 1)
    elseif themeName == "Frost" then
        local crystal = frame(icon, "Crystal", 10, 10, 16, 16, Color3.fromRGB(223,249,255), 4)
        crystal.Rotation = 45; crystal.BackgroundTransparency = .08
        stroke(crystal, Color3.fromRGB(173,224,235), .16, 1)
        local core = frame(icon, "Core", 14, 14, 8, 8, Color3.fromRGB(240,253,255), 4)
        core.BackgroundTransparency = .02
    else
        local core = frame(icon, "Core", 11, 11, 14, 14, C.violet2, 7)
        core.BackgroundTransparency = 0.25
        stroke(core, C.cyan, 0.45, 1)
    end
    safeText(row, "Title", title, 60, 8, 190, 18, 12.5, C.ink, Enum.Font.GothamBold)
    safeText(row, "Desc", desc, 60, 28, 205, 18, 9.5, C.faint, Enum.Font.GothamMedium)
    local select = button(row, "Select", "SELECT", W - 104, 14, 76, 34, C.panel2, 9)
    select.TextColor3 = C.faint
    select.Active = true
    select.ZIndex = 40
    row.ZIndex = 30
    stroke(select, C.line, 0.58, 1)
    local selecting = false
    local function chooseTheme()
        if selecting then return end
        selecting = true
        task.defer(function()
            selecting = false
            if UI.setTheme then UI.setTheme(themeName) end
        end)
    end
    connect(select.Activated, chooseTheme)
    connect(select.MouseButton1Click, chooseTheme)
    return row, select, rowStroke
end

ThemeUI.defaultRow, ThemeUI.defaultButton = ThemeUI.makePreset(
    114, "Default", "Original Void Nexus interface", "Default"
)
ThemeUI.blackholeRow, ThemeUI.blackholeButton = ThemeUI.makePreset(
    186, "Blackhole V1", "HTML-matched black-hole reactor interface", "Blackhole"
)
ThemeUI.empyreanRow, ThemeUI.empyreanButton = ThemeUI.makePreset(
    258, "EMPYREAN", "Celestial gold / heaven-inspired interface", "Empyrean"
)
ThemeUI.frostRow, ThemeUI.frostButton = ThemeUI.makePreset(
    330, "FROSTBOUND", "Frozen sanctum / glacial glass interface", "Frost"
)
ThemeUI.hint = safeText(ThemeUI.page, "Hint", "Theme changes are saved immediately.", 16, 402, W - 32, 18, 9, C.faint, Enum.Font.GothamMedium)
ThemeUI.hint.TextXAlignment = Enum.TextXAlignment.Center

UI.count = safeText(skillsPage, "Count", "4 / 4 ENABLED", 0, 0, 1, 1, 1, C.dim)
UI.cycle = safeText(skillsPage, "Cycle", "", 0, 0, 1, 1, 1, C.dim)
UI.status = safeText(skillsPage, "Status", "STANDBY", 0, 0, 1, 1, 1, C.dim)
UI.detail = safeText(skillsPage, "Detail", "", 0, 0, 1, 1, 1, C.dim)
UI.statusDot = frame(skillsPage, "StatusDot", 0, 0, 1, 1, C.dim, 1)
UI.healthStatusDot = frame(healthPage, "HealthDot", 0, 0, 1, 1, C.dim, 1)
UI.healthSource = safeText(healthPage, "Source", "Auto", 0, 0, 1, 1, 1, C.dim)
UI.healthSourceDetail = safeText(healthPage, "SourceDetail", "", 0, 0, 1, 1, 1, C.dim)
UI.healthRearm = safeText(healthPage, "Rearm", "", 0, 0, 1, 1, 1, C.dim)
UI.healthNumbers = safeText(healthPage, "Numbers", "", 0, 0, 1, 1, 1, C.dim)
UI.healthPercent = safeText(healthPage, "Percent", "", 0, 0, 1, 1, 1, C.dim)
UI.healthFill = frame(healthPage, "HealthFill", -100, -100, 1, 1, C.green, 1)
UI.healthFill.Visible = false
UI.healthMarker = frame(healthPage, "HealthMarker", -100, -100, 1, 1, C.red, 1)
UI.healthMarker.Visible = false
UI.healthRelease = safeText(healthPage, "Release", "", 0, 0, 1, 1, 1, C.dim)
UI.espCount = safeText(espPage, "ESPCount", "0 TRACKED", 0, 0, 1, 1, 1, C.dim)
UI.espDetail = safeText(espPage, "ESPDetail", "", 0, 0, 1, 1, 1, C.dim)
UI.espStatus = safeText(espPage, "ESPStatus", "ESP OFF", 0, 0, 1, 1, 1, C.dim)
UI.espStatusDot = frame(espPage, "ESPStatusDot", 0, 0, 1, 1, C.dim, 1)
UI.espMasterStroke = stroke(espPage, C.line, 1, 1)
UI.healthMasterStroke = stroke(healthPage, C.line, 1, 1)
UI.masterStroke = stroke(skillsPage, C.line, 1, 1)
UI.farmHeaderGlow = frame(farmPage, "FarmGlow", 0, 0, 1, 1, C.violet2, 1)
UI.advancedArrow = safeText(farmPage, "Advanced", "", 0, 0, 1, 1, 1, C.dim)
UI.filterArrow = safeText(farmPage, "Filter", "", 0, 0, 1, 1, 1, C.dim)
UI.bossDwell = safeText(farmPage, "Dwell", "", 0, 0, 1, 1, 1, C.dim)
UI.bossRadius = safeText(farmPage, "Radius", "", 0, 0, 1, 1, 1, C.dim)
UI.bossDiscover = safeText(farmPage, "Discover", "", 0, 0, 1, 1, 1, C.dim)
UI.bossSaveStatus = safeText(farmPage, "SaveStatus", "", 0, 0, 1, 1, 1, C.dim)
UI.bossDiscoveryStatus = safeText(farmPage, "DiscoveryStatus", "", 0, 0, 1, 1, 1, C.dim)

UI.footerBar = frame(panel, "FooterCompatibility", 0, 0, 1, 1, C.panel, 1)
UI.footerBar.Visible = false
UI.footerConnected = safeText(panel, "FooterConnected", "CONNECTED", 0, 0, 1, 1, 1, C.green)
UI.footerConnected.Visible = false
local footerDot = frame(panel, "FooterDot", 0, 0, 1, 1, C.green, 1)
footerDot.Visible = false

-- Command palette overlay
local commandOverlay = make("Frame", root, {Name="CommandPalette", Position=UDim2.fromScale(.5,.18), Size=UDim2.fromOffset(math.min(520, W-40), 112), AnchorPoint=Vector2.new(.5,0), BackgroundColor3=C.panel, BackgroundTransparency=.04, BorderSizePixel=0, Visible=false, ZIndex=80})
stroke(commandOverlay,C.line,.25,1)
local commandTitle=safeText(commandOverlay,"Title","COMMAND PALETTE  •  CTRL+K",14,10,400,18,10,C.ink,Enum.Font.GothamBold)
local commandInput=make("TextBox",commandOverlay,{Name="Input",Position=UDim2.fromOffset(14,36),Size=UDim2.new(1,-28,36,0),BackgroundColor3=C.panel2,TextColor3=C.ink,PlaceholderText="Try: boss, esp players, theme empyrean, stop, core",PlaceholderColor3=C.faint,Text="",TextSize=11,Font=Enum.Font.GothamMedium,ClearTextOnFocus=false,ZIndex=81})
stroke(commandInput,C.line,.5,1)
local commandHint=safeText(commandOverlay,"Hint","ENTER executes  •  ESC closes",14,78,400,16,8,C.faint,Enum.Font.GothamMedium)
UI.commandOverlay=commandOverlay; UI.commandInput=commandInput
local utilityOverlay = make("Frame", root, {Name="UtilityOverlay", Position=UDim2.fromScale(.5,.5), Size=UDim2.fromOffset(math.min(560,W-32), 420), AnchorPoint=Vector2.new(.5,.5), BackgroundColor3=C.panel, BackgroundTransparency=.03, BorderSizePixel=0, Visible=false, ZIndex=90})
stroke(utilityOverlay,C.line,.22,1)
local utilityTitle=safeText(utilityOverlay,"Title","CONTROL CENTER",16,12,400,20,12,C.ink,Enum.Font.GothamBold)
local utilityBody=make("ScrollingFrame",utilityOverlay,{Name="Body",Position=UDim2.fromOffset(14,46),Size=UDim2.new(1,-28,1,-92),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.fromOffset(0,0),ZIndex=91})
local utilityText=safeText(utilityBody,"Text","",4,4,500,500,10,C.faint,Enum.Font.GothamMedium); utilityText.TextWrapped=true; utilityText.TextYAlignment=Enum.TextYAlignment.Top
local utilityInput=make("TextBox",utilityOverlay,{Name="Editor",Position=UDim2.new(0,14,1,-78),Size=UDim2.new(1,-124,0,34),BackgroundColor3=C.panel2,TextColor3=C.ink,PlaceholderText="Keybind: EmergencyStop=F10",PlaceholderColor3=C.faint,Text="",TextSize=9,Font=Enum.Font.GothamMedium,ClearTextOnFocus=false,ZIndex=92})
stroke(utilityInput,C.line,.55,1)
local utilityClose=make("TextButton",utilityOverlay,{Name="Close",Position=UDim2.new(1,-96,1,-40),Size=UDim2.fromOffset(78,34),BackgroundColor3=C.panel2,Text="CLOSE",TextColor3=C.ink,TextSize=9,Font=Enum.Font.GothamBold,AutoButtonColor=false,ZIndex=92})
stroke(utilityClose,C.line,.55,1); connect(utilityClose.Activated,function() utilityOverlay.Visible=false end)
UI.utilityOverlay=utilityOverlay; UI.utilityTitle=utilityTitle; UI.utilityText=utilityText; UI.utilityInput=utilityInput
local function openUtility(title,text) utilityTitle.Text=title; utilityText.Text=text; utilityOverlay.Visible=true; utilityBody.CanvasPosition=Vector2.new(0,0) end
connect(utilityInput.FocusLost,function(enter)
    if not enter then return end
    local action,key=tostring(utilityInput.Text):match("^%s*([%w_]+)%s*=%s*([%w_]+)%s*$")
    if action and key and Enum.KeyCode[key] then
        local kc=Enum.KeyCode[key]; System.keybinds[action]=kc
        local map={ToggleAutomation="ToggleKey",StopAutomation="StopKey",ToggleUI="VisibilityKey",ToggleESP="ESPToggleKey",ToggleHealth="HealthToggleKey"}
        if map[action] then Settings[map[action]]=kc end
        System.savePrefs(); System.notify("Keybind updated: "..action.." = "..key)
    else System.notify("Invalid keybind format. Example: EmergencyStop=F10") end
    utilityInput.Text=""
end)
System.showLocations=function()
    local lines={"LOCATION DATABASE","", "Remembered bosses: "..tostring(#(Farm.remembered or {})), "Saved catalog: "..tostring((function() local n=0; for _ in pairs(Farm.catalog or {}) do n=n+1 end; return n end)()), "", "FAVORITES / SAVED ROUTES"}
    local entries={}; for _,e in pairs(Farm.catalog or {}) do entries[#entries+1]=e end; table.sort(entries,function(a,b) return tostring(a.name)<tostring(b.name) end)
    for i,e in ipairs(entries) do if i>80 then break end; lines[#lines+1]=string.format("%02d  %s  [%.0f, %.0f, %.0f]",i,tostring(e.name),e.spawn.X,e.spawn.Y,e.spawn.Z) end
    openUtility("LOCATION DATABASE",table.concat(lines,"\n"))
end
System.showKeybinds=function()
    openUtility("KEYBIND MANAGER",table.concat({"F6  •  Toggle Automation","F7  •  Stop / unload","F8  •  Toggle ESP","F9  •  Toggle Health","RIGHT SHIFT  •  Toggle UI","CTRL+K  •  Command Palette","END  •  Emergency Stop","","To change a keybind, edit the profile after saving it. Keybind state is kept separately from theme state."},"\n"))
end
System.showNotifications=function()
    local lines={"NOTIFICATION CENTER",""}; for i=1,math.min(#System.notificationLog,80) do local e=System.notificationLog[i]; lines[#lines+1]=string.format("[%s] %s",e.time,e.message) end; openUtility("NOTIFICATION CENTER",table.concat(lines,"\n"))
end
connect(commandInput.FocusLost,function(enter) if enter then System.executeCommand(commandInput.Text); commandInput.Text="" end end)
connect(Input.InputBegan,function(input,processed)
    if processed then return end
    if input.KeyCode==Enum.KeyCode.Escape and System.commandOpen then System.commandOpen=false; commandOverlay.Visible=false; return end
    if input.KeyCode==Enum.KeyCode.K and (Input:IsKeyDown(Enum.KeyCode.LeftControl) or Input:IsKeyDown(Enum.KeyCode.RightControl)) then System.toggleCommandPalette() end
    if input.KeyCode==System.keybinds.EmergencyStop then System.emergencyStop() end
end)

local pageMap = {Skills = skillsPage, ESP = espPage, Health = healthPage, Farm = farmPage, Move = movePage, System = systemPage, Theme = ThemeUI.page, Core = CoreUI.page}
local pageBaseY = 0

showPage = function(key)
    State.tab = key
    for name, page in pairs(pageMap) do page.Visible = name == key end
    render()
    local page = pageMap[key]
    if page then
        page.CanvasPosition = Vector2.new(0, 0)
        page.Position = UDim2.fromOffset(8, pageBaseY)
        page.BackgroundTransparency = 1
        animate(page, {Position = UDim2.fromOffset(0, pageBaseY)}, false)
        task.delay(0.01, function()
            if State.alive and page.Parent and State.tab == key then
                page.BackgroundTransparency = 1
            end
        end)
    end
end

-- Frost renderer handle is declared before every navigation callback that can reference it.
local FrostNav = {sidebar=nil, crest=nil, realm=nil, sanctum=nil, control=nil, lore=nil}

for key, tab in pairs(navButtons) do
    connect(tab.MouseEnter, function()
        if State.tab ~= key then
            if System.theme == "Frost" then
                FrostNav.paintTab(tab,false,true)
            else
                local hoverColor = System.theme == "Empyrean" and Color3.fromRGB(255,243,200) or Color3.fromRGB(24,13,38)
                animate(tab, {BackgroundColor3 = hoverColor}, false)
            end
        end
    end)
    connect(tab.MouseLeave, function()
        if State.tab ~= key then
            if System.theme == "Frost" then
                FrostNav.paintTab(tab,false,false)
            else
                local normalColor = System.theme == "Empyrean" and Color3.fromRGB(255,255,255) or Color3.fromRGB(8,4,16)
                animate(tab, {BackgroundColor3 = normalColor}, false)
            end
        end
    end)
    connect(tab.Activated, function() showPage(key) end)
end

local function updateTabVisuals()
    local emp = System.theme == "Empyrean"
    local frost = System.theme == "Frost"
    if frost then
        FrostNav.ensure()
        return
    end
    for key, tab in pairs(navButtons) do
        local selected = State.tab == key
        if emp then
            tab.BackgroundColor3 = selected and Color3.fromRGB(255,243,200) or Color3.fromRGB(255,253,247)
            tab.BackgroundTransparency = selected and .04 or .18
            tab.TextColor3 = selected and C.ink or C.faint
        else
            tab.BackgroundColor3 = selected and Color3.fromRGB(30,14,48) or Color3.fromRGB(8,4,16)
            tab.BackgroundTransparency = 0
            tab.TextColor3 = selected and C.ink or C.faint
        end
        local strokeObj = UI.navStrokes[key]
        if strokeObj then
            strokeObj.Transparency = selected and .42 or .88
            strokeObj.Color = C.line
        end
        local bar = UI.navBars[key]
        if bar then
            bar.Visible = selected
            bar.BackgroundColor3 = C.violet2
        end
        local icon = tab:FindFirstChild("Icon")
        if icon then
            for _, child in ipairs(icon:GetDescendants()) do
                if child:IsA("Frame") then
                    child.BackgroundColor3 = selected and (emp and C.violet2 or C.cyan) or C.faint
                elseif child:IsA("UIStroke") then
                    child.Color = selected and (emp and C.violet2 or C.cyan) or C.faint
                end
            end
        end
    end
end

local EMP = {}

local resizeGrip
local windowPlaced = false
local MIN_WINDOW_WIDTH = W
local windowHeight = H

resizeGrip = button(panel, "ResizeGrip", "", W - 28, H - 28, 28, 28, C.panel, 1)
resizeGrip.BackgroundTransparency = 1
resizeGrip.ZIndex = 30
resizeGrip.Active = true
for i = 1, 3 do
    local line = frame(resizeGrip, "Line" .. i, 26 - i * 6, 26 - i * 6, i * 6, 1, C.violet2, 1)
    line.Rotation = -45
    line.ZIndex = 31
end
connect(resizeGrip.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        State.gesture = {kind = "resize", input = input, start = input.Position, width = windowWidth}
    end
end)

local function setObjectWidth(obj, width)
    if obj and obj.Parent then
        obj.Size = UDim2.new(0, math.max(1, width), obj.Size.Y.Scale, obj.Size.Y.Offset)
    end
end

-- ============================================================
-- FROSTBOUND ISOLATED RENDERER
-- This is presentation-only. It never changes automation state.
-- The legacy Nav frame is hidden in Frost and restored on exit.
-- ============================================================
function FrostNav.paintTab(tab, selected, hover)
    if not tab then return end
    tab.BackgroundColor3 = hover and Color3.fromRGB(40,76,87) or (selected and Color3.fromRGB(48,87,98) or Color3.fromRGB(23,54,64))
    tab.BackgroundTransparency = hover and .56 or (selected and .34 or .78)
    tab.TextColor3 = selected and Color3.fromRGB(240,253,255) or (hover and Color3.fromRGB(223,249,255) or Color3.fromRGB(151,192,202))
    tab.TextSize = 9
    tab.TextXAlignment = Enum.TextXAlignment.Left
    tab.TextYAlignment = Enum.TextYAlignment.Center
    tab.Font = Enum.Font.GothamBold
    tab.AutoButtonColor = false
    tab.ZIndex = 42
    local icon=tab:FindFirstChild("Icon")
    if icon then
        icon.Position=UDim2.fromOffset(12,8)
        icon.ZIndex=43
        for _,d in ipairs(icon:GetDescendants()) do
            if d:IsA("Frame") then d.BackgroundColor3 = selected and Color3.fromRGB(223,249,255) or Color3.fromRGB(151,192,202)
            elseif d:IsA("UIStroke") then d.Color = selected and Color3.fromRGB(173,224,235) or Color3.fromRGB(113,157,168) end
        end
    end
    local key=tab.Name
    local st=UI.navStrokes[key]
    if st then st.Color=Color3.fromRGB(153,211,222); st.Transparency=selected and .42 or .84 end
    local bar=UI.navBars[key]
    if bar then
        bar.Position=UDim2.fromOffset(4,5)
        bar.Size=UDim2.fromOffset(2,26)
        bar.BackgroundColor3=Color3.fromRGB(173,224,235)
        bar.Visible=selected
    end
end

function FrostNav.ensure()
    -- Hide the old container FIRST. This prevents a frame of stale Nexus geometry.
    tabs.Visible=false
    tabs.Active=false

    if not FrostNav.sidebar or not FrostNav.sidebar.Parent then
        FrostNav.sidebar=frame(panel,"FrostboundSidebar",0,64,170,math.max(1,windowHeight-64),Color3.fromRGB(13,34,41),0)
        FrostNav.sidebar.ZIndex=40
        FrostNav.sidebar.ClipsDescendants=false
        local st=stroke(FrostNav.sidebar,Color3.fromRGB(153,211,222),.72,1)
        st.Name="FrostSidebarStroke"
        FrostNav.crest=frame(FrostNav.sidebar,"Crest",61,18,48,48,Color3.fromRGB(223,249,255),8)
        FrostNav.crest.BackgroundTransparency=.91
        FrostNav.crest.Rotation=45
        FrostNav.crest.ZIndex=41
        stroke(FrostNav.crest,Color3.fromRGB(153,211,222),.34,1)
        local core=frame(FrostNav.crest,"Core",15,15,18,18,Color3.fromRGB(240,253,255),4)
        core.BackgroundTransparency=.03; core.Rotation=-45; core.ZIndex=42
        stroke(core,Color3.fromRGB(173,224,235),.25,1)
        FrostNav.realm=safeText(FrostNav.sidebar,"Realm","FROSTBOUND",15,77,140,18,11,Color3.fromRGB(240,253,255),Enum.Font.GothamBold)
        FrostNav.realm.TextXAlignment=Enum.TextXAlignment.Center; FrostNav.realm.ZIndex=42
        FrostNav.sanctum=safeText(FrostNav.sidebar,"Sanctum","SANCTUM",15,98,140,14,7,Color3.fromRGB(113,157,168),Enum.Font.GothamBold)
        FrostNav.sanctum.TextXAlignment=Enum.TextXAlignment.Center; FrostNav.sanctum.ZIndex=42
        FrostNav.control=safeText(FrostNav.sidebar,"Control","CONTROL",15,120,140,14,7,Color3.fromRGB(113,157,168),Enum.Font.GothamBold)
        FrostNav.control.ZIndex=42
        local divider=frame(FrostNav.sidebar,"Divider",14,127,142,1,Color3.fromRGB(153,211,222),0)
        divider.BackgroundTransparency=.78; divider.ZIndex=41
        FrostNav.lore=safeText(FrostNav.sidebar,"Lore","A quiet interface forged\nfrom winter glass.\n\nLet the frost remain still.",15,486,140,62,8,Color3.fromRGB(113,157,168),Enum.Font.GothamMedium)
        FrostNav.lore.TextWrapped=true; FrostNav.lore.ZIndex=42
    end

    FrostNav.sidebar.Position=UDim2.fromOffset(0,64)
    FrostNav.sidebar.Size=UDim2.fromOffset(170,math.max(1,windowHeight-64))
    FrostNav.sidebar.Visible=true
    FrostNav.sidebar.BackgroundColor3=Color3.fromRGB(13,34,41)
    FrostNav.sidebar.BackgroundTransparency=.02

    -- Functional navigation buttons are the original buttons; only their parent
    -- changes. Their Activated callbacks therefore remain untouched.
    for i,key in ipairs(navNames) do
        local tab=navButtons[key]
        if tab then
            if tab.Parent~=FrostNav.sidebar then tab.Parent=FrostNav.sidebar end
            tab.Position=UDim2.fromOffset(15,132+(i-1)*42)
            tab.Size=UDim2.fromOffset(140,36)
            FrostNav.paintTab(tab,State.tab==key,false)
        end
    end
end

function FrostNav.restore()
    if FrostNav.sidebar then FrostNav.sidebar.Visible=false end
    for _,key in ipairs(navNames) do
        local tab=navButtons[key]
        if tab and tab.Parent~=tabs then tab.Parent=tabs end
    end
    tabs.Visible=true
    tabs.Active=true
end

function FrostNav.removeLegacyDecor()
    for _,name in ipairs({"FrostCrest","FrostRealm","FrostSanctum","FrostLabel","FrostLore"}) do
        local obj=tabs:FindFirstChild(name)
        if obj then obj:Destroy() end
    end
end

local function applyWindowWidth(width)
    windowWidth = math.max(MIN_WINDOW_WIDTH, math.floor(width + 0.5))
    setObjectWidth(holder, windowWidth)
    holder.Size = UDim2.fromOffset(windowWidth, windowHeight)
    shadow.Size = UDim2.fromOffset(windowWidth + 12, windowHeight + 12)
    panel.Size = UDim2.fromOffset(windowWidth, windowHeight)
    setObjectWidth(header, windowWidth)
    headerLine.Size = UDim2.fromOffset(windowWidth, 1)
    statusDot.Position = UDim2.fromOffset(windowWidth - 84, 27)
    UI.badge.Position = UDim2.fromOffset(windowWidth - 72, 18)
    setObjectWidth(ticker, windowWidth)
    setObjectWidth(tickerClip, windowWidth)
    setObjectWidth(tickerText, windowWidth * 2)
    setObjectWidth(tabs, windowWidth)
    setObjectWidth(content, windowWidth)
    setObjectWidth(panelBackdrop, windowWidth)
    setObjectWidth(voidFX, windowWidth)
    if System.theme == "Blackhole" then
        BH.hero.Size = UDim2.fromOffset(windowWidth, 152)
        BH.backA.Size = UDim2.fromOffset(windowWidth, 152)
        BH.backB.Size = UDim2.fromOffset(windowWidth, 152)
        BH.front.Size = UDim2.fromOffset(windowWidth, 152)
        BH.backA.Position = UDim2.fromOffset(windowWidth * 0.5, 76)
        BH.backB.Position = UDim2.fromOffset(windowWidth * 0.5, 76)
        BH.front.Position = UDim2.fromOffset(windowWidth * 0.5, 76)
        for _, star in ipairs(BH.stars) do
            star.x = (star.baseX or star.x) * (windowWidth / W)
            star.object.Position = UDim2.fromOffset(math.floor(star.x), math.floor(star.y))
        end
        tabs.Position = UDim2.fromOffset(0, 216)
        content.Position = UDim2.fromOffset(0, 280)
        content.Size = UDim2.fromOffset(windowWidth, windowHeight - 280)
    elseif System.theme == "Empyrean" then
        -- EMPYREAN owns the same 64/160/64/312 layout every time the window is resized.
        -- The old generic branch was resetting these to 88/152, which put the navigation
        -- directly on top of the hero and made the content appear to be from another theme.
        EMP.layoutResponsive(windowWidth, 160)
        tabs.Position = UDim2.fromOffset(0, 224)
        content.Position = UDim2.fromOffset(0, 288)
        content.Size = UDim2.fromOffset(windowWidth, windowHeight - 288)
    elseif System.theme == "Frost" then
        -- FROSTBOUND owns a permanent left sanctum sidebar. Never let the generic
        -- horizontal navigation branch below overwrite its geometry while dragging.
        tabs.Position = UDim2.fromOffset(0, 64)
        tabs.Size = UDim2.fromOffset(170, windowHeight - 64)
        content.Position = UDim2.fromOffset(170, 64)
        content.Size = UDim2.fromOffset(math.max(1, windowWidth - 170), windowHeight - 64)
        FrostNav.ensure()
    else
        tabs.Position = UDim2.fromOffset(0, 88)
        content.Position = UDim2.fromOffset(0, 152)
        content.Size = UDim2.fromOffset(windowWidth, windowHeight - 152)
    end
    resizeVoidEffects(windowWidth)

    if System.theme ~= "Frost" then
        if FrostFX.layer then FrostFX.layer.Visible = false end
        local navCount = #navNames
        local availableNav = math.max(240, windowWidth - 24 - navGap * math.max(0, navCount - 1))
        local dynamicNavW = math.floor(availableNav / navCount)
        for i, key in ipairs(navNames) do
            local tab = navButtons[key]
            if tab then
                tab.Size = UDim2.fromOffset(dynamicNavW, 44)
                tab.Position = UDim2.fromOffset(navX + (i - 1) * (dynamicNavW + navGap), 10)
                local icon = tab:FindFirstChild("Icon")
                if icon then icon.Position = UDim2.fromOffset(math.floor((dynamicNavW - 19) / 2), 5) end
                local bar = UI.navBars[key]
                if bar then
                    bar.Position = UDim2.fromOffset(8, 40)
                    bar.Size = UDim2.fromOffset(math.max(12, dynamicNavW - 16), 2)
                end
            end
        end
    end

    local contentWidth = System.theme == "Frost" and math.max(1, windowWidth - 170) or windowWidth
    for _, page in pairs(pageMap) do
        setObjectWidth(page, contentWidth)
        for _, child in ipairs(page:GetChildren()) do
            if child.Name == "PaneHead" then
                child.Size = UDim2.fromOffset(contentWidth - 32, child.Size.Y.Offset)
            elseif child.Name:match("^Row_") or child.Name:match("^Slider_") or child.Name == "KeyLoadout" then
                local rowWidth = contentWidth - 32
                child.Size = UDim2.fromOffset(rowWidth, child.Size.Y.Offset)
                local toggle = child:FindFirstChild("Toggle")
                if toggle then toggle.Position = UDim2.fromOffset(rowWidth - 54, 14) end
                local value = child:FindFirstChild("Value")
                if value then value.Position = UDim2.fromOffset(rowWidth - 120, 8) end
                local hit = child:FindFirstChild("Slider")
                if hit then
                    hit.Size = UDim2.fromOffset(rowWidth - 56, 24)
                    local rail = hit:FindFirstChild("Rail")
                    if rail then rail.Size = UDim2.fromOffset(rowWidth - 56, 4) end
                end
            end
            if child:IsA("TextLabel") and (child.Name == "Hint") then
                child.Size = UDim2.fromOffset(windowWidth - 32, child.Size.Y.Offset)
            end
        end
    end
    resizeGrip.Position = UDim2.fromOffset(windowWidth - 28, windowHeight - 28)
    if Theme and Theme.syncAllThemeVisuals then Theme.syncAllThemeVisuals() end
    if System.theme == "Frost" and Theme and Theme.applyFrostFinal then
        pcall(function() Theme.applyFrostFinal() end)
    end
end

local function fitWindow(centerIfNeeded)
    if not State.alive then return end
    local viewport = canvas.AbsoluteSize
    if viewport.X <= 0 or viewport.Y <= 0 then return end
    local maxWidth = math.max(MIN_WINDOW_WIDTH, viewport.X - 16)
    windowWidth = math.clamp(windowWidth, MIN_WINDOW_WIDTH, maxWidth)
    applyWindowWidth(windowWidth)
    local width, height = windowWidth, windowHeight
    local x, y
    if centerIfNeeded or not windowPlaced then
        x = (viewport.X - width) / 2
        y = math.max(8, viewport.Y * 0.08)
    else
        x = holder.Position.X.Offset
        y = holder.Position.Y.Offset

        x = math.clamp(x, 8, math.max(8, viewport.X - width - 8))
    end
    holder.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
    windowPlaced = true
end

-- EMPYREAN visual preset hero. Isolated from all other theme visuals.
EMP.hero = frame(panel, "EmpyreanHero", 0, 64, W, 160, Color3.fromRGB(255,250,235), 0)
EMP.hero.ZIndex = 4; EMP.hero.ClipsDescendants = true; EMP.hero.Visible = false
EMP.heroStroke = stroke(EMP.hero, Color3.fromRGB(217,169,78), 0.58, 1)
EMP.sky = frame(EMP.hero, "Sky", 0, 0, W, 160, Color3.fromRGB(255,250,235), 0)
EMP.sky.ZIndex = 1
EMP.skyGradient = make("UIGradient", EMP.sky, {Rotation=90, Color=ColorSequence.new({
    ColorSequenceKeypoint.new(0,Color3.fromRGB(255,250,240)), ColorSequenceKeypoint.new(0.45,Color3.fromRGB(253,238,199)), ColorSequenceKeypoint.new(1,Color3.fromRGB(243,226,186))
})})
EMP.vignette = frame(EMP.hero,"Vignette",0,0,W,160,Color3.fromRGB(255,245,210),0)
EMP.vignette.BackgroundTransparency=.88; EMP.vignette.ZIndex=3
EMP.vignetteGradient=make("UIGradient",EMP.vignette,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(255,245,210)),Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.82),NumberSequenceKeypoint.new(.5,1),NumberSequenceKeypoint.new(1,.82)})})
EMP.glow = frame(EMP.hero,"Glow",0,0,150,150,Color3.fromRGB(255,243,200),75); EMP.glow.AnchorPoint=Vector2.new(.5,.5); EMP.glow.Position=UDim2.fromOffset(W*.5,78); EMP.glow.BackgroundTransparency=.84; EMP.glow.ZIndex=2
EMP.glowStroke=stroke(EMP.glow,Color3.fromRGB(255,224,150),.76,1)
EMP.rayGroup=frame(EMP.hero,"GodRays",0,0,W,160,Color3.new(1,1,1),0); EMP.rayGroup.BackgroundTransparency=1; EMP.rayGroup.AnchorPoint=Vector2.new(.5,.5); EMP.rayGroup.Position=UDim2.fromOffset(W*.5,78); EMP.rayGroup.ZIndex=2
EMP.rays={}
for i=1,12 do
    local width=(i%2==1) and 3 or 2
    local ray=frame(EMP.rayGroup,"Ray"..i,0,0,math.max(74,W*.10),width,Color3.fromRGB(255,243,200),1)
    ray.AnchorPoint=Vector2.new(.5,.5); ray.Position=UDim2.fromOffset(W*.5,78); ray.Rotation=(i-1)*30; ray.BackgroundTransparency=.50; ray.ZIndex=2
    EMP.rays[#EMP.rays+1]=ray
end
EMP.wingL=frame(EMP.hero,"WingL",0,0,150,90,Color3.new(1,1,1),0); EMP.wingL.BackgroundTransparency=1; EMP.wingL.AnchorPoint=Vector2.new(1,.5); EMP.wingL.Position=UDim2.fromOffset(W*.5-5,90); EMP.wingL.ZIndex=5
EMP.wingR=frame(EMP.hero,"WingR",0,0,150,90,Color3.new(1,1,1),0); EMP.wingR.BackgroundTransparency=1; EMP.wingR.AnchorPoint=Vector2.new(0,.5); EMP.wingR.Position=UDim2.fromOffset(W*.5+5,90); EMP.wingR.ZIndex=5
EMP.wingStrokes={}
local wingColors={Color3.fromRGB(217,169,78),Color3.fromRGB(255,243,200),Color3.fromRGB(196,151,64)}
for side,group in ipairs({EMP.wingL,EMP.wingR}) do for i=1,4 do local f=frame(group,"Feather"..i,0,0,78-i*7,2,wingColors[(i%#wingColors)+1],1); f.AnchorPoint=Vector2.new(.5,.5); f.Position=UDim2.fromOffset(side==1 and 54+i*3 or 96-i*3,22+i*12); f.Rotation=side==1 and(-12-i*4)or(12+i*4); f.BackgroundTransparency=.35+i*.08; f.ZIndex=5; EMP.wingStrokes[#EMP.wingStrokes+1]=f end end
EMP.haloA=frame(EMP.hero,"HaloA",0,0,172,40,Color3.new(1,1,1),20); EMP.haloA.AnchorPoint=Vector2.new(.5,.5); EMP.haloA.Position=UDim2.fromOffset(W*.5,78); EMP.haloA.BackgroundTransparency=1; EMP.haloA.ZIndex=6; EMP.haloAStroke=stroke(EMP.haloA,Color3.fromRGB(217,169,78),.28,2)
EMP.haloB=frame(EMP.hero,"HaloB",0,0,104,104,Color3.new(1,1,1),52); EMP.haloB.AnchorPoint=Vector2.new(.5,.5); EMP.haloB.Position=UDim2.fromOffset(W*.5,78); EMP.haloB.BackgroundTransparency=1; EMP.haloB.ZIndex=6; EMP.haloBStroke=stroke(EMP.haloB,Color3.fromRGB(242,193,78),.46,1); EMP.haloBStroke.Transparency=.46
EMP.core=frame(EMP.hero,"Core",0,0,70,70,Color3.fromRGB(255,243,200),35); EMP.core.AnchorPoint=Vector2.new(.5,.5); EMP.core.Position=UDim2.fromOffset(W*.5,78); EMP.core.BackgroundTransparency=.76; EMP.core.ZIndex=7; EMP.coreStroke=stroke(EMP.core,Color3.fromRGB(255,224,150),.22,1)
EMP.dot=frame(EMP.hero,"CoreDot",0,0,8,8,Color3.fromRGB(255,254,248),4); EMP.dot.AnchorPoint=Vector2.new(.5,.5); EMP.dot.Position=UDim2.fromOffset(W*.5,78); EMP.dot.ZIndex=8
EMP.sparkles={}
for i,d in ipairs({{.23,42,1.8},{.77,48,1.6},{.18,118,1.5},{.82,116,1.8},{.5,18,1.3}}) do local sp=frame(EMP.hero,"Spark"..i,0,0,d[3]*2,d[3]*2,Color3.fromRGB(255,243,200),d[3]); sp.AnchorPoint=Vector2.new(.5,.5); sp.Position=UDim2.fromOffset(W*d[1],d[2]); sp.ZIndex=9; sp.BackgroundTransparency=.35; EMP.sparkles[#EMP.sparkles+1]={object=sp,phase=(i-1)*.5} end
EMP.scan=frame(EMP.hero,"Scan",0,-61,W,61,Color3.fromRGB(255,255,255),0); EMP.scan.BackgroundTransparency=.97; EMP.scan.ZIndex=10
EMP.scanGradient=make("UIGradient",EMP.scan,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(255,224,150)),Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,.22),NumberSequenceKeypoint.new(1,1)})})
EMP.clock=os.clock(); EMP.last=EMP.clock; EMP.connection=nil

-- Responsive EMPYREAN composition layout.
-- IMPORTANT: this is deliberately separate from the animation loop.  The old
-- implementation resized the artwork only from RenderStepped, which meant a
-- wide UI could have a full-width hero surface while the actual celestial
-- artwork stayed at its original 300-ish pixel construction size.
function EMP.layoutResponsive(heroWidth, heroHeight)
    heroWidth = math.max(300, math.floor((heroWidth or EMP.hero.AbsoluteSize.X or W) + 0.5))
    heroHeight = math.max(160, math.floor((heroHeight or EMP.hero.AbsoluteSize.Y or 160) + 0.5))

    -- The supplied HTML uses a 300x160 SVG.  We intentionally scale X to the
    -- actual hero width so the celestial composition expands with the Roblox UI,
    -- while preserving the 160px vertical composition and animation timings.
    local sx = heroWidth / 300
    local cx, cy = heroWidth * 0.5, 78
    local function x(v) return math.floor(v * sx + 0.5) end
    local function y(v) return math.floor(v + 0.5) end

    -- Reassert the canonical hero rectangle on every rebuild. No hide/show or
    -- theme pass is allowed to move this surface itself.
    EMP.hero.Position = UDim2.fromOffset(0, 64)
    EMP.hero.Size = UDim2.fromOffset(heroWidth, heroHeight)
    EMP.sky.Position = UDim2.fromOffset(0, 0)
    EMP.sky.Size = UDim2.fromOffset(heroWidth, heroHeight)
    EMP.vignette.Position = UDim2.fromOffset(0, 0)
    EMP.vignette.Size = UDim2.fromOffset(heroWidth, heroHeight)

    EMP.glow.Size = UDim2.fromOffset(x(150), x(150))
    EMP.glow.Position = UDim2.fromOffset(cx, cy)

    -- Keep the ray canvas exactly coincident with the hero. The previous
    -- centered-anchor setup made this container vulnerable to compounded
    -- offsets during visibility/layout rebuilds. Rotation still pivots around
    -- the GUI object's center, while the rays use the hero-local center below.
    EMP.rayGroup.AnchorPoint = Vector2.new(0, 0)
    EMP.rayGroup.Position = UDim2.fromOffset(0, 0)
    EMP.rayGroup.Size = UDim2.fromOffset(heroWidth, heroHeight)

    -- Full-width scan layer, matching the HTML's left:0/right:0 behavior.
    EMP.scan.Size = UDim2.fromOffset(heroWidth, x(61))

    -- Rays use the actual 300->heroWidth horizontal scale, not a fixed-width
    -- approximation.  Their local center remains the HTML's 150px center.
    for i, ray in ipairs(EMP.rays) do
        local baseLength = (i % 2 == 1) and 74 or 74
        ray.Size = UDim2.fromOffset(math.max(40, x(baseLength)), (i % 2 == 1) and 3 or 2)
        ray.Position = UDim2.fromOffset(cx, cy)
    end

    EMP.wingL.Size = UDim2.fromOffset(x(150), 90)
    EMP.wingR.Size = UDim2.fromOffset(x(150), 90)
    EMP.wingL.Position = UDim2.fromOffset(cx - x(5), 90)
    EMP.wingR.Position = UDim2.fromOffset(cx + x(5), 90)

    for side, group in ipairs({EMP.wingL, EMP.wingR}) do
        for i = 1, 4 do
            local feather = group:FindFirstChild("Feather" .. i)
            if feather then
                feather.Size = UDim2.fromOffset(math.max(8, x(78 - i * 7)), 2)
                feather.Position = UDim2.fromOffset(
                    side == 1 and x(54 + i * 3) or x(96 - i * 3),
                    22 + i * 12
                )
            end
        end
    end

    EMP.haloA.Size = UDim2.fromOffset(x(172), math.max(2, 40))
    EMP.haloA.Position = UDim2.fromOffset(cx, cy)
    EMP.haloB.Size = UDim2.fromOffset(x(104), x(104))
    EMP.haloB.Position = UDim2.fromOffset(cx, cy)
    EMP.core.Size = UDim2.fromOffset(x(70), x(70))
    EMP.core.Position = UDim2.fromOffset(cx, cy)
    EMP.dot.Size = UDim2.fromOffset(math.max(4, x(8)), math.max(4, x(8)))
    EMP.dot.Position = UDim2.fromOffset(cx, cy)

    local presets = {{.23,42,1.8},{.77,48,1.6},{.18,118,1.5},{.82,116,1.8},{.5,18,1.3}}
    for i, info in ipairs(EMP.sparkles) do
        local preset = presets[i]
        if preset then
            info.object.Position = UDim2.fromOffset(x(300 * preset[1]), y(preset[2]))
            local size = math.max(2, x(preset[3] * 2))
            info.object.Size = UDim2.fromOffset(size, size)
        end
    end
end

function EMP.startVisuals()
    -- Dedicated EMPYREAN visual engine.  This is intentionally independent
    -- from theme-control recoloring and uses RenderStepped (the same scheduler
    -- used by the working loaders) so the celestial animation cannot silently
    -- disappear when the theme bootstrap is rebuilt.
    if not EMP.hero or not EMP.hero.Parent or not State.alive or System.theme ~= "Empyrean" then return end

    if EMP.connection then
        pcall(function() EMP.connection:Disconnect() end)
        EMP.connection = nil
    end

    EMP.hero.Visible=true
    EMP.hero.ZIndex=4
    EMP.sky.Visible=true
    EMP.vignette.Visible=true
    EMP.rayGroup.Visible=true; EMP.wingL.Visible=true; EMP.wingR.Visible=true
    EMP.haloA.Visible=true; EMP.haloB.Visible=true; EMP.core.Visible=true
    EMP.dot.Visible=true; EMP.scan.Visible=true; EMP.glow.Visible=true

    EMP.clock=os.clock()
    EMP.last=EMP.clock
    EMP.lastWidth=0

    -- IMPORTANT: use the logical window size, not AbsoluteSize. AbsoluteSize is
    -- multiplied by the holder UIScale. During hide/show that UIScale moves from
    -- 1 -> .90 -> 1 and the old renderer treated those animation frames as real
    -- layout changes. That could leave the celestial composition offset after
    -- reopening the menu.
    local okLayout = pcall(function()
        EMP.layoutResponsive(windowWidth, 160)
    end)
    if not okLayout then
        pcall(function() EMP.layoutResponsive(math.max(W, windowWidth), 160) end)
    end
    EMP.lastWidth=windowWidth
    EMP.lastHeight=160

    local function animateCelestial()
        if not State.alive or System.theme ~= "Empyrean" or State.minimized or not EMP.hero.Parent then return end
        local ok, err = pcall(function()
            -- Never let another visual pass hide the celestial composition.
            EMP.hero.Visible=true
            EMP.sky.Visible=true
            EMP.vignette.Visible=true
            EMP.rayGroup.Visible=true; EMP.wingL.Visible=true; EMP.wingR.Visible=true
            EMP.haloA.Visible=true; EMP.haloB.Visible=true; EMP.core.Visible=true
            EMP.dot.Visible=true; EMP.scan.Visible=true; EMP.glow.Visible=true

            local now=os.clock()
            EMP.last=now
            local t=now-EMP.clock
            -- The renderer follows the logical UI dimensions. Do not use
            -- AbsoluteSize here because the menu hide/show animation uses a
            -- UIScale on holder, which intentionally changes AbsoluteSize.
            local heroWidth=math.max(MIN_WINDOW_WIDTH, windowWidth)
            local heroHeight=160

            if math.abs(heroWidth-(EMP.lastWidth or 0)) > 0.5 or math.abs(heroHeight-(EMP.lastHeight or 0)) > 0.5 then
                EMP.lastWidth=heroWidth
                EMP.lastHeight=heroHeight
                EMP.layoutResponsive(heroWidth,heroHeight)
            end

            local sx=heroWidth/300
            -- EMPYREAN (1).html-derived motion timings.
            local breath=(math.sin(t*math.pi*2/4.5)+1)*.5
            EMP.core.BackgroundTransparency=.84-breath*.18
            EMP.glow.BackgroundTransparency=.92-breath*.10
            EMP.haloA.Rotation=t*(360/44)
            EMP.haloB.Rotation=-t*(360/60)
            EMP.rayGroup.Rotation=t*(360/90)
            EMP.wingL.Rotation=-2 + math.sin(t*math.pi*2/5)*4
            EMP.wingR.Rotation=2 - math.sin(t*math.pi*2/5.4)*4

            for i,ray in ipairs(EMP.rays) do
                ray.BackgroundTransparency=.90-((math.sin(t*.9+i*.6)+1)*.5)*.16
            end
            for i,f in ipairs(EMP.wingStrokes) do
                f.BackgroundTransparency=.28+((i%4)*.07)+((math.sin(t*1.2+i)+1)*.5)*.10
            end
            for _,info in ipairs(EMP.sparkles) do
                local pulse=(math.sin((t+info.phase)*math.pi*2/3)+1)*.5
                local ss=math.max(2,(2+3*pulse)*sx)
                info.object.BackgroundTransparency=.86-pulse*.68
                info.object.Size=UDim2.fromOffset(ss,ss)
            end

            local scanH=math.max(42,math.floor(61*sx+.5))
            EMP.scan.Size=UDim2.fromOffset(heroWidth,scanH)
            EMP.scan.Position=UDim2.fromOffset(0,-scanH+((t/7)%1)*(math.max(160,heroHeight+scanH)))
            EMP.scan.BackgroundTransparency=.965
        end)
        if not ok then
            -- Keep the engine alive even if an executor/Roblox GUI object is
            -- temporarily unavailable during a resize or destruction pass.
            EMP.lastError=tostring(err)
        end
    end

    -- RenderStepped is deliberately used instead of Heartbeat because the
    -- loader and the rest of the UI animation stack already run reliably on it.
    EMP.connection=RunService.RenderStepped:Connect(animateCelestial)
    connections[#connections+1]=EMP.connection
    animateCelestial()
end

function EMP.ensureVisuals()
    -- Idempotent entry point used after loader teardown, startup and resizing.
    if System.theme~="Empyrean" or not State.alive or not EMP.hero or not EMP.hero.Parent then return end

    local connected=false
    if EMP.connection then
        local ok, value=pcall(function() return EMP.connection.Connected end)
        connected=ok and value == true
    end

    if not connected then
        EMP.startVisuals()
        return
    end

    EMP.hero.Visible=true
    EMP.sky.Visible=true
    EMP.vignette.Visible=true
    EMP.rayGroup.Visible=true; EMP.wingL.Visible=true; EMP.wingR.Visible=true
    EMP.haloA.Visible=true; EMP.haloB.Visible=true; EMP.core.Visible=true
    EMP.dot.Visible=true; EMP.scan.Visible=true; EMP.glow.Visible=true
    -- Rebind from the logical window dimensions. AbsoluteSize is intentionally
    -- ignored because it includes holder UIScale during menu transitions.
    pcall(function()
        EMP.layoutResponsive(math.max(MIN_WINDOW_WIDTH, windowWidth), 160)
        EMP.lastWidth=windowWidth
        EMP.lastHeight=160
    end)
end

-- A tiny watchdog is intentionally separate from the animation connection.
-- If any theme/bootstrap pass replaces or disconnects the animation connection,
-- the celestial engine is restored on the next frame without touching controls.
-- Lifetime watchdog: this connection deliberately survives theme switches.
-- It does not animate anything itself; it only guarantees that the active
-- EMPYREAN renderer exists whenever EMPYREAN is selected.
EMP.watchdog = EMP.watchdog or RunService.RenderStepped:Connect(function()
    if not State.alive or System.theme ~= "Empyrean" or State.minimized or not EMP.hero or not EMP.hero.Parent then return end
    local connected=false
    if EMP.connection then
        local ok, value=pcall(function() return EMP.connection.Connected end)
        connected=ok and value == true
    end
    if not connected then
        pcall(function() EMP.startVisuals() end)
    end
end)
if EMP.watchdog then
    local alreadyTracked=false
    for _,c in ipairs(connections) do if c==EMP.watchdog then alreadyTracked=true break end end
    if not alreadyTracked then connections[#connections+1]=EMP.watchdog end
end

-- Visibility recovery for EMPYREAN. Hiding the ScreenGui is intentionally a
-- presentation operation only; it must never become a theme/layout operation.
-- On reopen we wait for the UIScale tween to settle, then rebuild the celestial
-- composition from the authoritative logical window size.
function EMP.recoverAfterShow()
    if not State.alive or System.theme ~= "Empyrean" or State.minimized then return end
    EMP.visibilityGeneration = (EMP.visibilityGeneration or 0) + 1
    local generation = EMP.visibilityGeneration
    task.spawn(function()
        for _ = 1, 3 do
            if not State.alive or System.theme ~= "Empyrean" or State.minimized
                or generation ~= EMP.visibilityGeneration then return end
            RunService.RenderStepped:Wait()
        end
        if not State.alive or System.theme ~= "Empyrean" or State.minimized
            or generation ~= EMP.visibilityGeneration then return end
        pcall(function()
            -- No AbsoluteSize/UIScale measurement here. The logical window width
            -- is authoritative and the position-only visibility tween cannot
            -- alter it.
            fitWindow(false)
            EMP.hero.Visible = true
            EMP.layoutResponsive(math.max(MIN_WINDOW_WIDTH, windowWidth), 160)
            EMP.lastWidth = windowWidth
            EMP.lastHeight = 160
            EMP.ensureVisuals()
        end)
    end)
end

local Theme = {
    Default = {
        black = C.black, deep = C.deep, panel = C.panel, panel2 = C.panel2,
        violet = C.violet, violet2 = C.violet2, magenta = C.magenta, cyan = C.cyan,
        ink = C.ink, dim = C.dim, faint = C.faint, line = C.line,
        accent = C.accent, bright = C.bright, muted = C.muted, surface = C.surface,
        text = C.text, voidDeep = C.voidDeep, toggleOn = C.toggleOn, toggleOff = C.toggleOff,
    },
    Blackhole = {
        black = Color3.fromRGB(0,0,0),
        deep = Color3.fromRGB(8,8,12),
        panel = Color3.fromRGB(8,8,12),
        panel2 = Color3.fromRGB(4,4,7),
        violet = Color3.fromRGB(74,37,144),
        violet2 = Color3.fromRGB(122,63,242),
        magenta = Color3.fromRGB(90,45,170),
        cyan = Color3.fromRGB(238,241,251),
        ink = Color3.fromRGB(236,234,245),
        dim = Color3.fromRGB(150,146,170),
        faint = Color3.fromRGB(85,80,105),
        line = Color3.fromRGB(150,120,230),
        accent = Color3.fromRGB(122,63,242),
        bright = Color3.fromRGB(238,241,251),
        muted = Color3.fromRGB(150,146,170),
        surface = Color3.fromRGB(8,8,12),
        text = Color3.fromRGB(236,234,245),
        voidDeep = Color3.fromRGB(4,4,7),
        toggleOn = Color3.fromRGB(70,38,125),
        toggleOff = Color3.fromRGB(24,24,31),
    },
    Empyrean = {
        black = Color3.fromRGB(248, 244, 232), deep = Color3.fromRGB(238, 232, 213),
        panel = Color3.fromRGB(255, 253, 247), panel2 = Color3.fromRGB(255, 248, 232),
        violet = Color3.fromRGB(196, 151, 64), violet2 = Color3.fromRGB(217, 169, 78),
        magenta = Color3.fromRGB(232, 198, 126), cyan = Color3.fromRGB(207, 230, 255),
        ink = Color3.fromRGB(58, 47, 26), dim = Color3.fromRGB(122, 108, 74),
        faint = Color3.fromRGB(171, 157, 120), line = Color3.fromRGB(217, 169, 78),
        accent = Color3.fromRGB(217, 169, 78), bright = Color3.fromRGB(255, 243, 200),
        muted = Color3.fromRGB(171, 157, 120), surface = Color3.fromRGB(255, 250, 235),
        text = Color3.fromRGB(74, 58, 28), voidDeep = Color3.fromRGB(245, 238, 218),
        toggleOn = Color3.fromRGB(217, 169, 78), toggleOff = Color3.fromRGB(226, 220, 202),
    },
    Frost = {
        black = Color3.fromRGB(8, 24, 30), deep = Color3.fromRGB(18, 43, 51),
        panel = Color3.fromRGB(20, 48, 57), panel2 = Color3.fromRGB(30, 65, 75),
        violet = Color3.fromRGB(126, 190, 204), violet2 = Color3.fromRGB(173, 224, 235),
        magenta = Color3.fromRGB(191, 232, 240), cyan = Color3.fromRGB(223, 249, 255),
        ink = Color3.fromRGB(234, 250, 255), dim = Color3.fromRGB(151, 192, 202),
        faint = Color3.fromRGB(113, 157, 168), line = Color3.fromRGB(153, 211, 222),
        accent = Color3.fromRGB(173, 224, 235), bright = Color3.fromRGB(240, 253, 255),
        muted = Color3.fromRGB(151, 192, 202), surface = Color3.fromRGB(27, 59, 69),
        text = Color3.fromRGB(234, 250, 255), voidDeep = Color3.fromRGB(15, 37, 44),
        toggleOn = Color3.fromRGB(116, 190, 204), toggleOff = Color3.fromRGB(47, 79, 87),
    },
    height = H,
    current = nil,
}

-- ========================= MINI MODE =========================
-- Compact live dashboard. It is independent from the normal hide/show system
-- and never changes the main window's UIScale or layout dimensions.
local miniFrame = make("Frame", canvas, {
    Name = "MiniDashboard", Position = UDim2.fromOffset(18, 18), Size = UDim2.fromOffset(292, 94),
    BackgroundColor3 = C.panel, BackgroundTransparency = 0.06, BorderSizePixel = 0,
    Visible = false, Active = true, ZIndex = 200,
})
corner(miniFrame, 14)
local miniStroke = stroke(miniFrame, C.line, 0.45, 1)
local miniTitle = safeText(miniFrame, "Title", "✦ VOID AUTOMATION", 14, 9, 170, 18, 10.5, C.ink, Enum.Font.GothamBold)
local miniDot = frame(miniFrame, "Dot", 264, 12, 8, 8, C.green, 4)
local miniTarget = safeText(miniFrame, "Target", "No target", 14, 31, 190, 18, 11, C.ink, Enum.Font.GothamBold)
local miniStatus = safeText(miniFrame, "Status", "IDLE", 205, 31, 70, 18, 8.5, C.green, Enum.Font.GothamBold)
miniStatus.TextXAlignment = Enum.TextXAlignment.Right
local miniStats = safeText(miniFrame, "Stats", "00:00:00  •  0 Kills  •  0 Bosses", 14, 55, 260, 17, 8.5, C.faint, Enum.Font.GothamMedium)
local miniExpand = button(miniFrame, "Expand", "EXPAND", 14, 73, 68, 15, C.panel2, 7)
miniExpand.TextSize = 7
miniExpand.ZIndex = 205
miniExpand.TextColor3 = C.ink
local miniClose = button(miniFrame, "Close", "×", 268, 7, 18, 18, C.panel2, 9)
miniClose.TextSize = 13
miniClose.ZIndex = 205
miniClose.TextColor3 = C.ink
CoreUI.miniStats = miniStats
CoreUI.miniTarget = miniTarget
CoreUI.miniStatus = miniStatus
CoreUI.miniFrame = miniFrame
CoreUI.miniDot = miniDot

-- Mini Mode has its own live updater.  It must not depend on the main
-- analytics page being rendered or visible; otherwise the compact dashboard
-- can remain at its boot-time zeros while the real session counters change.
function MiniMode.updateLive()
    if not State.alive or not CoreUI or not CoreUI.miniFrame or not CoreUI.miniFrame.Parent then return end

    -- IMPORTANT: Mini Mode must mirror the exact analytics surface that the
    -- Control Center uses.  Keeping a second interpretation of the counters
    -- caused the compact dashboard to drift/stay at its boot-time zeros.
    -- System.stats remains the authoritative event store, while the rendered
    -- CoreUI analytics labels are the authoritative presentation of that store.
    local stats = System and System.stats
    if type(stats) ~= "table" then return end

    local statsText = CoreUI.statsLabel and CoreUI.statsLabel.Parent and CoreUI.statsLabel.Text or nil
    local liveText = CoreUI.liveLabel and CoreUI.liveLabel.Parent and CoreUI.liveLabel.Text or nil

    -- Force the same runtime calculation used by Session Analytics before
    -- reading the display text, without calling refreshStatsUI (which calls us
    -- back and would recurse).
    local now = time()
    local started = tonumber(stats.startedAt)
    if not started or started <= 0 then
        started = now
        stats.startedAt = started
    end
    stats.runtime = math.max(0, now - started)

    -- If the main analytics label exists, parse its already-rendered values.
    -- This guarantees Mini Mode can never show a different counter set.
    local runtimeText, killsText, bossesText
    if type(statsText) == "string" then
        local flat = statsText:gsub("\n", " ")
        runtimeText = flat:match("Runtime%s+(%d+:%d+:%d+)")
        killsText = flat:match("Kills%s+(%d+)")
        bossesText = flat:match("Bosses%s+(%d+)")
    end

    -- Fallback directly to the authoritative numeric store if the label has
    -- not been rendered yet.
    if not runtimeText then
        local sec = math.floor(stats.runtime)
        runtimeText = string.format("%02d:%02d:%02d", math.floor(sec/3600), math.floor((sec%3600)/60), sec%60)
    end
    killsText = tostring(tonumber(killsText) or tonumber(stats.kills) or 0)
    bossesText = tostring(tonumber(bossesText) or tonumber(stats.bosses) or 0)

    -- Prefer the exact LIVE label for target/action.  If the label is not yet
    -- available, fall back to the live Farm state.
    local targetName
    local status
    if type(liveText) == "string" and liveText ~= "" then
        local firstLine = liveText:match("^LIVE%s+([^\n]+)")
        local action = liveText:match("|%s*([%w%s_%-]+)%s*$")
        if firstLine and firstLine ~= "No target" then
            targetName = firstLine
        end
        if action and action ~= "IDLE" then
            status = action:gsub("^%s+", ""):gsub("%s+$", "")
        end
    end

    local selected = Farm and Farm.selected or nil
    if not targetName or targetName == "" then
        targetName = selected and selected.name or stats.lastTarget
    end
    if not targetName or targetName == "" or targetName == "--" then
        targetName = "No target"
    end

    local active = false
    if Settings then
        active = Settings.AutoBoss == true or Settings.FarmEnabled == true
    end
    active = active or State.farming == true or State.discovering == true

    if not status or status == "" then
        status = tostring((Farm and Farm.status) or (active and "ACTIVE" or "IDLE"))
    end

    CoreUI.miniStats.Text = string.format(
        "%s  •  %s Kills  •  %s Bosses",
        runtimeText, killsText, bossesText
    )
    CoreUI.miniTarget.Text = tostring(targetName)
    CoreUI.miniStatus.Text = tostring(status)
    CoreUI.miniStatus.TextColor3 = active and C.green or C.faint
    CoreUI.miniDot.BackgroundColor3 = active and C.green or C.faint
end

local miniDragging = nil
connect(miniFrame.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        miniDragging = {input=input, start=input.Position, x=miniFrame.Position.X.Offset, y=miniFrame.Position.Y.Offset}
    end
end)
connect(Input.InputChanged, function(input)
    if not miniDragging then return end
    local isMouse = miniDragging.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
    if not isMouse and input ~= miniDragging.input then return end
    local d = input.Position - miniDragging.start
    miniFrame.Position = UDim2.fromOffset(miniDragging.x + d.X, miniDragging.y + d.Y)
end)
connect(Input.InputEnded, function(input)
    if miniDragging and input == miniDragging.input then miniDragging=nil end
end)

function MiniMode.applyTheme()
    local emp = System.theme == "Empyrean"
    local bh = System.theme == "Blackhole"
    local frost = System.theme == "Frost"
    local P = frost and Theme.Frost or nil
    miniFrame.BackgroundColor3 = frost and P.panel or C.panel
    miniFrame.BackgroundTransparency = frost and .06 or .06
    miniStroke.Color = frost and P.line or C.line
    miniTitle.TextColor3 = frost and P.bright or C.ink
    miniTarget.TextColor3 = frost and P.bright or C.ink
    miniStats.TextColor3 = frost and P.faint or C.faint
    miniExpand.BackgroundColor3 = frost and P.panel2 or C.panel2
    miniExpand.TextColor3 = frost and P.bright or C.ink
    miniClose.BackgroundColor3 = frost and P.panel2 or C.panel2
    miniClose.TextColor3 = frost and P.bright or C.ink
    miniDot.BackgroundColor3 = frost and P.bright or C.green
    miniTitle.Text = emp and "✦ EMPYREAN" or (bh and "◉ BLACKHOLE V1" or (frost and "✧ FROSTBOUND" or "✦ VOID AUTOMATION"))
end

function MiniMode.show()
    if not State.alive then return end
    State.miniMode = true
    State.minimized = false
    if State.visibilityTween then pcall(function() State.visibilityTween:Cancel() end); State.visibilityTween=nil end
    if holder then
        State.miniX = holder.Position.X.Offset
        State.miniY = holder.Position.Y.Offset
        holder.Visible = false
    end
    miniFrame.Visible = true
    root.Enabled = true
    MiniMode.applyTheme()
    MiniMode.updateLive()
end

function MiniMode.hide()
    if not State.alive then return end
    State.miniMode = false
    miniFrame.Visible = false
    holder.Visible = true
    root.Enabled = true
    if State.minimized then State.minimized = false end
    if State.miniX and State.miniY then holder.Position = UDim2.fromOffset(State.miniX, State.miniY) end
    if System.theme == "Empyrean" and EMP and EMP.recoverAfterShow then EMP.recoverAfterShow() end
end

function MiniMode.toggle()
    if State.miniMode then MiniMode.hide() else MiniMode.show() end
end

connect(miniExpand.Activated, function() MiniMode.hide() end)
connect(miniClose.Activated, function() MiniMode.hide() end)
MiniMode.applyTheme()

-- Keep Mini Mode live even if the main Control Center page is not being
-- rendered.  This intentionally reads the same authoritative System.stats
-- object used by Session Analytics instead of maintaining a second counter.
task.spawn(function()
    while State.alive do
        task.wait(0.10)
        if State.miniMode then
            pcall(function() MiniMode.updateLive() end)
        end
    end
end)

-- Direct synchronization: when Session Analytics redraws its authoritative
-- labels, Mini Mode updates on the same frame instead of waiting for its poll.
task.defer(function()
    if CoreUI and CoreUI.statsLabel then
        connect(CoreUI.statsLabel:GetPropertyChangedSignal("Text"), function()
            if State.miniMode then pcall(function() MiniMode.updateLive() end) end
        end)
    end
    if CoreUI and CoreUI.liveLabel then
        connect(CoreUI.liveLabel:GetPropertyChangedSignal("Text"), function()
            if State.miniMode then pcall(function() MiniMode.updateLive() end) end
        end)
    end
end)

function Theme.copy(source)
    for key, value in pairs(source) do C[key] = value end
end

function Theme.restyleText()
    local bh = System.theme == "Blackhole"
    local emp = System.theme == "Empyrean"
    for _, obj in ipairs(panel:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            if obj.Name == "Desc" or obj.Name == "Sub" or obj.Name == "Modules" or obj.Name == "Hint"
                or obj.Name == "Status" or obj.Name == "Percent" or obj.Name == "ScanStatus"
                or obj.Name == "RejoinStatus" then
                obj.TextColor3 = C.faint
            elseif obj.Name == "Value" then
                obj.TextColor3 = emp and C.violet2 or C.cyan
            elseif obj.Name ~= "Status" then
                obj.TextColor3 = C.ink
            end
            if (bh or emp) and obj:IsA("TextButton") and obj.Name ~= "Status" then obj.AutoButtonColor = false end
        end
    end
end

function Theme.restyleRows()
    local emp = System.theme == "Empyrean"
    for _, page in pairs(pageMap) do
        for _, child in ipairs(page:GetChildren()) do
            if child.Name:match("^Row_") or child.Name:match("^Slider_") or child.Name == "KeyLoadout"
                or child.Name == "ThemeInfo" or child.Name:match("^Preset_") then
                child.BackgroundColor3 = C.panel2
                child.BackgroundTransparency = emp and .12 or 0
                local st = child:FindFirstChildOfClass("UIStroke")
                if st then st.Color = C.line end
            elseif emp and child.Name == "PaneHead" then
                for _, desc in ipairs(child:GetDescendants()) do
                    if desc:IsA("Frame") then desc.BackgroundColor3=C.violet2 end
                    if desc:IsA("UIStroke") then desc.Color=C.violet2 end
                end
            end
        end
    end
    for _, view in ipairs(toggleViews) do
        view.track.BackgroundColor3 = view.getter() and C.toggleOn or C.toggleOff
        view.knob.BackgroundColor3 = view.getter() and (emp and C.bright or C.cyan) or C.faint
        local st = view.track:FindFirstChildOfClass("UIStroke")
        if st then st.Color = C.line end
    end
    for _, view in ipairs(sliders) do
        view.fill.BackgroundColor3 = C.violet2
        view.knob.BackgroundColor3 = emp and C.bright or C.cyan
        local rail = view.hit:FindFirstChild("Rail")
        if rail then rail.BackgroundColor3 = C.toggleOff end
    end
end

function Theme.restyleEmpyreanThemePage()
    if System.theme ~= "Empyrean" then return end
    local cream = Color3.fromRGB(255,248,232)
    local creamBright = Color3.fromRGB(255,253,247)
    local gold = Color3.fromRGB(217,169,78)
    local goldLight = Color3.fromRGB(255,243,200)
    local ink = Color3.fromRGB(58,47,26)
    local faint = Color3.fromRGB(171,157,120)
    if ThemeUI.themeInfo then
        ThemeUI.themeInfo.BackgroundColor3 = cream
        ThemeUI.themeInfo.BackgroundTransparency = 0.06
        local st = ThemeUI.themeInfo:FindFirstChildOfClass("UIStroke")
        if st then st.Color = gold; st.Transparency = .42 end
    end
    local rows = {{ThemeUI.defaultRow,ThemeUI.defaultButton},{ThemeUI.blackholeRow,ThemeUI.blackholeButton},{ThemeUI.empyreanRow,ThemeUI.empyreanButton}}
    for _, pair in ipairs(rows) do
        local row, button = pair[1], pair[2]
        if row then
            row.BackgroundColor3 = creamBright
            row.BackgroundTransparency = 0.02
            local st = row:FindFirstChildOfClass("UIStroke")
            if st then st.Color = gold; st.Transparency = .48 end
            local icon = row:FindFirstChild("Icon")
            if icon then
                icon.BackgroundColor3 = goldLight
                icon.BackgroundTransparency = .08
                local ist = icon:FindFirstChildOfClass("UIStroke")
                if ist then ist.Color = gold; ist.Transparency = .28 end
                for _, d in ipairs(icon:GetDescendants()) do
                    if d:IsA("Frame") then d.BackgroundColor3 = gold elseif d:IsA("UIStroke") then d.Color = gold end
                end
            end
            local title = row:FindFirstChild("Title"); if title then title.TextColor3 = ink end
            local desc = row:FindFirstChild("Desc"); if desc then desc.TextColor3 = faint end
            if button then
                local active = (row == ThemeUI.empyreanRow)
                button.BackgroundColor3 = active and gold or cream
                button.BackgroundTransparency = active and 0 or .02
                button.TextColor3 = active and ink or faint
                local bst = button:FindFirstChildOfClass("UIStroke")
                if bst then bst.Color = gold; bst.Transparency = .42 end
                button.AutoButtonColor = false
            end
        end
    end
    if ThemeUI.hint then ThemeUI.hint.TextColor3 = faint end
end

function Theme.syncAllThemeVisuals()
    -- One authoritative visual pass.  This deliberately runs after Theme.apply,
    -- resize, and render so an older theme cannot leave child controls behind.
    local theme = System.theme
    local bh = theme == "Blackhole"
    local emp = theme == "Empyrean"
    local frost = theme == "Frost"

    -- Frost has its own complete presentation pass. Returning here is important:
    -- the legacy Nexus/Blackhole renderer below intentionally owns a different
    -- horizontal layout and would repaint Frost during drag/resize/render cycles.
    if frost then
        pcall(function() Theme.applyFrostFinal() end)
        return
    end

    -- Theme identity must be authoritative too: header title/subtitle and
    -- every page-heading symbol are rebuilt from the ACTIVE theme instead of
    -- retaining the colors they had when the UI was first constructed.
    local accent = emp and Color3.fromRGB(156,116,32) or C.violet2
    local accentBright = emp and Color3.fromRGB(217,169,78) or C.violet2
    local symbolMuted = emp and Color3.fromRGB(122,108,74) or C.faint

    if brandTitle then
        brandTitle.Text = emp and "EMPYREAN" or (bh and "BLACKHOLE V1" or "VOID NEXUS")
        brandTitle.TextColor3 = emp and Color3.fromRGB(58,47,26) or C.ink
    end
    local headerSub = header and header:FindFirstChild("Sub")
    if headerSub and headerSub:IsA("TextLabel") then
        headerSub.Text = emp and "GRACE ATTAINED" or (bh and "REACTOR ONLINE" or "CORE LINK STABLE")
        headerSub.TextColor3 = emp and Color3.fromRGB(122,108,74) or C.faint
    end

    -- Header emblem: reset every child so the old Blackhole cyan/purple
    -- strokes cannot survive a theme switch.
    if brandmark then
        brandmark.BackgroundColor3 = emp and Color3.fromRGB(255,243,200) or C.panel2
        local bs = brandmark:FindFirstChildOfClass("UIStroke")
        if bs then bs.Color = accentBright; bs.Transparency = emp and .22 or .12 end
        if markCore then markCore.BackgroundColor3 = accentBright end
        if markH then markH.BackgroundColor3 = accent end
        if markV then markV.BackgroundColor3 = accent end
    end

    -- Every page heading uses the active theme's symbol color. pageHead()
    -- creates these icons once, so palette-only restyling otherwise leaves
    -- their original Blackhole purple behind forever.
    for _, page in pairs(pageMap) do
        local head = page:FindFirstChild("PaneHead")
        if head then
            local title = head:FindFirstChild("Title")
            local modules = head:FindFirstChild("Modules")
            if title and title:IsA("TextLabel") then title.TextColor3 = emp and Color3.fromRGB(58,47,26) or C.ink end
            if modules and modules:IsA("TextLabel") then modules.TextColor3 = emp and Color3.fromRGB(122,108,74) or C.faint end
            local icon = head:FindFirstChild("Icon")
            if icon then
                for _, d in ipairs(icon:GetDescendants()) do
                    if d:IsA("UIStroke") then d.Color = accentBright
                    elseif d:IsA("Frame") then d.BackgroundColor3 = accentBright end
                end
            end
        end
    end

    -- Navigation container + every navigation button.
    if tabs then
        if emp then
            tabs.BackgroundColor3 = Color3.fromRGB(255,250,235)
            tabs.BackgroundTransparency = 0.42
        elseif bh then
            tabs.BackgroundColor3 = C.black
            tabs.BackgroundTransparency = 0.28
        else
            tabs.BackgroundColor3 = C.black
            tabs.BackgroundTransparency = 0.35
        end
        local navStroke = tabs:FindFirstChildOfClass("UIStroke")
        if navStroke then navStroke.Color = C.line end
    end

    for key, tab in pairs(navButtons) do
        local selected = State.tab == key
        if emp then
            tab.BackgroundColor3 = selected and Color3.fromRGB(255,224,150) or Color3.fromRGB(255,255,255)
            tab.BackgroundTransparency = selected and 0.10 or 0.34
            tab.TextColor3 = selected and Color3.fromRGB(90,63,16) or C.faint
        elseif bh then
            tab.BackgroundColor3 = selected and Color3.fromRGB(30,14,48) or C.panel2
            tab.BackgroundTransparency = 0
            tab.TextColor3 = selected and C.ink or C.faint
        else
            tab.BackgroundColor3 = selected and Color3.fromRGB(30,14,48) or Color3.fromRGB(8,4,16)
            tab.BackgroundTransparency = 0
            tab.TextColor3 = selected and C.ink or C.faint
        end
        local st = UI.navStrokes[key]
        if st then st.Color = C.line; st.Transparency = selected and 0.42 or 0.88 end
        local bar = UI.navBars[key]
        if bar then
            bar.Visible = selected
            bar.BackgroundColor3 = accentBright
        end
        local icon = tab:FindFirstChild("Icon")
        if icon then
            for _, d in ipairs(icon:GetDescendants()) do
                if d:IsA("UIStroke") then
                    d.Color = selected and accentBright or symbolMuted
                elseif d:IsA("Frame") then
                    d.BackgroundColor3 = selected and accentBright or symbolMuted
                end
            end
        end
    end

    -- The content container must never retain EMPYREAN's gradient when leaving it.
    local contentGradient = content and content:FindFirstChild("EmpyreanSurfaceGradient")
    if not emp and contentGradient then contentGradient:Destroy() end
    if content then
        if emp then
            content.BackgroundColor3 = C.panel
            content.BackgroundTransparency = 0
        else
            content.BackgroundTransparency = 1
        end
    end

    -- Every page is transparent over the current theme's content surface.
    for _, page in pairs(pageMap) do
        page.BackgroundTransparency = 1
        page.ScrollBarImageColor3 = C.violet2
        page.ScrollBarImageTransparency = emp and 0.55 or 0.35
    end

    -- All reusable rows/controls are reset from the CURRENT theme, including
    -- nested children.  This is the part the old palette-only restyler missed.
    for _, page in pairs(pageMap) do
        for _, child in ipairs(page:GetChildren()) do
            local isRow = child.Name:match("^Row_") or child.Name:match("^Slider_") or child.Name == "KeyLoadout"
            if isRow then
                child.BackgroundColor3 = C.panel2
                child.BackgroundTransparency = emp and 0.08 or 0
                local rowStroke = child:FindFirstChildOfClass("UIStroke")
                if rowStroke then rowStroke.Color = C.line; rowStroke.Transparency = emp and 0.42 or 0.72 end
                for _, d in ipairs(child:GetDescendants()) do
                    if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                        if d.Name == "Desc" or d.Name == "Hint" then
                            d.TextColor3 = C.faint
                        elseif d.Name == "Value" then
                            d.TextColor3 = emp and C.violet2 or C.cyan
                        else
                            d.TextColor3 = C.ink
                        end
                    elseif d:IsA("UIStroke") then
                        d.Color = C.line
                    end
                end
            end
        end
    end

    -- Toggle/slider instances are shared across all tabs.
    for _, view in ipairs(toggleViews) do
        local value = view.getter()
        view.track.BackgroundColor3 = value and C.toggleOn or C.toggleOff
        view.track.BackgroundTransparency = emp and 0.10 or 0
        view.knob.BackgroundColor3 = value and (emp and C.bright or C.cyan) or C.faint
        local st = view.track:FindFirstChildOfClass("UIStroke")
        if st then st.Color = C.line end
    end
    for _, view in ipairs(sliders) do
        view.fill.BackgroundColor3 = C.violet2
        view.knob.BackgroundColor3 = emp and C.bright or C.cyan
        local knobStroke = view.knob:FindFirstChildOfClass("UIStroke")
        if knobStroke then knobStroke.Color = C.line end
        local rail = view.hit:FindFirstChild("Rail")
        if rail then rail.BackgroundColor3 = emp and C.toggleOff or C.line end
    end

    -- Theme page is explicitly restored for ALL themes.  Previously only the
    -- EMPYREAN branch touched it, so switching away left cream controls behind.
    if ThemeUI.themeInfo then
        ThemeUI.themeInfo.BackgroundColor3 = C.panel2
        ThemeUI.themeInfo.BackgroundTransparency = emp and 0.06 or 0
        local st = ThemeUI.themeInfo:FindFirstChildOfClass("UIStroke")
        if st then st.Color = C.line; st.Transparency = emp and 0.42 or 0.72 end
    end
    local themeRows = {
        {ThemeUI.defaultRow, ThemeUI.defaultButton},
        {ThemeUI.blackholeRow, ThemeUI.blackholeButton},
        {ThemeUI.empyreanRow, ThemeUI.empyreanButton},
    }
    for _, pair in ipairs(themeRows) do
        local row, button = pair[1], pair[2]
        if row then
            row.BackgroundColor3 = C.panel2
            row.BackgroundTransparency = emp and 0.02 or 0
            local st = row:FindFirstChildOfClass("UIStroke")
            if st then st.Color = C.line; st.Transparency = emp and 0.48 or 0.72 end
            local icon = row:FindFirstChild("Icon")
            if icon then
                icon.BackgroundColor3 = emp and C.bright or C.black
                icon.BackgroundTransparency = emp and 0.08 or 0.18
            end
            local title = row:FindFirstChild("Title")
            local desc = row:FindFirstChild("Desc")
            if title then title.TextColor3 = C.ink end
            if desc then desc.TextColor3 = C.faint end
        end
        if button then
            local active = (row == ThemeUI.empyreanRow and emp) or (row == ThemeUI.blackholeRow and bh) or (row == ThemeUI.defaultRow and not bh and not emp)
            button.BackgroundColor3 = active and C.violet2 or C.panel2
            button.BackgroundTransparency = 0
            button.TextColor3 = active and C.ink or C.faint
            local st = button:FindFirstChildOfClass("UIStroke")
            if st then st.Color = C.line; st.Transparency = 0.58 end
            button.AutoButtonColor = false
        end
    end
    if ThemeUI.activeLabel then
        ThemeUI.activeLabel.Text = bh and "BLACKHOLE V1" or (emp and "EMPYREAN" or "DEFAULT")
        ThemeUI.activeLabel.TextColor3 = C.ink
    end
    if ThemeUI.hint then ThemeUI.hint.TextColor3 = C.faint end

    -- Header and resize grip are also reset here, so leaving EMPYREAN cannot
    -- retain its light treatment.
    if emp then
        header.BackgroundColor3 = C.panel
        header.BackgroundTransparency = 0.04
        headerLine.BackgroundColor3 = C.line
        brandTitle.TextColor3 = C.text
    elseif bh then
        header.BackgroundColor3 = C.panel
        header.BackgroundTransparency = 0.08
        headerLine.BackgroundColor3 = C.line
        brandTitle.TextColor3 = C.ink
    else
        header.BackgroundColor3 = C.panel
        header.BackgroundTransparency = 0.08
        headerLine.BackgroundColor3 = C.violet
        brandTitle.TextColor3 = C.ink
    end
    if resizeGrip then
        for i = 1,3 do
            local line = resizeGrip:FindFirstChild("Line"..i)
            if line then line.BackgroundColor3 = emp and C.violet2 or C.violet2 end
        end
    end
    Theme.canonicalizeControls()
end

function Theme.syncEmpyreanControls()
    local emp = System.theme == "Empyrean"
    local bh = System.theme == "Blackhole"
    if not emp then return end
    local gold=Color3.fromRGB(217,169,78)
    local goldLight=Color3.fromRGB(255,243,200)
    local goldDeep=Color3.fromRGB(156,116,32)
    local cream=Color3.fromRGB(255,253,247)
    local cream2=Color3.fromRGB(255,248,232)
    local ink=Color3.fromRGB(58,47,26)
    local faint=Color3.fromRGB(171,157,120)

    -- Every ordinary page button/textbox is owned by EMPYREAN while this theme
    -- is active. This removes constructor-time Blackhole colors from nested UI.
    for key,page in pairs(pageMap) do
        if key ~= "Theme" then
            for _,obj in ipairs(page:GetDescendants()) do
                if obj:IsA("TextButton") then
                    obj.BackgroundColor3=cream2
                    obj.BackgroundTransparency=.08
                    obj.TextColor3=ink
                    obj.AutoButtonColor=false
                    local st=obj:FindFirstChildOfClass("UIStroke")
                    if st then st.Color=gold; st.Transparency=.42 end
                elseif obj:IsA("TextBox") then
                    obj.BackgroundColor3=cream2
                    obj.BackgroundTransparency=.08
                    obj.TextColor3=ink
                    local st=obj:FindFirstChildOfClass("UIStroke")
                    if st then st.Color=gold; st.Transparency=.42 end
                end
            end
        end
    end

    -- The loadout keys are nested TextButtons and were one of the remaining
    -- Blackhole-colored objects.
    -- Reset every TextButton/TextBox on ordinary pages for non-EMPYREAN
    -- themes as well. This prevents EMPYREAN cream controls from surviving
    -- when returning to Default/Nexus.
    if System.theme ~= "Empyrean" then
        for _, page in pairs(pageMap) do
            for _, obj in ipairs(page:GetDescendants()) do
                if obj:IsA("TextButton") then
                    obj.BackgroundColor3 = bh and Color3.fromRGB(8,8,12) or Color3.fromRGB(8,4,16)
                    obj.BackgroundTransparency = 0
                    obj.TextColor3 = bh and Color3.fromRGB(236,234,245) or Color3.fromRGB(233,226,247)
                    obj.AutoButtonColor = false
                    local st = obj:FindFirstChildOfClass("UIStroke")
                    if st then st.Color = bh and Color3.fromRGB(150,120,230) or Color3.fromRGB(82,55,122) end
                elseif obj:IsA("TextBox") then
                    obj.BackgroundColor3 = bh and Color3.fromRGB(8,8,12) or Color3.fromRGB(8,4,16)
                    obj.BackgroundTransparency = 0
                    obj.TextColor3 = bh and Color3.fromRGB(236,234,245) or Color3.fromRGB(233,226,247)
                    local st = obj:FindFirstChildOfClass("UIStroke")
                    if st then st.Color = bh and Color3.fromRGB(150,120,230) or Color3.fromRGB(82,55,122) end
                end
            end
        end
    end

    local loadout=skillsPage and skillsPage:FindFirstChild("KeyLoadout")
    if loadout then
        for _,obj in ipairs(loadout:GetDescendants()) do
            if obj:IsA("TextButton") then
                obj.BackgroundColor3=cream2
                obj.BackgroundTransparency=.02
                obj.TextColor3=goldDeep
                local st=obj:FindFirstChildOfClass("UIStroke")
                if st then st.Color=gold; st.Transparency=.34 end
            end
        end
    end

    -- Action buttons (SCANNING, map actions, farm actions, etc.) get the same
    -- light/gold treatment instead of inheriting Blackhole purple.
    if UI.staticScanButton then
        UI.staticScanButton.BackgroundColor3=gold
        UI.staticScanButton.TextColor3=ink
        local st=UI.staticScanButton:FindFirstChildOfClass("UIStroke")
        if st then st.Color=goldDeep; st.Transparency=.28 end
    end
    if UI.privateMapBox then
        UI.privateMapBox.BackgroundColor3=cream2
        UI.privateMapBox.TextColor3=ink
    end

    -- Theme page itself is explicitly celestial. The icon artwork may represent
    -- another theme, but its surrounding UI never inherits that theme's colors.
    if ThemeUI then
        for _,row in ipairs({ThemeUI.defaultRow,ThemeUI.blackholeRow,ThemeUI.empyreanRow}) do
            if row then
                row.BackgroundColor3=cream2
                row.BackgroundTransparency=.02
                local st=row:FindFirstChildOfClass("UIStroke")
                if st then st.Color=gold; st.Transparency=.42 end
                for _,d in ipairs(row:GetDescendants()) do
                    if d:IsA("TextLabel") then
                        d.TextColor3=(d.Name=="Desc") and faint or ink
                    elseif d:IsA("TextButton") then
                        local active=(d==ThemeUI.empyreanButton)
                        d.BackgroundColor3=active and gold or cream
                        d.TextColor3=active and ink or faint
                        d.AutoButtonColor=false
                        local ds=d:FindFirstChildOfClass("UIStroke")
                        if ds then ds.Color=gold; ds.Transparency=.42 end
                    end
                end
            end
        end
    end

    -- HTML nav: light glass buttons, gold active state and muted-gold icons.
    for key,tab in pairs(navButtons) do
        local selected=State.tab==key
        tab.BackgroundColor3=selected and goldLight or cream
        tab.BackgroundTransparency=selected and .10 or .30
        tab.TextColor3=selected and ink or faint
        local st=UI.navStrokes[key]
        if st then st.Color=gold; st.Transparency=selected and .42 or .78 end
        local bar=UI.navBars[key]
        if bar then bar.BackgroundColor3=gold; bar.Visible=selected end
        local icon=tab:FindFirstChild("Icon")
        if icon then
            for _,d in ipairs(icon:GetDescendants()) do
                if d:IsA("UIStroke") then d.Color=selected and goldDeep or Color3.fromRGB(122,108,74) end
                if d:IsA("Frame") then d.BackgroundColor3=selected and goldDeep or Color3.fromRGB(122,108,74) end
            end
        end
    end

    for _,page in pairs(pageMap) do
        page.ScrollBarImageColor3=gold
        page.ScrollBarImageTransparency=.42
    end

    -- Keep the animated hero visibly alive.
    if EMP.hero then
        EMP.hero.Visible=true
        EMP.sky.BackgroundColor3=Color3.fromRGB(255,250,240)
        EMP.sky.BackgroundTransparency=0
        EMP.rayGroup.Visible=true; EMP.wingL.Visible=true; EMP.wingR.Visible=true
        EMP.haloA.Visible=true; EMP.haloB.Visible=true; EMP.core.Visible=true
        EMP.dot.Visible=true; EMP.scan.Visible=true
    end
end

-- FINAL CANONICAL CONTROL PASS
--
-- All three themes are now rendered from one authoritative palette here.
-- Earlier restylers are allowed to run for legacy layout work, but this pass
-- is always last for control colors.  This prevents a control constructed in
-- Blackhole/Nexus from carrying its constructor color into EMPYREAN and also
-- prevents EMPYREAN cream controls from surviving a switch back.
function Theme.canonicalizeControls()
    local theme = System.theme
    if theme ~= "Default" and theme ~= "Blackhole" and theme ~= "Empyrean" and theme ~= "Frost" then
        theme = "Default"
    end

    local emp = theme == "Empyrean"
    local bh = theme == "Blackhole"
    local frost = theme == "Frost"
    if frost then
        pcall(function() Theme.applyFrostFinal() end)
        return
    end
    local P = emp and {
        panel = Color3.fromRGB(255,253,247), panel2 = Color3.fromRGB(255,248,232),
        surface = Color3.fromRGB(255,250,235), line = Color3.fromRGB(217,169,78),
        accent = Color3.fromRGB(217,169,78), accentDeep = Color3.fromRGB(156,116,32),
        text = Color3.fromRGB(58,47,26), muted = Color3.fromRGB(171,157,120),
        bright = Color3.fromRGB(255,243,200), off = Color3.fromRGB(226,220,202),
        nav = Color3.fromRGB(255,255,255), selected = Color3.fromRGB(255,224,150),
    } or bh and {
        panel = Color3.fromRGB(8,8,12), panel2 = Color3.fromRGB(4,4,7),
        surface = Color3.fromRGB(8,8,12), line = Color3.fromRGB(150,120,230),
        accent = Color3.fromRGB(122,63,242), accentDeep = Color3.fromRGB(74,37,144),
        text = Color3.fromRGB(236,234,245), muted = Color3.fromRGB(150,146,170),
        bright = Color3.fromRGB(238,241,251), off = Color3.fromRGB(24,24,31),
        nav = Color3.fromRGB(4,4,7), selected = Color3.fromRGB(30,14,48),
    } or {
        panel = C.panel, panel2 = C.panel2, surface = C.surface, line = C.violet,
        accent = C.violet2, accentDeep = C.violet, text = C.ink, muted = C.faint,
        bright = C.bright, off = C.toggleOff, nav = C.deep, selected = C.panel2,
    }

    local function paintStroke(obj, color, transparency)
        local st = obj and obj:FindFirstChildOfClass("UIStroke")
        if st then st.Color=color; st.Transparency=transparency or 0.5 end
    end
    local function paintText(obj, color)
        if obj and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
            obj.TextColor3=color
        end
    end

    -- Every normal content row.
    for _,page in pairs(pageMap) do
        if page then
            for _,child in ipairs(page:GetChildren()) do
                local row = child.Name:match("^Row_") or child.Name:match("^Slider_") or child.Name == "KeyLoadout"
                if row and child:IsA("GuiObject") then
                    child.BackgroundColor3=P.panel2
                    child.BackgroundTransparency=emp and 0.08 or 0
                    paintStroke(child,P.line,emp and 0.42 or 0.72)
                    for _,d in ipairs(child:GetDescendants()) do
                        if d:IsA("TextButton") or d:IsA("TextBox") then
                            d.AutoButtonColor=false
                            d.BackgroundColor3=P.panel
                            d.BackgroundTransparency=emp and 0.05 or 0
                            d.TextColor3=P.text
                            paintStroke(d,P.line,emp and 0.42 or 0.72)
                        elseif d:IsA("TextLabel") then
                            if d.Name=="Desc" or d.Name=="Hint" or d.Name=="Modules" then
                                d.TextColor3=P.muted
                            elseif d.Name=="Value" then
                                d.TextColor3=P.accent
                            else
                                d.TextColor3=P.text
                            end
                        end
                    end
                end
            end

            -- Catch ALL nested action/key buttons, including the ones that do
            -- not live directly under Row_/Slider_ containers.
            for _,obj in ipairs(page:GetDescendants()) do
                if obj:IsA("TextButton") then
                    obj.AutoButtonColor=false
                    -- Theme-page buttons are handled separately below.
                    if not ThemeUI or (obj ~= ThemeUI.defaultButton and obj ~= ThemeUI.blackholeButton and obj ~= ThemeUI.empyreanButton) then
                        obj.BackgroundColor3=P.panel
                        obj.BackgroundTransparency=emp and 0.05 or 0
                        obj.TextColor3=P.text
                        paintStroke(obj,P.line,emp and 0.42 or 0.72)
                    end
                elseif obj:IsA("TextBox") then
                    obj.BackgroundColor3=P.panel
                    obj.BackgroundTransparency=emp and 0.05 or 0
                    obj.TextColor3=P.text
                    paintStroke(obj,P.line,emp and 0.42 or 0.72)
                end
            end
        end
    end

    -- Shared toggles: one palette, no previous-theme colors.
    for _,view in ipairs(toggleViews) do
        local value=false
        local ok,v=pcall(view.getter)
        if ok then value=v end
        view.track.BackgroundColor3=value and P.accent or P.off
        view.track.BackgroundTransparency=emp and 0.10 or 0
        view.knob.BackgroundColor3=value and P.bright or P.muted
        paintStroke(view.track,P.line,emp and 0.35 or 0.65)
    end

    -- Shared sliders: rail, fill, knob, value all come from the same palette.
    for _,view in ipairs(sliders) do
        view.fill.BackgroundColor3=P.accent
        view.knob.BackgroundColor3=P.bright
        view.valueLabel.TextColor3=P.accentDeep
        local rail=view.hit and view.hit:FindFirstChild("Rail")
        if rail then rail.BackgroundColor3=P.off end
        paintStroke(view.knob,P.line,emp and 0.25 or 0.55)
    end

    -- Navigation is completely independent from the page controls.
    if tabs then
        tabs.BackgroundColor3=emp and Color3.fromRGB(255,250,235) or P.surface
        tabs.BackgroundTransparency=emp and 0.42 or (bh and 0.28 or 0.35)
        paintStroke(tabs,P.line,0.72)
    end
    for key,tab in pairs(navButtons) do
        local selected=State.tab==key
        tab.BackgroundColor3=selected and P.selected or P.nav
        tab.BackgroundTransparency=emp and (selected and 0.10 or 0.34) or 0
        tab.TextColor3=selected and P.text or P.muted
        local st=UI.navStrokes[key]
        if st then st.Color=P.line; st.Transparency=selected and 0.42 or 0.82 end
        local bar=UI.navBars[key]
        if bar then bar.BackgroundColor3=P.accent; bar.Visible=selected end
        local icon=tab:FindFirstChild("Icon")
        if icon then
            for _,d in ipairs(icon:GetDescendants()) do
                if d:IsA("UIStroke") then d.Color=selected and P.accentDeep or P.muted end
                if d:IsA("Frame") then d.BackgroundColor3=selected and P.accentDeep or P.muted end
            end
        end
    end

    -- Theme selector is also canonicalized, but each row represents a theme;
    -- only the ACTIVE selection receives the active accent.
    if ThemeUI then
        if ThemeUI.themeInfo then
            ThemeUI.themeInfo.BackgroundColor3=P.panel2
            ThemeUI.themeInfo.BackgroundTransparency=emp and 0.06 or 0
            paintStroke(ThemeUI.themeInfo,P.line,emp and 0.42 or 0.72)
        end
        local entries={
            {ThemeUI.defaultRow,ThemeUI.defaultButton,"Default"},
            {ThemeUI.blackholeRow,ThemeUI.blackholeButton,"Blackhole"},
            {ThemeUI.empyreanRow,ThemeUI.empyreanButton,"Empyrean"},
            {ThemeUI.frostRow,ThemeUI.frostButton,"Frost"},
        }
        for _,entry in ipairs(entries) do
            local row,button,name=entry[1],entry[2],entry[3]
            if row then
                row.BackgroundColor3=P.panel2
                row.BackgroundTransparency=emp and 0.02 or 0
                paintStroke(row,P.line,emp and 0.42 or 0.72)
                local title=row:FindFirstChild("Title"); local desc=row:FindFirstChild("Desc")
                if title then title.TextColor3=P.text end
                if desc then desc.TextColor3=P.muted end
            end
            if button then
                local active=name==theme
                button.AutoButtonColor=false
                button.BackgroundColor3=active and P.accent or P.panel
                button.BackgroundTransparency=0
                button.TextColor3=active and (emp and P.text or P.bright) or P.muted
                paintStroke(button,P.line,active and 0.35 or 0.65)
            end
        end
        if ThemeUI.activeLabel then
            ThemeUI.activeLabel.Text=bh and "BLACKHOLE V1" or (emp and "EMPYREAN" or (System.theme=="Frost" and "FROSTBOUND" or "DEFAULT"))
            ThemeUI.activeLabel.TextColor3=P.text
        end
        if ThemeUI.hint then ThemeUI.hint.TextColor3=P.muted end
    end

    -- System/Farm action buttons are explicitly included; these were among the
    -- controls visible in the user's screenshots.
    if UI.staticScanButton then
        UI.staticScanButton.BackgroundColor3=emp and P.panel2 or P.accent
        UI.staticScanButton.TextColor3=emp and P.text or P.bright
        paintStroke(UI.staticScanButton,P.line,0.45)
    end
    if UI.privateMapBox then
        UI.privateMapBox.BackgroundColor3=P.panel2
        UI.privateMapBox.TextColor3=P.text
        paintStroke(UI.privateMapBox,P.line,0.55)
    end

    -- Control Center owns two non-row container cards.  The generic control
    -- pass above correctly handles their buttons, but these parent frames need
    -- their own theme pass so a page created while Blackhole is active cannot
    -- leave a dark panel behind after switching to EMPYREAN (or vice versa).
    if CoreUI and CoreUI.page then
        local cards = {CoreUI.profileBox, CoreUI.profileBox and CoreUI.profileBox.Parent and CoreUI.profileBox.Parent:FindFirstChild("Analytics")}
        for _,card in ipairs(cards) do
            if card and card:IsA("GuiObject") then
                card.BackgroundColor3=P.panel2
                card.BackgroundTransparency=emp and 0.06 or 0
                paintStroke(card,P.line,emp and 0.42 or 0.72)
                for _,d in ipairs(card:GetDescendants()) do
                    if d:IsA("TextLabel") then
                        d.TextColor3=(d.Name=="Active" or d.Name=="Target") and P.muted or P.text
                    elseif d:IsA("TextButton") then
                        d.AutoButtonColor=false
                        d.BackgroundColor3=P.panel
                        d.BackgroundTransparency=emp and 0.05 or 0
                        d.TextColor3=P.text
                        paintStroke(d,P.line,emp and 0.42 or 0.72)
                    elseif d:IsA("TextBox") then
                        d.BackgroundColor3=P.panel
                        d.BackgroundTransparency=emp and 0.05 or 0
                        d.TextColor3=P.text
                        d.PlaceholderColor3=P.muted
                        paintStroke(d,P.line,emp and 0.42 or 0.72)
                    end
                end
            end
        end
        if CoreUI.safetyLabel then CoreUI.safetyLabel.TextColor3=emp and Color3.fromRGB(42,150,82) or C.green end
        if CoreUI.statsLabel then CoreUI.statsLabel.TextColor3=P.muted end
        if CoreUI.profileName then CoreUI.profileName.TextColor3=P.muted end
    end

    -- Page symbols and header identity.
    local brandAccent=P.accentDeep
    if brandTitle then
        brandTitle.Text=emp and "EMPYREAN" or (bh and "BLACKHOLE V1" or (frost and "FROSTBOUND" or "VOID NEXUS"))
        brandTitle.TextColor3=P.text
    end
    local sub=header and header:FindFirstChild("Sub")
    if sub then
        sub.Text=emp and "GRACE ATTAINED" or (bh and "REACTOR ONLINE" or "CORE LINK STABLE")
        sub.TextColor3=P.muted
    end
    if brandmark then
        brandmark.BackgroundColor3=P.panel2
        paintStroke(brandmark,P.line,0.25)
        if markCore then markCore.BackgroundColor3=P.accent end
        if markH then markH.BackgroundColor3=brandAccent end
        if markV then markV.BackgroundColor3=brandAccent end
    end
    for _,page in pairs(pageMap) do
        local head=page:FindFirstChild("PaneHead")
        if head then
            local title=head:FindFirstChild("Title"); local modules=head:FindFirstChild("Modules"); local icon=head:FindFirstChild("Icon")
            if title then title.TextColor3=P.text end
            if modules then modules.TextColor3=P.muted end
            if icon then
                for _,d in ipairs(icon:GetDescendants()) do
                    if d:IsA("UIStroke") then d.Color=brandAccent end
                    if d:IsA("Frame") then d.BackgroundColor3=brandAccent end
                end
            end
        end
    end
end

function Theme.stopSpecialVisuals()
    -- Only the actual celestial animation connection belongs to the active
    -- theme. The watchdog is intentionally NEVER disconnected here: it is a
    -- lifetime UI service which sleeps for Nexus/Blackhole and wakes EMPYREAN
    -- back up when the user returns to it.
    if EMP and EMP.connection then
        pcall(function() EMP.connection:Disconnect() end)
        EMP.connection=nil
    end
    if EMP and EMP.hero then EMP.hero.Visible=false end
    if BH and BH.hero then BH.hero.Visible=false end
end

-- Hard reset pass for the reusable controls.  Several controls are constructed
-- before the theme is known, so changing only C.* leaves their original colors
-- behind.  This pass deliberately assigns every visible control from the active
-- theme on every theme transition/startup.
function Theme.hardResetControls()
    local theme = System.theme
    local bh = theme == "Blackhole"
    local emp = theme == "Empyrean"

    local darkPanel = bh and Color3.fromRGB(4,4,7) or Color3.fromRGB(20,10,36)
    local darkPanelAlt = bh and Color3.fromRGB(8,8,12) or Color3.fromRGB(30,14,48)
    local darkLine = bh and Color3.fromRGB(150,120,230) or Color3.fromRGB(82,55,122)
    local darkText = bh and Color3.fromRGB(236,234,245) or Color3.fromRGB(233,226,247)
    local darkMuted = bh and Color3.fromRGB(150,146,170) or Color3.fromRGB(155,143,184)
    local darkFaint = bh and Color3.fromRGB(85,80,105) or Color3.fromRGB(92,82,122)
    local darkAccent = bh and Color3.fromRGB(122,63,242) or Color3.fromRGB(168,85,247)
    local darkBright = bh and Color3.fromRGB(238,241,251) or Color3.fromRGB(143,227,255)

    for _, page in pairs(pageMap) do
        for _, child in ipairs(page:GetChildren()) do
            if child.Name:match("^Row_") or child.Name:match("^Slider_") or child.Name == "KeyLoadout" then
                child.BackgroundColor3 = emp and C.panel2 or darkPanelAlt
                child.BackgroundTransparency = emp and .08 or 0
                local st=child:FindFirstChildOfClass("UIStroke")
                if st then st.Color=emp and C.line or darkLine; st.Transparency=emp and .42 or .72 end
            end
        end
    end

    for _, view in ipairs(toggleViews) do
        local value=view.getter()
        view.track.BackgroundColor3 = value and (emp and C.toggleOn or (bh and Color3.fromRGB(70,38,125) or Color3.fromRGB(88,48,124))) or (emp and C.toggleOff or (bh and Color3.fromRGB(24,24,31) or Color3.fromRGB(32,24,43)))
        view.track.BackgroundTransparency = emp and .10 or 0
        view.knob.BackgroundColor3 = value and (emp and C.bright or darkBright) or (emp and C.faint or darkFaint)
        local st=view.track:FindFirstChildOfClass("UIStroke")
        if st then st.Color=emp and C.line or darkLine end
    end

    for _, view in ipairs(sliders) do
        view.fill.BackgroundColor3 = emp and C.violet2 or darkAccent
        view.knob.BackgroundColor3 = emp and C.bright or darkBright
        view.valueLabel.TextColor3 = emp and C.violet2 or darkBright
        local rail=view.hit:FindFirstChild("Rail")
        if rail then rail.BackgroundColor3 = emp and C.toggleOff or (bh and Color3.fromRGB(24,24,31) or Color3.fromRGB(47,32,65)) end
        local ks=view.knob:FindFirstChildOfClass("UIStroke")
        if ks then ks.Color=emp and C.line or darkLine end
    end

    local loadout=skillsPage and skillsPage:FindFirstChild("KeyLoadout")
    if loadout then
        loadout.BackgroundColor3=emp and C.panel2 or darkPanelAlt
        for _,obj in ipairs(loadout:GetDescendants()) do
            if obj:IsA("TextButton") then
                obj.BackgroundColor3=emp and C.panel2 or darkPanel
                obj.TextColor3=emp and Color3.fromRGB(156,116,32) or darkText
                local st=obj:FindFirstChildOfClass("UIStroke")
                if st then st.Color=emp and C.line or darkLine end
            end
        end
    end

    if UI.staticScanButton then
        UI.staticScanButton.BackgroundColor3=emp and C.panel2 or darkPanelAlt
        UI.staticScanButton.TextColor3=emp and Color3.fromRGB(58,47,26) or darkBright
        local st=UI.staticScanButton:FindFirstChildOfClass("UIStroke")
        if st then st.Color=emp and C.line or darkAccent end
    end

    if UI.privateMapBox then
        UI.privateMapBox.BackgroundColor3=emp and C.panel2 or darkPanel
        UI.privateMapBox.TextColor3=emp and Color3.fromRGB(58,47,26) or darkText
        local st=UI.privateMapBox:FindFirstChildOfClass("UIStroke")
        if st then st.Color=emp and C.line or darkLine end
    end

    if ThemeUI then
        ThemeUI.themeInfo.BackgroundColor3=emp and C.panel2 or darkPanel
        ThemeUI.themeInfo.BackgroundTransparency=emp and .06 or 0
        for _,pair in ipairs({
            {ThemeUI.defaultRow,ThemeUI.defaultButton},
            {ThemeUI.blackholeRow,ThemeUI.blackholeButton},
            {ThemeUI.empyreanRow,ThemeUI.empyreanButton},
        }) do
            local row,button=pair[1],pair[2]
            if row then
                row.BackgroundColor3=emp and C.panel2 or darkPanel
                local st=row:FindFirstChildOfClass("UIStroke")
                if st then st.Color=emp and C.line or darkLine end
            end
            if button then
                local active=(row==ThemeUI.empyreanRow and emp) or (row==ThemeUI.blackholeRow and bh) or (row==ThemeUI.defaultRow and not bh and not emp)
                button.BackgroundColor3=active and (emp and C.violet2 or darkAccent) or (emp and C.panel2 or darkPanel)
                button.TextColor3=active and (emp and Color3.fromRGB(58,47,26) or darkText) or (emp and C.faint or darkFaint)
                local st=button:FindFirstChildOfClass("UIStroke")
                if st then st.Color=emp and C.line or darkLine end
            end
        end
    end

    -- Page symbols, including the symbols that used to remain purple after a
    -- theme switch.
    local iconColor=emp and Color3.fromRGB(156,116,32) or darkAccent
    local iconMuted=emp and Color3.fromRGB(122,108,74) or darkMuted
    for _,page in pairs(pageMap) do
        local head=page:FindFirstChild("PaneHead")
        local icon=head and head:FindFirstChild("Icon")
        if icon then
            for _,d in ipairs(icon:GetDescendants()) do
                if d:IsA("UIStroke") then d.Color=iconColor elseif d:IsA("Frame") then d.BackgroundColor3=iconColor end
            end
        end
    end
end

-- Defensive final theme pass. This pass is intentionally independent from the
-- older restylers so one optional/missing object cannot abort visual application.
function Theme.forceThemeControls()
    local theme = System.theme
    local emp = theme == "Empyrean"
    local bh = theme == "Blackhole"
    local frost = theme == "Frost"
    if frost then
        pcall(function() Theme.applyFrostFinal() end)
        return
    end
    local gold = Color3.fromRGB(217,169,78)
    local goldDeep = Color3.fromRGB(156,116,32)
    local cream = Color3.fromRGB(255,253,247)
    local cream2 = Color3.fromRGB(255,248,232)
    local ink = Color3.fromRGB(58,47,26)
    local faint = Color3.fromRGB(171,157,120)
    local dark = bh and Color3.fromRGB(8,8,12) or Color3.fromRGB(8,4,16)
    local dark2 = bh and Color3.fromRGB(4,4,7) or Color3.fromRGB(20,10,36)
    local darkAccent = bh and Color3.fromRGB(122,63,242) or Color3.fromRGB(168,85,247)
    local darkText = bh and Color3.fromRGB(236,234,245) or Color3.fromRGB(233,226,247)
    local darkMuted = bh and Color3.fromRGB(150,146,170) or Color3.fromRGB(155,143,184)
    local line = emp and gold or (bh and Color3.fromRGB(150,120,230) or Color3.fromRGB(82,55,122))

    pcall(function()
        for key, tab in pairs(navButtons) do
            local selected = State.tab == key
            tab.BackgroundColor3 = emp and (selected and Color3.fromRGB(255,224,150) or cream) or (selected and dark2 or dark)
            tab.BackgroundTransparency = emp and (selected and .10 or .30) or 0
            tab.TextColor3 = emp and (selected and ink or faint) or (selected and darkText or darkMuted)
            local st = UI.navStrokes[key]; if st then st.Color=line; st.Transparency=selected and .42 or .82 end
            local bar = UI.navBars[key]; if bar then bar.Visible=selected; bar.BackgroundColor3=emp and gold or darkAccent end
            local icon=tab:FindFirstChild("Icon")
            if icon then for _,d in ipairs(icon:GetDescendants()) do
                if d:IsA("UIStroke") then d.Color=emp and (selected and goldDeep or Color3.fromRGB(122,108,74)) or (selected and darkAccent or darkMuted)
                elseif d:IsA("Frame") then d.BackgroundColor3=emp and (selected and goldDeep or Color3.fromRGB(122,108,74)) or (selected and darkAccent or darkMuted) end
            end end
        end
    end)

    pcall(function()
        for _, view in ipairs(toggleViews) do
            local value=view.getter()
            view.track.BackgroundColor3 = emp and (value and gold or Color3.fromRGB(226,220,202)) or (value and (bh and Color3.fromRGB(70,38,125) or Color3.fromRGB(88,48,124)) or (bh and Color3.fromRGB(24,24,31) or Color3.fromRGB(32,24,43)))
            view.track.BackgroundTransparency=emp and .10 or 0
            view.knob.BackgroundColor3=emp and (value and Color3.fromRGB(255,243,200) or faint) or (value and (bh and Color3.fromRGB(238,241,251) or Color3.fromRGB(143,227,255)) or (bh and Color3.fromRGB(85,80,105) or Color3.fromRGB(92,82,122)))
            local st=view.track:FindFirstChildOfClass("UIStroke"); if st then st.Color=line end
        end
    end)

    pcall(function()
        for _, view in ipairs(sliders) do
            view.fill.BackgroundColor3=emp and gold or darkAccent
            view.knob.BackgroundColor3=emp and Color3.fromRGB(255,243,200) or (bh and Color3.fromRGB(238,241,251) or Color3.fromRGB(143,227,255))
            view.valueLabel.TextColor3=emp and goldDeep or (bh and Color3.fromRGB(238,241,251) or Color3.fromRGB(143,227,255))
            local rail=view.hit:FindFirstChild("Rail"); if rail then rail.BackgroundColor3=emp and Color3.fromRGB(226,220,202) or (bh and Color3.fromRGB(24,24,31) or Color3.fromRGB(47,32,65)) end
            local st=view.knob:FindFirstChildOfClass("UIStroke"); if st then st.Color=line end
        end
    end)

    pcall(function()
        for _,page in pairs(pageMap) do
            for _,obj in ipairs(page:GetDescendants()) do
                if obj:IsA("TextButton") then
                    obj.AutoButtonColor=false
                    obj.BackgroundColor3=emp and cream2 or dark
                    obj.BackgroundTransparency=emp and .08 or 0
                    obj.TextColor3=emp and ink or darkText
                    local st=obj:FindFirstChildOfClass("UIStroke"); if st then st.Color=line end
                elseif obj:IsA("TextBox") then
                    obj.BackgroundColor3=emp and cream2 or dark
                    obj.BackgroundTransparency=emp and .08 or 0
                    obj.TextColor3=emp and ink or darkText
                    local st=obj:FindFirstChildOfClass("UIStroke"); if st then st.Color=line end
                end
            end
            local head=page:FindFirstChild("PaneHead"); local icon=head and head:FindFirstChild("Icon")
            if icon then for _,d in ipairs(icon:GetDescendants()) do
                if d:IsA("UIStroke") then d.Color=emp and goldDeep or darkAccent
                elseif d:IsA("Frame") then d.BackgroundColor3=emp and goldDeep or darkAccent end
            end end
        end
    end)

    pcall(function()
        if ThemeUI then
            local rows={ThemeUI.defaultRow,ThemeUI.blackholeRow,ThemeUI.empyreanRow,ThemeUI.frostRow}
            local buttons={ThemeUI.defaultButton,ThemeUI.blackholeButton,ThemeUI.empyreanButton,ThemeUI.frostButton}
            for _,row in ipairs(rows) do if row then row.BackgroundColor3=emp and cream2 or dark; row.BackgroundTransparency=emp and .02 or 0; local st=row:FindFirstChildOfClass("UIStroke"); if st then st.Color=line end end end
            for i,button in ipairs(buttons) do if button then
                local active=(i==3 and emp) or (i==2 and bh) or (i==1 and not emp and not bh)
                button.BackgroundColor3=active and (emp and gold or darkAccent) or (emp and cream or dark)
                button.TextColor3=active and (emp and ink or darkText) or (emp and faint or darkMuted)
                button.AutoButtonColor=false
                local st=button:FindFirstChildOfClass("UIStroke"); if st then st.Color=line end
            end end
            if ThemeUI.activeLabel then ThemeUI.activeLabel.Text=bh and "BLACKHOLE V1" or (emp and "EMPYREAN" or (System.theme=="Frost" and "FROSTBOUND" or "DEFAULT")); ThemeUI.activeLabel.TextColor3=emp and ink or darkText end
            if ThemeUI.hint then ThemeUI.hint.TextColor3=emp and faint or darkMuted end
        end
    end)

    pcall(function()
        for _,page in pairs(pageMap) do page.ScrollBarImageColor3=emp and gold or darkAccent; page.ScrollBarImageTransparency=emp and .42 or .35 end
    end)
end


-- ============================================================
-- FROSTBOUND ATMOSPHERE
-- Dedicated background-only frost particle layer.
-- It never receives input and never participates in layout.
-- ============================================================
local FrostFX = {
    layer = nil,
    flakes = {},
    connection = nil,
    seeded = false,
}

function FrostFX.ensure()
    if System.theme ~= "Frost" then
        if FrostFX.layer then FrostFX.layer.Visible = false end
        return
    end

    if not FrostFX.layer or not FrostFX.layer.Parent then
        FrostFX.layer = frame(panel, "FrostAtmosphere", 0, 0, math.max(1, windowWidth), math.max(1, windowHeight), Color3.new(1,1,1), 0)
        FrostFX.layer.BackgroundTransparency = 1
        FrostFX.layer.BorderSizePixel = 0
        FrostFX.layer.Active = false
        FrostFX.layer.Selectable = false
        FrostFX.layer.ZIndex = 2
        FrostFX.layer.ClipsDescendants = true

        local veil = frame(FrostFX.layer, "IceVeil", 0, 64, math.max(1, windowWidth), math.max(1, windowHeight - 64), Color3.fromRGB(194,239,248), 0)
        veil.BackgroundTransparency = 0.985
        veil.Active = false
        veil.ZIndex = 2

        for i = 1, 30 do
            local flake = frame(FrostFX.layer, "Flake" .. i, 0, 0, 12, 12, Color3.new(1,1,1), 0)
            flake.BackgroundTransparency = 1
            flake.BorderSizePixel = 0
            flake.Active = false
            flake.ZIndex = 3

            local armA = frame(flake, "A", 5, 1, 2, 10, Color3.fromRGB(223,249,255), 1)
            local armB = frame(flake, "B", 1, 5, 10, 2, Color3.fromRGB(173,224,235), 1)
            local armC = frame(flake, "C", 2, 2, 8, 2, Color3.fromRGB(240,253,255), 1)
            armC.Rotation = 45

            FrostFX.flakes[i] = {
                object = flake,
                x = 0,
                y = 0,
                speed = 8 + ((i * 17) % 19),
                drift = -7 + ((i * 13) % 15),
                phase = (i * 0.73) % (math.pi * 2),
                size = 0.55 + ((i * 7) % 8) / 10,
                spin = -24 + ((i * 11) % 49),
            }
        end
    end

    FrostFX.layer.Position = UDim2.fromOffset(0, 0)
    FrostFX.layer.Size = UDim2.fromOffset(math.max(1, windowWidth), math.max(1, windowHeight))
    FrostFX.layer.Visible = true

    if not FrostFX.seeded then
        FrostFX.seeded = true
        for i, f in ipairs(FrostFX.flakes) do
            local w = math.max(1, windowWidth)
            local h = math.max(1, windowHeight - 64)
            f.x = ((i * 83) % math.max(1, w - 20)) + 10
            f.y = 64 + ((i * 47) % math.max(1, h - 10))
        end
    end

    if not FrostFX.connection then
        FrostFX.connection = connect(RunService.RenderStepped, function()
            if not State.alive then
                if FrostFX.connection then
                    FrostFX.connection:Disconnect()
                    FrostFX.connection = nil
                end
                return
            end

            if System.theme ~= "Frost" or not FrostFX.layer or not FrostFX.layer.Parent then
                if FrostFX.layer then FrostFX.layer.Visible = false end
                return
            end

            local now = os.clock()
            local w = math.max(1, windowWidth)
            local bottom = math.max(70, windowHeight)
            local span = math.max(1, bottom - 64)

            for i, f in ipairs(FrostFX.flakes) do
                f.y = f.y + f.speed * 0.016
                f.x = f.x + math.sin(now * 0.55 + f.phase) * f.drift * 0.016

                if f.y > bottom + 12 then
                    f.y = 60 - ((i * 17) % 40)
                    f.x = ((i * 83 + math.floor(now * 4)) % math.max(1, w - 20)) + 10
                end
                if f.x < -12 then f.x = w + 8 end
                if f.x > w + 12 then f.x = -8 end

                local twinkle = (math.sin(now * 1.35 + f.phase) + 1) * 0.5
                local alpha = 0.28 + twinkle * 0.42
                local size = f.size * (0.88 + twinkle * 0.18)

                f.object.Position = UDim2.fromOffset(math.floor(f.x), math.floor(f.y))
                f.object.Size = UDim2.fromOffset(math.max(6, math.floor(12 * size)), math.max(6, math.floor(12 * size)))
                f.object.Rotation = (now * f.spin + f.phase * 35) % 360

                for _, child in ipairs(f.object:GetChildren()) do
                    if child:IsA("Frame") then
                        child.BackgroundTransparency = alpha
                    end
                end
            end
        end)
    end
end

function Theme.applyFrostFinal()
    if System.theme ~= "Frost" then return end
    local P = Theme.Frost
    FrostFX.ensure()
    local frostLine = Color3.fromRGB(153,211,222)
    local frostBright = Color3.fromRGB(240,253,255)
    local frostMuted = Color3.fromRGB(151,192,202)
    local frostFaint = Color3.fromRGB(113,157,168)

    -- Frost is a presentation layer only. It does not alter automation state,
    -- analytics counters, Mini Mode data, farm logic, teleport logic, or input.
    windowHeight = 630
    windowWidth = math.max(680, windowWidth or W)
    holder.Size = UDim2.fromOffset(windowWidth, windowHeight)
    shadow.Size = UDim2.fromOffset(windowWidth + 12, windowHeight + 12)
    panel.Size = UDim2.fromOffset(windowWidth, windowHeight)
    panel.BackgroundColor3 = P.deep
    panel.BackgroundTransparency = .02
    panelStroke.Color = frostLine
    panelStroke.Transparency = .34

    header.Position = UDim2.fromOffset(170,0)
    header.Size = UDim2.fromOffset(windowWidth-170,64)
    header.BackgroundColor3 = P.panel
    header.BackgroundTransparency = .04
    headerLine.Position = UDim2.fromOffset(0,63)
    headerLine.Size = UDim2.fromOffset(windowWidth-170,1)
    headerLine.BackgroundColor3 = frostLine
    headerLine.BackgroundTransparency = .42
    brandTitle.Text = "FROSTBOUND"
    brandTitle.TextColor3 = frostBright
    header:FindFirstChild("Sub").Text = "THE SANCTUM IS QUIET"
    header:FindFirstChild("Sub").TextColor3 = frostMuted
    brandmark.BackgroundColor3 = P.panel2
    local bs = brandmark:FindFirstChildOfClass("UIStroke")
    if bs then bs.Color = frostLine; bs.Transparency = .20 end
    markCore.BackgroundColor3 = frostBright
    markH.BackgroundColor3 = P.accent
    markV.BackgroundColor3 = P.cyan
    statusDot.BackgroundColor3 = frostBright
    statusGlow.Color = P.accent
    UI.badge.TextColor3 = frostMuted

    -- Hide the old ticker; Frost uses the quieter sanctum composition.
    ticker.Visible = false
    tickerText.Visible = false
    edgeSheen.BackgroundColor3 = P.cyan
    edgeSheen.BackgroundTransparency = .965
    edgeSheenGradient.Color = ColorSequence.new(P.cyan, P.accent)

    -- Frost owns a dedicated sidebar. Legacy navigation remains hidden.
    FrostNav.removeLegacyDecor()
    FrostNav.ensure()
    if FrostFX.layer then
        FrostFX.layer.ZIndex = 2
        FrostFX.layer.Position = UDim2.fromOffset(0,0)
        FrostFX.layer.Size = UDim2.fromOffset(windowWidth,windowHeight)
        FrostFX.layer.Visible = true
    end

    local frostContentWidth = math.max(1, windowWidth - 170)
    content.Position=UDim2.fromOffset(170,64)
    content.Size=UDim2.fromOffset(frostContentWidth,windowHeight-64)
    content.BackgroundColor3=P.deep
    content.BackgroundTransparency=.62
    local frostGradient = content:FindFirstChild("FrostSurfaceGradient")
    if not frostGradient then
        frostGradient = make("UIGradient", content, {
            Name = "FrostSurfaceGradient",
            Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(30,65,75)),
                ColorSequenceKeypoint.new(.5, Color3.fromRGB(18,43,51)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(10,29,36)),
            }),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, .88),
                NumberSequenceKeypoint.new(.48, .93),
                NumberSequenceKeypoint.new(1, .84),
            }),
        })
    end
    frostGradient.Enabled = true
    FrostFX.ensure()

    for _,page in pairs(pageMap) do
        page.Size=UDim2.fromOffset(frostContentWidth,windowHeight-64)
        page.Position=UDim2.fromOffset(0,pageBaseY)
        for _,child in ipairs(page:GetChildren()) do
            if child.Name=="PaneHead" then
                child.Size=UDim2.fromOffset(math.max(1,frostContentWidth-32),child.Size.Y.Offset)
            elseif child.Name:match("^Row_") or child.Name:match("^Slider_") or child.Name=="KeyLoadout" then
                local rw=math.max(1,frostContentWidth-32)
                child.Size=UDim2.fromOffset(rw,child.Size.Y.Offset)
                local toggle=child:FindFirstChild("Toggle")
                if toggle then toggle.Position=UDim2.fromOffset(rw-54,14) end
                local value=child:FindFirstChild("Value")
                if value then value.Position=UDim2.fromOffset(rw-120,8) end
                local hit=child:FindFirstChild("Slider")
                if hit then
                    hit.Size=UDim2.fromOffset(math.max(1,rw-56),24)
                    local rail=hit:FindFirstChild("Rail")
                    if rail then rail.Size=UDim2.fromOffset(math.max(1,rw-56),4) end
                end
            end
        end
        page.ScrollBarImageColor3=P.accent
        page.ScrollBarImageTransparency=.60
        for _,obj in ipairs(page:GetDescendants()) do
            if obj:IsA("Frame") then
                if obj.Name:match("^Row_") or obj.Name:match("^Slider_") or obj.Name=="KeyLoadout" or obj.Name=="TargetSettings" or obj.Name=="Analytics" or obj.Name=="Profiles" or obj.Name=="ThemeInfo" or obj.Name:match("^Preset_") then
                    obj.BackgroundColor3=P.surface
                    obj.BackgroundTransparency=.08
                end
                local st=obj:FindFirstChildOfClass("UIStroke")
                if st and (obj.Name:match("^Row_") or obj.Name:match("^Slider_") or obj.Name=="KeyLoadout" or obj.Name:match("^Preset_") or obj.Name=="ThemeInfo" or obj.Name=="Analytics" or obj.Name=="Profiles") then
                    st.Color=frostLine; st.Transparency=.72
                end
            elseif obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                if obj.Name=="Modules" or obj.Name=="Hint" or obj.Name=="Desc" or obj.Name=="Sub" or obj.Name=="Status" or obj.Name=="Percent" or obj.Name=="ScanStatus" then
                    obj.TextColor3=frostMuted
                else
                    obj.TextColor3=frostBright
                end
                if obj:IsA("TextButton") then obj.AutoButtonColor=false end
            end
        end
    end

    for _,view in ipairs(toggleViews) do
        local on=view.getter()
        view.track.BackgroundColor3=on and P.toggleOn or P.toggleOff
        view.track.BackgroundTransparency=.08
        view.knob.BackgroundColor3=on and frostBright or frostFaint
        local st=view.track:FindFirstChildOfClass("UIStroke")
        if st then st.Color=frostLine; st.Transparency=.45 end
    end
    for _,view in ipairs(sliders) do
        view.fill.BackgroundColor3=P.accent
        view.knob.BackgroundColor3=frostBright
        view.valueLabel.TextColor3=P.cyan
        local rail=view.hit:FindFirstChild("Rail")
        if rail then rail.BackgroundColor3=P.toggleOff end
        local ks=view.knob:FindFirstChildOfClass("UIStroke")
        if ks then ks.Color=frostLine end
    end


    -- Exhaustive Frost control pass.
    -- The original UI was constructed with Blackhole colors in many nested
    -- TextButtons/icons. Frost must own those visual properties too, not only
    -- the outer rows.
    local frostButton = P.panel2
    local frostButtonText = frostBright
    local frostStroke = frostLine
    local frostIcon = P.accent
    local frostIconBright = P.cyan

    for _, page in pairs(pageMap) do
        for _, obj in ipairs(page:GetDescendants()) do
            if obj:IsA("TextButton") then
                obj.AutoButtonColor = false
                obj.BackgroundColor3 = frostButton
                obj.BackgroundTransparency = .02
                obj.TextColor3 = frostButtonText
                obj.TextStrokeTransparency = 1
                local st = obj:FindFirstChildOfClass("UIStroke")
                if st then
                    st.Color = frostStroke
                    st.Transparency = .48
                end
            elseif obj:IsA("TextBox") then
                obj.BackgroundColor3 = P.surface
                obj.BackgroundTransparency = .02
                obj.TextColor3 = frostBright
                obj.PlaceholderColor3 = frostMuted
                local st = obj:FindFirstChildOfClass("UIStroke")
                if st then
                    st.Color = frostStroke
                    st.Transparency = .48
                end
            elseif obj:IsA("TextLabel") then
                -- Remove constructor-time purple/blackhole text from every
                -- visible Frost page label while retaining muted/status text.
                if obj.Visible then
                    if obj.Name == "Modules" or obj.Name == "Hint" or obj.Name == "Desc"
                        or obj.Name == "Sub" or obj.Name == "Status" or obj.Name == "Percent"
                        or obj.Name == "ScanStatus" or obj.Name == "Count" or obj.Name == "Cycle"
                        or obj.Name == "Detail" or obj.Name == "Advanced" or obj.Name == "Filter"
                        or obj.Name == "Dwell" or obj.Name == "Radius" or obj.Name == "Discover"
                        or obj.Name == "SaveStatus" or obj.Name == "DiscoveryStatus" then
                        obj.TextColor3 = frostMuted
                    else
                        obj.TextColor3 = frostBright
                    end
                end
            elseif obj:IsA("Frame") then
                -- Every icon in Frost gets the same crystalline language.
                if obj.Name == "Icon" then
                    obj.BackgroundColor3 = P.surface
                    obj.BackgroundTransparency = .16
                    local st = obj:FindFirstChildOfClass("UIStroke")
                    if st then
                        st.Color = frostStroke
                        st.Transparency = .34
                    end
                    for _, d in ipairs(obj:GetDescendants()) do
                        if d:IsA("Frame") then
                            d.BackgroundColor3 = frostIconBright
                            d.BackgroundTransparency = math.min(d.BackgroundTransparency, .08)
                        elseif d:IsA("UIStroke") then
                            d.Color = frostIcon
                            d.Transparency = .22
                        end
                    end
                elseif obj.Name == "Core" or obj.Name == "Pupil" or obj.Name == "Center"
                    or obj.Name == "Void" then
                    obj.BackgroundColor3 = frostIconBright
                end
            elseif obj:IsA("UIStroke") then
                -- Purple strokes that survived from the constructor are
                -- converted unless they belong to the external utility layer.
                if obj.Parent and obj.Parent:IsDescendantOf(page) then
                    obj.Color = frostStroke
                end
            end
        end
    end

    -- Skill loadout gets a distinct frosted-crystal selected state.
    local loadout = skillsPage and skillsPage:FindFirstChild("KeyLoadout")
    if loadout then
        loadout.BackgroundColor3 = P.surface
        for _, obj in ipairs(loadout:GetDescendants()) do
            if obj:IsA("TextButton") then
                obj.BackgroundColor3 = P.panel2
                obj.BackgroundTransparency = .02
                obj.TextColor3 = frostBright
                local st = obj:FindFirstChildOfClass("UIStroke")
                if st then st.Color = frostLine; st.Transparency = .34 end
            end
        end
    end

    -- Control Center / Core buttons are explicitly Frost, including buttons
    -- whose constructor color came from Blackhole V1.
    local corePage = pageMap.Core
    if corePage then
        for _, obj in ipairs(corePage:GetDescendants()) do
            if obj:IsA("TextButton") then
                obj.BackgroundColor3 = P.panel2
                obj.TextColor3 = frostBright
                obj.AutoButtonColor = false
                local st = obj:FindFirstChildOfClass("UIStroke")
                if st then st.Color = frostLine; st.Transparency = .42 end
            end
        end
    end

    -- Theme preset icons are intentionally allowed to depict their own theme,
    -- but the surrounding Frost controls never inherit Blackhole purple.
    if ThemeUI then
        for _, row in ipairs({ThemeUI.defaultRow, ThemeUI.blackholeRow, ThemeUI.empyreanRow, ThemeUI.frostRow}) do
            if row then
                row.BackgroundColor3 = P.surface
                row.BackgroundTransparency = .08
                for _, obj in ipairs(row:GetDescendants()) do
                    if obj:IsA("TextButton") then
                        obj.BackgroundColor3 = P.panel2
                        obj.TextColor3 = frostMuted
                        obj.AutoButtonColor = false
                        local st = obj:FindFirstChildOfClass("UIStroke")
                        if st then st.Color = frostLine; st.Transparency = .42 end
                    end
                end
            end
        end
    end

    -- The sidebar symbols and labels are Frost-only; no legacy purple remains.
    for _, key in ipairs(navNames) do
        local tab = navButtons[key]
        if tab then
            FrostNav.paintTab(tab, State.tab == key, false)
            local icon = tab:FindFirstChild("Icon")
            if icon then
                for _, d in ipairs(icon:GetDescendants()) do
                    if d:IsA("Frame") then
                        d.BackgroundColor3 = (State.tab == key) and frostIconBright or frostMuted
                    elseif d:IsA("UIStroke") then
                        d.Color = frostIcon
                    end
                end
            end
        end
    end

    if UI.staticScanButton then UI.staticScanButton.BackgroundColor3=P.panel2; UI.staticScanButton.TextColor3=frostBright end
    if UI.privateMapBox then UI.privateMapBox.BackgroundColor3=P.panel2; UI.privateMapBox.TextColor3=frostBright end
    if resizeGrip then
        resizeGrip.Position=UDim2.fromOffset(windowWidth-28,windowHeight-28)
        for i=1,3 do local line=resizeGrip:FindFirstChild("Line"..i); if line then line.BackgroundColor3=P.accent end end
    end

    if ThemeUI then
        ThemeUI.themeInfo.BackgroundColor3=P.surface
        ThemeUI.themeInfo.BackgroundTransparency=.08
        ThemeUI.activeLabel.Text="FROSTBOUND"
        ThemeUI.activeLabel.TextColor3=frostBright
        for _,row in ipairs({ThemeUI.defaultRow,ThemeUI.blackholeRow,ThemeUI.empyreanRow,ThemeUI.frostRow}) do
            if row then row.BackgroundColor3=P.surface; row.BackgroundTransparency=.08 end
        end
        for _,btn in ipairs({ThemeUI.defaultButton,ThemeUI.blackholeButton,ThemeUI.empyreanButton,ThemeUI.frostButton}) do
            if btn then btn.BackgroundColor3=P.panel2; btn.TextColor3=frostMuted end
        end
        if ThemeUI.frostButton then ThemeUI.frostButton.BackgroundColor3=P.accent; ThemeUI.frostButton.TextColor3=Color3.fromRGB(18,43,51) end
    end

    if CoreUI then
        for _,obj in ipairs({CoreUI.profileBox,CoreUI.statsBox}) do
            if obj then obj.BackgroundColor3=P.surface end
        end
    end

    if miniFrame and miniFrame.Parent then
        miniFrame.BackgroundColor3=P.panel
        miniFrame.BackgroundTransparency=.06
        miniStroke.Color=P.line
        miniTitle.TextColor3=frostBright
        miniTarget.TextColor3=frostBright
        miniStats.TextColor3=frostMuted
        miniExpand.BackgroundColor3=P.panel2; miniExpand.TextColor3=frostBright
        miniClose.BackgroundColor3=P.panel2; miniClose.TextColor3=frostBright
        miniDot.BackgroundColor3=frostBright
        miniTitle.Text="✧ FROSTBOUND"
    end
end

function Theme.apply(themeName)
    if themeName~="Blackhole" and themeName~="Empyrean" and themeName~="Frost" then themeName="Default" end
    Theme.stopSpecialVisuals(); System.theme=themeName
    if themeName=="Frost" then
        FrostNav.ensure()
        FrostFX.ensure()
    else
        FrostNav.restore()
        if FrostFX.layer then FrostFX.layer.Visible=false end
    end
    local bh=themeName=="Blackhole"; local emp=themeName=="Empyrean"; local frost=themeName=="Frost"
    Theme.current=bh and Theme.Blackhole or(emp and Theme.Empyrean or(frost and Theme.Frost or Theme.Default)); Theme.copy(Theme.current)
    if bh then
        Theme.height=600; windowHeight=Theme.height; holder.Size=UDim2.fromOffset(windowWidth,windowHeight); shadow.Size=UDim2.fromOffset(windowWidth+12,windowHeight+12); panel.Size=UDim2.fromOffset(windowWidth,windowHeight); panel.BackgroundColor3=C.panel; panel.BackgroundTransparency=.18; panelStroke.Color=C.line; panelStroke.Transparency=.72; panelBackdrop.Visible=false; voidFX.Visible=false; ticker.Visible=false; content.BackgroundTransparency=1
        local panelGradient=panel:FindFirstChildOfClass("UIGradient"); if panelGradient then panelGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(23,12,39)),ColorSequenceKeypoint.new(.45,Color3.fromRGB(14,7,26)),ColorSequenceKeypoint.new(1,Color3.fromRGB(5,2,12))}); panelGradient.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.18),NumberSequenceKeypoint.new(.48,.28),NumberSequenceKeypoint.new(1,.12)}) end
        header.Position=UDim2.fromOffset(0,0); header.Size=UDim2.fromOffset(windowWidth,64); header.BackgroundColor3=C.panel; header.BackgroundTransparency=.08; local headerGradient=header:FindFirstChildOfClass("UIGradient"); if headerGradient then headerGradient.Color=ColorSequence.new(C.violet,C.panel); headerGradient.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.82),NumberSequenceKeypoint.new(1,1)}) end; headerLine.BackgroundColor3=C.line; headerLine.BackgroundTransparency=.70; brandTitle.Text="BLACKHOLE V1"; brandTitle.TextColor3=C.ink; header:FindFirstChild("Sub").Text="REACTOR ONLINE"; BH.hero.Visible=true; BH.hero.Position=UDim2.fromOffset(0,64); BH.hero.Size=UDim2.fromOffset(windowWidth,152); BH.hero.BackgroundColor3=C.black; BH.heroStroke.Color=C.line; BH.heroStroke.Transparency=.82; tabs.Position=UDim2.fromOffset(0,216); tabs.BackgroundColor3=C.black; tabs.BackgroundTransparency=.28; content.Position=UDim2.fromOffset(0,280); content.Size=UDim2.fromOffset(windowWidth,windowHeight-280); edgeSheen.BackgroundColor3=C.cyan; BH.atmosphere.BackgroundColor3=Color3.fromRGB(12,8,20)
    elseif emp then
        -- EMPYREAN follows EMPYREAN (1).html: cream glass, gold primary accent,
        -- pale sky secondary accent, light celestial navigation and content.
        Theme.height=600
        windowHeight=Theme.height
        holder.Size=UDim2.fromOffset(windowWidth,windowHeight)
        shadow.Size=UDim2.fromOffset(windowWidth+12,windowHeight+12)
        panel.Size=UDim2.fromOffset(windowWidth,windowHeight)
        panel.BackgroundColor3=C.panel
        panel.BackgroundTransparency=0
        panelStroke.Color=C.line
        panelStroke.Transparency=.18
        panelBackdrop.Visible=false
        voidFX.Visible=false
        ticker.Visible=false

        local panelGradient=panel:FindFirstChildOfClass("UIGradient")
        if panelGradient then
            panelGradient.Color=ColorSequence.new({
                ColorSequenceKeypoint.new(0,Color3.fromRGB(255,253,247)),
                ColorSequenceKeypoint.new(.45,Color3.fromRGB(255,248,232)),
                ColorSequenceKeypoint.new(1,Color3.fromRGB(255,248,232))
            })
            panelGradient.Transparency=NumberSequence.new(0)
        end

        header.Position=UDim2.fromOffset(0,0)
        header.Size=UDim2.fromOffset(windowWidth,64)
        header.BackgroundColor3=C.panel
        header.BackgroundTransparency=.04
        local headerGradient=header:FindFirstChildOfClass("UIGradient")
        if headerGradient then
            headerGradient.Color=ColorSequence.new(
                Color3.fromRGB(255,224,150),
                Color3.fromRGB(255,253,247)
            )
            headerGradient.Transparency=NumberSequence.new({
                ColorSequenceKeypoint.new(0,.18),
                ColorSequenceKeypoint.new(1,.88)
            })
        end
        headerLine.BackgroundColor3=C.line
        headerLine.BackgroundTransparency=.55
        brandTitle.Text="EMPYREAN"
        brandTitle.TextColor3=C.text
        header:FindFirstChild("Sub").Text="GRACE ATTAINED"

        EMP.hero.Visible=true
        EMP.hero.Position=UDim2.fromOffset(0,64)
        EMP.hero.Size=UDim2.fromOffset(windowWidth,160)
        EMP.hero.BackgroundColor3=C.surface
        EMP.hero.BackgroundTransparency=0
        EMP.heroStroke.Color=C.line
        EMP.heroStroke.Transparency=.34

        tabs.Position=UDim2.fromOffset(0,224)
        tabs.BackgroundColor3=Color3.fromRGB(255,250,235)
        tabs.BackgroundTransparency=.42

        content.Position=UDim2.fromOffset(0,288)
        content.Size=UDim2.fromOffset(windowWidth,windowHeight-288)
        content.BackgroundColor3=C.panel
        content.BackgroundTransparency=0
        local contentGradient=content:FindFirstChild("EmpyreanSurfaceGradient")
        if not contentGradient then
            contentGradient=make("UIGradient",content,{Name="EmpyreanSurfaceGradient"})
        end
        contentGradient.Rotation=90
        contentGradient.Color=ColorSequence.new({
            ColorSequenceKeypoint.new(0,Color3.fromRGB(255,253,247)),
            ColorSequenceKeypoint.new(0.30,Color3.fromRGB(255,248,232)),
            ColorSequenceKeypoint.new(0.62,Color3.fromRGB(234,243,255)),
            ColorSequenceKeypoint.new(1,Color3.fromRGB(220,235,255))
        })
        contentGradient.Transparency=NumberSequence.new(0)

        edgeSheen.BackgroundColor3=C.line
    elseif frost then
        Theme.height=630
        windowHeight=Theme.height
        windowWidth=math.max(680, windowWidth)
        holder.Size=UDim2.fromOffset(windowWidth,windowHeight)
        shadow.Size=UDim2.fromOffset(windowWidth+12,windowHeight+12)
        panel.Size=UDim2.fromOffset(windowWidth,windowHeight)
        panel.BackgroundColor3=C.deep
        panel.BackgroundTransparency=.02
        panelStroke.Color=C.line
        panelStroke.Transparency=.34
        panelBackdrop.Visible=false
        voidFX.Visible=false
        ticker.Visible=false
        local panelGradient=panel:FindFirstChildOfClass("UIGradient")
        if panelGradient then
            panelGradient.Color=ColorSequence.new({
                ColorSequenceKeypoint.new(0,Color3.fromRGB(31,67,77)),
                ColorSequenceKeypoint.new(.48,Color3.fromRGB(18,43,51)),
                ColorSequenceKeypoint.new(1,Color3.fromRGB(9,27,34))
            })
            panelGradient.Transparency=NumberSequence.new({
                ColorSequenceKeypoint.new(0,.08),ColorSequenceKeypoint.new(.5,.12),ColorSequenceKeypoint.new(1,.04)
            })
        end
        header.Position=UDim2.fromOffset(170,0)
        header.Size=UDim2.fromOffset(windowWidth-170,64)
        header.BackgroundColor3=C.panel
        header.BackgroundTransparency=.04
        local headerGradient=header:FindFirstChildOfClass("UIGradient")
        if headerGradient then
            headerGradient.Color=ColorSequence.new(Color3.fromRGB(68,116,128),Color3.fromRGB(25,57,67))
            headerGradient.Transparency=NumberSequence.new({ColorSequenceKeypoint.new(0,.22),ColorSequenceKeypoint.new(1,.92)})
        end
        headerLine.Position=UDim2.fromOffset(0,63); headerLine.Size=UDim2.fromOffset(windowWidth-170,1)
        headerLine.BackgroundColor3=C.line; headerLine.BackgroundTransparency=.42
        brandTitle.Text="FROSTBOUND"; brandTitle.TextColor3=C.ink
        header:FindFirstChild("Sub").Text="THE SANCTUM IS QUIET"
        statusDot.BackgroundColor3=C.bright; statusGlow.Color=C.accent
        tabs.Position=UDim2.fromOffset(0,64)
        tabs.Size=UDim2.fromOffset(170,windowHeight-64)
        tabs.BackgroundColor3=Color3.fromRGB(13,34,41)
        tabs.BackgroundTransparency=.02
        content.Position=UDim2.fromOffset(170,64)
        content.Size=UDim2.fromOffset(windowWidth-170,windowHeight-64)
        content.BackgroundTransparency=0
        content.BackgroundColor3=C.deep
        edgeSheen.Visible=true
        edgeSheen.BackgroundColor3=C.cyan
    else
        local contentGradient=content:FindFirstChild("EmpyreanSurfaceGradient")
        if contentGradient then contentGradient:Destroy() end
        Theme.height=H; windowHeight=Theme.height; holder.Size=UDim2.fromOffset(windowWidth,windowHeight); shadow.Size=UDim2.fromOffset(windowWidth+12,windowHeight+12); panel.Size=UDim2.fromOffset(windowWidth,windowHeight); panel.BackgroundColor3=C.panel; panel.BackgroundTransparency=.40; panelStroke.Color=C.violet2; panelStroke.Transparency=.28; panelBackdrop.Visible=true; voidFX.Visible=true; ticker.Visible=true; content.BackgroundTransparency=1
        local panelGradient=panel:FindFirstChildOfClass("UIGradient"); if panelGradient then panelGradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(23,12,39)),ColorSequenceKeypoint.new(.45,Color3.fromRGB(14,7,26)),ColorSequenceKeypoint.new(1,Color3.fromRGB(5,2,12))}); panelGradient.Transparency=NumberSequence.new({ColorSequenceKeypoint.new(0,.18),ColorSequenceKeypoint.new(.48,.28),ColorSequenceKeypoint.new(1,.12)}) end
        header.Position=UDim2.fromOffset(0,0); header.Size=UDim2.fromOffset(windowWidth,64); header.BackgroundColor3=C.panel; header.BackgroundTransparency=.08; headerLine.BackgroundColor3=C.violet; headerLine.BackgroundTransparency=.48; brandTitle.Text="VOID NEXUS"; brandTitle.TextColor3=C.ink; header:FindFirstChild("Sub").Text="CORE LINK STABLE"; tabs.Position=UDim2.fromOffset(0,88); tabs.BackgroundColor3=C.black; tabs.BackgroundTransparency=.35; content.Position=UDim2.fromOffset(0,152); content.Size=UDim2.fromOffset(windowWidth,windowHeight-152); edgeSheen.BackgroundColor3=C.cyan
    end
    brandmark.BackgroundColor3=C.panel2
    local brandStroke=brandmark:FindFirstChildOfClass("UIStroke")
    if brandStroke then brandStroke.Color=C.line end
    markCore.BackgroundColor3=emp and Color3.fromRGB(217,169,78) or C.violet2
    markH.BackgroundColor3=emp and Color3.fromRGB(156,116,32) or C.violet2
    markV.BackgroundColor3=emp and Color3.fromRGB(156,116,32) or C.cyan
    ticker.BackgroundColor3=emp and C.panel2 or C.black
    tickerText.TextColor3=C.faint
    tabs:FindFirstChildOfClass("UIStroke").Color=C.line
    edgeSheenGradient.Color=emp and ColorSequence.new(Color3.fromRGB(255,243,200),Color3.fromRGB(207,230,255)) or ColorSequence.new(C.cyan,C.violet2)
    for key,tab in pairs(navButtons) do
        if emp then
            tab.BackgroundColor3=Color3.fromRGB(255,255,255)
            tab.BackgroundTransparency=.34
            tab.TextColor3=C.faint
        else
            tab.BackgroundColor3=bh and C.panel2 or Color3.fromRGB(8,4,16)
            tab.BackgroundTransparency=0
        end
        local st=UI.navStrokes[key]
        if st then st.Color=C.line end
        local bar=UI.navBars[key]
        if bar then bar.BackgroundColor3=emp and Color3.fromRGB(217,169,78) or C.violet2 end
    end
    Theme.restyleRows(); Theme.restyleText()
    if emp then
        Theme.restyleEmpyreanThemePage()
        if UI.staticScanButton then UI.staticScanButton.TextColor3=Color3.fromRGB(156,116,32); UI.staticScanButton.BackgroundColor3=C.panel2 end
        if UI.privateMapBox then UI.privateMapBox.BackgroundColor3=C.panel2; UI.privateMapBox.TextColor3=C.text end
        if resizeGrip then
            for i=1,3 do
                local gripLine=resizeGrip:FindFirstChild("Line"..i)
                if gripLine then gripLine.BackgroundColor3=Color3.fromRGB(156,116,32) end
            end
        end
        for _, view in ipairs(toggleViews) do
            view.track.BackgroundColor3=view.getter() and C.toggleOn or C.toggleOff
            view.knob.BackgroundColor3=view.getter() and C.bright or C.faint
        end
        for _, view in ipairs(sliders) do
            view.fill.BackgroundColor3=C.violet2
            view.knob.BackgroundColor3=C.bright
            local rail=view.hit:FindFirstChild("Rail")
            if rail then rail.BackgroundColor3=C.toggleOff end
        end
        for _, page in pairs(pageMap) do
            page.ScrollBarImageColor3=C.violet2
            page.ScrollBarImageTransparency=.55
        end
        if ThemeUI.themeInfo then
            ThemeUI.themeInfo.BackgroundColor3=C.panel2
            ThemeUI.themeInfo.BackgroundTransparency=.12
        end
        for _, row in ipairs({ThemeUI.defaultRow, ThemeUI.blackholeRow, ThemeUI.empyreanRow}) do
            if row then
                row.BackgroundColor3=C.panel2
                row.BackgroundTransparency=.12
            end
        end
        if ThemeUI.defaultButton then
            ThemeUI.defaultButton.BackgroundColor3=C.panel2
            ThemeUI.defaultButton.TextColor3=C.faint
        end
        if ThemeUI.blackholeButton then
            ThemeUI.blackholeButton.BackgroundColor3=C.panel2
            ThemeUI.blackholeButton.TextColor3=C.faint
        end
        if ThemeUI.empyreanButton then
            ThemeUI.empyreanButton.BackgroundColor3=C.violet2
            ThemeUI.empyreanButton.TextColor3=C.ink
        end
    end
    if ThemeUI.activeLabel then ThemeUI.activeLabel.Text=bh and "BLACKHOLE V1" or(emp and "EMPYREAN" or(frost and "FROSTBOUND" or "DEFAULT")); ThemeUI.activeLabel.TextColor3=C.ink end
    if ThemeUI.defaultButton then ThemeUI.defaultButton.BackgroundColor3=(not bh and not emp) and C.violet2 or C.panel2; ThemeUI.defaultButton.TextColor3=(not bh and not emp) and C.ink or C.faint end
    if ThemeUI.blackholeButton then ThemeUI.blackholeButton.BackgroundColor3=bh and C.violet2 or C.panel2; ThemeUI.blackholeButton.TextColor3=bh and C.ink or C.faint end
    if ThemeUI.empyreanButton then ThemeUI.empyreanButton.BackgroundColor3=emp and C.violet2 or C.panel2; ThemeUI.empyreanButton.TextColor3=emp and C.ink or C.faint end
    if ThemeUI.defaultRow then local st=ThemeUI.defaultRow:FindFirstChildOfClass("UIStroke"); if st then st.Color=(not bh and not emp) and C.violet2 or C.line end end
    if ThemeUI.blackholeRow then local st=ThemeUI.blackholeRow:FindFirstChildOfClass("UIStroke"); if st then st.Color=bh and C.violet2 or C.line end end
    if ThemeUI.empyreanRow then local st=ThemeUI.empyreanRow:FindFirstChildOfClass("UIStroke"); if st then st.Color=emp and C.violet2 or C.line end end
    if bh then
        BH.core.BackgroundColor3=Color3.new(0,0,0); BH.coreGlow.BackgroundColor3=Color3.fromRGB(65,35,135); BH.silverStroke.Color=Color3.fromRGB(238,241,251); BH.purpleStroke.Color=Color3.fromRGB(122,63,242)
    elseif emp then
        -- Restart the active EMPYREAN renderer after every theme transition.
        -- The lifetime watchdog below remains alive even while another theme is
        -- selected, so switching away and back cannot permanently kill the
        -- celestial effects.
        pcall(function() EMP.startVisuals() end)
        task.defer(function()
            if State.alive and System.theme=="Empyrean" then
                pcall(function() EMP.ensureVisuals() end)
            end
        end)
    end
    pcall(function() if MiniMode and MiniMode.applyTheme then MiniMode.applyTheme() end end)
    applyWindowWidth(windowWidth)
    fitWindow(false)
    Theme.syncAllThemeVisuals()
    Theme.hardResetControls()
    render()
    Theme.hardResetControls()
    Theme.canonicalizeControls()
    if System.theme=="Frost" then pcall(function() Theme.applyFrostFinal() end) end
    -- All synchronous theme passes are finished. Rebind EMPYREAN once more on
    -- the next scheduler turn so no legacy restyler can race the animation.
    if System.theme=="Empyrean" then
        task.defer(function()
            if State.alive and System.theme=="Empyrean" then
                pcall(function() EMP.ensureVisuals() end)
            end
        end)
    end
end

UI.setTheme = function(themeName)
    local normalized = (themeName == "Blackhole" or themeName == "Empyrean" or themeName == "Frost" or themeName == "Default")
        and themeName or "Default"

    -- Commit the selection BEFORE touching any visuals. This is the single
    -- authoritative state used by both the next loader and the current UI.
    System.theme = normalized
    System.startupTheme = normalized
    setSessionTheme(normalized)

    local okApply, applyErr = pcall(function()
        Theme.apply(normalized)
        System.theme = normalized
        System.startupTheme = normalized
        Theme.syncAllThemeVisuals()
        Theme.hardResetControls()
        if normalized == "Empyrean" and Theme.syncEmpyreanControls then
            Theme.syncEmpyreanControls()
        end
    end)

    local saved = true
    if type(System.savePrefs) == "function" then
        saved = System.savePrefs() ~= false
    end

    -- Theme.apply contains legacy visual code. A failure in any optional visual
    -- object must not leave the current theme half-applied, so run the isolated
    -- final pass regardless of whether the legacy pass threw.
    pcall(function() Theme.forceThemeControls() end)
    pcall(function() Theme.canonicalizeControls() end)
    if System.theme=="Frost" then pcall(function() Theme.applyFrostFinal() end) end

    if not okApply then
        warn("[Void Automation] legacy theme visual pass skipped: " .. tostring(applyErr))
    end

    -- Session persistence is successful even when the executor's file API is
    -- unavailable. Never claim that the selection was not saved in-session.
    notify("Theme saved: " .. normalized)
    pcall(function() if MiniMode and MiniMode.applyTheme then MiniMode.applyTheme() end end)
    render()
end


local function renderPageState()
    if not State.alive then return end
    local running, statusName, description = availability()
    local count = selectedCount()
    local mainColor = State.fault and C.red or (running and C.green or (State.enabled and C.amber or C.faint))
    UI.badge.Text = State.fault and "ERROR" or (State.tab == "Skills" and (running and "SYNCED" or "PAUSED")
        or State.tab == "Farm" and (Settings.AutoBoss and "BOSS" or Settings.FarmEnabled and "FARM" or "SYNCED")
        or State.tab == "ESP" and (Settings.ESPEnabled and "ESP" or "SYNCED")
        or State.tab == "Health" and (Settings.HealthEscapeEnabled and "HP" or "SYNCED")
        or State.tab == "Move" and (Settings.FlyEnabled and "FLY" or Settings.NoClip and "MOVE" or "SYNCED")
        or State.tab == "Theme" and (System.theme == "Blackhole" and "BLACKHOLE" or (System.theme == "Empyrean" and "EMPYREAN" or (System.theme == "Frost" and "FROST" or "DEFAULT")))
        or "SYNCED")
    UI.badge.TextColor3 = mainColor
    statusDot.BackgroundColor3 = mainColor
    UI.count.Text = tostring(count) .. " / 4 ENABLED"
    UI.cycle.Text = count > 0 and string.format("~ %.2f s / cycle", count * (Settings.HoldTime + Settings.KeyGap)) or "No keys selected"
    UI.status.Text = statusName
    UI.detail.Text = description
    UI.statusDot.BackgroundColor3 = mainColor

    UI.espCount.Text = tostring(State.espCount) .. " TRACKED"
    UI.espDetail.Text = State.espFault or (Settings.ESPEnabled and "ESP active" or "Turn on Player ESP or press F8.")
    UI.espStatus.Text = State.espFault and "ESP ERROR" or (Settings.ESPEnabled and "ESP ACTIVE" or "ESP OFF")
    UI.espStatusDot.BackgroundColor3 = State.espFault and C.red or (Settings.ESPEnabled and C.green or C.faint)

    UI.healthStatus.Text = Guard.status
    UI.healthDetail.Text = Guard.detail
    UI.healthSource.Text = Guard.sourceLabel
    UI.healthSourceDetail.Text = Guard.sourceDetail
    UI.healthRearm.Text = string.format("Re-arm at %.0f%% health.", Settings.HealthThreshold + 5)
    UI.healthNumbers.Text = Guard.current and string.format("%.0f / %.0f HP", Guard.current, Guard.maximum) or "-- / -- HP"
    UI.healthPercent.Text = Guard.percent and string.format("%.1f%%", Guard.percent) or "--%"
    UI.healthFill.Size = UDim2.fromScale(math.clamp((Guard.percent or 0) / 100, 0, 1), 1)
    UI.healthMarker.Position = UDim2.new(math.clamp(Settings.HealthThreshold / 100, 0, 1), 0, 0, -3)
    UI.healthRelease.Text = Guard.held and "LOCKED" or "RELEASED"

    UI.farmHint.Text = Settings.AutoBoss and string.format("Auto Boss active - %d saved locations.", #Farm.remembered)
        or "Automate farming, bosses and loot collection."
    local remembered = Farm.pinned and Farm.catalog[Farm.pinned]
    UI.farmName.Text = remembered and remembered.name or (Farm.selected and Farm.selected.name or (Settings.AutoBoss and "Finding next boss" or "None"))
    UI.farmID.Text = Farm.selected and Farm.selected.id or "--"
    UI.farmPath.Text = Farm.selected and Farm.selected.path or "Replicated NPCs"
    local targetHP, targetMax = Farm.read(Farm.selected)
    UI.farmHP.Text = targetHP and string.format("%.0f / %.0f HP", targetHP, targetMax) or "Unavailable"
    UI.farmParts.Text = Farm.detail or ""
    UI.farmStatus.Text = Farm.status or "OFF"
    UI.farmDetail.Text = Farm.detail or ""
    UI.refTargetName.Text = UI.farmName.Text
    UI.refBossDelay.Text = string.format("%.1f", Settings.BossNoAttackTimeout)
    UI.refRunDot.BackgroundColor3 = (Settings.FarmEnabled or Settings.AutoBoss) and C.green or C.faint
    UI.refElapsed.Text = string.format("%02d:%02d:%02d", math.floor(os.clock()/3600)%100, math.floor(os.clock()/60)%60, math.floor(os.clock())%60)

    UI.moveStatus.Text = Movement.status
    UI.moveDetail.Text = Movement.detail
    UI.moveStatusDot.BackgroundColor3 = (Settings.FlyEnabled or Settings.SpeedEnabled or Settings.NoClip) and C.green or C.faint
    UI.systemStatus.Text = System.status
    UI.systemDetail.Text = System.persistStatus .. "\n" .. System.friendReadyStatus
    UI.systemStatusDot.BackgroundColor3 = (Settings.StaticMapScan or Settings.AutoRejoin or Settings.AutoExecute) and C.green or C.faint
    UI.staticScanButton.Text = Farm.staticScanBusy and "SCANNING..." or "SCAN MAP NOW"
    UI.staticScanStatus.Text = Farm.staticScanStatus
    UI.rejoinStatus.Text = System.rejoinStatus
    if Input:GetFocusedTextBox() ~= UI.privateMapBox then UI.privateMapBox.Text = Settings.PrivateServerMap end

    for _, view in ipairs(toggleViews) do
        local value = view.getter()
        if view.last ~= value then
            view.last = value
            view.track.BackgroundColor3 = value and C.toggleOn or C.toggleOff
            view.knob.Position = UDim2.fromOffset(value and 22 or 3, 3)
            view.knob.BackgroundColor3 = value and (System.theme == "Empyrean" and C.bright or C.cyan) or C.faint
        end
    end
    for _, view in ipairs(sliders) do
        local value = view.getter()
        local fraction = math.clamp((value - view.minimum) / (view.maximum - view.minimum), 0, 1)
        view.valueLabel.Text = string.format(view.format, value)
        view.fill.Size = UDim2.new(fraction, 0, 1, 0)
        view.knob.Position = UDim2.new(fraction, -7, 0.5, -7)
    end
    updateTabVisuals()
    if Theme.syncAllThemeVisuals then Theme.syncAllThemeVisuals() end
    if Theme.canonicalizeControls then Theme.canonicalizeControls() end
    if System.theme=="Frost" and Theme.applyFrostFinal then pcall(function() Theme.applyFrostFinal() end) end
end

local uiRenderError = nil
local rawRenderPageState = renderPageState
render = function()
    local ok, err = pcall(rawRenderPageState)
    if not ok then
        uiRenderError = tostring(err)
    end
    return ok
end

if System.theme=="Empyrean" and EMP.ensureVisuals then
    task.defer(function() if State.alive then EMP.ensureVisuals() end end)
end

showPage("Skills")
connect(UI.badge.Activated, function()
    if State.tab == "ESP" then setESPEnabled(not Settings.ESPEnabled)
    elseif State.tab == "Farm" then Farm.setEnabled(not Settings.FarmEnabled)
    elseif State.tab == "Health" then Guard.setEnabled(not Settings.HealthEscapeEnabled)
    elseif State.tab == "Move" then Movement.setFly(not Settings.FlyEnabled)
    elseif State.tab == "System" then System.setAutoRejoin(not Settings.AutoRejoin)
    else setEnabled(not State.enabled) end
end)
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        State.gesture = {kind = "window", input = input, start = input.Position,
            x = holder.Position.X.Offset, y = holder.Position.Y.Offset}
    end
end)
connect(Input.InputChanged, function(input)
    local gesture = State.gesture
    if not gesture then return end
    local mouseMove = gesture.input.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseMovement
    if not mouseMove and input ~= gesture.input then return end
    if gesture.kind == "slider" then
        gesture.view.updateFromX(input.Position.X)
    elseif gesture.kind == "resize" then
        local deltaX = input.Position.X - gesture.start.X
        local viewport = canvas.AbsoluteSize
        local maxWidth = math.max(MIN_WINDOW_WIDTH, viewport.X - holder.Position.X.Offset - 8)

        windowWidth = math.clamp(gesture.width + deltaX, MIN_WINDOW_WIDTH, maxWidth)
        applyWindowWidth(windowWidth)
        fitWindow(false)
    elseif gesture.kind == "window" then
        local delta = input.Position - gesture.start
        holder.Position = UDim2.fromOffset(gesture.x + delta.X, gesture.y + delta.Y)
        fitWindow(false)
    end
end)
connect(Input.InputEnded, function(input)
    local gesture = State.gesture
    if gesture and (input == gesture.input or (input.UserInputType == Enum.UserInputType.MouseButton1
        and gesture.input.UserInputType == Enum.UserInputType.MouseButton1)) then
        State.gesture = nil
        render()
    end
end)
connect(canvas:GetPropertyChangedSignal("AbsoluteSize"), function() fitWindow(false) end)
-- EMPYREAN layout is driven only by the logical window width. Do not attach
-- a geometry feedback loop to EMP.hero.AbsoluteSize; visibility/presentation
-- changes must never become layout inputs.
-- Startup is intentionally ordered: persisted theme -> theme application -> loader.
-- Do not render the Default theme first; doing so can leave stale theme visuals behind.
fitWindow(true)
local __startupTheme = System.startupTheme
local __themeOK, __themeERR = pcall(function() Theme.apply(__startupTheme) end)
pcall(function() if Theme.forceThemeControls then Theme.forceThemeControls() end end)
pcall(function() if System.theme=="Frost" and Theme.applyFrostFinal then Theme.applyFrostFinal() end end)
if not __themeOK then
    warn("[Void Automation] Theme initialization failed for saved theme " .. tostring(__startupTheme) .. ": " .. tostring(__themeERR))
    -- Never substitute Default for a persisted theme. The loader and UI must
    -- remain on the same theme even if one cosmetic pass fails.
    System.startupTheme = __startupTheme
    System.theme = __startupTheme
    pcall(function()
        local selected = __startupTheme
        Theme.current = selected == "Blackhole" and Theme.Blackhole or (selected == "Empyrean" and Theme.Empyrean or (selected == "Frost" and Theme.Frost or Theme.Default))
        Theme.copy(Theme.current)
        Theme.hardResetControls()
        render()
    end)
end

do
    local __loaderLayer
    local __loaderOK, __loaderERR = pcall(function()
        __loaderLayer = make("Frame", loaderCanvas, {
            Name = "VoidLoading", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.fromRGB(1, 1, 4), BackgroundTransparency = 0.06,
            BorderSizePixel = 0, Active = true, ZIndex = 100,
        })
        local loadingLayer = __loaderLayer

        local startupTheme = System.startupTheme
        if startupTheme == "Empyrean" then
            loadingLayer.BackgroundColor3 = Color3.fromRGB(247,242,226); loadingLayer.BackgroundTransparency=0.02
            local loadCard=frame(loadingLayer,"LoadingCard",0,0,326,402,Color3.fromRGB(255,253,247),18); loadCard.AnchorPoint=Vector2.new(.5,.5); loadCard.Position=UDim2.fromScale(.5,.5); loadCard.BackgroundTransparency=.08; loadCard.ZIndex=101; stroke(loadCard,Color3.fromRGB(217,169,78),.34,1)
            local loadScale=make("UIScale",loadCard,{Scale=.88}); TweenService:Create(loadScale,TweenInfo.new(.62,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
            local loadTitle=safeText(loadCard,"Title","EMPYREAN",0,16,326,22,17,Color3.fromRGB(58,47,26),Enum.Font.GothamBold); loadTitle.TextXAlignment=Enum.TextXAlignment.Center; loadTitle.ZIndex=103
            local loadSub=safeText(loadCard,"Sub","GRACE ATTAINED",0,40,326,16,8,Color3.fromRGB(122,108,74),Enum.Font.GothamBold); loadSub.TextXAlignment=Enum.TextXAlignment.Center; loadSub.ZIndex=103
            local symbol=frame(loadCard,"Symbol",0,0,220,220,Color3.new(1,1,1),110); symbol.AnchorPoint=Vector2.new(.5,.5); symbol.Position=UDim2.new(.5,0,0,156); symbol.BackgroundTransparency=1; symbol.ZIndex=102
            local bloom=frame(symbol,"Bloom",0,0,140,140,Color3.fromRGB(255,224,150),70); bloom.AnchorPoint=Vector2.new(.5,.5); bloom.Position=UDim2.fromScale(.5,.5); bloom.BackgroundTransparency=.90; bloom.ZIndex=102
            local guide=frame(symbol,"Guide",0,0,160,160,Color3.new(1,1,1),80); guide.AnchorPoint=Vector2.new(.5,.5); guide.Position=UDim2.fromScale(.5,.5); guide.BackgroundTransparency=1; guide.ZIndex=103; stroke(guide,Color3.fromRGB(242,193,78),.82,1)
            local ticks={}; for i=1,8 do local tick=frame(symbol,"Tick"..i,0,0,2,14,Color3.fromRGB(217,169,78),1); tick.AnchorPoint=Vector2.new(.5,.5); tick.Position=UDim2.fromScale(.5,.5); tick.Rotation=(i-1)*45; tick.ZIndex=105; ticks[#ticks+1]=tick end
            local outer=frame(symbol,"OuterArc",0,0,126,126,Color3.new(1,1,1),63); outer.AnchorPoint=Vector2.new(.5,.5); outer.Position=UDim2.fromScale(.5,.5); outer.BackgroundTransparency=1; outer.ZIndex=106
            local outerSegments={}; for i=1,24 do local a=((i-1)/24)*math.pi*2; local seg=frame(outer,"Seg"..i,0,0,18,3.2,Color3.fromRGB(217,169,78),1); seg.AnchorPoint=Vector2.new(.5,.5); seg.Position=UDim2.fromScale(.5,.5); seg.Rotation=math.deg(a); seg.BackgroundTransparency=(i<=7 and .08 or .96); seg.ZIndex=106; outerSegments[#outerSegments+1]=seg end
            local inner=frame(symbol,"InnerArc",0,0,94,94,Color3.new(1,1,1),47); inner.AnchorPoint=Vector2.new(.5,.5); inner.Position=UDim2.fromScale(.5,.5); inner.BackgroundTransparency=1; inner.ZIndex=107
            local innerSegments={}; for i=1,24 do local a=((i-1)/24)*math.pi*2; local seg=frame(inner,"Seg"..i,0,0,12,1.4,Color3.fromRGB(255,243,200),1); seg.AnchorPoint=Vector2.new(.5,.5); seg.Position=UDim2.fromScale(.5,.5); seg.Rotation=math.deg(a); seg.BackgroundTransparency=(i<=5 and .24 or .96); seg.ZIndex=107; innerSegments[#innerSegments+1]=seg end
            local dot=frame(symbol,"CoreDot",0,0,10,10,Color3.fromRGB(255,254,248),5); dot.AnchorPoint=Vector2.new(.5,.5); dot.Position=UDim2.fromScale(.5,.5); dot.ZIndex=108
            local sparks={}; for i,pos in ipairs({{.5,.17},{.83,.5},{.5,.83},{.17,.5}}) do local sp=frame(symbol,"Spark"..i,0,0,4,4,Color3.fromRGB(255,243,200),2); sp.AnchorPoint=Vector2.new(.5,.5); sp.Position=UDim2.fromScale(pos[1],pos[2]); sp.ZIndex=109; sparks[#sparks+1]={object=sp,phase=(i-1)*.4} end
            local loadStatus=safeText(loadCard,"Status","ASCENDING...",0,286,326,18,9,Color3.fromRGB(156,116,32),Enum.Font.GothamBold); loadStatus.TextXAlignment=Enum.TextXAlignment.Center; loadStatus.ZIndex=121
            local loadRail=frame(loadCard,"Rail",39,318,248,4,Color3.fromRGB(231,224,205),2); loadRail.ZIndex=121; local loadFill=frame(loadRail,"Fill",0,0,0,4,Color3.fromRGB(217,169,78),2); loadFill.ZIndex=122
            local loadPercent=safeText(loadCard,"Percent","0%",0,330,326,16,8,Color3.fromRGB(122,108,74),Enum.Font.GothamMedium); loadPercent.TextXAlignment=Enum.TextXAlignment.Center; loadPercent.ZIndex=121
            local loadHint=safeText(loadCard,"Hint","EMPYREAN // CELESTIAL LINK",0,365,326,14,7,Color3.fromRGB(171,157,120),Enum.Font.GothamMedium); loadHint.TextXAlignment=Enum.TextXAlignment.Center; loadHint.ZIndex=121
            local loadStart=os.clock(); local loadDuration=2.65; local loadAnimConn
            loadAnimConn=connect(RunService.RenderStepped,function()
                if not State.alive or not loadingLayer.Parent then if loadAnimConn then loadAnimConn:Disconnect() end; return end
                local elapsed=os.clock()-loadStart; local progress=math.clamp(elapsed/loadDuration,0,1); local pulse=(math.sin(elapsed*math.pi*2/1.8)+1)*.5
                bloom.BackgroundTransparency=.95-pulse*.10; outer.Rotation=elapsed*(360/1.4); inner.Rotation=-elapsed*(360/3.6); guide.Rotation=-elapsed*2
                local arcHead=(math.floor(elapsed*24/1.4)%24)+1; for i,seg in ipairs(outerSegments) do local d=(i-arcHead)%24; seg.BackgroundTransparency=d<7 and(.06+d*.035)or .97 end
                local innerHead=(math.floor(elapsed*24/3.6)%24)+1; for i,seg in ipairs(innerSegments) do local d=(i-innerHead)%24; seg.BackgroundTransparency=d<5 and(.22+d*.06)or .97 end
                for i,tick in ipairs(ticks) do tick.BackgroundTransparency=.70-((math.sin(elapsed*math.pi*2/1.8+i)+1)*.5)*.45 end
                for _,info in ipairs(sparks) do local q=(math.sin((elapsed+info.phase)*math.pi*2/1.6)+1)*.5; info.object.BackgroundTransparency=.80-q*.65; info.object.Size=UDim2.fromOffset(2+3*q,2+3*q) end
                local stages={{0,"ASCENDING..."},{.18,"AWAKENING CELESTIAL CORE..."},{.37,"ALIGNING HALO RINGS..."},{.56,"OPENING THE EMPYREAN..."},{.75,"SYNCHRONIZING GRACE..."},{.90,"EMPYREAN ONLINE"}}; loadStatus.Text=stages[1][2]; for i=#stages,1,-1 do if progress>=stages[i][1] then loadStatus.Text=stages[i][2]; break end end
                loadFill.Size=UDim2.new(progress,0,1,0); loadPercent.Text=string.format("%d%%",math.floor(progress*100+.5))
                if progress>=1 then
                    loadAnimConn:Disconnect(); loadStatus.Text="EMPYREAN ONLINE"; task.wait(.10); if not State.alive then return end; TweenService:Create(loadScale,TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Scale=.78}):Play(); TweenService:Create(loadingLayer,TweenInfo.new(.32,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{BackgroundTransparency=1}):Play()
                    task.delay(.36,function() if not State.alive then return end; if loaderRoot and loaderRoot.Parent then loaderRoot.Enabled=false end; if loadingLayer and loadingLayer.Parent then loadingLayer:Destroy() end; holder.Visible=true; root.Enabled=true; if System.theme=="Empyrean" and EMP.ensureVisuals then EMP.ensureVisuals() end; local bootStroke=panel:FindFirstChildOfClass("UIStroke"); if bootStroke then bootStroke.Transparency=1; TweenService:Create(bootStroke,TweenInfo.new(.55,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Transparency=.38}):Play() end; if loaderRoot and loaderRoot.Parent then loaderRoot:Destroy() end end)
                end
            end)
        elseif startupTheme == "Frost" then
            -- FROSTBOUND loader: derived from the Frost Glacial loading reference.
            loadingLayer.BackgroundTransparency=1
            local loadCard=frame(loadingLayer,"LoadingCard",0,0,310,370,Color3.fromRGB(20,48,57),18)
            loadCard.AnchorPoint=Vector2.new(.5,.5); loadCard.Position=UDim2.fromScale(.5,.5); loadCard.BackgroundTransparency=.05; loadCard.ZIndex=101
            stroke(loadCard,Color3.fromRGB(153,211,222),.34,1)
            local loadScale=make("UIScale",loadCard,{Scale=.90})
            TweenService:Create(loadScale,TweenInfo.new(.55,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
            local loadTitle=safeText(loadCard,"Title","FROSTBOUND",0,17,310,22,17,Color3.fromRGB(234,250,255),Enum.Font.GothamBold); loadTitle.TextXAlignment=Enum.TextXAlignment.Center; loadTitle.ZIndex=103
            local loadSub=safeText(loadCard,"Sub","ENTERING THE SANCTUM",0,42,310,16,8,Color3.fromRGB(151,192,202),Enum.Font.GothamBold); loadSub.TextXAlignment=Enum.TextXAlignment.Center; loadSub.ZIndex=103
            local symbol=frame(loadCard,"Symbol",0,0,190,190,Color3.new(1,1,1),95); symbol.AnchorPoint=Vector2.new(.5,.5); symbol.Position=UDim2.new(.5,0,0,164); symbol.BackgroundTransparency=1; symbol.ZIndex=102
            local ring=frame(symbol,"Ring",0,0,128,128,Color3.new(1,1,1),64); ring.AnchorPoint=Vector2.new(.5,.5); ring.Position=UDim2.fromScale(.5,.5); ring.BackgroundTransparency=1; ring.ZIndex=103; stroke(ring,Color3.fromRGB(153,211,222),.72,1)
            local ring2=frame(symbol,"Ring2",0,0,96,96,Color3.new(1,1,1),48); ring2.AnchorPoint=Vector2.new(.5,.5); ring2.Position=UDim2.fromScale(.5,.5); ring2.BackgroundTransparency=1; ring2.ZIndex=103; stroke(ring2,Color3.fromRGB(223,249,255),.80,1)
            local crystal=frame(symbol,"Crystal",0,0,64,64,Color3.fromRGB(223,249,255),10); crystal.AnchorPoint=Vector2.new(.5,.5); crystal.Position=UDim2.fromScale(.5,.5); crystal.Rotation=45; crystal.BackgroundTransparency=.06; crystal.ZIndex=104; stroke(crystal,Color3.fromRGB(173,224,235),.20,1)
            local core=frame(symbol,"Core",0,0,17,17,Color3.fromRGB(240,253,255),9); core.AnchorPoint=Vector2.new(.5,.5); core.Position=UDim2.fromScale(.5,.5); core.ZIndex=105
            local flakes={}; for i,pos in ipairs({{.20,.26},{.80,.35},{.26,.75},{.75,.78}}) do local f=frame(symbol,"Flake"..i,0,0,4,4,Color3.fromRGB(223,249,255),2); f.AnchorPoint=Vector2.new(.5,.5); f.Position=UDim2.fromScale(pos[1],pos[2]); f.ZIndex=106; flakes[#flakes+1]={o=f,p=(i-1)*.45} end
            local loadStatus=safeText(loadCard,"Status","FROST AWAKENING...",0,278,310,18,9,Color3.fromRGB(173,224,235),Enum.Font.GothamBold); loadStatus.TextXAlignment=Enum.TextXAlignment.Center; loadStatus.ZIndex=121
            local rail=frame(loadCard,"Rail",40,311,230,3,Color3.fromRGB(47,79,87),2); rail.ZIndex=121; local fill=frame(rail,"Fill",0,0,0,3,Color3.fromRGB(173,224,235),2); fill.ZIndex=122
            local percent=safeText(loadCard,"Percent","0%",0,324,310,16,8,Color3.fromRGB(151,192,202),Enum.Font.GothamMedium); percent.TextXAlignment=Enum.TextXAlignment.Center; percent.ZIndex=121
            local hint=safeText(loadCard,"Hint","FROST / GLACIAL",0,350,310,14,7,Color3.fromRGB(113,157,168),Enum.Font.GothamMedium); hint.TextXAlignment=Enum.TextXAlignment.Center; hint.ZIndex=121
            local start=os.clock(); local duration=2.55; local conn
            conn=connect(RunService.RenderStepped,function()
                if not State.alive or not loadingLayer.Parent then if conn then conn:Disconnect() end; return end
                local elapsed=os.clock()-start; local progress=math.clamp(elapsed/duration,0,1); local pulse=(math.sin(elapsed*math.pi*2/2.2)+1)*.5
                crystal.Rotation=45+math.sin(elapsed*.75)*7; crystal.BackgroundTransparency=.10-pulse*.035; core.Size=UDim2.fromOffset(13+math.floor(pulse*8),13+math.floor(pulse*8)); core.BackgroundTransparency=.05+pulse*.08
                ring.Rotation=elapsed*18; ring2.Rotation=-elapsed*28
                for i,info in ipairs(flakes) do local q=(math.sin(elapsed*2+info.p)+1)*.5; info.o.BackgroundTransparency=.35+q*.5; info.o.Position=UDim2.fromScale(info.o.Position.X.Scale,info.o.Position.Y.Scale+math.sin(elapsed*.8+info.p)*.002) end
                local stages={{0,"FROST AWAKENING..."},{.20,"ALIGNING CRYSTAL..."},{.42,"OPENING THE SANCTUM..."},{.64,"SYNCHRONIZING ICE..."},{.84,"THE FROST REMAINS STILL..."},{.94,"FROSTBOUND ONLINE"}}; for i=#stages,1,-1 do if progress>=stages[i][1] then loadStatus.Text=stages[i][2]; break end end
                fill.Size=UDim2.new(progress,0,1,0); percent.Text=string.format("%d%%",math.floor(progress*100+.5))
                if progress>=1 then
                    conn:Disconnect(); loadStatus.Text="FROSTBOUND ONLINE"; task.wait(.10); if not State.alive then return end
                    TweenService:Create(loadScale,TweenInfo.new(.24,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Scale=.82}):Play(); TweenService:Create(loadingLayer,TweenInfo.new(.30,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{BackgroundTransparency=1}):Play()
                    task.delay(.34,function() if not State.alive then return end; if loaderRoot and loaderRoot.Parent then loaderRoot.Enabled=false end; if loadingLayer and loadingLayer.Parent then loadingLayer:Destroy() end; holder.Visible=true; root.Enabled=true; if System.theme=="Frost" then pcall(function() Theme.applyFrostFinal() end) end; if loaderRoot and loaderRoot.Parent then loaderRoot:Destroy() end end)
                end
            end)
        elseif startupTheme == "Blackhole" then

        -- BLACKHOLE V1 loader. This branch is intentionally Blackhole-only.
        -- VOID NEXUS has its own loader below and never shares this animation.
        -- 220x220 singularity, deep-space bloom, accretion disk, lens arc,
        -- split photon ring, distant stars and slow breathing/flicker motion.
        local loadCard = frame(loadingLayer, "LoadingCard", 0, 0, 326, 402, Color3.fromRGB(5, 3, 11), 18)
        loadCard.AnchorPoint = Vector2.new(0.5, 0.5)
        loadCard.Position = UDim2.fromScale(0.5, 0.5)
        loadCard.BackgroundTransparency = 0.08
        loadCard.ZIndex = 101
        stroke(loadCard, Color3.fromRGB(104, 63, 160), 0.34, 1)

        local loadScale = make("UIScale", loadCard, {Scale = 0.88})
        TweenService:Create(loadScale, TweenInfo.new(0.62, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()

        local loadTitle = safeText(loadCard, "Title", startupTheme == "Blackhole" and "BLACKHOLE V1" or "VOID NEXUS", 0, 16, 326, 22, 17, C.ink, Enum.Font.GothamBold)
        loadTitle.TextXAlignment = Enum.TextXAlignment.Center
        loadTitle.ZIndex = 103

        local loadSub = safeText(loadCard, "Sub", startupTheme == "Blackhole" and "GALACTIC REACTOR" or "VOID CORE ONLINE", 0, 40, 326, 16, 8, C.dim, Enum.Font.GothamBold)
        loadSub.TextXAlignment = Enum.TextXAlignment.Center
        loadSub.ZIndex = 103

        local symbol = frame(loadCard, "Symbol", 0, 0, 220, 220, C.black, 110)
        symbol.AnchorPoint = Vector2.new(0.5, 0.5)
        symbol.Position = UDim2.new(0.5, 0, 0, 156)
        symbol.BackgroundTransparency = 1
        symbol.ZIndex = 102

        local WHITE = Color3.fromRGB(255, 243, 214)
        local STAR = Color3.fromRGB(231, 217, 255)
        local PURPLE = Color3.fromRGB(123, 47, 247)
        local PURPLE_DARK = Color3.fromRGB(76, 20, 140)
        local MAGENTA = Color3.fromRGB(201, 98, 154)
        local BLACK = Color3.fromRGB(0, 0, 0)

        local function circle(parent, name, diameter, color, transparency, z)
            local f = frame(parent, name, 0, 0, diameter, diameter, color, math.floor(diameter / 2))
            f.AnchorPoint = Vector2.new(0.5, 0.5)
            f.Position = UDim2.fromScale(0.5, 0.5)
            f.BackgroundTransparency = transparency == nil and 1 or transparency
            f.ZIndex = z or 102
            return f
        end

        local function line(parent, name, x, y, w, h, color, transparency, z, rotation)
            local f = frame(parent, name, x, y, w, h, color, math.floor(math.min(w, h) / 2))
            f.AnchorPoint = Vector2.new(0.5, 0.5)
            f.BackgroundTransparency = transparency == nil and 0 or transparency
            f.ZIndex = z or 105
            f.Rotation = rotation or 0
            return f
        end

        -- Deep-space bloom behind the system.
        local bloomOuter = circle(symbol, "BloomOuter", 194, Color3.fromRGB(42, 16, 80), 0.94, 102)
        local bloomMid = circle(symbol, "BloomMid", 164, Color3.fromRGB(21, 7, 48), 0.84, 103)
        local bloomInner = circle(symbol, "BloomInner", 132, Color3.fromRGB(20, 8, 38), 0.72, 104)

        -- Four distant stars from the SVG.
        local stars = {}
        local starData = {
            {30, 46, 2.2, 0.2}, {190, 34, 2.6, 1.1},
            {26, 176, 2.0, 1.8}, {196, 182, 2.4, 0.7},
        }
        for i, d in ipairs(starData) do
            local star = circle(symbol, "Star" .. i, d[3], STAR, 0.25, 106)
            star.Position = UDim2.fromOffset(d[1], d[2])
            stars[#stars + 1] = {object = star, phase = d[4]}
        end

        -- Everything below this point belongs to the breathing SVG "system" group.
        local system = frame(symbol, "System", 0, 0, 220, 220, BLACK, 0)
        system.BackgroundTransparency = 1
        system.ZIndex = 107
        local systemScale = make("UIScale", system, {Scale = 1})

        -- Accretion disk: many small curved dashes approximate the SVG stroke-dasharray.
        local diskGroup = frame(system, "AccretionDisk", 0, 0, 220, 220, BLACK, 0)
        diskGroup.BackgroundTransparency = 1
        diskGroup.ZIndex = 108
        local diskDashes = {}
        local diskCount = 34
        for i = 1, diskCount do
            local t = ((i - 1) / diskCount) * math.pi * 2
            local rx, ry = 98, 24
            local px = 110 + math.cos(t) * rx
            local py = 110 + math.sin(t) * ry
            local dx = -rx * math.sin(t)
            local dy = ry * math.cos(t)
            local tangent = math.deg(math.atan2(dy, dx))
            local col
            local normalized = (math.cos(t) + 1) * 0.5
            if normalized > 0.70 then
                col = PURPLE_DARK
            elseif normalized > 0.43 then
                col = MAGENTA
            else
                col = WHITE
            end
            local dash = line(diskGroup, "Dash" .. i, px, py, 10 + (i % 3) * 2, 6, col, 0.28, 108, tangent)
            dash.BackgroundTransparency = 0.34
            diskDashes[#diskDashes + 1] = dash
        end
        diskGroup.Rotation = -7

        -- Lensed far-side arc above the horizon.
        local lensGroup = frame(system, "LensArc", 0, 0, 220, 220, BLACK, 0)
        lensGroup.BackgroundTransparency = 1
        lensGroup.ZIndex = 110
        local lensSegments = {}
        local lensCount = 22
        for i = 1, lensCount do
            local t1 = math.pi + ((i - 1) / lensCount) * math.pi
            local t2 = math.pi + (i / lensCount) * math.pi
            local rx, ry = 46, 15
            local x1, y1 = 110 + math.cos(t1) * rx, 78 + math.sin(t1) * ry
            local x2, y2 = 110 + math.cos(t2) * rx, 78 + math.sin(t2) * ry
            local dx, dy = x2 - x1, y2 - y1
            local len = math.sqrt(dx * dx + dy * dy)
            local angle = math.deg(math.atan2(dy, dx))
            local mix = i / lensCount
            local col = mix < 0.5 and WHITE or PURPLE
            local seg = line(lensGroup, "Lens" .. i, (x1 + x2) * 0.5, (y1 + y2) * 0.5, len + 1, 2.6, col, 0.30 + mix * 0.25, 110, angle)
            lensSegments[#lensSegments + 1] = seg
        end

        -- True black event horizon.
        local eventHorizon = circle(system, "EventHorizon", 100, BLACK, 0, 112)

        -- Photon ring: bright cream/white approaching side and purple receding side.
        local photonGroup = frame(system, "PhotonRing", 0, 0, 220, 220, BLACK, 0)
        photonGroup.BackgroundTransparency = 1
        photonGroup.ZIndex = 113
        local photonSegments = {}
        local photonCount = 44
        for i = 1, photonCount do
            local t = ((i - 1) / photonCount) * math.pi * 2
            local r = 51
            local px = 110 + math.cos(t) * r
            local py = 110 + math.sin(t) * r
            local tangent = math.deg(t + math.pi * 0.5)
            local col = math.sin(t) < 0 and WHITE or PURPLE
            local seg = line(photonGroup, "Photon" .. i, px, py, 4.4, 1.8, col, math.sin(t) < 0 and 0.04 or 0.32, 113, tangent)
            photonSegments[#photonSegments + 1] = seg
        end

        -- Small moving glow at the singularity.
        local coreBloom = circle(system, "CoreBloom", 78, Color3.fromRGB(42, 16, 80), 0.72, 114)
        local coreBloom2 = circle(system, "CoreBloom2", 66, Color3.fromRGB(123, 47, 247), 0.82, 115)
        local core = circle(system, "Core", 100, BLACK, 0, 116)

        local loadStatus = safeText(loadCard, "Status", "OPENING THE VOID...", 0, 286, 326, 18, 9, C.bright, Enum.Font.GothamBold)
        loadStatus.TextXAlignment = Enum.TextXAlignment.Center
        loadStatus.ZIndex = 121

        local loadRail = frame(loadCard, "Rail", 39, 318, 248, 4, Color3.fromRGB(27, 16, 44), 2)
        loadRail.ZIndex = 121
        local loadFill = frame(loadRail, "Fill", 0, 0, 0, 4, Color3.fromRGB(123, 47, 247), 2)
        loadFill.ZIndex = 122
        local loadPercent = safeText(loadCard, "Percent", "0%", 0, 330, 326, 16, 8, C.dim, Enum.Font.GothamMedium)
        loadPercent.TextXAlignment = Enum.TextXAlignment.Center
        loadPercent.ZIndex = 121

        local loadHint = safeText(loadCard, "Hint", "VOID NEXUS // GALACTIC LINK", 0, 365, 326, 14, 7, C.dim, Enum.Font.GothamMedium)
        loadHint.TextXAlignment = Enum.TextXAlignment.Center
        loadHint.ZIndex = 121

        local loadStart = os.clock()
        local loadDuration = 2.65
        local loadStages = {
            {0.00, "OPENING THE VOID..."},
            {0.18, "LOCATING SINGULARITY..."},
            {0.37, "IGNITING ACCRETION DISK..."},
            {0.56, "BENDING SPACETIME..."},
            {0.75, "SYNCHRONIZING ORBITAL RINGS..."},
            {0.90, startupTheme == "Blackhole" and "BLACKHOLE V1 ONLINE" or "VOID NEXUS ONLINE"},
        }

        local loadAnimConn
        loadAnimConn = connect(RunService.RenderStepped, function()
            if not State.alive or not loadingLayer.Parent then
                if loadAnimConn then loadAnimConn:Disconnect() end
                return
            end

            local elapsed = os.clock() - loadStart
            local progress = math.clamp(elapsed / loadDuration, 0, 1)

            -- SVG .system breathe animation.
            local breathe = (math.sin(elapsed * math.pi * 2 / 6.5) + 1) * 0.5
            systemScale.Scale = 1 + breathe * 0.025

            -- SVG bloomPulse animation.
            local bloomPulse = (math.sin(elapsed * math.pi * 2 / 7) + 1) * 0.5
            bloomOuter.BackgroundTransparency = 0.95 - bloomPulse * 0.08
            bloomMid.BackgroundTransparency = 0.88 - bloomPulse * 0.08
            bloomInner.BackgroundTransparency = 0.76 - bloomPulse * 0.08

            -- SVG twinkle animation, with the original delays preserved.
            for _, info in ipairs(stars) do
                local pulse = (math.sin((elapsed + info.phase) * math.pi * 2 / 3) + 1) * 0.5
                info.object.BackgroundTransparency = 0.88 - pulse * 0.68
            end

            -- SVG flow approximation: the dashed accretion disk slowly advances around the horizon.
            diskGroup.Rotation = -7 + elapsed * (360 / 5.5)
            for i, dash in ipairs(diskDashes) do
                local phase = ((i - 1) / diskCount) * math.pi * 2
                local pulse = (math.sin(elapsed * 2.0 + phase) + 1) * 0.5
                dash.BackgroundTransparency = math.clamp(0.62 - pulse * 0.30, 0.22, 0.68)
            end

            -- Lens arc shimmer.
            local arcPulse = (math.sin(elapsed * math.pi * 2 / 4.2) + 1) * 0.5
            for i, seg in ipairs(lensSegments) do
                local p = (i - 1) / math.max(1, #lensSegments - 1)
                seg.BackgroundTransparency = math.clamp(0.52 - arcPulse * 0.30 + p * 0.12, 0.14, 0.68)
            end

            -- Photon-ring flicker/shimmer.
            local ringPulse = (math.sin(elapsed * math.pi * 2 / 3.4) + 1) * 0.5
            for i, seg in ipairs(photonSegments) do
                local p = (i - 1) / photonCount
                local wave = (math.sin(elapsed * 3.0 + p * math.pi * 4) + 1) * 0.5
                seg.BackgroundTransparency = math.clamp(0.38 - ringPulse * 0.28 - wave * 0.12, 0.03, 0.58)
            end

            -- Soft singularity breathing.
            local corePulse = (math.sin(elapsed * math.pi * 2 / 3.8) + 1) * 0.5
            coreBloom.BackgroundTransparency = 0.82 - corePulse * 0.16
            coreBloom2.BackgroundTransparency = 0.88 - corePulse * 0.16

            -- Loading text / progress.
            loadStatus.Text = loadStages[1][2]
            for i = #loadStages, 1, -1 do
                if progress >= loadStages[i][1] then
                    loadStatus.Text = loadStages[i][2]
                    break
                end
            end
            loadFill.Size = UDim2.new(progress, 0, 1, 0)
            loadPercent.Text = string.format("%d%%", math.floor(progress * 100 + 0.5))

            if progress >= 1 then
                loadAnimConn:Disconnect()
                loadStatus.Text = startupTheme == "Blackhole" and "BLACKHOLE V1 ONLINE" or "VOID NEXUS ONLINE"
                task.wait(0.10)
                if not State.alive then return end

                TweenService:Create(loadScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.78}):Play()
                TweenService:Create(loadingLayer, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()

                task.delay(0.36, function()
                    if not State.alive then return end
                    if loaderRoot and loaderRoot.Parent then loaderRoot.Enabled = false end
                    if loadingLayer and loadingLayer.Parent then loadingLayer:Destroy() end

                    holder.Visible = true
                    root.Enabled = true
                    local bootStroke = panel:FindFirstChildOfClass("UIStroke")
                    if bootStroke then
                        bootStroke.Transparency = 1
                        TweenService:Create(bootStroke, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 0.28}):Play()
                    end
                    if loaderRoot and loaderRoot.Parent then loaderRoot:Destroy() end
                end)
            end
        end)

        elseif startupTheme == "Default" then
            -- ================================================================
            -- VOID NEXUS LOADER
            -- Explicit Default/Nexus-only loader.

            -- Dedicated loader for the Default/Nexus theme.
            --
            -- This is a Roblox-native recreation of the supplied
            -- `void-nexus-symbol-animated(1).svg`:
            --   * breathing violet atmospheric bloom
            --   * expanding shock rings
            --   * 8 rotating corona spikes
            --   * three independently rotating accretion disks
            --   * structural/dashed orbital rings
            --   * cardinal reticle ticks
            --   * three orbiting comet particles
            --   * flickering gravitational lens ring
            --   * breathing black event horizon / core
            --
            -- It is deliberately isolated from the Blackhole loader so
            -- Default/Nexus can never inherit Blackhole's loading animation.
            -- ================================================================

            loadingLayer.BackgroundColor3 = Color3.fromRGB(2, 5, 16)
            loadingLayer.BackgroundTransparency = 0.02

            local N = {
                black = Color3.fromRGB(0, 0, 0),
                deep = Color3.fromRGB(4, 2, 12),
                violet = Color3.fromRGB(168, 85, 247),
                violetDeep = Color3.fromRGB(76, 20, 140),
                magenta = Color3.fromRGB(239, 79, 208),
                cyan = Color3.fromRGB(143, 227, 255),
                lavender = Color3.fromRGB(201, 182, 255),
                white = Color3.fromRGB(248, 247, 255),
                text = Color3.fromRGB(235, 231, 250),
                dim = Color3.fromRGB(145, 132, 178),
                rail = Color3.fromRGB(26, 17, 43),
            }

            local loadCard = frame(loadingLayer, "NexusLoadingCard", 0, 0, 326, 402, N.deep, 18)
            loadCard.AnchorPoint = Vector2.new(0.5, 0.5)
            loadCard.Position = UDim2.fromScale(0.5, 0.5)
            loadCard.BackgroundTransparency = 0.05
            loadCard.ZIndex = 101
            stroke(loadCard, Color3.fromRGB(123, 47, 247), 0.22, 1)

            local loadScale = make("UIScale", loadCard, {Scale = 0.88})
            TweenService:Create(loadScale, TweenInfo.new(0.62, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()

            local title = safeText(loadCard, "Title", "VOID NEXUS", 0, 16, 326, 22, 17, N.text, Enum.Font.GothamBold)
            title.TextXAlignment = Enum.TextXAlignment.Center
            title.ZIndex = 130

            local sub = safeText(loadCard, "Sub", "GALACTIC LINK", 0, 40, 326, 16, 8, N.dim, Enum.Font.GothamBold)
            sub.TextXAlignment = Enum.TextXAlignment.Center
            sub.ZIndex = 130

            local symbol = frame(loadCard, "NexusSymbol", 0, 0, 220, 220, N.black, 110)
            symbol.AnchorPoint = Vector2.new(0.5, 0.5)
            symbol.Position = UDim2.new(0.5, 0, 0, 156)
            symbol.BackgroundTransparency = 1
            symbol.ZIndex = 110

            local function nCircle(parent, name, diameter, color, transparency, z)
                local f = frame(parent, name, 0, 0, diameter, diameter, color, math.floor(diameter / 2))
                f.AnchorPoint = Vector2.new(0.5, 0.5)
                f.Position = UDim2.fromScale(0.5, 0.5)
                f.BackgroundTransparency = transparency or 0
                f.ZIndex = z or 112
                return f
            end

            local function nLine(parent, name, x, y, w, h, color, transparency, z, rotation)
                local f = frame(parent, name, x, y, w, h, color, math.max(1, math.floor(math.min(w, h) / 2)))
                f.AnchorPoint = Vector2.new(0.5, 0.5)
                f.BackgroundTransparency = transparency or 0
                f.ZIndex = z or 114
                f.Rotation = rotation or 0
                return f
            end

            -- Atmospheric bloom.
            local bloom = nCircle(symbol, "AtmosphericBloom", 172, N.violetDeep, 0.91, 111)
            local bloom2 = nCircle(symbol, "AtmosphericBloom2", 138, N.violet, 0.97, 112)

            -- Shock rings.
            local shock1 = nCircle(symbol, "ShockRing1", 92, N.lavender, 1, 113)
            shock1.BackgroundTransparency = 1
            stroke(shock1, N.lavender, 0.12, 1.4)

            local shock2 = nCircle(symbol, "ShockRing2", 92, N.cyan, 1, 113)
            shock2.BackgroundTransparency = 1
            stroke(shock2, N.cyan, 0.28, 1.1)

            -- Corona spikes matching the supplied SVG's eight directions.
            local spikes = frame(symbol, "CoronaSpikes", 0, 0, 220, 220, N.black, 0)
            spikes.BackgroundTransparency = 1
            spikes.ZIndex = 114
            local spikeList = {}
            for i = 1, 8 do
                local rotation = (i - 1) * 45
                local col = (i % 3 == 1) and N.cyan or ((i % 3 == 2) and N.magenta or N.violet)
                local sp = nLine(spikes, "Spike" .. i, 157, 110, 94, 2.2, col, 0.35, 114, rotation)
                sp.AnchorPoint = Vector2.new(0.5, 0.5)
                spikeList[#spikeList + 1] = sp
            end

            -- Three broken accretion disks, matching the source SVG's
            -- different directions and speeds.
            local diskA = frame(symbol, "DiskA", 0, 0, 220, 220, N.black, 0)
            diskA.BackgroundTransparency = 1
            diskA.ZIndex = 115

            local diskB = frame(symbol, "DiskB", 0, 0, 220, 220, N.black, 0)
            diskB.BackgroundTransparency = 1
            diskB.ZIndex = 116

            local diskC = frame(symbol, "DiskC", 0, 0, 220, 220, N.black, 0)
            diskC.BackgroundTransparency = 1
            diskC.ZIndex = 117

            local diskSets = {}
            local function buildDisk(parent, count, rx, ry, baseRotation, colorA, colorB, width)
                local set = {}
                for i = 1, count do
                    local t = ((i - 1) / count) * math.pi * 2
                    local px = 110 + math.cos(t) * rx
                    local py = 110 + math.sin(t) * ry
                    local dx = -rx * math.sin(t)
                    local dy = ry * math.cos(t)
                    local tangent = math.deg(math.atan2(dy, dx)) + baseRotation
                    local col = (i / count < 0.5) and colorA or colorB
                    local dash = nLine(
                        parent, "D" .. i, px, py,
                        width + ((i % 3) * 1.3), 2.2,
                        col, 0.25 + ((i % 5) * 0.05), 118, tangent
                    )
                    set[#set + 1] = dash
                end
                return set
            end

            local diskAList = buildDisk(diskA, 38, 90, 32, -18, N.magenta, N.violet, 5)
            local diskBList = buildDisk(diskB, 32, 90, 32, 162, N.cyan, N.lavender, 4)
            local diskCList = buildDisk(diskC, 28, 75, 24, 60, N.lavender, N.magenta, 3)
            diskSets = {diskAList, diskBList, diskCList}

            -- Structural orbital rings.
            local ringOuter = nCircle(symbol, "RingOuter", 196, N.black, 1, 119)
            ringOuter.BackgroundTransparency = 1
            stroke(ringOuter, N.violet, 0.18, 1.5)

            local ringDashed = nCircle(symbol, "RingDashed", 172, N.black, 1, 119)
            ringDashed.BackgroundTransparency = 1
            stroke(ringDashed, N.violet, 0.55, 1)

            local ringDashed2 = nCircle(symbol, "RingDashed2", 128, N.black, 1, 119)
            ringDashed2.BackgroundTransparency = 1
            stroke(ringDashed2, N.magenta, 0.68, 1)

            -- Cardinal reticle.
            local ticks = {}
            for i, rotation in ipairs({0, 90, 180, 270}) do
                local tick = nLine(symbol, "Tick" .. i, 110, 12, 2, 16, N.lavender, 0.12, 120, rotation)
                ticks[#ticks + 1] = tick
            end

            -- Orbiting comet satellites.
            local orbitA = nCircle(symbol, "OrbitA", 7, N.cyan, 0.04, 121)
            orbitA.Position = UDim2.fromOffset(110, 24)
            local orbitB = nCircle(symbol, "OrbitB", 6, N.magenta, 0.08, 121)
            orbitB.Position = UDim2.fromOffset(184, 110)
            local orbitC = nCircle(symbol, "OrbitC", 4, N.lavender, 0.12, 121)
            orbitC.Position = UDim2.fromOffset(110, 42)

            -- Gravitational lens ring.
            local lens = nCircle(symbol, "LensRing", 88, N.white, 1, 122)
            lens.BackgroundTransparency = 1
            stroke(lens, N.white, 0.46, 1.2)

            -- True event horizon / core.
            local coreBloom = nCircle(symbol, "CoreBloom", 106, N.violetDeep, 0.86, 123)
            local coreGlow = nCircle(symbol, "CoreGlow", 82, N.violet, 0.92, 124)
            local eventHorizon = nCircle(symbol, "EventHorizon", 76, N.black, 0, 125)
            local eventPoint = nCircle(symbol, "EventPoint", 20, N.black, 0, 126)

            -- Center highlight from the SVG's event point.
            local centerDot = nCircle(symbol, "CenterDot", 3, N.white, 0.05, 127)

            local status = safeText(loadCard, "Status", "OPENING THE NEXUS...", 0, 286, 326, 18, 9, N.cyan, Enum.Font.GothamBold)
            status.TextXAlignment = Enum.TextXAlignment.Center
            status.ZIndex = 130

            local rail = frame(loadCard, "Rail", 39, 318, 248, 4, N.rail, 2)
            rail.ZIndex = 130
            local fill = frame(rail, "Fill", 0, 0, 0, 4, N.violet, 2)
            fill.ZIndex = 131

            local percent = safeText(loadCard, "Percent", "0%", 0, 330, 326, 16, 8, N.dim, Enum.Font.GothamMedium)
            percent.TextXAlignment = Enum.TextXAlignment.Center
            percent.ZIndex = 130

            local hint = safeText(loadCard, "Hint", "VOID NEXUS // GALACTIC LINK", 0, 365, 326, 14, 7, N.dim, Enum.Font.GothamMedium)
            hint.TextXAlignment = Enum.TextXAlignment.Center
            hint.ZIndex = 130

            local loadStart = os.clock()
            local loadDuration = 2.65
            local stages = {
                {0.00, "OPENING THE NEXUS..."},
                {0.18, "LOCATING SINGULARITY..."},
                {0.37, "IGNITING ACCRETION DISK..."},
                {0.56, "BENDING SPACETIME..."},
                {0.75, "SYNCHRONIZING ORBITAL RINGS..."},
                {0.90, "VOID NEXUS ONLINE"},
            }

            local anim
            anim = connect(RunService.RenderStepped, function()
                if not State.alive or not loadingLayer.Parent then
                    if anim then anim:Disconnect() end
                    return
                end

                local elapsed = os.clock() - loadStart
                local progress = math.clamp(elapsed / loadDuration, 0, 1)

                -- Source-SVG-inspired breathing and rotation.
                local bloomPulse = (math.sin(elapsed * math.pi * 2 / 5) + 1) * 0.5
                bloom.BackgroundTransparency = 0.96 - bloomPulse * 0.12
                bloom2.BackgroundTransparency = 0.98 - bloomPulse * 0.10

                local shockScale = 0.55 + ((elapsed % 3.6) / 3.6) * 1.35
                shock1.Size = UDim2.fromOffset(92 * shockScale, 92 * shockScale)
                shock2.Size = UDim2.fromOffset(92 * math.max(0.55, shockScale - 0.45), 92 * math.max(0.55, shockScale - 0.45))
                shock1.BackgroundTransparency = 1
                shock2.BackgroundTransparency = 1
                local shockPhase = (elapsed % 3.6) / 3.6
                local shockAlpha = 0.10 + shockPhase * 0.82
                local s1 = shock1:FindFirstChildOfClass("UIStroke")
                local s2 = shock2:FindFirstChildOfClass("UIStroke")
                if s1 then s1.Transparency = shockAlpha end
                if s2 then s2.Transparency = math.clamp(shockAlpha + 0.18, 0, 1) end

                spikes.Rotation = elapsed * 6
                for i, sp in ipairs(spikeList) do
                    local q = (math.sin(elapsed * math.pi * 2 / 2.2 + i * 0.55) + 1) * 0.5
                    sp.BackgroundTransparency = 0.68 - q * 0.48
                    sp.Size = UDim2.fromOffset(72 + q * 30, 2.2)
                end

                diskA.Rotation = elapsed * (360 / 7.5)
                diskB.Rotation = -elapsed * (360 / 11.5)
                diskC.Rotation = elapsed * (360 / 17)

                for setIndex, set in ipairs(diskSets) do
                    for i, dash in ipairs(set) do
                        local q = (math.sin(elapsed * (1.4 + setIndex * 0.3) + i * 0.7) + 1) * 0.5
                        dash.BackgroundTransparency = 0.68 - q * 0.48
                    end
                end

                ringOuter.Rotation = elapsed * 2
                ringDashed.Rotation = -elapsed * 12
                ringDashed2.Rotation = elapsed * 8

                for i, tick in ipairs(ticks) do
                    local q = (math.sin(elapsed * 3 + i) + 1) * 0.5
                    tick.BackgroundTransparency = 0.72 - q * 0.46
                end

                local oa = elapsed * (math.pi * 2 / 5)
                local ob = -elapsed * (math.pi * 2 / 8.5)
                local oc = elapsed * (math.pi * 2 / 13)
                orbitA.Position = UDim2.fromOffset(110 + math.cos(oa) * 86, 110 + math.sin(oa) * 86)
                orbitB.Position = UDim2.fromOffset(110 + math.cos(ob) * 74, 110 + math.sin(ob) * 74)
                orbitC.Position = UDim2.fromOffset(110 + math.cos(oc) * 68, 110 + math.sin(oc) * 68)

                local lensPulse = (math.sin(elapsed * math.pi * 2 / 3) + 1) * 0.5
                local lensStroke = lens:FindFirstChildOfClass("UIStroke")
                if lensStroke then
                    lensStroke.Transparency = 0.68 - lensPulse * 0.48
                end

                local corePulse = (math.sin(elapsed * math.pi * 2 / 3.2) + 1) * 0.5
                coreBloom.BackgroundTransparency = 0.92 - corePulse * 0.15
                coreGlow.BackgroundTransparency = 0.96 - corePulse * 0.20
                eventHorizon.Size = UDim2.fromOffset(72 + corePulse * 7, 72 + corePulse * 7)
                eventPoint.Size = UDim2.fromOffset(18 + corePulse * 4, 18 + corePulse * 4)
                centerDot.BackgroundTransparency = 0.05 + (1 - corePulse) * 0.5

                status.Text = stages[1][2]
                for i = #stages, 1, -1 do
                    if progress >= stages[i][1] then
                        status.Text = stages[i][2]
                        break
                    end
                end
                fill.Size = UDim2.new(progress, 0, 1, 0)
                percent.Text = string.format("%d%%", math.floor(progress * 100 + 0.5))

                if progress >= 1 then
                    anim:Disconnect()
                    status.Text = "VOID NEXUS ONLINE"
                    task.wait(0.10)
                    if not State.alive then return end

                    TweenService:Create(loadScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.78}):Play()
                    TweenService:Create(loadingLayer, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()

                    task.delay(0.36, function()
                        if not State.alive then return end
                        if loaderRoot and loaderRoot.Parent then loaderRoot.Enabled = false end
                        if loadingLayer and loadingLayer.Parent then loadingLayer:Destroy() end

                        holder.Visible = true
                        root.Enabled = true
                    local bootStroke = panel:FindFirstChildOfClass("UIStroke")
                        if bootStroke then
                            bootStroke.Transparency = 1
                            TweenService:Create(bootStroke, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 0.28}):Play()
                        end
                        if loaderRoot and loaderRoot.Parent then loaderRoot:Destroy() end
                    end)
                end
            end)
        end
    end)

    if not __loaderOK then
        if __loaderLayer and __loaderLayer.Parent then __loaderLayer:Destroy() end
        if loaderRoot and loaderRoot.Parent then loaderRoot:Destroy() end
        holder.Visible = true
        root.Enabled = true
        warn("AutoSkills VOID loader failed safely: " .. tostring(__loaderERR))
    end
end

-- EMPYREAN CELESTIAL EASTER EGGS --------------------------------------------
-- Visual-only interactions.  This subsystem deliberately does not touch farm,
-- analytics, theme persistence, layout sizing, visibility, or movement logic.
-- It is safe to sleep whenever EMPYREAN is not active.
do
    local egg = EMP._easterEggs
    if not egg then
        egg = {lastInput=time(), lastBosses=0, lastKills=0, lastTargets=0, lastIdlePulse=0, lastDoubleClick=0}
        EMP._easterEggs = egg

        -- A dedicated pulse surface keeps the effect completely separate from
        -- the live celestial renderer, so its animation cannot fight EMP.core.
        EMP.easterPulse = frame(EMP.hero, "EasterPulse", 0, 0, 70, 70, Color3.fromRGB(255,224,150), 35)
        EMP.easterPulse.AnchorPoint = Vector2.new(.5,.5)
        EMP.easterPulse.Position = UDim2.fromScale(.5, .4875)
        EMP.easterPulse.BackgroundTransparency = 1
        EMP.easterPulse.ZIndex = 8

        local pulseStroke = stroke(EMP.easterPulse, Color3.fromRGB(255,243,200), 1, 1)
        EMP.easterPulseStroke = pulseStroke

        -- Invisible click target over the celestial core.  It is deliberately
        -- small so it cannot interfere with dragging or the rest of the hero.
        local clicker = make("TextButton", EMP.hero, {
            Name = "CelestialEasterEgg",
            Position = UDim2.fromScale(.5, .4875),
            Size = UDim2.fromOffset(92, 92),
            AnchorPoint = Vector2.new(.5,.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 20,
        })
        clicker.Active = true
        EMP.easterClicker = clicker

        local function celestialPulse(strong)
            if not State.alive or System.theme ~= "Empyrean" or State.minimized or not EMP.hero.Visible then return end
            local centerY = 78
            local startSize = strong and 78 or 70
            local endSize = strong and 150 or 118
            local startTransparency = strong and .52 or .68
            EMP.easterPulse.Position = UDim2.fromOffset(windowWidth * .5, centerY)
            EMP.easterPulse.Size = UDim2.fromOffset(startSize, startSize)
            EMP.easterPulse.BackgroundTransparency = startTransparency
            EMP.easterPulseStroke.Transparency = strong and .18 or .34

            local tween = TweenService:Create(EMP.easterPulse,
                TweenInfo.new(strong and .65 or .48, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {Size = UDim2.fromOffset(endSize, endSize), BackgroundTransparency = 1})
            local strokeTween = TweenService:Create(EMP.easterPulseStroke,
                TweenInfo.new(strong and .65 or .48, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {Transparency = 1})
            tween:Play(); strokeTween:Play()

            if strong then
                -- Briefly brighten the existing rays/wings. Their geometry is
                -- untouched and the normal EMPYREAN animation continues running.
                for _, ray in ipairs(EMP.rays or {}) do
                    if ray and ray.Parent then
                        local normal = ray.BackgroundTransparency
                        ray.BackgroundTransparency = .14
                        TweenService:Create(ray, TweenInfo.new(.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                            {BackgroundTransparency = normal}):Play()
                    end
                end
                for _, feather in ipairs(EMP.wingStrokes or {}) do
                    if feather and feather.Parent then
                        local normal = feather.BackgroundTransparency
                        feather.BackgroundTransparency = .12
                        TweenService:Create(feather, TweenInfo.new(.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                            {BackgroundTransparency = normal}):Play()
                    end
                end
            end
        end
        EMP.celestialPulse = celestialPulse

        connect(clicker.Activated, function()
            if System.theme ~= "Empyrean" or State.minimized then return end
            local now = time()
            local double = now - (egg.lastDoubleClick or 0) <= .38
            egg.lastDoubleClick = now
            celestialPulse(double)
            if double then
                -- A second click within the short window triggers the stronger
                -- "Ascended" flash; no gameplay state is changed.
                task.delay(.08, function()
                    if State.alive and System.theme == "Empyrean" and not State.minimized then
                        celestialPulse(true)
                    end
                end)
            end
        end)

        -- Small gold underline on navigation hover. It does not resize or
        -- recolor the actual navigation button.
        EMP.easterHoverLines = {}
        for key, tab in pairs(navButtons) do
            if tab then
                local line = frame(tab, "CelestialHover", 0, math.max(0, tab.Size.Y.Offset - 2), tab.Size.X.Offset, 2, Color3.fromRGB(217,169,78), 1)
                line.BackgroundTransparency = 1
                line.ZIndex = (tab.ZIndex or 1) + 1
                line.Active = false
                EMP.easterHoverLines[key] = line
                connect(tab.MouseEnter, function()
                    if System.theme ~= "Empyrean" then return end
                    TweenService:Create(line, TweenInfo.new(.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                        {BackgroundTransparency = .18}):Play()
                end)
                connect(tab.MouseLeave, function()
                    TweenService:Create(line, TweenInfo.new(.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                        {BackgroundTransparency = 1}):Play()
                end)
            end
        end
    end

    -- User activity resets the celestial idle timer. This listener is visual-only.
    connect(Input.InputBegan, function()
        if EMP._easterEggs then EMP._easterEggs.lastInput = time() end
    end)

    -- Detect successful boss kills / milestones from the already-authoritative
    -- Session Analytics counters. No counter is modified here.
    connect(RunService.RenderStepped, function()
        if not State.alive then return end
        local stats = System and System.stats
        if not stats then return end
        local now = time()
        local e = EMP._easterEggs
        local bosses = tonumber(stats.bosses) or 0
        local kills = tonumber(stats.kills) or 0
        local targets = tonumber(stats.targets) or 0

        if bosses < e.lastBosses then e.lastBosses = bosses end
        if kills < e.lastKills then e.lastKills = kills end
        if targets < e.lastTargets then e.lastTargets = targets end

        if System.theme == "Empyrean" and not State.minimized and EMP.hero.Visible then
            if bosses > e.lastBosses then
                celestialPulse(true)
            elseif kills > e.lastKills and kills % 10 == 0 then
                celestialPulse(false)
            elseif targets > e.lastTargets and targets % 25 == 0 then
                celestialPulse(false)
            end

            -- Every 30 seconds of genuine user inactivity, give the celestial
            -- core one quiet pulse. This is deliberately subtle and infrequent.
            if now - (e.lastInput or now) >= 30 and now - (e.lastIdlePulse or 0) >= 30 then
                e.lastIdlePulse = now
                celestialPulse(false)
            end
        end

        e.lastBosses = bosses
        e.lastKills = kills
        e.lastTargets = targets
    end)
end
-- END EMPYREAN CELESTIAL EASTER EGGS ----------------------------------------

connect(Input.InputBegan, function(input, gameProcessed)
    if not State.alive then return end

    if input.KeyCode == Settings.StopKey then
        controller.Stop()
        return
    elseif input.KeyCode == Enum.KeyCode.F10 then
        if MiniMode and MiniMode.toggle then MiniMode.toggle() end
        return
    elseif input.KeyCode == Settings.VisibilityKey then
        if State.miniMode then
            if MiniMode and MiniMode.hide then MiniMode.hide() end
            return
        end
        State.minimized = not State.minimized
        if root then
            -- IMPORTANT: visibility is now completely independent from UIScale.
            -- UIScale changes AbsoluteSize and was the source of the Empyrean
            -- hide/show geometry race. A small position tween gives the same
            -- polished hide/show feel without changing any layout dimensions.
            if State.visibilityTween then
                pcall(function() State.visibilityTween:Cancel() end)
                State.visibilityTween = nil
            end

            local currentX = holder.Position.X.Offset
            local currentY = holder.Position.Y.Offset
            if State.minimized then
                State.visibilityX = currentX
                State.visibilityY = currentY
                local tween = TweenService:Create(holder,
                    TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                    {Position = UDim2.fromOffset(currentX, currentY - 8)})
                State.visibilityTween = tween
                tween:Play()
                task.delay(0.18, function()
                    if State.alive and State.minimized then
                        root.Enabled = false
                        holder.Position = UDim2.fromOffset(State.visibilityX or currentX, State.visibilityY or currentY)
                    end
                end)
            else
                local restoreX = State.visibilityX or currentX
                local restoreY = State.visibilityY or currentY
                root.Enabled = true
                holder.Position = UDim2.fromOffset(restoreX, restoreY - 8)
                local tween = TweenService:Create(holder,
                    TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                    {Position = UDim2.fromOffset(restoreX, restoreY)})
                State.visibilityTween = tween
                tween:Play()

                if System.theme == "Empyrean" and EMP.recoverAfterShow then
                    EMP.recoverAfterShow()
                end
            end
        end
        return
    end

    if gameProcessed then return end
    if input.KeyCode == Settings.ToggleKey then
        setEnabled(not State.enabled)
        render()
    end
end)

connect(GuiService.MenuOpened, function() render() end)
connect(Input.WindowFocusReleased, function()
    State.focused = false
    State.gesture = nil
    if Settings.PauseWhenUnfocused then releaseOrPause() end
end)
connect(Input.WindowFocused, function() State.focused = true; render() end)
connect(Player.CharacterRemoving, function()
    if Settings.AutoBoss then
        Farm.autoResumePath = Farm.autoCurrent or Farm.pinned or Farm.autoLastPath
        Farm.autoRespawnResume = Farm.autoResumePath ~= nil

        Farm.autoCombatAt = 0
        Farm.autoLastProgressAt = 0
        Farm.autoLastHP = nil
        Farm.autoEngaged = false
        Farm.autoDefeated = false

        Farm.stopM1()
        Farm.clearLoot()
        Farm.restoreHitbox()
        Farm.release(false)

        Settings.AutoBoss = true
        Settings.FarmEnabled = true

        Farm.status = "AUTO BOSS RESPAWN"
        Farm.detail = Farm.autoRespawnResume
            and "Player died. Auto Boss stayed ON; same boss retained."
            or "Player died. Auto Boss stayed ON."
    else
        stopFarm()
    end

    Guard.release()
    Movement.restoreFly()
    Movement.restoreSpeed()
    Movement.restoreNoClip(true)
    Movement.character, Movement.humanoid, Movement.rootPart = nil, nil, nil
    releaseOrPause()
end)

connect(Player.CharacterAdded, function(character)
    if not Settings.AutoBoss then return end

    Settings.AutoBoss = true
    Settings.FarmEnabled = true
    Farm.nextScan = 0

    task.spawn(function()
        local humanoid = character:WaitForChild("Humanoid", 12)
        local rootPart = character:WaitForChild("HumanoidRootPart", 12)
        if not State.alive or not Settings.AutoBoss or not humanoid or not rootPart then return end

        task.wait(0.35)
        Farm.status = "AUTO BOSS RESPAWN"
        Farm.detail = Farm.autoRespawnResume
            and "Respawn complete. Returning to the SAME boss."
            or "Respawn complete. Continuing Auto Boss."
        Farm.step()
        render()
    end)
end)

local function waitResponsive(duration, isHolding)
    local deadline = os.clock() + duration
    while State.alive do
        local remaining = deadline - os.clock()
        if remaining <= 0 then return end
        if not availability() or (isHolding and State.heldKey == nil) then return end
        task.wait(math.min(0.03, remaining))
    end
end
pcall(render)
pcall(function() fitWindow(true) end)
local skillWorkerAlive = false
local function runAutoCastCycle(chosen)
    if not chosen or not State.alive then return end

    local blocked = type(Farm.inventoryOrBlockingUIOpen) == "function"
        and Farm.inventoryOrBlockingUIOpen(false)

    if blocked and type(Farm.inventorySkillPulse) == "function" then
        State.heldKey = nil
        local pressed = Farm.inventorySkillPulse(chosen.key)

        if pressed then
            State.lastKey = chosen.name .. " (inventory pulse)"
            pcall(render)
            waitResponsive(math.max(0.03, Settings.KeyGap), false)
            return
        end

        State.heldKey = chosen.key
        local fallbackOK, err = pcall(function()
            VirtualInput:SendKeyEvent(true, chosen.key, false, game)
        end)
        if not fallbackOK then
            inputFault(err)
            return
        end
        State.lastKey = chosen.name .. " (fallback)"
        pcall(render)
        waitResponsive(math.max(0.03, Settings.HoldTime), true)
        releaseOrPause()
        waitResponsive(math.max(0.03, Settings.KeyGap), false)
        return
    end

    State.heldKey = chosen.key
    local pressed, err = pcall(function()
        VirtualInput:SendKeyEvent(true, chosen.key, false, game)
    end)
    if not pressed then
        inputFault(err)
        return
    end

    State.lastKey = chosen.name
    pcall(render)
    waitResponsive(math.max(0.03, Settings.HoldTime), true)
    releaseOrPause()
    waitResponsive(math.max(0.03, Settings.KeyGap), false)
end

task.spawn(function()
    local nextIndex = 1
    skillWorkerAlive = true
    while State.alive do
        local cycleOK, cycleErr = pcall(function()
            if not availability() then
                task.wait(0.05)
                return
            end

            local chosen
            for _ = 1, #Skills do
                local candidate = Skills[nextIndex]
                nextIndex = nextIndex % #Skills + 1
                if candidate.enabled then
                    chosen = candidate
                    break
                end
            end

            if chosen then
                runAutoCastCycle(chosen)
            else
                task.wait(0.05)
            end
        end)

        if not cycleOK then

            warn("AutoSkills Auto Cast recovered from: " .. tostring(cycleErr))
            pcall(releaseKey)
            task.wait(0.08)
        end
    end
    skillWorkerAlive = false
end)
task.spawn(function()
    while State.alive do
        pcall(render)
        task.wait(0.12)
    end
end)
task.spawn(function()
    while State.alive do
        refreshESP()
        render()
        task.wait(0.2)
    end
end)
task.spawn(function()
    while State.alive do
        Guard.step()
        task.wait(0.1)
    end
end)

if type(BUILT_IN_BOSS_SEED_CODE) == "string"
    and BUILT_IN_BOSS_SEED_CODE:sub(1, 7) == "ASLOC1:" then
    local okSeed, seedMessage = Farm.importCode(BUILT_IN_BOSS_SEED_CODE)
    if okSeed then
        Farm.configStatus = "Built-in boss seed loaded"
    else
        warn("AutoSkills built-in boss seed: " .. tostring(seedMessage))
    end
end

Farm.scan(true)

if Settings.StaticMapScan then
    task.delay(0.8, function()
        if State.alive and Farm.staticMapScan then
            Farm.staticMapScan(true)
        end
    end)
end

if Settings.BossFirstDiscovery then
    Farm.bootDiscovery()
end

task.delay(1.5, function()
    if State.alive and System and System.writeFriendReady then
        System.writeFriendReady()
        render()
    end
end)

notify("Void UI ready | boss seeds + static scan + original stable loot active")

]====]

local __env = (type(getgenv) == "function" and getgenv()) or _G
-- Resolve the startup theme BEFORE the generated body is executed. This prevents
-- an old body/JSON preference from ever selecting the Blackhole loader first.
local function __normalizeStartupTheme(v)
    if type(v) ~= "string" then return nil end
    v = v:gsub("^%s+", ""):gsub("%s+$", "")
    if v == "Default" or v == "Blackhole" or v == "Empyrean" or v == "Frost" then return v end
    return nil
end
local __startupTheme
local __themeFileTheme
-- Current Roblox session is authoritative. Old disk state is fallback only.
pcall(function()
    local __plr = game:GetService("Players").LocalPlayer
    local __pg = __plr and __plr:FindFirstChildOfClass("PlayerGui")
    if __plr then
        __startupTheme = __normalizeStartupTheme(__plr:GetAttribute("AutoSkills_Theme"))
            or __normalizeStartupTheme(__plr:GetAttribute("AutoSkills_StartupTheme"))
            or __normalizeStartupTheme(__plr:GetAttribute("AutoSkills_LastTheme"))
    end
    if __pg and not __startupTheme then
        __startupTheme = __normalizeStartupTheme(__pg:GetAttribute("AutoSkills_StartupTheme"))
            or __normalizeStartupTheme(__pg:GetAttribute("AutoSkills_LastTheme"))
    end
end)
__startupTheme = __startupTheme
    or __normalizeStartupTheme(__env.__AutoSkills_StartupTheme)
    or __normalizeStartupTheme(__env.__AutoSkills_LastTheme)
if not __startupTheme then
    local __rf = type(readfile) == "function" and readfile or __env.readfile
    if __rf then
        local __ok1, __raw1 = pcall(__rf, "AutoSkills_Theme_v2.state")
        local __ok2, __raw2 = pcall(__rf, "AutoSkills_Theme_v1.txt")
        if __ok1 then __themeFileTheme = __normalizeStartupTheme(__raw1) end
        if not __themeFileTheme and __ok2 then __themeFileTheme = __normalizeStartupTheme(__raw2) end
    end
    __startupTheme = __themeFileTheme
end
__startupTheme = __startupTheme or "Default"
-- IMPORTANT: do not write the startup fallback back into session state here.
-- Session state is only written by an actual theme selection. Otherwise a stale
-- Blackhole disk value would become a new "authoritative" session value and
-- permanently win on every re-execution.
__env.__AutoSkills_StartupTheme = __startupTheme
__env.__AutoSkills_LastTheme = __startupTheme
__env.__AUTOSKILLS_SOURCE = __AUTOSKILLS_SOURCE
pcall(function()
    local wf = type(writefile) == "function" and writefile or __env.writefile
    if wf then
        wf("AutoSkills_Void_AutoRun.lua", __AUTOSKILLS_SOURCE)
    end
end)
local __fn, __err = loadstring(__AUTOSKILLS_SOURCE)
if not __fn then
    warn("AutoSkills compile error: " .. tostring(__err))
    return
end
local __ok, __runtimeErr = xpcall(__fn, function(err)
    return debug and debug.traceback and debug.traceback(tostring(err), 2) or tostring(err)
end)
if not __ok then
    warn("AutoSkills runtime error: " .. tostring(__runtimeErr))
end
]=====])()
