loadstring([=====[
-- AutoSkills / Void bootstrap
local __AUTOSKILLS_SOURCE = [====[
-- AUTOSKILLS / VOID EDITION
-- F6: skills | F8: ESP | F9: health escape | F7: unload all | Right Shift: panel.
-- Drag the header; use the minus button to collapse the panel.
-- Z / X / C / V only. B is not used. Starts OFF.
-- Requires the same virtual-input support as the original script.
-- Repeats keypresses, not cooldown detection. Equip your tool and aim normally.
-- All UI is built locally. Cyan side-navigation control-panel layout; no downloaded UI libraries or assets.
-- Player ESP uses available character models; it cannot reveal unloaded characters.
-- Health Escape: moves your character exactly 70 studs UP in world space.
-- Uses CURRENT Health / MaxHealth, including live maximum-health changes.
-- Select a detected custom source if the live readout differs from the game HUD.
-- Fires once at/below the threshold; heals 5 percentage points above it to re-arm.
-- Minimum 5 seconds between escapes. Optional lock holds position until released or disabled.
-- Hidden/server-only health and server-enforced movement need game-specific support.
-- Auto M1 and loot run only with Auto Farm ON; both have independent toggles.
-- M1 is restored to the reliable original behavior:
-- normal gameplay = paired virtual mouse click; UI/inventory blocking combat = direct equipped Tool:Activate().
-- This matters because the game's inventory itself suppresses normal M1 input.
-- Auto Skills do not pause for inventory UI; when UI is blocking normal keys, they bypass the UI input sink
-- by calling local input listeners directly, then fall back to normal key input when the UI is not blocking.
-- Only actual chat typing can pause combat when that option is enabled.
-- Loot uses the original boss-drop behavior: scan only around the kill location for 10 seconds.
-- Custom chest menus and server restrictions can require game-specific integration.
-- Auto Farm starts OFF. Enable to select a living target automatically.
-- Attack targets are HARD-CAPPED to MaxHealth 3000-3200 inclusive.
-- Anything below 3000 or above 3200 MaxHealth is never attacked, including statues.
-- Holds the rig facing UP underneath the NPC. Local target expansion is optional;
-- server hit detection may ignore it. Resizes only the selected root and restores it.
-- Target health uses the NPC Humanoid; custom boss health needs game-specific support.
-- Default depth: exactly 7 studs below the target ROOT (not terrain height).
-- Farming can repeat selected skills; equip the required weapon/tool first.
-- OFF returns to the farming start point and restores original CanCollide values.
-- Escape locks take priority. Release and heal to resume farming; respawn turns farm OFF.

-- Boss config: local file APIs are optional; without them, memory lasts this session only.
-- Auto Boss: visits the nearest unvisited saved boss location within 500,000 studs,
-- farms + loots it, then continues. A boss that never takes first damage is skipped after 5 seconds.
-- Once that boss takes ANY damage, the 5-second skip timer is permanently disabled for that fight until death/loot.
-- Anti-AFK is enabled automatically for this script session.
-- Static boss discovery runs from your spawn/current position WITHOUT moving your character.
-- It scans replicated boss spawn/timer/location objects inside the 500,000-stud route and saves coordinates.
-- Legacy moving/grid discovery remains available only as a manual fallback.
-- Auto-rejoin can retry the last private instance, then navigate the game's menu to Ouwigahara/private join.
-- Auto-execute uses queue_on_teleport and a best-effort executor autoexec loader scoped to this Roblox universe.
-- Timer markers are hints, never proof that a 3000-3200 HP NPC is alive.
local Settings = {
    BossAutoSave = true, BossFirstDiscovery = false, BossGridSearch = true,
    BossDwell = 1.5, BossGridRadius = 2048,
    AutoBoss = false, BossAutoRange = 500000, BossLocalScanRadius = 2500, BossNoAttackTimeout = 5,
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
}
-- Optional game adapter. Replace false with a NON-YIELDING function:
-- function(player, character, humanoid) return currentHealth, currentMaxHealth end
-- It must read health visible to this client. Then select "Game adapter" in the UI.
local CustomHealthReader = false
local Skills = {
    {name = "Z", key = Enum.KeyCode.Z, enabled = true},
    {name = "X", key = Enum.KeyCode.X, enabled = true},
    {name = "C", key = Enum.KeyCode.C, enabled = true},
    {name = "V", key = Enum.KeyCode.V, enabled = true},
}
local Input = game:GetService("UserInputService")
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

-- Keep the original slot to unload the previous version when re-running.
local environment = type(getgenv) == "function" and getgenv() or _G
local slot = "__AutoSkills_ZXCVB"
local previous = environment[slot]
if type(previous) == "table" and type(previous.Stop) == "function" then previous.Stop() end

local State = {
    alive = true, enabled = false, focused = true, minimized = false,
    heldKey = nil, lastKey = nil, fault = nil, gesture = nil,
    tab = "Skills", espCount = 0, espFault = nil,
}
local connections, tweens = {}, setmetatable({}, {__mode = "k"})
local controller, UI = {}, {}
local render = function() end
local clearESP = function() end
local stopHealthGuard = function() end
local stopFarm = function() end
local stopMovement = function() end
local pauseFarmForEscape = function() end
local root

environment[slot] = controller
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    connections[#connections + 1] = connection
    return connection
end

-- Anti-AFK: Roblox fires LocalPlayer.Idled before an inactivity disconnect.
-- Use VirtualUser when the client exposes it; the connection is cleaned up by controller.Stop().
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

-- Game inventories often contain TextBoxes or consume normal keyboard input.
-- Only treat an actually focused CHAT box as a typing pause. Inventory/search
-- UI is intentionally ignored so Auto M1 and Auto Skills keep running.
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
    if Settings.PauseWhenUnfocused and not State.focused then
        return false, "PAUSED", "Return to Roblox to resume."
    end
    -- Do not pause for game inventories/menus; the combat workers handle blocked input directly.
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
            -- Inspect only known local stat containers, never accessories, NPCs or the entire game.
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
            -- Humanoid is the normal Roblox health authority. Multiple custom
            -- stores may contain stale/base stats, so never guess between them.
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
        -- Check lifetime again: a custom reader must never act on an old character.
        if not State.alive or not Settings.HealthEscapeEnabled or character ~= Guard.character then return end
        Guard.latched, Guard.lastTeleport = true, os.clock()
        -- Adding a world-space offset preserves facing and moves the whole rig.
        character:PivotTo(character:GetPivot() + Vector3.new(0, 70, 0))
        pauseFarmForEscape()
        if Settings.HealthLock then
            Guard.held = {root = rootPart, anchored = rootPart.Anchored, pivot = character:GetPivot()}
            rootPart.Anchored = true
        end
        -- Clear fall speed; the optional anchor holds the escape position.
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
        -- Reviewing a different source must not trigger a surprise teleport.
        Guard.setEnabled(false)
    end
    stopHealthGuard = function()
        Guard.release()
        Settings.HealthEscapeEnabled = false
        disconnectSource()
        Guard.sources, Guard.source, Guard.character = {}, nil, nil
    end
end

-- Only replicated NPCs can be discovered. IDs below are attributes when supplied
-- by the game, otherwise session IDs; they are not Roblox asset IDs.
local System
local BUILT_IN_BOSS_SEED_CODE = "__AUTOSKILLS_BOSS_SEED_PLACEHOLDER__"
local Farm = {catalog = {}, remembered = {}, pinned = nil, records = {}, selected = nil, nextScan = 0, status = "OFF",
    detail = "Select a target, then enable Auto farm.", count = 0, aliveCount = 0,
    autoVisited = {}, autoCurrent = nil, autoLastPath = nil, autoArrivedAt = 0,
    autoCombatAt = 0, autoLastProgressAt = 0, autoLastHP = nil, autoDefeated = false,
    autoCycles = 0, autoSkipped = 0}
local function attackHealthAllowed(maximum)
    return type(maximum) == "number"
        and maximum == maximum
        and maximum >= Settings.FarmMinHP
        and maximum <= Settings.FarmMaxHP
end
-- Boss metadata is data-only JSON, scoped to a Roblox place. Never loadstring a config.
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
        -- Turning autosave OFF retains the previously saved locations, and saves the preference only.
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
    -- Share codes contain JSON location data only, never Lua instructions.
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
            -- Stage the merge so rejection cannot partly alter the active catalog.
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
                -- Canonicalize marker keys from position, not an arbitrary sender-supplied identifier.
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
        Farm.setEnabled(false) -- also cancels pending or active first-run discovery
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

                    -- Prefer the outermost ancestor that still clearly belongs
                    -- to the inventory, but do not disable an unrelated whole HUD.
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

        -- Give Roblox one scheduler slice to drop the GUI input capture.
        task.wait(0.015)

        local okDown, downResult = pcall(downCallback)

        if okDown and upCallback then
            task.wait(math.max(0.025, holdTime or 0.03))
            pcall(upCallback)
        end

        -- Let the release reach the game's input listeners before reopening UI.
        task.wait(0.015)
        restore()

        return okDown, downResult, rootCount
    end

    -- Soft bypass retained as a fallback for inventories whose roots cannot
    -- be identified by name.
    -- Temporarily remove the inventory's ability to consume input without
    -- closing it. Properties are restored immediately after the local action
    -- callbacks are invoked.
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

        -- If no identifiable inventory root existed, also try the local-listener path.
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
            -- Prefer the game's Mouse.Button1Down/Up listeners because these are
            -- normally the same callbacks used when M1 works outside inventory.
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

        local point = Vector2.new(math.floor(viewport.X / 2), math.floor(viewport.Y / 2))
        local blocked = Farm.inventoryOrBlockingUIOpen(false)

        if blocked then
            -- The game itself blocks normal M1 while inventory is open.
            -- Pulse the inventory root off for one input frame, send a REAL VIM
            -- mouse press/release, then restore the inventory exactly as it was.
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

            -- If the inventory has an unusual name/state, try the local listeners.
            if directMouseM1(true) then
                mouseDown = "DIRECT"
                nextM1, releaseM1At = os.clock() + 0.16, os.clock() + 0.035
                Farm.m1Status = "M1: local inventory bypass"
                return
            end

            -- Tool-based fallback.
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

        -- Normal gameplay keeps the original working M1 path.
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
        Farm.stopM1(); Farm.restoreHitbox(); State.farming = false; releaseOrPause()

        loot = {
            center = position,
            destination = position + Vector3.new(0, 2, 0),
            deadline = os.clock() + 10,
            nextScan = 0,
            tries = {},
            count = 0,
            fresh = setmetatable({}, {__mode = "k"}),
            message = "Waiting for boss drops near the kill.",
        }

        -- Mark objects that appear AFTER the kill. These are allowed a wider
        -- horizontal search radius, while old map crates keep the original 60-stud limit.
        loot.spawnConnection = World.DescendantAdded:Connect(function(object)
            if not loot then return end
            local node = object
            for _ = 1, 8 do
                if not node or node == World then break end
                loot.fresh[node] = true
                node = node.Parent
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
        deathConnection = watched.HealthChanged:Connect(function(hp)
            if hp <= 0 then
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
        local descendants = World:GetDescendants()
        for _, object in ipairs(descendants) do
            if object:IsA("ProximityPrompt") or object:IsA("ClickDetector") then
                local entity, marked = lootIdentity(object)
                local allowed = true
                if object:IsA("ProximityPrompt") then
                    local pickup; allowed, pickup = allowedPrompt(object)
                    marked = marked or pickup
                    allowed = allowed and object.Enabled
                end
                if entity and marked then
                    interactive[entity] = true
                    local part = lootPart(object.Parent)
                    if allowed and part and available(object) then
                        local inRange, fresh, horizontal = lootDistanceOK(part, entity)
                        if inRange then
                            candidates[#candidates+1] = {
                                object=object, part=part, entity=entity,
                                fresh=fresh, horizontal=horizontal
                            }
                        end
                    end
                end
            end
        end
        for _, object in ipairs(descendants) do
            if object:IsA("BasePart") and object.CanTouch then
                local entity, marked = lootIdentity(object)
                if entity and marked and not interactive[entity] and not seen[entity]
                    and available(entity) then
                    local inRange, fresh, horizontal = lootDistanceOK(object, entity)
                    if inRange then
                        seen[entity] = true
                        candidates[#candidates+1] = {
                            object=entity, part=object, entity=entity, touch=true,
                            fresh=fresh, horizontal=horizontal
                        }
                    end
                end
            end
        end
        table.sort(candidates, function(a,b)
            -- Boss-created objects first, then nearest horizontal distance.
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
            loot.nextScan = os.clock() + 0.20
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
        if not ok and loot then endPrompt(); loot.message = "Pickup failed: " .. tostring(err) end
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

        -- Prefer the boss name saved for this location. If its live rig uses a
        -- different display/model name, fall back to the nearest valid 3k-3.2k boss.
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
                if autoBossEligible(entry) and not Farm.autoVisited[entry.path]
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
        Farm.status = "AUTO BOSS"
        Farm.detail = string.format("Next: %s | %.0f studs away", entry.name, distance or 0)
        return entry
    end
    local function advanceAutoBoss(reason, rootPart, skipped)
        local previous = Farm.autoCurrent and Farm.catalog[Farm.autoCurrent]
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
        Farm.nextScan = 0
        Farm.status = "AUTO BOSS"
        Farm.detail = (reason or "Moving to next boss") .. (previous and (" | " .. previous.name) or "")
        return pickAutoBoss(rootPart)
    end
    function Farm.setAutoBoss(value)
        if not State.alive then return end
        if Farm.stopDiscovery then Farm.stopDiscovery() end
        Settings.AutoBoss = value and true or false
        Farm.fault = nil
        Farm.nextScan = 0
        if Settings.AutoBoss then
            -- Auto Boss is a complete farm mode: save every learned location and start farming.
            Settings.BossAutoSave = true
            Settings.FarmEnabled = true
            Farm.markDirty(); Farm.saveConfig(true)
            Farm.stopM1(); Farm.clearLoot(); Farm.restoreHitbox()
            Farm.pinned, Farm.selected = nil, nil
            Farm.autoCycles, Farm.autoSkipped = 0, 0
            resetAutoBossRoute(true)
        else
            Settings.FarmEnabled = false
            resetAutoBossRoute(true)
            Farm.release(true)
        end
        Farm.step()
        render()
    end
    function Farm.release(returnToStart)
        State.farming = false
        Farm.travelKey, Farm.travelAt = nil, nil
        Farm.stopM1(); Farm.clearLoot()
        Farm.restoreHitbox()
        if rotationState then
            local saved = rotationState; rotationState = nil
            pcall(function() saved.humanoid.AutoRotate = saved.autoRotate end)
        end
        if returnToStart and origin and farmCharacter and farmCharacter.Parent
            and farmCharacter == Player.Character then
            local ok, err = pcall(function() farmCharacter:PivotTo(origin) end)
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
            Farm.release(true)
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
            local entry = Farm.autoCurrent and Farm.catalog[Farm.autoCurrent] or nil
            if not entry or not autoBossEligible(entry) then entry = pickAutoBoss(rootPart) end
            if not entry then
                Farm.stopM1(); Farm.restoreHitbox()
                Farm.status = "AUTO BOSS WAITING"
                Farm.detail = string.format("No saved boss location within %.0f studs. Discover or import locations first.", Settings.BossAutoRange)
                return
            end
            Farm.pinned = entry.path
            Farm.selected = entry.live
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
                    -- A valid boss was found inside the expanded saved-location scan.
                    Farm.travelKey, Farm.travelAt = nil, nil
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
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if collisionState[part] == nil then collisionState[part] = part.CanCollide end
                        part.CanCollide = false
                    end
                end
                if Farm.travelKey ~= entry.path then
                    Farm.travelKey, Farm.travelAt = entry.path, os.clock()
                    Farm.travelDestination = location - Vector3.new(0, math.clamp(Settings.FarmDepth,6,7),0)
                    Farm.nextScan = 0
                    if Settings.AutoBoss then
                        Farm.autoArrivedAt = os.clock()
                        Farm.autoCombatAt, Farm.autoLastProgressAt, Farm.autoLastHP = 0, 0, nil
                        Farm.autoEngaged = false
                    end
                end
                character:PivotTo(character:GetPivot() + (Farm.travelDestination - rootPart.Position))
                rootPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
                rootPart.AssemblyAngularVelocity = Vector3.new(0,0,0)
                if Settings.AutoBoss and os.clock() - Farm.autoArrivedAt >= Settings.BossNoAttackTimeout then
                    advanceAutoBoss("No live attack target after 5s; skipped", rootPart, true)
                    return
                end
                Farm.status = Settings.AutoBoss and "AUTO BOSS LOADING" or (hp and hp <= 0 and "WAITING FOR RESPAWN" or "LOADING BOSS")
                Farm.detail = Settings.AutoBoss
                    and string.format("At %s | scanning %.0f studs for a live boss", entry.name, Settings.BossLocalScanRadius)
                    or (os.clock() - Farm.travelAt > 15
                        and "Not loaded yet; waiting at saved location. OFF returns you."
                        or ("At saved location: " .. entry.name .. ". Waiting for a live rig."))
                    return
                end
            end
            if Settings.AutoBoss and Farm.autoCombatAt == 0 then
                Farm.autoCombatAt = os.clock()
                Farm.autoLastProgressAt = Farm.autoCombatAt
                Farm.autoLastHP = hp
            end
            Farm.travelKey, Farm.travelAt = nil, nil
        end
        if Settings.AutoBoss and (not hp or hp <= 0 or not targetRoot or not attackHealthAllowed(maximum)) then
            if Farm.autoDefeated or (hp and hp <= 0) then
                Farm.autoDefeated = true
                beginLoot(lastTargetPosition or (targetRoot and targetRoot.Position) or rootPart.Position)
                if stepLoot(character, rootPart) then return end
                advanceAutoBoss("Killed + loot pass complete; moving on", rootPart, false)
            elseif Farm.autoEngaged then
                -- Once this boss has taken damage, never use the 5-second skip timer for this fight.
                -- This prevents stuns, knockback, invulnerability phases, animations, or temporary rig loss
                -- from making Auto Boss abandon a boss that was already successfully engaged.
                Farm.stopM1()
                Farm.restoreHitbox()
                Farm.status = "AUTO BOSS ENGAGED"
                Farm.detail = "Boss already took damage; skip timer disabled until it dies."
            elseif os.clock() - Farm.autoArrivedAt >= Settings.BossNoAttackTimeout then
                advanceAutoBoss("Target unavailable before first damage; skipped", rootPart, true)
            end
            return
        end
        if not hp or hp <= 0 or not targetRoot or not attackHealthAllowed(maximum) then
            Farm.stopM1()
            Farm.restoreHitbox()
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
        end
        humanoid.AutoRotate = false
        expandHitbox(targetRoot)
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                if collisionState[part] == nil then collisionState[part] = part.CanCollide end
                part.CanCollide = false
            end
        end
        local destination = targetRoot.Position - Vector3.new(0, math.clamp(Settings.FarmDepth, 6, 7), 0)
        character:PivotTo(character:GetPivot() + (destination - rootPart.Position))
        -- Forward points at the NPC above. A horizontal up vector avoids the
        -- lookAt singularity when the target is exactly vertical.
        rootPart.CFrame = CFrame.lookAt(rootPart.Position, targetRoot.Position, Vector3.new(0, 0, 1))
        rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        State.farming = true
        watchTarget(Farm.selected, targetRoot)
        if Settings.AutoBoss then
            local now = os.clock()
            if Farm.autoCombatAt == 0 then
                -- The five-second timer exists only to prove that we can actually damage this boss.
                Farm.autoCombatAt = now
                Farm.autoLastProgressAt = now
                Farm.autoLastHP = hp
                Farm.autoEngaged = false
            else
                local previousHP = Farm.autoLastHP
                if previousHP ~= nil and hp < previousHP - 0.01 then
                    -- First confirmed damage permanently locks this boss in until death/loot.
                    Farm.autoEngaged = true
                    Farm.autoLastProgressAt = now
                end
                Farm.autoLastHP = hp
            end

            -- IMPORTANT: after first confirmed damage, stuns / knockback / i-frames / long boss attacks
            -- can last as long as they need to. Auto Boss will not skip this boss for inactivity.
            if not Farm.autoEngaged and now - Farm.autoCombatAt >= Settings.BossNoAttackTimeout then
                advanceAutoBoss("No first damage within 5s; skipped", rootPart, true)
                return
            end
        end
        stepM1()
        Farm.status = Settings.AutoBoss and "AUTO BOSS FARMING" or "FARMING"
        Farm.detail = Settings.AutoBoss
            and string.format("%s | %s | route %d visited, %d skipped", Farm.m1Status, Farm.selected.name,
                (function() local n=0 for _ in pairs(Farm.autoVisited) do n=n+1 end return n end)(), Farm.autoSkipped)
            or (Farm.m1Status .. " | " .. Farm.selected.name)
    end
    function Farm.step()
        if not State.alive or Farm.updating then return end
        Farm.updating = true
        local ok, err = pcall(update)
        Farm.updating = false
        if not ok then
            if Farm.stopDiscovery then Farm.stopDiscovery("Discovery stopped after an error") end
            Settings.FarmEnabled = false
            Settings.AutoBoss = false
            resetAutoBossRoute(true)
            Farm.fault = "Farming stopped. Toggle on to retry."
            Farm.release(true)
            Farm.status, Farm.detail = "ERROR", Farm.fault
            warn("AutoSkills Farm: " .. tostring(err))
        end
    end
    stopFarm = function()
        if Farm.stopDiscovery then Farm.stopDiscovery() end
        Farm.saveConfig(true)
        Settings.FarmEnabled = false
        Settings.AutoBoss = false
        resetAutoBossRoute(true)
        Farm.release(true)
    end
    local runOK, Run = pcall(function() return game:GetService("RunService") end)
    if runOK then
        -- Apply noclip before physics each frame; discovery remains throttled.
        connect(Run.Stepped, function() Farm.step() end)
    else
        task.spawn(function()
            while State.alive do Farm.step(); task.wait(0.03) end
        end)
    end
end

-- Discovery follows replicated world timers, then a bounded grid. Hidden map data is not invented.
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
                    -- One malformed/unloaded GUI must not abort NPC discovery.
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

        -- Merge with any already-known coordinate for this boss nearby.
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

            -- Capture once. The scan never moves the character.
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

                -- Yield occasionally so a large Workspace scan does not freeze the client.
                if inspected % 2500 == 0 then
                    Farm.staticScanStatus = string.format(
                        "Static scan: %d objects checked / %d new boss locations",
                        inspected, found
                    )
                    render()
                    task.wait()
                end
            end

            -- Ask Roblox to stream around coordinates we already discovered.
            -- This does not move the local character and may reveal nearby live rigs/markers.
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
            -- User-selected finite square, centered at discovery start. Never claims unseen map bounds.
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
            Farm.discoveryStatus=string.format("%d visited / %d queued | %s",run.completed,#run.queue+1,point.label)
            -- Request once at each stop; async callback never moves the character.
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
            -- A short visible delay allows the configuration or Stop button to cancel.
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


-- Movement controls. No-clip starts ON immediately when the script executes.
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
        -- Fly always needs no-clip so movement works in every direction through geometry.
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

        -- Full 3D camera vectors: looking upward and pressing W actually flies upward.
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

        -- Kill gravity/inertia every frame for precise stop/start movement.
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

-- Apply the initial No Clip/T-block state immediately, not only after opening the Move tab.
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


-- Persistent system controls: static scanning, private-server recovery and auto-execute.
System = {
    configPath = "AutoSkills_System_v1.json",
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
}

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

    function System.loadPrefs()
        if type(reader) ~= "function" or type(exists) ~= "function" then return end
        local okExists, present = pcall(exists, System.configPath)
        if not okExists or not present then return end

        local ok, data = pcall(function()
            return HttpService:JSONDecode(reader(System.configPath))
        end)
        if not ok or type(data) ~= "table" then return end

        if type(data.StaticMapScan) == "boolean" then Settings.StaticMapScan = data.StaticMapScan end
        if type(data.AutoRejoin) == "boolean" then Settings.AutoRejoin = data.AutoRejoin end
        if type(data.AutoExecute) == "boolean" then Settings.AutoExecute = data.AutoExecute end
        if finiteText(data.PrivateServerMap, 80) then Settings.PrivateServerMap = data.PrivateServerMap end
        if finiteText(data.TargetGameId, 40) then System.targetGameId = data.TargetGameId end
        if finiteText(data.LastPrivateJob, 120) then System.lastPrivateJob = data.LastPrivateJob end
        if type(data.LastPrivatePlace) == "number" then System.lastPrivatePlace = data.LastPrivatePlace end
    end

    function System.savePrefs()
        if type(writer) ~= "function" then
            System.persistStatus = "File write unavailable; preferences are session-only."
            return false
        end

        local ok, err = pcall(function()
            writer(System.configPath, HttpService:JSONEncode({
                schema = 1,
                StaticMapScan = Settings.StaticMapScan,
                AutoRejoin = Settings.AutoRejoin,
                AutoExecute = Settings.AutoExecute,
                PrivateServerMap = Settings.PrivateServerMap,
                TargetGameId = System.targetGameId,
                LastPrivatePlace = System.lastPrivatePlace,
                LastPrivateJob = System.lastPrivateJob,
            }))
        end)

        if not ok then
            System.persistStatus = "Preference save failed: " .. tostring(err)
            return false
        end
        return true
    end

    System.loadPrefs()

    -- First execution defines which Roblox universe this autoexec belongs to.
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

    -- If this body auto-runs in the same universe but outside the private gameplay
    -- instance, treat that as a recovery/menu state.
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
    panel = Color3.fromRGB(5, 14, 23),
    surface = Color3.fromRGB(10, 25, 38),
    raised = Color3.fromRGB(14, 36, 52),
    line = Color3.fromRGB(30, 67, 88),
    text = Color3.fromRGB(235, 248, 255),
    muted = Color3.fromRGB(149, 177, 202),
    dim = Color3.fromRGB(91, 125, 151),
    accent = Color3.fromRGB(24, 207, 255),
    bright = Color3.fromRGB(145, 234, 255),
    green = Color3.fromRGB(55, 238, 147),
    amber = Color3.fromRGB(255, 201, 96),
    red = Color3.fromRGB(255, 103, 127),
}
local W, H = 900, 720
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

-- ESP visuals have their own lifetime, independent of skill input and UI visibility.
-- Polling also handles respawns, newly streamed parts and team changes without
-- retaining per-character event connections.
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
    -- Register before building so a partial creation can also be cleaned up.
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
})
local canvas = make("Frame", root, {
    Name = "Canvas", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
    BorderSizePixel = 0, Active = false,
})
local holder = frame(canvas, "Window", 24, 58, W, H)
holder.BackgroundTransparency = 1
local uiScale = make("UIScale", holder, {Scale = 1})
local shadow = frame(holder, "Shadow", -7, 9, W + 14, H + 14, Color3.new(0, 0, 0), 18)
shadow.BackgroundTransparency = 0.48
local halo = frame(holder, "EdgeGlow", -2, -2, W + 4, H + 4, C.accent, 16)
halo.BackgroundTransparency = 0.88
local panel = frame(holder, "Panel", 0, 0, W, H, C.panel, 14)
panel.Active, panel.ClipsDescendants = true, true
stroke(panel, C.accent, 0.16, 1)
make("UIGradient", panel, {
    Rotation = 35,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 26, 39)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(5, 15, 24)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(3, 10, 18)),
    }),
})
local accentLine = frame(panel, "AccentLine", 0, 58, W, 1, C.accent)
make("UIGradient", accentLine, {
    Color = ColorSequence.new(C.accent, Color3.fromRGB(91, 210, 230)),
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.35, 0),
        NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 0.8),
    }),
})
local header = button(panel, "HeaderDrag", "", 0, 0, W - 170, 58, C.panel)
header.BackgroundTransparency = 1
local logo = frame(header, "Logo", 18, 13, 32, 32, C.surface, 7)
stroke(logo, C.accent, 0.08, 1)
make("UIGradient", logo, {
    Rotation = 45,
    Color = ColorSequence.new(Color3.fromRGB(11, 66, 82), Color3.fromRGB(19, 201, 245)),
})
local logoText = label(logo, "Mark", "V", 0, 0, 32, 32, 19, C.text, Enum.Font.GothamBlack)
logoText.TextXAlignment = Enum.TextXAlignment.Center
local brand = label(header, "Title", "G A M E   C O N T R O L", 68, 11, 300, 22, 13, C.text, Enum.Font.GothamBold)
label(header, "Edition", "P A N E L", 369, 11, 120, 22, 12, C.accent, Enum.Font.GothamBold)
label(header, "SubTitle", "VOID AUTOMATION SUITE", 68, 32, 280, 15, 8, C.dim, Enum.Font.GothamMedium)
UI.badge = button(panel, "HeaderToggle", "OFF", W - 238, 17, 82, 25, C.surface, 10)
stroke(UI.badge, C.line, 0.3)
local minimize = button(panel, "Minimize", "-", W - 140, 15, 32, 28, C.surface, 19)
local close = button(panel, "Unload", "x", W - 94, 15, 32, 28, C.surface, 15)
hover(minimize, C.muted, C.text)
hover(close, C.muted, C.red)
local tabs = frame(panel, "Tabs", 14, 74, 166, 348, C.surface, 12)
stroke(tabs, C.line, 0.34)
label(tabs, "MenuTitle", "NAVIGATION", 14, 8, 138, 16, 9, C.dim, Enum.Font.GothamBold)

