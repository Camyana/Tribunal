-- Tribunal :: Core
-- Namespace, saved variables, event plumbing, slash commands.

local ADDON, T = ...

T.name     = ADDON
T.version  = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "1.0.0"
T.protocol = 1
T.prefix   = "TRIBUNAL"

T.MEDIA   = "Interface\\AddOns\\Tribunal\\Media\\"
T.TEXTURE = T.MEDIA .. "Textures\\"
T.SOUND   = T.MEDIA .. "Sounds\\"

-- Modules register themselves here and get :OnInit / :OnLogin called in order.
T.modules = {}

function T:NewModule(name)
    local m = { moduleName = name }
    self.modules[#self.modules + 1] = m
    self[name] = m
    return m
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

local DEFAULTS = {
    version = 1,
    settings = {
        voteDuration    = 30,     -- seconds a ballot stays open
        voteCooldown    = 60,     -- seconds before the same player may call again
        autoPrompt      = true,   -- offer a vote after a detected wipe
        soundEnabled    = true,
        soundChannel    = "SFX",
        ambientEnabled  = true,   -- the low drone under the ballot
        anonymous       = true,   -- hide who voted for whom until the reveal
        selfVoteAllowed = true,   -- may you convict yourself
        announceVerdict = false,  -- post the verdict to party chat
        portraits       = true,   -- show unit portraits on the ballot
        scale           = 1.0,
    },
    minimap = { angle = 214, hide = false },
    ui      = {},   -- remembered frame positions, keyed by window
    players = {},
    history = {},
    stats   = { trials = 0 },
}

local function DeepFill(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            DeepFill(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

--------------------------------------------------------------------------------
-- Player identity helpers
--------------------------------------------------------------------------------

-- Everything is keyed on "Name-Realm" so cross-realm groups stay distinct.
function T:FullName(unit)
    local name, realm = UnitName(unit)
    if not name then return nil end
    if not realm or realm == "" then realm = GetNormalizedRealmName() or "" end
    return realm ~= "" and (name .. "-" .. realm) or name
end

function T:Qualify(name)
    if not name then return nil end
    if name:find("-", 1, true) then return name end
    local realm = GetNormalizedRealmName()
    return realm and (name .. "-" .. realm) or name
end

function T:ShortName(full)
    return full and (full:match("^([^-]+)") or full) or "?"
end

-- The party as an ordered list of { full, short, class, unit, isPlayer }.
function T:GetRoster()
    local roster, seen = {}, {}
    local function add(unit)
        if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
        local full = self:FullName(unit)
        if not full or seen[full] then return end
        seen[full] = true
        local _, class = UnitClass(unit)
        roster[#roster + 1] = {
            full     = full,
            short    = self:ShortName(full),
            class    = class,
            unit     = unit,
            isPlayer = UnitIsUnit(unit, "player"),
        }
    end

    add("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    else
        for i = 1, 4 do add("party" .. i) end
    end
    return roster
end

-- The unit token for a full name, resolved live: party indices shift when
-- somebody leaves, so a token cached at ballot time goes stale.
function T:UnitFor(full)
    if not full then return nil end
    for _, m in ipairs(self:GetRoster()) do
        if m.full == full then return m.unit end
    end
    return nil
end

function T:InGroup(full)
    for _, m in ipairs(self:GetRoster()) do
        if m.full == full then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Player records
--------------------------------------------------------------------------------

function T:GetRecord(full, class)
    local rec = TribunalDB.players[full]
    if not rec then
        rec = {
            name = self:ShortName(full), class = class,
            guilty = 0, votesCast = 0, votesReceived = 0, trials = 0,
            lastGuilty = nil, lastDungeon = nil,
        }
        TribunalDB.players[full] = rec
    end
    if class and rec.class ~= class then rec.class = class end
    return rec
end

-- Most convictions first, then conviction rate, then name.
function T:GetLeaderboard()
    local list = {}
    for full, rec in pairs(TribunalDB.players) do
        local trials = rec.trials or 0
        list[#list + 1] = {
            full = full, short = self:ShortName(full), class = rec.class,
            guilty = rec.guilty or 0, trials = trials,
            votesCast = rec.votesCast or 0, votesReceived = rec.votesReceived or 0,
            lastGuilty = rec.lastGuilty, lastDungeon = rec.lastDungeon,
            rate = trials > 0 and ((rec.guilty or 0) / trials) or 0,
        }
    end
    table.sort(list, function(a, b)
        if a.guilty ~= b.guilty then return a.guilty > b.guilty end
        if a.rate   ~= b.rate   then return a.rate   > b.rate   end
        return a.short < b.short
    end)
    return list
end

--------------------------------------------------------------------------------
-- Context: where are we, and does it count
--------------------------------------------------------------------------------

function T:GetContext()
    local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    local keyLevel
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        keyLevel = C_ChallengeMode.GetActiveKeystoneInfo()
    end
    local isKey = (difficultyID == 8) and (keyLevel or 0) > 0
    return {
        zone       = name or GetRealZoneText() or UNKNOWN,
        instanceID = instanceID,
        type       = instanceType,
        isKeystone = isKey,
        keyLevel   = isKey and keyLevel or nil,
    }
end

-- A short docket label: "Ara-Kara +18", or just the zone name.
function T:ContextLabel(ctx)
    ctx = ctx or self:GetContext()
    if ctx.isKeystone and ctx.keyLevel then
        return ("%s +%d"):format(ctx.zone, ctx.keyLevel)
    end
    return ctx.zone
end

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

function T:Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    print(("|cffE8B23ATribunal|r  %s"):format(msg))
end

function T:Sound(file, force)
    local s = TribunalDB and TribunalDB.settings
    if not force and s and not s.soundEnabled then return end
    return PlaySoundFile(T.SOUND .. file .. ".ogg", (s and s.soundChannel) or "SFX")
end

--------------------------------------------------------------------------------
-- Event dispatch
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
T.eventFrame = frame

local handlers = {}

function T:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        -- Unit events and unknown events would throw; a failed register just
        -- means the handler never fires, which is the correct degradation.
        pcall(frame.RegisterEvent, frame, event)
    end
    local list = handlers[event]
    list[#list + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            geterrorhandler()(("Tribunal: error in %s handler: %s"):format(event, err))
        end
    end
end)

--------------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------------

local booted = false

T:On("ADDON_LOADED", function(addon)
    if addon ~= ADDON or booted then return end
    booted = true

    TribunalDB = DeepFill(TribunalDB or {}, DEFAULTS)

    for _, m in ipairs(T.modules) do
        if m.OnInit then
            local ok, err = pcall(m.OnInit, m)
            if not ok then
                geterrorhandler()(("Tribunal: %s:OnInit failed: %s"):format(m.moduleName, err))
            end
        end
    end
end)

T:On("PLAYER_LOGIN", function()
    for _, m in ipairs(T.modules) do
        if m.OnLogin then
            local ok, err = pcall(m.OnLogin, m)
            if not ok then
                geterrorhandler()(("Tribunal: %s:OnLogin failed: %s"):format(m.moduleName, err))
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

SLASH_TRIBUNAL1 = "/tribunal"
SLASH_TRIBUNAL2 = "/trib"

SlashCmdList.TRIBUNAL = function(input)
    local cmd, rest = (input or ""):lower():match("^(%S*)%s*(.-)$")

    if cmd == "" or cmd == "board" or cmd == "leaderboard" then
        T.Board:Toggle()

    elseif cmd == "vote" or cmd == "call" or cmd == "court" then
        T.Session:Request()

    elseif cmd == "config" or cmd == "options" or cmd == "settings" then
        T.Config:Open()

    elseif cmd == "minimap" then
        TribunalDB.minimap.hide = not TribunalDB.minimap.hide
        T.Minimap:Refresh()
        T:Print(TribunalDB.minimap.hide and "Minimap button hidden." or "Minimap button shown.")

    elseif cmd == "who" then
        local n = 0
        for peer in pairs(T.Comm.peers) do
            T:Print("  |cff3FBF8F%s|r is running Tribunal.", T:ShortName(peer))
            n = n + 1
        end
        if n == 0 then T:Print("Nobody else in the group is running Tribunal.") end

    elseif cmd == "debug" then
        T:Print("Diagnostics:")
        local S = TribunalDB.settings
        print(("  portraits setting: |cffE8B23A%s|r   art enabled: |cffE8B23A%s|r")
            :format(tostring(S.portraits), tostring(T.Theme.useArt)))
        print(("  in group: %s   peers: %d   session: %s")
            :format(tostring(Comm and true or true),
                    T.Comm:PeerCount(),
                    T.Session.current and T.Session.current.state or "none"))

        for _, m in ipairs(T:GetRoster()) do
            print(("  %s  unit=%s exists=%s connected=%s visible=%s")
                :format(m.short, tostring(m.unit),
                        tostring(UnitExists(m.unit)),
                        tostring(UnitIsConnected(m.unit)),
                        tostring(UnitIsVisible(m.unit))))
        end

        local rows = T.Ballot.rows or {}
        if #rows == 0 then
            print("  no ballot has been built yet; call a vote first")
        end
        for i, row in ipairs(rows) do
            if row:IsShown() and row.candidate then
                print(("  row %d: %s  portrait shown=%s mode=%s texture=%s")
                    :format(i, row.candidate.short,
                            tostring(row.portrait:IsShown()),
                            tostring(row.portrait.mode),
                            tostring(row.portrait.icon:GetTexture())))
            end
        end

        -- The circular mask is the single point of failure for every disc in
        -- the addon; if this path stops resolving they all vanish at once.
        local probe = UIParent:CreateTexture()
        probe:SetTexture("Interface\CharacterFrame\TempPortraitAlphaMask")
        print(("  circle mask resolves: |cffE8B23A%s|r"):format(tostring(probe:GetTexture() ~= nil)))
        local emblem = UIParent:CreateTexture()
        emblem:SetTexture(T.TEXTURE .. "MinimapIcon")
        print(("  minimap icon path: %s"):format(tostring(emblem:GetTexture())))

    elseif cmd == "reset" then
        if rest == "confirm" then
            wipe(TribunalDB.players)
            wipe(TribunalDB.history)
            TribunalDB.stats.trials = 0
            T.Board:Refresh()
            T:Print("The docket has been expunged.")
        else
            T:Print("This erases every verdict on record. Type |cffE8B23A/trib reset confirm|r if you mean it.")
        end

    else
        T:Print("Commands:")
        print("  |cffE8B23A/trib|r - open the leaderboard")
        print("  |cffE8B23A/trib vote|r - call the court to order")
        print("  |cffE8B23A/trib config|r - settings")
        print("  |cffE8B23A/trib who|r - who in the group has the addon")
        print("  |cffE8B23A/trib minimap|r - toggle the minimap button")
        print("  |cffE8B23A/trib debug|r - print diagnostics")
        print("  |cffE8B23A/trib reset|r - expunge the docket")
    end
end

-- Blizzard's addon compartment, the list next to the minimap.
function Tribunal_OnCompartmentClick()
    T.Board:Toggle()
end
