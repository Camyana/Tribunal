-- A minimal World of Warcraft API mock, enough to load Tribunal outside the
-- game and drive a whole trial. Not a general-purpose emulator: it exists so
-- logic bugs surface here instead of in a raid.

local M = {}

--------------------------------------------------------------------------------
-- Clock and scheduler
--------------------------------------------------------------------------------

local now = 1000
local timers = {}

function M.Now() return now end

-- Advances the clock, firing every timer due in the interval.
function M.Advance(seconds, step)
    step = step or 0.05
    local target = now + seconds
    while now < target do
        now = math.min(now + step, target)
        for i = #timers, 1, -1 do
            local t = timers[i]
            if not t.cancelled and now >= t.at then
                if t.interval then
                    t.at = now + t.interval
                else
                    table.remove(timers, i)
                end
                local ok, err = pcall(t.fn)
                if not ok then M.Error("timer: " .. tostring(err)) end
            end
        end
        if M.onTick then M.onTick() end
    end
end

--------------------------------------------------------------------------------
-- Error collection
--------------------------------------------------------------------------------

M.errors = {}
M.output = {}

function M.Error(msg)
    M.errors[#M.errors + 1] = tostring(msg)
end

--------------------------------------------------------------------------------
-- Widget mock
--------------------------------------------------------------------------------

-- Numeric getters need believable values or layout maths produces nil.
local GETTERS = {
    GetWidth = 300, GetHeight = 40, GetStringWidth = 42, GetAlpha = 1,
    GetScale = 1, GetEffectiveScale = 1, GetFrameLevel = 5, GetFrameStrata = "MEDIUM",
    GetVerticalScroll = 0, GetNumPoints = 1, GetTexture = "mock-texture",
    GetValue = 0, GetObjectType = "Frame", GetName = "MockFrame",
}

local BOOLS = {
    IsShown = true, IsVisible = true, IsMouseOver = false, IsMouseEnabled = true,
    IsForbidden = false, IsProtected = false, IsObjectType = true,
}

local function NewWidget(kind, name, parent)
    local w = { __kind = kind, __name = name, __parent = parent, __shown = true, __alpha = 1 }

    local special = {
        -- Text measurement has to be roughly real, or width-dependent layout
        -- (truncation, right-alignment) cannot be tested at all.
        SetFont = function(self, path, size, flags)
            rawset(self, "__size", size or 12)
        end,
        SetText = function(self, t) rawset(self, "__text", tostring(t or "")) end,
        SetTexture = function(self, v) rawset(self, "__texture", v) end,
        GetTexture = function(self) return rawget(self, "__texture") end,
        SetColorTexture = function(self, r, g, b, a)
            rawset(self, "__color", { r, g, b, a })
            rawset(self, "__texture", "colour")
        end,
        GetDrawColor = function(self) return rawget(self, "__color") end,
        GetText = function(self) return rawget(self, "__text") end,
        GetStringWidth = function(self)
            local t = rawget(self, "__text") or ""
            local size = rawget(self, "__size") or 12
            -- Count code points, not bytes: a 3-byte ellipsis is one glyph.
            -- Continuation bytes are 0x80..0xBF; every other byte starts
            -- a new code point. Written without string escapes, which
            -- do not reliably survive being edited through a shell.
            local n = 0
            for k = 1, #t do
                local byte = t:byte(k)
                if byte < 128 or byte > 191 then n = n + 1 end
            end
            -- ~0.62em average advance for the uppercase this addon sets.
            return n * size * 0.62
        end,
        CreateTexture     = function() return NewWidget("Texture") end,
        CreateFontString  = function() return NewWidget("FontString") end,
        CreateMaskTexture = function() return NewWidget("MaskTexture") end,
        CreateAnimationGroup = function() return NewWidget("AnimGroup") end,
        -- Real, because the chrome a widget inherits is resolved by walking up
        -- the parent chain; a stub returning nil would make every frame look
        -- like a top-level one.
        GetParent = function(self) return rawget(self, "__parent") end,
        -- Recorded, because the legibility shadow on the veiled windows is a
        -- deliberate exception to a rule the design states, and a test has to
        -- be able to see that it is on there and nowhere else.
        SetShadowColor = function(self, r, g, b, a)
            rawset(self, "__shadow", { r, g, b, a })
        end,
        GetShadowColor = function(self)
            local s = rawget(self, "__shadow")
            if not s then return 0, 0, 0, 0 end
            return s[1], s[2], s[3], s[4]
        end,
        GetPoint  = function() return "CENTER", M.UIParent, "CENTER", 0, 0 end,
        GetCenter = function() return 400, 300 end,
        GetMinMaxValues = function() return 0, 1 end,
        GetRegions = function() return end,
        Show = function(self) rawset(self, "__shown", true) end,
        Hide = function(self) rawset(self, "__shown", false) end,
        SetShown = function(self, v) rawset(self, "__shown", v and true or false) end,
        IsShown = function(self) return rawget(self, "__shown") end,
        IsVisible = function(self) return rawget(self, "__shown") end,
        SetAlpha = function(self, a) rawset(self, "__alpha", a) end,
        GetAlpha = function(self) return rawget(self, "__alpha") or 1 end,
        SetScript = function(self, script, fn) rawset(self, "__" .. script, fn) end,
        GetScript = function(self, script) return rawget(self, "__" .. script) end,
        HookScript = function(self, script, fn) rawset(self, "__" .. script, fn) end,
        RegisterEvent = function(self, e)
            local list = M.registry[e]
            if not list then list = {}; M.registry[e] = list end
            list[#list + 1] = self
        end,
        UnregisterEvent = function() end,
        SetThumbTexture = function() end,
    }

    setmetatable(w, {
        __index = function(t, k)
            if type(k) ~= "string" then return nil end
            if special[k] then return special[k] end
            if GETTERS[k] ~= nil then
                local v = GETTERS[k]
                return function() return v end
            end
            if BOOLS[k] ~= nil then
                local v = BOOLS[k]
                return function() return v end
            end
            -- Heuristic: WoW widget methods are CamelCase, addon data fields
            -- are lowercase. Unknown CamelCase keys become no-op methods;
            -- unknown lowercase keys stay nil so `if not self.foo` works.
            local first = k:sub(1, 1)
            if first:match("%u") then
                local stub = function() return nil end
                rawset(t, k, stub)
                return stub
            end
            return nil
        end,
    })

    return w
end

M.NewWidget = NewWidget

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

M.registry = {}   -- [event] = { frame, ... }

function M.Fire(event, ...)
    local list = M.registry[event]
    if not list then return end
    for _, frame in ipairs(list) do
        local fn = rawget(frame, "__OnEvent")
        if fn then
            local ok, err = pcall(fn, frame, event, ...)
            if not ok then M.Error(("%s: %s"):format(event, err)) end
        end
    end
end

-- The simulated group. Index 1 is always the player.
M.group = {
    { name = "Vaelorin",  realm = "Ravencrest", class = "MAGE",     dead = false },
    { name = "Thornhide", realm = "Ravencrest", class = "DRUID",    dead = false },
    { name = "Morgrath",  realm = "Ravencrest", class = "DEATHKNIGHT", dead = false },
    { name = "Sylvenne",  realm = "Ravencrest", class = "PALADIN",  dead = false },
    { name = "Kazrul",    realm = "Ravencrest", class = "WARLOCK",  dead = false },
}
M.inGroup = true
M.inCombat = false

local function UnitIndex(unit)
    if unit == "player" then return 1 end
    local n = unit:match("^party(%d)$")
    if n then return tonumber(n) + 1 end
    n = unit:match("^raid(%d)$")
    if n then return tonumber(n) end
    return nil
end

function M.Install(env)
    local G = env

    G.UIParent = NewWidget("Frame", "UIParent")
    G.Minimap  = NewWidget("Frame", "Minimap")
    G.GameTooltip = NewWidget("GameTooltip", "GameTooltip")
    G.SettingsPanel = NewWidget("Frame", "SettingsPanel")
    M.UIParent = G.UIParent

    G.CreateFrame = function(kind, name, parent, template)
        local f = NewWidget(kind, name, parent)
        if name then G[name] = f end
        return f
    end

    G.GetTime = function() return now end
    G.time = function() return 1700000000 + math.floor(now) end
    G.date = function() return "2026-08-19" end

    G.C_Timer = {
        After = function(delay, fn)
            timers[#timers + 1] = { at = now + delay, fn = fn }
        end,
        NewTimer = function(delay, fn)
            local t = { at = now + delay, fn = fn }
            timers[#timers + 1] = t
            return { Cancel = function() t.cancelled = true
                for i = #timers, 1, -1 do if timers[i] == t then table.remove(timers, i) end end
            end }
        end,
        NewTicker = function(interval, fn)
            local t = { at = now + interval, interval = interval, fn = fn }
            timers[#timers + 1] = t
            return { Cancel = function() t.cancelled = true
                for i = #timers, 1, -1 do if timers[i] == t then table.remove(timers, i) end end
            end }
        end,
    }

    G.C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }

    -- Comms: everything sent is captured so tests can assert on the wire.
    M.sent = {}
    G.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, msg, channel)
            M.sent[#M.sent + 1] = { prefix = prefix, msg = msg, channel = channel }
        end,
    }
    G.SendChatMessage = function(msg, channel)
        M.output[#M.output + 1] = ("[%s] %s"):format(channel, msg)
    end

    G.IsInGroup = function() return M.inGroup end
    G.IsInRaid  = function() return false end
    G.GetNumGroupMembers = function() return M.inGroup and #M.group or 0 end
    G.LE_PARTY_CATEGORY_INSTANCE = 2
    G.InCombatLockdown = function() return M.inCombat end
    G.UnitAffectingCombat = function() return M.inCombat end

    G.UnitExists = function(unit)
        local i = UnitIndex(unit)
        if not i then return false end
        if i > 1 and not M.inGroup then return false end
        return M.group[i] ~= nil
    end
    G.UnitIsPlayer = G.UnitExists
    G.UnitName = function(unit)
        local i = UnitIndex(unit)
        local m = i and M.group[i]
        if not m then return nil end
        return m.name, (i == 1 and "" or m.realm)
    end
    G.UnitClass = function(unit)
        local i = UnitIndex(unit)
        local m = i and M.group[i]
        if not m then return nil end
        return m.class, m.class
    end
    G.UnitIsUnit = function(a, b)
        return UnitIndex(a) == UnitIndex(b)
    end
    -- Portraits only exist for units the client can see; tests need to be able
    -- to take somebody out of range.
    M.outOfRange = {}
    G.UnitIsVisible = function(unit)
        local i = UnitIndex(unit)
        local m = i and M.group[i]
        return m ~= nil and not M.outOfRange[m.name]
    end
    G.UnitIsConnected = function(unit) return UnitIndex(unit) ~= nil end
    G.SetPortraitTexture = function(tex, unit)
        if tex and tex.SetTexture then tex:SetTexture("portrait:" .. tostring(unit)) end
    end
    G.CLASS_ICON_TCOORDS = setmetatable({}, {
        __index = function() return { 0, 0.25, 0, 0.25 } end,
    })

    G.UnitIsDeadOrGhost = function(unit)
        local i = UnitIndex(unit)
        return i and M.group[i] and M.group[i].dead or false
    end

    G.GetNormalizedRealmName = function() return "Ravencrest" end
    G.GetRealZoneText = function() return "Ara-Kara, City of Echoes" end
    G.GetInstanceInfo = function()
        return "Ara-Kara, City of Echoes", "party", 8, "Mythic Keystone", 5, 0, false, 2660
    end
    G.C_ChallengeMode = { GetActiveKeystoneInfo = function() return 18, {} end }

    G.RAID_CLASS_COLORS = setmetatable({}, {
        __index = function()
            return { r = 0.5, g = 0.6, b = 0.9,
                     GenerateHexColor = function() return "ff8090e0" end }
        end,
    })
    G.CUSTOM_CLASS_COLORS = nil
    G.LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k end })

    G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    G.PlaySoundFile = function(path, channel)
        M.output[#M.output + 1] = ("sound %s"):format(path)
        return true, 12345
    end
    G.StopSound = function() end

    G.UISpecialFrames = {}
    G.StaticPopupDialogs = {}
    G.StaticPopup_Show = function(k) M.output[#M.output + 1] = "popup " .. k end
    G.HideUIPanel = function() end
    G.UNKNOWN = "Unknown"
    G.CANCEL = "Cancel"

    G.Settings = {
        RegisterCanvasLayoutCategory = function(_, name) return { name = name } end,
        RegisterAddOnCategory = function() end,
    }

    G.geterrorhandler = function()
        return function(err) M.Error(err) end
    end

    G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        M.output[#M.output + 1] = table.concat(parts, " ")
    end

    G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    G.tinsert = table.insert
    G.SLASH_TRIBUNAL1, G.SLASH_TRIBUNAL2 = nil, nil
    G.SlashCmdList = {}

    return G
end

return M