UI.skillsTab = button(tabs, "SkillsTab", "   Skills", 12, 32, 142, 43, C.raised, 11)
UI.espTab = button(tabs, "ESPTab", "   ESP", 12, 84, 142, 43, C.surface, 11)
UI.healthTab = button(tabs, "HealthTab", "   Health", 12, 136, 142, 43, C.surface, 11)
UI.farmTab = button(tabs, "FarmTab", "   Farm", 12, 188, 142, 43, C.surface, 11)
UI.moveTab = button(tabs, "MoveTab", "   Move", 12, 240, 142, 43, C.surface, 11)
UI.systemTab = button(tabs, "SystemTab", "   System", 12, 292, 142, 43, C.surface, 11)

UI.navStrokes, UI.navBars = {}, {}
for _, entry in ipairs({
    {"Skills", UI.skillsTab}, {"ESP", UI.espTab}, {"Health", UI.healthTab},
    {"Farm", UI.farmTab}, {"Move", UI.moveTab}, {"System", UI.systemTab},
}) do
    local key, tab = entry[1], entry[2]
    tab.TextXAlignment = Enum.TextXAlignment.Left
    tab.UICorner.CornerRadius = UDim.new(0, 9)
    UI.navStrokes[key] = stroke(tab, C.accent, 0.86, 1)
    UI.navBars[key] = frame(tab, "ActiveBar", 0, 7, 3, 29, C.accent, 2)
end

local sidebarInfo = frame(panel, "SidebarInfo", 14, 438, 166, 212, C.surface, 12)
stroke(sidebarInfo, C.line, 0.45)
label(sidebarInfo, "Label", "SESSION", 14, 12, 138, 15, 9, C.dim, Enum.Font.GothamBold)
UI.sidebarState = label(sidebarInfo, "State", "CONNECTED", 14, 36, 138, 18, 11, C.green, Enum.Font.GothamBold)
label(sidebarInfo, "Hint1", "F7  Unload", 14, 70, 138, 18, 10, C.muted, Enum.Font.GothamMedium)
label(sidebarInfo, "Hint2", "R-Shift  Hide UI", 14, 94, 138, 18, 10, C.muted, Enum.Font.GothamMedium)
label(sidebarInfo, "Hint3", "F6  Skills", 14, 118, 138, 18, 10, C.muted, Enum.Font.GothamMedium)
label(sidebarInfo, "Version", "VOID  v1.5", 14, 173, 138, 18, 9, C.dim, Enum.Font.GothamBold)
local body = frame(panel, "Controls", 192, 74, W - 206, H - 102)
body.BackgroundTransparency = 1
local master = frame(body, "MasterCard", 24, 0, 392, 80, C.raised, 13)
UI.masterStroke = stroke(master, C.accent, 0.65)
label(master, "Eyebrow", "AUTOMATION", 18, 10, 220, 14, 9, C.bright, Enum.Font.GothamBold)
label(master, "Title", "Auto skills", 18, 27, 260, 24, 19, C.text, Enum.Font.GothamBold)
label(master, "Hint", "One switch. Your selected skills on repeat.", 18, 53, 278, 15, 10, C.muted)

local toggleViews = {}
local function toggle(parent, name, x, y, width, height, getter, setter)
    local track = button(parent, name, "", x, y, width, height, C.line)
    track.UICorner.CornerRadius = UDim.new(1, 0)
    local knob = frame(track, "Knob", 4, 4, height - 8, height - 8, C.muted, height)
    toggleViews[#toggleViews + 1] = {
        track = track, knob = knob, getter = getter, last = nil, width = width, height = height,
    }
    connect(track.Activated, function() setter(not getter()); render() end)
    return track
end
toggle(master, "MasterToggle", 318, 26, 54, 28, function() return State.enabled end, setEnabled)
label(body, "KeysLabel", "SKILL KEYS", 24, 103, 220, 15, 10, C.muted, Enum.Font.GothamBold)
UI.count = label(body, "SelectedCount", "4 / 4 ENABLED", 266, 103, 150, 15, 10, C.accent, Enum.Font.GothamMedium)
UI.count.TextXAlignment = Enum.TextXAlignment.Right
UI.keys = {}
for index, skill in ipairs(Skills) do
    local current = skill
    local keyButton = button(body, "Skill_" .. current.name, "", 24 + (index - 1) * 100, 126, 92, 76, C.raised)
    keyButton.UICorner.CornerRadius = UDim.new(0, 12)
    local border = stroke(keyButton, C.accent, 0.58)
    local keyText = label(keyButton, "Key", current.name, 14, 9, 42, 32, 26, C.bright, Enum.Font.GothamBold)
    local dot = frame(keyButton, "EnabledDot", 72, 17, 6, 6, C.accent, 6)
    local hint = label(keyButton, "State", "ENABLED", 14, 48, 72, 14, 9, C.muted, Enum.Font.GothamMedium)
    local flash = frame(keyButton, "InputFlash", 14, 69, 64, 2, C.bright, 2)
    flash.BackgroundTransparency = 1
    UI.keys[index] = {button = keyButton, border = border, keyText = keyText, dot = dot,
        hint = hint, flash = flash, selected = nil, pressed = nil}
    connect(keyButton.Activated, function()
        current.enabled = not current.enabled
        if not current.enabled and State.heldKey == current.key then releaseOrPause() end
        render()
    end)
end

local timing = frame(body, "TimingCard", 24, 222, 392, 168, C.surface, 13)
stroke(timing, C.line, 0.45)
label(timing, "Heading", "TIMING", 16, 11, 100, 16, 10, C.muted, Enum.Font.GothamBold)
UI.cycle = label(timing, "CycleTime", "", 152, 11, 224, 16, 10, C.dim, Enum.Font.GothamMedium)
UI.cycle.TextXAlignment = Enum.TextXAlignment.Right
local sliders = {}
local function slider(name, title, property, y, minimum, maximum, options)
    options = options or {}
    local parent = options.parent or timing
    label(parent, name .. "Label", title, 16, y, 180, 18, 12, C.text, Enum.Font.GothamMedium)
    local valueLabel = label(parent, name .. "Value", "", 272, y, 104, 18, 12, C.bright, Enum.Font.Code)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    local hit = button(parent, name .. "Slider", "", 16, y + 19, 360, 22, C.surface)
    hit.BackgroundTransparency = 1
    local rail = frame(hit, "Rail", 0, 9, 360, 4, C.line, 3)
    local fill = frame(rail, "Fill", 0, 0, 0, 4, C.accent, 3)
    local knob = frame(hit, "Handle", 0, 11, 12, 12, C.bright, 7)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    stroke(knob, C.accent, 0.6, 2)
    local view = {property = property, hit = hit, fill = fill, knob = knob,
        valueLabel = valueLabel, minimum = minimum, maximum = maximum,
        format = options.format or "%.2f s"}
    sliders[#sliders + 1] = view
    local function updateFromX(x)
        if hit.AbsoluteSize.X <= 0 then return end
        local fraction = math.clamp((x - hit.AbsolutePosition.X) / hit.AbsoluteSize.X, 0, 1)
        local step = options.step or 0.01
        Settings[property] = math.clamp(math.floor((minimum + fraction * (maximum - minimum)) / step + 0.5) * step,
            minimum, maximum)
        if options.onChange then options.onChange() end
        render()
    end
    view.updateFromX = updateFromX
    connect(hit.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            State.gesture = {kind = "slider", input = input, view = view}
            releaseOrPause()
            updateFromX(input.Position.X)
        end
    end)
end
slider("KeyGap", "Key gap", "KeyGap", 36, 0.03, 1.00)
slider("HoldTime", "Key hold", "HoldTime", 82, 0.03, 2.00)
local presets = {
    {name = "Fast", gap = 0.06, hold = 0.04},
    {name = "Balanced", gap = 0.15, hold = 0.05},
    {name = "Relaxed", gap = 0.35, hold = 0.10},
}
for index, preset in ipairs(presets) do
    local current = preset
    current.button = button(timing, "Preset_" .. current.name, current.name, 16 + (index - 1) * 122, 134, 116, 24, C.panel, 10)
    connect(current.button.Activated, function()
        Settings.KeyGap, Settings.HoldTime = current.gap, current.hold
        render()
    end)
end
label(body, "TypingLabel", "Pause while typing in chat", 26, 408, 305, 24, 12, C.muted, Enum.Font.GothamMedium)
toggle(body, "PauseTypingToggle", 376, 409, 40, 22,
    function() return Settings.PauseWhileTyping end,
    function(value)
        Settings.PauseWhileTyping = value
        if value and Input:GetFocusedTextBox() then releaseOrPause() end
    end)
label(body, "FocusLabel", "Pause when tabbed out", 26, 442, 305, 24, 12, C.muted, Enum.Font.GothamMedium)
toggle(body, "PauseFocusToggle", 376, 443, 40, 22,
    function() return Settings.PauseWhenUnfocused end,
    function(value)
        Settings.PauseWhenUnfocused = value
        if value and not State.focused then releaseOrPause() end
    end)
local status = frame(body, "StatusCard", 24, 484, 392, 40, C.surface, 10)
UI.statusDot = frame(status, "Dot", 13, 12, 6, 6, C.dim, 4)
UI.status = label(status, "Status", "STANDBY", 26, 5, 354, 16, 9, C.muted, Enum.Font.GothamBold)
UI.detail = label(status, "Detail", "", 13, 22, 366, 12, 9, C.muted)
label(body, "Hotkeys", "F6  TOGGLE    /    F7  UNLOAD    /    R-SHIFT  HIDE", 26, 536, 390, 15, 9, C.dim, Enum.Font.GothamMedium)

local espBody = frame(panel, "ESPControls", 192, 74, W - 206, H - 102)
espBody.BackgroundTransparency, espBody.Visible = 1, false
local espMaster = frame(espBody, "ESPMasterCard", 24, 0, 392, 80, C.raised, 13)
UI.espMasterStroke = stroke(espMaster, C.accent, 0.65)
label(espMaster, "Eyebrow", "PLAYER VISUALS", 18, 10, 220, 14, 9, C.bright, Enum.Font.GothamBold)
label(espMaster, "Title", "Player ESP", 18, 27, 260, 24, 19, C.text, Enum.Font.GothamBold)
label(espMaster, "Hint", "Outlines and live player information.", 18, 53, 278, 15, 10, C.muted)
toggle(espMaster, "ESPMasterToggle", 318, 26, 54, 28,
    function() return Settings.ESPEnabled end, setESPEnabled)
label(espBody, "ESPOptionsLabel", "DISPLAY OPTIONS", 24, 103, 230, 15, 10, C.muted, Enum.Font.GothamBold)
UI.espCount = label(espBody, "ESPCount", "0 TRACKED", 276, 103, 140, 15, 10, C.accent, Enum.Font.GothamMedium)
UI.espCount.TextXAlignment = Enum.TextXAlignment.Right
local espOptionsCard = frame(espBody, "ESPOptionsCard", 24, 126, 392, 206, C.surface, 13)
stroke(espOptionsCard, C.line, 0.45)
local espOptions = {
    {property = "ESPShowNames", title = "Player names"},
    {property = "ESPShowDistance", title = "Distance labels"},
    {property = "ESPShowHealth", title = "Health bars"},
    {property = "ESPThroughWalls", title = "Show through walls"},
    {property = "ESPHideTeammates", title = "Hide teammates"},
}
for index, option in ipairs(espOptions) do
    local current, y = option, 15 + (index - 1) * 36
    label(espOptionsCard, current.property .. "Label", current.title, 16, y, 285, 24, 12, C.muted, Enum.Font.GothamMedium)
    toggle(espOptionsCard, current.property .. "Toggle", 336, y + 1, 40, 22,
        function() return Settings[current.property] end,
        function(value) Settings[current.property] = value; refreshESP() end)
end
local espRange = frame(espBody, "ESPRangeCard", 24, 354, 392, 106, C.surface, 13)
stroke(espRange, C.line, 0.45)
label(espRange, "Heading", "RANGE", 16, 11, 220, 16, 10, C.muted, Enum.Font.GothamBold)
slider("ESPRange", "Maximum distance", "ESPMaxDistance", 34, 100, 10000, {
    parent = espRange, step = 50, format = "%.0f studs", onChange = refreshESP,
})
label(espRange, "Hint", "Players outside this range are hidden.", 16, 80, 360, 14, 9, C.dim)
local espStatusCard = frame(espBody, "ESPStatusCard", 24, 484, 392, 40, C.surface, 10)
UI.espStatusDot = frame(espStatusCard, "Dot", 13, 12, 6, 6, C.dim, 4)
UI.espStatus = label(espStatusCard, "ESPStatus", "ESP OFF", 26, 5, 354, 16, 9, C.muted, Enum.Font.GothamBold)
UI.espDetail = label(espStatusCard, "Detail", "", 13, 22, 366, 12, 9, C.muted)
label(espBody, "ESPHotkeys", "F8  ESP    /    F7  UNLOAD    /    R-SHIFT  HIDE", 26, 536, 390, 15, 9, C.dim, Enum.Font.GothamMedium)

local healthBody = frame(panel, "HealthControls", 192, 74, W - 206, H - 102)
healthBody.BackgroundTransparency, healthBody.Visible = 1, false
do
    local master = frame(healthBody, "HealthMasterCard", 24, 0, 392, 80, C.raised, 13)
    UI.healthMasterStroke = stroke(master, C.accent, 0.65)
    label(master, "Eyebrow", "LOW HEALTH RESPONSE", 18, 10, 250, 14, 9, C.bright, Enum.Font.GothamBold)
    label(master, "Title", "Health escape", 18, 27, 260, 24, 19, C.text, Enum.Font.GothamBold)
    label(master, "Hint", "Teleport 70 studs above your current position.", 18, 53, 285, 15, 10, C.muted)
    toggle(master, "HealthMasterToggle", 318, 26, 54, 28,
        function() return Settings.HealthEscapeEnabled end, Guard.setEnabled)
    local live = frame(healthBody, "HealthLiveCard", 24, 96, 392, 98, C.surface, 13)
    stroke(live, C.line, 0.45)
    label(live, "Heading", "LIVE HEALTH", 16, 10, 220, 16, 10, C.muted, Enum.Font.GothamBold)
    UI.healthNumbers = label(live, "HealthNumbers", "-- / -- HP", 16, 32, 260, 28, 18, C.text, Enum.Font.GothamBold)
    UI.healthNumbers.TextTruncate = Enum.TextTruncate.AtEnd
    UI.healthPercent = label(live, "HealthPercent", "--%", 278, 29, 98, 32, 23, C.bright, Enum.Font.GothamBold)
    UI.healthPercent.TextXAlignment = Enum.TextXAlignment.Right
    local track = frame(live, "HealthTrack", 16, 75, 360, 6, C.line, 4)
    UI.healthFill = frame(track, "HealthFill", 0, 0, 0, 6, C.green, 4)
    UI.healthMarker = frame(track, "ThresholdMarker", 0, -3, 2, 12, C.red, 1)
    UI.healthMarker.AnchorPoint = Vector2.new(0.5, 0)
    local threshold = frame(healthBody, "HealthThresholdCard", 24, 210, 392, 112, C.surface, 13)
    stroke(threshold, C.line, 0.45)
    label(threshold, "Heading", "TRIGGER THRESHOLD", 16, 10, 260, 16, 10, C.muted, Enum.Font.GothamBold)
    slider("HealthThreshold", "Teleport at or below", "HealthThreshold", 34, 1, 95, {
        parent = threshold, step = 1, format = "%.0f%%",
    })
    UI.healthRearm = label(threshold, "RearmHint", "", 16, 82, 360, 16, 9, C.dim)
    local sources = frame(healthBody, "HealthSourceCard", 24, 338, 392, 100, C.surface, 13)
    stroke(sources, C.line, 0.45)
    label(sources, "Heading", "HEALTH SOURCE", 16, 10, 240, 16, 10, C.muted, Enum.Font.GothamBold)
    local rescan = button(sources, "HealthRescan", "Rescan", 314, 8, 62, 22, C.raised, 10)
    local previousSource = button(sources, "HealthSourcePrevious", "<", 16, 36, 28, 28, C.raised, 13)
    local nextSource = button(sources, "HealthSourceNext", ">", 348, 36, 28, 28, C.raised, 13)
    UI.healthSource = label(sources, "HealthSourceName", "Auto", 52, 36, 288, 28, 11, C.bright, Enum.Font.GothamMedium)
    UI.healthSource.TextTruncate = Enum.TextTruncate.AtEnd
    UI.healthSourceDetail = label(sources, "HealthSourceDetail", "", 16, 73, 360, 16, 9, C.muted)
    UI.healthSourceDetail.TextTruncate = Enum.TextTruncate.AtEnd
    connect(previousSource.Activated, function() Guard.cycleSource(-1) end)
    connect(nextSource.Activated, function() Guard.cycleSource(1) end)
    connect(rescan.Activated, function() Guard.nextScan = 0; Guard.step() end)
    label(healthBody, "HealthLockLabel", "Lock after teleport", 26, 451, 200, 22, 11, C.text)
    UI.healthRelease = button(healthBody, "HealthRelease", "Release", 278, 450, 72, 26, C.raised, 10)
    toggle(healthBody, "HealthLockToggle", 364, 451, 50, 24,
        function() return Settings.HealthLock end, Guard.setLock)
    connect(UI.healthRelease.Activated, function() Guard.release(); Guard.step() end)
    local status = frame(healthBody, "HealthStatusCard", 24, 484, 392, 40, C.surface, 10)
    UI.healthStatusDot = frame(status, "Dot", 13, 12, 6, 6, C.dim, 4)
    UI.healthStatus = label(status, "HealthStatus", "OFF", 26, 5, 354, 16, 9, C.muted, Enum.Font.GothamBold)
    UI.healthDetail = label(status, "HealthDetail", "", 13, 22, 366, 12, 9, C.muted)
    UI.healthDetail.TextTruncate = Enum.TextTruncate.AtEnd
    label(healthBody, "HealthHotkeys", "F9  HEALTH    /    F7  UNLOAD    /    R-SHIFT  HIDE",
        26, 536, 390, 15, 9, C.dim, Enum.Font.GothamMedium)
end

local farmBody = frame(panel, "FarmControls", 192, 74, W - 206, H - 102)
farmBody.BackgroundTransparency, farmBody.Visible = 1, false
do
    local master = frame(farmBody, "FarmMasterCard", 24, 0, 392, 80, C.raised, 13)
    stroke(master, C.accent, 0.65)
    label(master, "Eyebrow", "BOSS TRACKING", 18, 10, 250, 14, 9, C.bright, Enum.Font.GothamBold)
    label(master, "Title", "Auto farm", 18, 27, 260, 24, 19, C.text, Enum.Font.GothamBold)
    label(master, "Hint", "Auto-target NPCs and attack upward from below.", 18, 53, 285, 15, 10, C.muted)
    toggle(master, "FarmMasterToggle", 318, 26, 54, 28,
        function() return Settings.FarmEnabled end, Farm.setEnabled)
    local targets = frame(farmBody, "FarmTargetCard", 24, 96, 392, 172, C.surface, 13)
    stroke(targets, C.line, 0.45)
    UI.farmCount = label(targets, "FarmCount", "DETECTED TARGETS", 16, 10, 275, 16, 10, C.muted, Enum.Font.GothamBold)
    local rescan = button(targets, "FarmRescan", "Rescan", 314, 8, 62, 22, C.raised, 10)
    local previous = button(targets, "FarmPrevious", "<", 16, 38, 28, 28, C.raised, 13)
    local nextTarget = button(targets, "FarmNext", ">", 348, 38, 28, 28, C.raised, 13)
    UI.farmName = button(targets, "FarmTargetName", "Choose boss", 52, 38, 288, 28, C.raised, 14)
    UI.farmID = label(targets, "FarmTargetID", "--", 16, 72, 360, 16, 11, C.muted)
    UI.farmHP = label(targets, "FarmTargetHealth", "--", 16, 94, 360, 18, 12, C.green)
    UI.farmParts = label(targets, "FarmTargetParts", "--", 16, 118, 360, 16, 10, C.muted)
    UI.farmPath = label(targets, "FarmTargetPath", "--", 16, 142, 188, 16, 9, C.dim)
    label(targets, "AutoBossLabel", "Auto Boss", 216, 141, 100, 18, 10, C.bright, Enum.Font.GothamBold)
    toggle(targets, "AutoBossToggle", 326, 138, 50, 24,
        function() return Settings.AutoBoss end, Farm.setAutoBoss)
    for _, view in ipairs({UI.farmName, UI.farmID, UI.farmHP, UI.farmParts, UI.farmPath}) do
        view.TextTruncate = Enum.TextTruncate.AtEnd
    end
    connect(rescan.Activated, function() Farm.scan(true); Farm.step(); render() end)
    connect(previous.Activated, function() Farm.cycle(-1) end)
    connect(nextTarget.Activated, function() Farm.cycle(1) end)
    local picker = frame(farmBody, "BossPicker", 24, 96, 392, 432, C.panel, 13)
    picker.Visible, picker.ZIndex, picker.Active = false, 20, true
    local title = label(picker,"PickerTitle","REMEMBERED BOSSES",16,10,300,24,14,C.bright)
    title.ZIndex = 21
    local close = button(picker,"CloseBossPicker","X",348,10,28,26,C.raised,12); close.ZIndex=21
    connect(close.Activated,function() picker.Visible=false end)
    local configOpen = button(picker,"OpenBossConfig","Boss config",240,46,128,28,C.raised,11);configOpen.ZIndex=21
    local list = make("ScrollingFrame",picker,{Name="BossList",Position=UDim2.fromOffset(12,82),
        Size=UDim2.fromOffset(368,310),BackgroundTransparency=1,BorderSizePixel=0,
        ScrollBarThickness=4,ZIndex=21,Active=true,CanvasSize=UDim2.fromOffset(0,0)})
    local note=label(picker,"PickerNote","Boss config: autosave, first-run discovery and route controls.",12,400,368,20,10,C.muted)
    note.ZIndex=21
    local config = frame(farmBody,"BossConfig",24,96,392,432,C.panel,13)
    config.Visible,config.ZIndex,config.Active=false,25,true
    local function top(object) object.ZIndex=26;return object end
    top(label(config,"ConfigTitle","BOSS LOCATIONS / CONFIG",16,12,300,24,14,C.bright))
    local configClose=top(button(config,"CloseBossConfig","X",348,10,28,26,C.raised,12))
    connect(configClose.Activated,function() config.Visible=false end)
    connect(configOpen.Activated,function() picker.Visible=false;config.Visible=true end)
    -- Available without opening the picker, including during first-run travel.
    local quickConfig=button(master,"QuickBossConfig","Config",246,8,60,22,C.surface,10)
    connect(quickConfig.Activated,function() picker.Visible=false;config.Visible=not config.Visible end)
    local function configToggle(name,text,y,key)
        top(label(config,name.."Label",text,16,y,288,24,11,C.text))
        toggle(config,name,326,y,50,24,function() return Settings[key] end,
            function(value) Farm.setConfig(key,value) end)
    end
    configToggle("BossSaveToggle","Autosave boss locations",50,"BossAutoSave")
    configToggle("BossFirstRunToggle","Legacy moving discovery on first run",86,"BossFirstDiscovery")
    configToggle("BossGridToggle","Grid search beyond timer markers",122,"BossGridSearch")
    UI.bossDwell=top(button(config,"BossDwell","",16,160,174,30,C.raised,11))
    UI.bossRadius=top(button(config,"BossRadius","",202,160,174,30,C.raised,11))
    connect(UI.bossDwell.Activated,function()
        local values={1,1.5,2.5,4};local nextValue=1
        for i,v in ipairs(values) do if v==Settings.BossDwell then nextValue=values[i%#values+1];break end end
        Farm.setConfig("BossDwell",nextValue)
    end)
    connect(UI.bossRadius.Activated,function()
        local values={1024,2048,4096,8192};local nextValue=1024
        for i,v in ipairs(values) do if v==Settings.BossGridRadius then nextValue=values[i%#values+1];break end end
        Farm.setConfig("BossGridRadius",nextValue)
    end)
    UI.bossDiscover=top(button(config,"BossDiscovery","Start discovery",16,202,222,32,C.raised,12))
    connect(UI.bossDiscover.Activated,function()
        if State.discovering or Farm.pendingDiscovery then Farm.stopDiscovery() else Farm.startDiscovery() end
    end)
    local saveNow=top(button(config,"BossSaveNow","Save now",250,202,126,32,C.raised,12))
    connect(saveNow.Activated,function() Farm.markDirty();Farm.saveConfig(true,false,true) end)
    UI.bossSaveStatus=top(label(config,"BossSaveStatus","",16,246,360,36,11,C.muted))
    UI.bossDiscoveryStatus=top(label(config,"BossDiscoveryStatus","",16,286,360,44,11,C.bright))
    UI.bossSaveStatus.TextWrapped,UI.bossDiscoveryStatus.TextWrapped=true,true
    local help=top(label(config,"BossConfigHelp",
        "Static scan is primary and never moves you. This legacy grid route is only a fallback for content Roblox will not replicate from spawn.",
        16,372,360,46,9,C.muted));help.TextWrapped=true
    local shareOpen=top(button(config,"BossShareOpen","Export / import location code",16,334,360,30,C.raised,12))
    local share=frame(farmBody,"BossSharePanel",24,96,392,432,C.panel,13)
    share.Visible,share.ZIndex,share.Active=false,30,true
    local title=label(share,"ShareTitle","SHARE BOSS LOCATIONS",16,12,315,24,14,C.bright);title.ZIndex=31
    local back=button(share,"BossShareBack","X",348,10,28,26,C.raised,12);back.ZIndex=31
    local hint=label(share,"ShareHint","Export yours, or paste another player's complete code.",16,42,360,24,10,C.muted);hint.ZIndex=31
    local codeBox=make("TextBox",share,{Name="BossShareCode",Position=UDim2.fromOffset(16,74),
        Size=UDim2.fromOffset(360,200),BackgroundColor3=C.surface,TextColor3=C.text,TextSize=11,
        Font=Enum.Font.Code,Text="",PlaceholderText="ASLOC1:...",ClearTextOnFocus=false,MultiLine=true,
        TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
        BorderSizePixel=0,ZIndex=31})
    local export=button(share,"BossExportCode","Export",16,286,112,32,C.raised,12);export.ZIndex=31
    local copy=button(share,"BossCopyCode","Copy",140,286,112,32,C.raised,12);copy.ZIndex=31
    local import=button(share,"BossImportCode","Import",264,286,112,32,C.raised,12);import.ZIndex=31
    local status=label(share,"BossShareStatus","Same Roblox place only. Existing locations are kept.",16,328,360,44,11,C.bright)
    status.TextWrapped,status.ZIndex=true,31
    local note=label(share,"ShareNote","Import loads the location list; bosses load when you travel there. Autosave keeps imported locations if file support is available.",16,378,360,42,10,C.muted)
    note.TextWrapped,note.ZIndex=true,31
    connect(shareOpen.Activated,function()
        Farm.stopDiscovery("Paused for location-code import/export")
        config.Visible=false;share.Visible=true
    end)
    connect(back.Activated,function() share.Visible=false;config.Visible=true end)
    connect(export.Activated,function()
        local code,message=Farm.exportCode()
        if code then codeBox.Text=code end
        status.Text=message
    end)
    connect(copy.Activated,function()
        if codeBox.Text=="" then status.Text="Export a code first.";return end
        local clipboard=type(setclipboard)=="function" and setclipboard or environment.setclipboard
        if type(clipboard)=="function" then
            local ok=pcall(clipboard,codeBox.Text)
            if ok then status.Text="Copied. Send the complete code to the other player.";return end
        end
        pcall(function() codeBox:CaptureFocus();codeBox.SelectionStart=1;codeBox.CursorPosition=#codeBox.Text+1 end)
        status.Text="Clipboard unavailable. Select the text and press Ctrl+C."
    end)
    connect(import.Activated,function()
        local ok,message=Farm.importCode(codeBox.Text)
        status.Text=message
        if ok then pcall(function() codeBox:ReleaseFocus() end) end
    end)
    for _,object in ipairs(config:GetDescendants()) do
        if object:IsA("GuiObject") then object.ZIndex=26 end
    end
    connect(UI.farmName.Activated,function()
        Farm.scan(true)
        for _, child in ipairs(list:GetChildren()) do child:Destroy() end
        local function row(text,key,index)
            local item=button(list,"BossOption"..index,text,0,index*38,356,34,C.raised,11)
            item.ZIndex=22; item.TextTruncate=Enum.TextTruncate.AtEnd
            item.Activated:Connect(function() picker.Visible=false; Farm.choose(key) end)
        end
        row("Auto nearest — loaded NPCs",nil,0)
        for i,entry in ipairs(Farm.remembered) do
            local hp,_,_,root=Farm.read(entry.live)
            local state=hp and (hp<=0 and "dead" or (root and "loaded" or "partial")) or "unloaded"
            row(entry.name.."  ["..state.."]",entry.path,i)
        end
        list.CanvasSize=UDim2.fromOffset(0,(#Farm.remembered+1)*38)
        picker.Visible=true
    end)
    local options = frame(farmBody, "FarmOptionsCard", 24, 284, 392, 244, C.surface, 13)
    stroke(options, C.line, 0.45)
    label(options, "FilterLabel", "Target MaxHP: 3,000 - 3,200 (locked)", 16, 10, 280, 24, 11, C.text)
    toggle(options, "FarmHealthOnlyToggle", 326, 10, 50, 24,
        function() return true end, function()
            Settings.FarmHealthOnly = true
            Farm.selected, Farm.pinned = nil, nil; Farm.scan(true); render()
        end)
    label(options, "SkillsLabel", "Use selected Z / X / C / V skills", 16, 45, 280, 24, 11, C.text)
    toggle(options, "FarmSkillsToggle", 326, 45, 50, 24,
        function() return Settings.FarmUseSkills end, function(value)
            Settings.FarmUseSkills = value; releaseOrPause()
        end)
    label(options, "HitboxLabel", "Expand target hitbox (local)", 16, 79, 280, 24, 11, C.text)
    toggle(options, "FarmHitboxToggle", 326, 79, 50, 24,
        function() return Settings.FarmExpandHitbox end, function(value)
            Settings.FarmExpandHitbox = value
            if not value then Farm.restoreHitbox() end
        end)
    label(options, "M1Label", "Auto M1 (inventory pulse bypass)", 16, 113, 280, 24, 11, C.text)
    toggle(options, "FarmM1Toggle", 326, 113, 50, 24,
        function() return Settings.FarmM1 end, Farm.setM1)
    label(options, "LootLabel", "Auto chest + ground loot", 16, 147, 280, 24, 11, C.text)
    toggle(options, "FarmLootToggle", 326, 147, 50, 24,
        function() return Settings.FarmAutoLoot end, Farm.setLoot)
    slider("FarmDepth", "Below target root (default 7)", "FarmDepth", 183, 6, 7, {
        parent = options, step = 0.1, format = "%.1f studs",
    })
    UI.farmHint = label(farmBody, "FarmHint", "Targets qualify by maximum HP, even after taking damage.", 26, 532, 390, 14, 9, C.dim)
    local status = frame(farmBody, "FarmStatusCard", 24, 554, 392, 40, C.surface, 10)
    UI.farmStatus = label(status, "FarmStatus", "OFF", 13, 5, 366, 16, 9, C.muted, Enum.Font.GothamBold)
    UI.farmDetail = label(status, "FarmDetail", "", 13, 22, 366, 12, 9, C.muted)
    UI.farmDetail.TextTruncate = Enum.TextTruncate.AtEnd
    label(farmBody, "FarmFooter", "OFF returns to the farming start point. F7 unloads all.", 26, 604, 390, 14, 9, C.dim)
end

local moveBody = frame(panel, "MovementControls", 192, 74, W - 206, H - 102)
moveBody.BackgroundTransparency, moveBody.Visible = 1, false

local moveMaster = frame(moveBody, "MovementMasterCard", 24, 0, 392, 80, C.raised, 13)
UI.moveMasterStroke = stroke(moveMaster, C.accent, 0.18)
label(moveMaster, "Eyebrow", "LOCAL MOVEMENT", 18, 10, 220, 14, 9, C.bright, Enum.Font.GothamBold)
label(moveMaster, "Title", "Movement", 18, 27, 260, 24, 19, C.text, Enum.Font.GothamBold)
label(moveMaster, "Hint", "Fly, no-clip and speed controls.", 18, 53, 278, 15, 10, C.muted)

local moveOptions = frame(moveBody, "MovementOptionsCard", 24, 103, 392, 344, C.surface, 13)
stroke(moveOptions, C.line, 0.45)

label(moveOptions, "FlyLabel", "Fly", 16, 14, 280, 24, 12, C.text, Enum.Font.GothamMedium)
toggle(moveOptions, "FlyToggle", 326, 14, 50, 24,
    function() return Settings.FlyEnabled end, Movement.setFly)

label(moveOptions, "NoClipLabel", "No Clip (starts ON)", 16, 52, 280, 24, 12, C.text, Enum.Font.GothamMedium)
toggle(moveOptions, "NoClipToggle", 326, 52, 50, 24,
    function() return Settings.NoClip end, Movement.setNoClip)

label(moveOptions, "SpeedToggleLabel", "Speed override", 16, 90, 280, 24, 12, C.text, Enum.Font.GothamMedium)
toggle(moveOptions, "SpeedToggle", 326, 90, 50, 24,
    function() return Settings.SpeedEnabled end, Movement.setSpeed)

slider("MoveFlySpeed", "Fly speed", "FlySpeed", 132, 20, 250, {
    parent = moveOptions, step = 5, format = "%.0f studs/s",
})
slider("MoveWalkSpeed", "Walk speed", "WalkSpeed", 205, 16, 150, {
    parent = moveOptions, step = 2, format = "%.0f",
    onChange = function()
        if Settings.SpeedEnabled then Movement.setSpeed(true) end
    end,
})

local flyHelp = label(moveOptions, "FlyHelp",
    "Fly: WASD follows full camera direction | Space/E up | Ctrl/Q down. Fly automatically uses No Clip.",
    16, 274, 360, 52, 10, C.muted)
flyHelp.TextWrapped = true

local moveStatusCard = frame(moveBody, "MovementStatusCard", 24, 470, 392, 58, C.surface, 10)
UI.moveStatusDot = frame(moveStatusCard, "Dot", 13, 14, 6, 6, C.green, 4)
UI.moveStatus = label(moveStatusCard, "Status", "NOCLIP ON", 26, 7, 354, 16, 10, C.green, Enum.Font.GothamBold)
UI.moveDetail = label(moveStatusCard, "Detail", "No-clip is active automatically.", 13, 28, 366, 22, 9, C.muted)
UI.moveDetail.TextWrapped = true

label(moveBody, "MovementFooter",
    "No Clip activates as soon as this script executes. F7 unload restores movement state.",
    26, 548, 390, 32, 9, C.dim, Enum.Font.GothamMedium)


local systemBody = frame(panel, "SystemControls", 192, 74, W - 206, H - 102)
systemBody.BackgroundTransparency, systemBody.Visible = 1, false

local systemMaster = frame(systemBody, "SystemMasterCard", 24, 0, 392, 80, C.raised, 13)
UI.systemMasterStroke = stroke(systemMaster, C.accent, 0.18)
label(systemMaster, "Eyebrow", "RECOVERY + DISCOVERY", 18, 10, 250, 14, 9, C.bright, Enum.Font.GothamBold)
label(systemMaster, "Title", "System", 18, 27, 260, 24, 19, C.text, Enum.Font.GothamBold)
label(systemMaster, "Hint", "Static map scan, private rejoin and persistence.", 18, 53, 330, 15, 10, C.muted)

local scanCard = frame(systemBody, "StaticScanCard", 24, 103, 392, 126, C.surface, 13)
stroke(scanCard, C.line, 0.45)
label(scanCard, "ScanEyebrow", "STATIC MAP SCAN", 16, 12, 210, 14, 9, C.bright, Enum.Font.GothamBold)
label(scanCard, "ScanTitle", "500,000-stud boss discovery", 16, 31, 280, 22, 13, C.text, Enum.Font.GothamBold)
local scanHint = label(scanCard, "ScanHint",
    "Reads replicated boss/spawn/timer coordinates while your character stays at spawn.",
    16, 54, 360, 32, 10, C.muted)
scanHint.TextWrapped = true
toggle(scanCard, "StaticScanToggle", 326, 12, 50, 24,
    function() return Settings.StaticMapScan end, System.setStaticScan)
UI.staticScanButton = button(scanCard, "StaticScanNow", "Scan map now", 16, 90, 142, 26, C.raised, 11)
UI.staticScanStatus = label(scanCard, "StaticScanStatus", "", 170, 89, 206, 28, 9, C.muted)
UI.staticScanStatus.TextWrapped = true
connect(UI.staticScanButton.Activated, function()
    Farm.staticMapScan(true)
end)

local rejoinCard = frame(systemBody, "RejoinCard", 24, 243, 392, 148, C.surface, 13)
stroke(rejoinCard, C.line, 0.45)
label(rejoinCard, "RejoinEyebrow", "PRIVATE SERVER RECOVERY", 16, 12, 240, 14, 9, C.bright, Enum.Font.GothamBold)
label(rejoinCard, "RejoinLabel", "Auto rejoin", 16, 36, 220, 22, 12, C.text, Enum.Font.GothamMedium)
toggle(rejoinCard, "AutoRejoinToggle", 326, 35, 50, 24,
    function() return Settings.AutoRejoin end, System.setAutoRejoin)
label(rejoinCard, "MapLabel", "Target map", 16, 70, 90, 20, 10, C.muted, Enum.Font.GothamBold)
UI.privateMapBox = make("TextBox", rejoinCard, {
    Name = "PrivateMap",
    Position = UDim2.fromOffset(108, 67),
    Size = UDim2.fromOffset(268, 28),
    BackgroundColor3 = C.raised,
    BorderSizePixel = 0,
    Text = Settings.PrivateServerMap,
    PlaceholderText = "Ouwigahara",
    TextColor3 = C.text,
    PlaceholderColor3 = C.dim,
    TextSize = 11,
    Font = Enum.Font.GothamMedium,
    ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
})
corner(UI.privateMapBox, 8)
UI.rejoinStatus = label(rejoinCard, "RejoinStatus", "", 16, 104, 360, 34, 9, C.muted)
UI.rejoinStatus.TextWrapped = true
connect(UI.privateMapBox.FocusLost, function()
    System.setPrivateMap(UI.privateMapBox.Text)
end)

local persistCard = frame(systemBody, "PersistCard", 24, 405, 392, 116, C.surface, 13)
stroke(persistCard, C.line, 0.45)
label(persistCard, "PersistEyebrow", "PERSISTENCE", 16, 12, 180, 14, 9, C.bright, Enum.Font.GothamBold)
label(persistCard, "PersistLabel", "Auto execute", 16, 36, 220, 22, 12, C.text, Enum.Font.GothamMedium)
toggle(persistCard, "AutoExecuteToggle", 326, 35, 50, 24,
    function() return Settings.AutoExecute end, System.setAutoExecute)
local persistHint = label(persistCard, "PersistHint",
    "Queues itself across teleports and installs a best-effort executor autoexec loader for this Roblox universe only.",
    16, 68, 360, 38, 9, C.muted)
persistHint.TextWrapped = true

local systemStatusCard = frame(systemBody, "SystemStatusCard", 24, 535, 392, 70, C.surface, 11)
UI.systemStatusDot = frame(systemStatusCard, "Dot", 13, 15, 6, 6, C.green, 4)
UI.systemStatus = label(systemStatusCard, "Status", "READY", 26, 8, 350, 16, 10, C.green, Enum.Font.GothamBold)
UI.systemDetail = label(systemStatusCard, "Detail", "", 13, 29, 366, 34, 9, C.muted)
UI.systemDetail.TextWrapped = true


-- Reference-style content shell. All original controls stay inside a centered
-- 440px content canvas, so behavior/callbacks are untouched while the outer
-- layout becomes a wide cyan game-control panel.
local function skinPage(page)
    page.BackgroundColor3 = Color3.fromRGB(6, 18, 29)
    page.BackgroundTransparency = 0.08
    page.ClipsDescendants = true
    corner(page, 12)
    stroke(page, C.line, 0.42)

    local oldChildren = {}
    for _, child in ipairs(page:GetChildren()) do
        if not child:IsA("UICorner") and not child:IsA("UIStroke") then
            oldChildren[#oldChildren + 1] = child
        end
    end

    local inner = frame(page, "PageContent", math.floor(((W - 206) - 440) / 2), 0, 440, H - 102)
    inner.BackgroundTransparency = 1

    for _, child in ipairs(oldChildren) do
        child.Parent = inner
    end

    -- Give cards a cooler cyan edge without changing their geometry.
    for _, object in ipairs(inner:GetDescendants()) do
        if object:IsA("Frame") and object.BackgroundTransparency < 1 then
            local existing = object:FindFirstChildOfClass("UIStroke")
            if existing then
                existing.Color = C.line
            end
        elseif object:IsA("TextButton") then
            local existing = object:FindFirstChildOfClass("UIStroke")
            if existing and object.Name ~= "HeaderToggle" then
                existing.Color = C.line
            end
        end
    end
end

for _, page in ipairs({body, espBody, healthBody, farmBody, moveBody, systemBody}) do
    skinPage(page)
end

local footerBar = frame(panel, "FooterBar", 0, H - 30, W, 30, Color3.fromRGB(4, 13, 21))
stroke(footerBar, C.line, 0.45)
local footerDot = frame(footerBar, "ConnectedDot", 16, 11, 7, 7, C.green, 4)
UI.footerConnected = label(footerBar, "Connected", "CONNECTED", 30, 5, 110, 20, 9, C.green, Enum.Font.GothamBold)
label(footerBar, "Divider1", "|", 139, 5, 12, 20, 9, C.dim, Enum.Font.GothamMedium)
label(footerBar, "FooterHint", "F7 UNLOAD    /    R-SHIFT HIDE", 156, 5, 260, 20, 9, C.muted, Enum.Font.GothamMedium)
local footerVersion = label(footerBar, "FooterVersion", "v1.5.0", W - 90, 5, 72, 20, 9, C.dim, Enum.Font.GothamMedium)
footerVersion.TextXAlignment = Enum.TextXAlignment.Right
UI.footerBar = footerBar

local function fitWindow(centerIfNeeded)
    if not State.alive then return end
    local viewport = canvas.AbsoluteSize
    if viewport.X <= 0 or viewport.Y <= 0 then return end
    uiScale.Scale = math.clamp(math.min((viewport.X - 28) / W, (viewport.Y - 48) / H), 0.32, 1)
    local width = W * uiScale.Scale
    local height = (State.minimized and 78 or H) * uiScale.Scale
    local maxX, maxY = math.max(12, viewport.X - width - 12), math.max(44, viewport.Y - height - 12)
    local x, y = holder.Position.X.Offset, holder.Position.Y.Offset
    if centerIfNeeded then x, y = 24, 58 end
    holder.Position = UDim2.fromOffset(math.clamp(x, 12, maxX), math.clamp(y, 44, maxY))
end
local function setMinimized(value)
    State.minimized = value
    minimize.Text = value and "+" or "-"
    local height = value and 60 or H
    animate(panel, {Size = UDim2.fromOffset(W, height)})
    animate(halo, {Size = UDim2.fromOffset(W + 4, height + 4)})
    animate(shadow, {Size = UDim2.fromOffset(W + 12, height + 12)})
    holder.Size = UDim2.fromOffset(W, height)
    render()
    fitWindow(false)
end
render = function()
    if not State.alive then return end
    local running, statusName, description = availability()
    local count = selectedCount()
    local color = State.fault and C.red or (running and C.green or (State.enabled and C.amber or C.dim))
    UI.badge.Text = State.enabled and (running and "ON" or "PAUSED")
        or (State.farming and Settings.FarmUseSkills and (running and "FARM" or "PAUSED") or "OFF")
    UI.badge.TextColor3 = color
    UI.badge.BackgroundColor3 = State.enabled and C.raised or C.surface
    UI.status.Text, UI.detail.Text = statusName, description
    UI.status.TextColor3, UI.statusDot.BackgroundColor3 = color, color
    UI.count.Text = tostring(count) .. " / 4 ENABLED"
    UI.cycle.Text = count > 0 and string.format("~ %.2f s / cycle", count * (Settings.HoldTime + Settings.KeyGap)) or "No keys selected"
    UI.masterStroke.Transparency = State.enabled and 0.18 or 0.65
    tabs.Visible = not State.minimized
    sidebarInfo.Visible = not State.minimized
    UI.footerBar.Visible = not State.minimized
    body.Visible = not State.minimized and State.tab == "Skills"
    espBody.Visible = not State.minimized and State.tab == "ESP"
    healthBody.Visible = not State.minimized and State.tab == "Health"
    farmBody.Visible = not State.minimized and State.tab == "Farm"
    moveBody.Visible = not State.minimized and State.tab == "Move"
    systemBody.Visible = not State.minimized and State.tab == "System"
    UI.farmTab.BackgroundColor3 = State.tab == "Farm" and C.raised or C.surface
    UI.farmTab.TextColor3 = State.tab == "Farm" and C.bright or C.dim
    UI.skillsTab.BackgroundColor3 = State.tab == "Skills" and C.raised or C.surface
    UI.skillsTab.TextColor3 = State.tab == "Skills" and C.bright or C.dim
    UI.espTab.BackgroundColor3 = State.tab == "ESP" and C.raised or C.surface
    UI.espTab.TextColor3 = State.tab == "ESP" and C.bright or C.dim
    UI.healthTab.BackgroundColor3 = State.tab == "Health" and C.raised or C.surface
    UI.healthTab.TextColor3 = State.tab == "Health" and C.bright or C.dim
    UI.moveTab.BackgroundColor3 = State.tab == "Move" and C.raised or C.surface
    UI.moveTab.TextColor3 = State.tab == "Move" and C.bright or C.dim
    UI.systemTab.BackgroundColor3 = State.tab == "System" and C.raised or C.surface
    UI.systemTab.TextColor3 = State.tab == "System" and C.bright or C.dim
    for key, navStroke in pairs(UI.navStrokes) do
        local selected = State.tab == key
        navStroke.Transparency = selected and 0.08 or 0.86
        UI.navBars[key].Visible = selected
    end
    UI.sidebarState.Text = State.fault and "ERROR" or "CONNECTED"
    UI.sidebarState.TextColor3 = State.fault and C.red or C.green
    UI.footerConnected.Text = State.fault and "ERROR" or "CONNECTED"
    UI.footerConnected.TextColor3 = State.fault and C.red or C.green
    footerDot.BackgroundColor3 = State.fault and C.red or C.green
    local espColor = State.espFault and C.red or (Settings.ESPEnabled and C.green or C.dim)
    UI.espStatus.Text = State.espFault and "ESP ERROR" or (Settings.ESPEnabled and "ESP ACTIVE" or "ESP OFF")
    UI.espStatus.TextColor3, UI.espStatusDot.BackgroundColor3 = espColor, espColor
    UI.espDetail.Text = State.espFault or (Settings.ESPEnabled
        and (tostring(State.espCount) .. " players in range. F8 toggles ESP.")
        or "Turn on Player ESP or press F8 to begin.")
    UI.espCount.Text = tostring(State.espCount) .. " TRACKED"
    UI.espMasterStroke.Transparency = Settings.ESPEnabled and 0.18 or 0.65
    if State.tab == "ESP" then
        UI.badge.Text = State.espFault and "ERROR" or (Settings.ESPEnabled and "ESP ON" or "ESP OFF")
        UI.badge.TextColor3 = espColor
        UI.badge.BackgroundColor3 = Settings.ESPEnabled and C.raised or C.surface
    end
    local hpColor = Guard.fault and C.red or (Settings.HealthEscapeEnabled
        and (Guard.status == "ARMED" and C.green or C.amber) or C.dim)
    UI.healthStatus.Text, UI.healthDetail.Text = Guard.status, Guard.detail
    UI.healthStatus.TextColor3, UI.healthStatusDot.BackgroundColor3 = hpColor, hpColor
    UI.healthMasterStroke.Transparency = Settings.HealthEscapeEnabled and 0.18 or 0.65
    UI.healthSource.Text, UI.healthSourceDetail.Text = Guard.sourceLabel, Guard.sourceDetail
    UI.healthRearm.Text = string.format("Re-arm at %.0f%% health. Minimum 5 seconds between escapes.", Settings.HealthThreshold + 5)
    UI.healthNumbers.Text = Guard.current and string.format("%.0f / %.0f HP", Guard.current, Guard.maximum) or "-- / -- HP"
    UI.healthPercent.Text = Guard.percent and string.format("%.1f%%", Guard.percent) or "--%"
    UI.healthFill.Size = UDim2.fromScale((Guard.percent or 0) / 100, 1)
    UI.healthFill.BackgroundColor3 = Guard.percent and Guard.percent <= Settings.HealthThreshold and C.red or C.green
    UI.healthMarker.Position = UDim2.new(Settings.HealthThreshold / 100, 0, 0, -3)
    if State.tab == "Health" then
        UI.badge.Text = Guard.fault and "ERROR" or (Settings.HealthEscapeEnabled and "HP ON" or "HP OFF")
        UI.badge.TextColor3 = hpColor
        UI.badge.BackgroundColor3 = Settings.HealthEscapeEnabled and C.raised or C.surface
    end
    UI.healthRelease.TextColor3 = Guard.held and C.bright or C.dim
    UI.bossDwell.Text=string.format("Dwell: %.1fs (click)",Settings.BossDwell)
    UI.bossRadius.Text=string.format("Radius: %d (click)",Settings.BossGridRadius)
    UI.bossDiscover.Text=(State.discovering or Farm.pendingDiscovery) and "Stop discovery / return" or "Start discovery"
    UI.bossSaveStatus.Text=Farm.configStatus
    UI.bossDiscoveryStatus.Text=Farm.pendingDiscovery and "First-run discovery starts shortly..." or Farm.discoveryStatus
    UI.farmHint.Text = Settings.AutoBoss
        and string.format("Auto Boss: %.0f-stud route | %.0f-stud local target scan | %d static/saved locations.", Settings.BossAutoRange, Settings.BossLocalScanRadius, Farm.staticScanCount or #Farm.remembered)
        or (Farm.count == 0 and string.format("%d NPC rigs loaded. Move near a target, then Rescan.", Farm.scanned or 0)
            or "Click the boss name to choose a remembered target.")
    UI.farmCount.Text = Settings.AutoBoss
        and string.format("%d ALIVE / %d SAVED / AUTO", Farm.aliveCount, #Farm.remembered)
        or string.format("%d ALIVE / %d REMEMBERED", Farm.aliveCount, #Farm.remembered)
    local remembered = Farm.pinned and Farm.catalog[Farm.pinned]
    UI.farmName.Text = remembered and remembered.name or (Farm.selected and Farm.selected.name or (Settings.AutoBoss and "Auto Boss: finding next" or "Choose boss / Auto nearest"))
    UI.farmID.Text = Farm.selected and Farm.selected.id or "--"
    UI.farmPath.Text = Farm.selected and Farm.selected.path or "Replicated NPCs with Humanoids"
    local targetHP, targetMax, targetHumanoid, targetRoot = Farm.read(Farm.selected)
    UI.farmHP.Text = targetHP and string.format("%s  /  %.0f of %.0f HP", targetHP > 0 and "ALIVE" or "DEAD", targetHP, targetMax) or (remembered and "UNLOADED / HEALTH UNKNOWN" or "UNAVAILABLE")
    UI.farmHP.TextColor3 = targetHP and targetHP > 0 and C.green or C.red
    UI.farmParts.Text = targetHumanoid and ("Humanoid: " .. targetHumanoid.Name .. "  /  Root: " .. (targetRoot and targetRoot.Name or "missing")) or (remembered and "Saved location; enable Farm to travel" or "Humanoid / root unavailable")
    if remembered and remembered.timerText and os.clock()-(remembered.timerAt or 0)<5 then
        UI.farmParts.Text="Observed timer: "..remembered.timerText
    end
    UI.farmStatus.Text, UI.farmDetail.Text = Farm.status, Farm.detail
    UI.farmStatus.TextColor3 = Farm.fault and C.red or (State.farming and C.green or C.muted)
    if State.tab == "Farm" then
        UI.badge.Text = Farm.fault and "ERROR" or (Settings.AutoBoss and "BOSS AUTO" or (Settings.FarmEnabled and "FARM ON" or "OFF"))
        UI.badge.TextColor3 = State.farming and C.green or C.dim
        UI.badge.BackgroundColor3 = Settings.FarmEnabled and C.raised or C.surface
    end
    if State.tab == "Move" then
        local movementOn = Settings.FlyEnabled or Settings.SpeedEnabled or Settings.NoClip
        local movementColor = movementOn and C.green or C.dim
        UI.badge.Text = Settings.FlyEnabled and "FLY ON" or (Settings.NoClip and "NOCLIP" or (Settings.SpeedEnabled and "SPEED" or "OFF"))
        UI.badge.TextColor3 = movementColor
        UI.badge.BackgroundColor3 = movementOn and C.raised or C.surface
        UI.moveStatus.Text = Movement.status
        UI.moveDetail.Text = Movement.detail
        UI.moveStatus.TextColor3 = movementColor
        UI.moveStatusDot.BackgroundColor3 = movementColor
        UI.moveMasterStroke.Transparency = movementOn and 0.18 or 0.65
    end
    if State.tab == "System" then
        local systemOn = Settings.StaticMapScan or Settings.AutoRejoin or Settings.AutoExecute
        local systemColor = systemOn and C.green or C.dim

        UI.badge.Text = Settings.AutoRejoin and "RECOVERY" or "SYSTEM"
        UI.badge.TextColor3 = systemColor
        UI.badge.BackgroundColor3 = systemOn and C.raised or C.surface

        UI.staticScanButton.Text = Farm.staticScanBusy and "Scanning..." or "Scan map now"
        UI.staticScanStatus.Text = Farm.staticScanStatus
        UI.rejoinStatus.Text = System.rejoinStatus
        UI.privateMapBox.Text = Input:GetFocusedTextBox() == UI.privateMapBox
            and UI.privateMapBox.Text or Settings.PrivateServerMap

        UI.systemStatus.Text = System.status
        UI.systemStatus.TextColor3 = systemColor
        UI.systemStatusDot.BackgroundColor3 = systemColor
        UI.systemDetail.Text = System.persistStatus .. "\n" .. System.friendReadyStatus
        UI.systemMasterStroke.Transparency = systemOn and 0.18 or 0.65
    end
    for _, view in ipairs(toggleViews) do
        local value = view.getter()
        if view.last ~= value then
            local instant = view.last == nil
            view.last = value
            animate(view.track, {BackgroundColor3 = value and C.accent or C.line}, instant)
            animate(view.knob, {
                Position = UDim2.fromOffset(value and (view.width - view.height + 4) or 4, 4),
                BackgroundColor3 = value and C.text or C.muted,
            }, instant)
        end
    end
    for index, skill in ipairs(Skills) do
        local view = UI.keys[index]
        local pressed = State.heldKey == skill.key
        if view.selected ~= skill.enabled or view.pressed ~= pressed then
            view.selected, view.pressed = skill.enabled, pressed
            view.button.BackgroundColor3 = pressed and Color3.fromRGB(12, 75, 99) or (skill.enabled and C.raised or C.surface)
            view.border.Color = pressed and C.bright or (skill.enabled and C.accent or C.line)
            view.border.Transparency = pressed and 0 or (skill.enabled and 0.58 or 0.45)
            view.keyText.TextColor3 = skill.enabled and C.bright or C.dim
            view.dot.BackgroundColor3 = skill.enabled and C.accent or C.line
            view.hint.Text = pressed and "PRESSING" or (skill.enabled and "ENABLED" or "DISABLED")
            view.hint.TextColor3 = pressed and C.bright or C.muted
            view.flash.BackgroundTransparency = pressed and 0 or 1
        end
    end
    for _, view in ipairs(sliders) do
        local value = Settings[view.property]
        local fraction = (value - view.minimum) / (view.maximum - view.minimum)
        view.valueLabel.Text = string.format(view.format, value)
        view.fill.Size = UDim2.new(fraction, 0, 1, 0)
        view.knob.Position = UDim2.new(fraction, 0, 0.5, 0)
    end
    for _, preset in ipairs(presets) do
        local selected = math.abs(Settings.KeyGap - preset.gap) < 0.001 and math.abs(Settings.HoldTime - preset.hold) < 0.001
        preset.button.BackgroundColor3 = selected and C.raised or C.panel
        preset.button.TextColor3 = selected and C.bright or C.dim
    end
end
connect(UI.skillsTab.Activated, function() State.tab = "Skills"; State.gesture = nil; render() end)
connect(UI.espTab.Activated, function() State.tab = "ESP"; State.gesture = nil; render() end)
connect(UI.farmTab.Activated, function() State.tab = "Farm"; State.gesture = nil; Farm.scan(true); Farm.step(); render() end)
connect(UI.healthTab.Activated, function() State.tab = "Health"; State.gesture = nil; Guard.step() end)
connect(UI.moveTab.Activated, function() State.tab = "Move"; State.gesture = nil; Movement.step(0); render() end)
connect(UI.systemTab.Activated, function() State.tab = "System"; State.gesture = nil; render() end)
connect(UI.badge.Activated, function()
    if State.tab == "ESP" then setESPEnabled(not Settings.ESPEnabled)
    elseif State.tab == "Farm" then Farm.setEnabled(not Settings.FarmEnabled)
    elseif State.tab == "Health" then Guard.setEnabled(not Settings.HealthEscapeEnabled)
    elseif State.tab == "Move" then Movement.setFly(not Settings.FlyEnabled)
    elseif State.tab == "System" then System.setAutoRejoin(not Settings.AutoRejoin)
    else setEnabled(not State.enabled) end
end)
connect(minimize.Activated, function() setMinimized(not State.minimized) end)
connect(close.Activated, function() controller.Stop() end)
connect(root.Destroying, function() controller.Stop() end)
connect(canvas:GetPropertyChangedSignal("AbsoluteSize"), function() fitWindow(false) end)
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        State.gesture = {kind = "window", input = input, start = input.Position,
            x = holder.Position.X.Offset, y = holder.Position.Y.Offset}
        releaseOrPause()
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
    else
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
connect(Input.InputBegan, function(input, processed)
    if Settings.NoClip and input.KeyCode == Enum.KeyCode.T then return end
    if input.KeyCode == Settings.StopKey then controller.Stop(); return end
    if processed or Input:GetFocusedTextBox() then return end
    if input.KeyCode == Settings.ToggleKey then
        setEnabled(not State.enabled)
    elseif input.KeyCode == Settings.ESPToggleKey then
        setESPEnabled(not Settings.ESPEnabled)
    elseif input.KeyCode == Settings.HealthToggleKey then
        Guard.setEnabled(not Settings.HealthEscapeEnabled)
    elseif input.KeyCode == Settings.VisibilityKey then
        root.Enabled = not root.Enabled
        State.gesture = nil
        render()
    end
end)
connect(Input.TextBoxFocused, function(box)
    if Settings.PauseWhileTyping and isChatTextBox(box) then
        releaseOrPause()
    end
end)
-- Menus/inventories no longer stop M1 or Auto Skills.
connect(GuiService.MenuOpened, function() render() end)
connect(Input.WindowFocusReleased, function()
    State.focused = false
    State.gesture = nil
    if Settings.PauseWhenUnfocused then releaseOrPause() end
end)
connect(Input.WindowFocused, function() State.focused = true; render() end)
connect(Player.CharacterRemoving, function()
    stopFarm()
    Guard.release()
    Movement.restoreFly()
    Movement.restoreSpeed()
    Movement.restoreNoClip(true)
    Movement.character, Movement.humanoid, Movement.rootPart = nil, nil, nil
    releaseOrPause()
end)

-- Cancellable waits release held skills promptly on OFF, pause or unload.
-- One key worker handles all toggles, so fast ON/OFF changes cannot stack loops.
local function waitResponsive(duration, isHolding)
    local deadline = os.clock() + duration
    while State.alive do
        local remaining = deadline - os.clock()
        if remaining <= 0 then return end
        if not availability() or (isHolding and State.heldKey == nil) then return end
        task.wait(math.min(0.03, remaining))
    end
end
render()
fitWindow(true)
task.defer(function() if State.alive then fitWindow(false) end end)
task.spawn(function()
    local nextIndex = 1
    while State.alive do
        if availability() then
            local chosen
            for _ = 1, #Skills do
                local candidate = Skills[nextIndex]
                nextIndex = nextIndex % #Skills + 1
                if candidate.enabled then chosen = candidate; break end
            end
            if chosen then
                local blocked = type(Farm.inventoryOrBlockingUIOpen) == "function"
                    and Farm.inventoryOrBlockingUIOpen(false)

                if blocked and type(Farm.inventorySkillPulse) == "function" then
                    State.heldKey = nil
                    local pressed = Farm.inventorySkillPulse(chosen.key)

                    if pressed then
                        State.lastKey = chosen.name .. " (inventory pulse)"
                        render()
                        waitResponsive(math.max(0.03, Settings.KeyGap), false)
                    else
                        -- Final fallback: original key path.
                        State.heldKey = chosen.key
                        local fallbackOK, err = pcall(function()
                            VirtualInput:SendKeyEvent(true, chosen.key, false, game)
                        end)
                        if not fallbackOK then
                            inputFault(err)
                        else
                            State.lastKey = chosen.name .. " (fallback)"
                            render()
                            waitResponsive(math.max(0.03, Settings.HoldTime), true)
                            releaseOrPause()
                            waitResponsive(math.max(0.03, Settings.KeyGap), false)
                        end
                    end
                else
                    State.heldKey = chosen.key
                    local pressed, err = pcall(function()
                        VirtualInput:SendKeyEvent(true, chosen.key, false, game)
                    end)
                    if not pressed then
                        inputFault(err)
                    else
                        State.lastKey = chosen.name
                        render()
                        waitResponsive(math.max(0.03, Settings.HoldTime), true)
                        releaseOrPause()
                        waitResponsive(math.max(0.03, Settings.KeyGap), false)
                    end
                end
            end
        else
            task.wait(0.05)
        end
    end
end)
task.spawn(function()
    while State.alive do
        render()
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
-- A generated FriendReady file has its owner's known coordinates baked here.
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

-- First-run discovery from spawn: no character movement.
if Settings.StaticMapScan then
    task.delay(0.8, function()
        if State.alive and Farm.staticMapScan then
            Farm.staticMapScan(true)
        end
    end)
end

-- Old moving/grid discovery is fallback-only.
if Settings.BossFirstDiscovery then
    Farm.bootDiscovery()
end

-- Owner copy automatically produces a distributable script containing all
-- locations currently saved on this machine.
task.delay(1.5, function()
    if State.alive and System and System.writeFriendReady then
        System.writeFriendReady()
        render()
    end
end)

notify("Void UI ready | boss seeds + static scan + original stable loot active")
]====]

local __env = (type(getgenv) == "function" and getgenv()) or _G
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
__fn()

]=====])()
