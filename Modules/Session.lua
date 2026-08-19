-- Tribunal :: Session
-- The trial state machine. Owns the lifecycle of a ballot, the tally, and the
-- writes to the permanent record. The UI modules only read from here.

local ADDON, T = ...
local Session = T:NewModule("Session")
local Comm = T.Comm

Session.current = nil
Session.lastCallBy = {}   -- [fullName] = GetTime() of their last ballot

local OP = Comm.OP
local GRACE = 1.4         -- seconds of "tallying" before the reveal

--------------------------------------------------------------------------------
-- Eligibility
--------------------------------------------------------------------------------

-- Returns true, or false plus the reason to show the caller.
function Session:CanCall()
    if not Comm.GroupChannel() then
        return false, "You are not in a group."
    end
    if InCombatLockdown() or UnitAffectingCombat("player") then
        return false, "No trials during combat."
    end
    if self.current and self.current.state ~= "done" then
        return false, "A trial is in session."
    end

    local me = T:FullName("player")
    local last = self.lastCallBy[me]
    local cd = TribunalDB.settings.voteCooldown
    if last and (GetTime() - last) < cd then
        return false, ("The court reconvenes in %ds.")
            :format(math.ceil(cd - (GetTime() - last)))
    end

    if #T:GetRoster() < 2 then
        return false, "Nobody else to try."
    end
    return true
end

--------------------------------------------------------------------------------
-- Opening
--------------------------------------------------------------------------------

-- Called by the player. Validates, broadcasts, and opens locally.
function Session:Request()
    local ok, reason = self:CanCall()
    if not ok then
        T:Print(reason)
        if self.current and self.current.state ~= "done" then T.Ballot:Focus() end
        return false
    end

    local id = tostring(math.random(100000, 999999))
    local duration = TribunalDB.settings.voteDuration
    local label = T:ContextLabel()

    Comm:Send(OP.OPEN, id, duration, label)
    self:Begin(T:FullName("player"), id, duration, label)
    return true
end

-- Opens a trial locally, whether we called it or somebody else did.
function Session:Begin(initiator, id, duration, label)
    duration = tonumber(duration) or 30
    duration = math.max(10, math.min(120, duration))

    local candidates = {}
    for _, m in ipairs(T:GetRoster()) do
        if TribunalDB.settings.selfVoteAllowed or not m.isPlayer then
            candidates[#candidates + 1] = {
                full = m.full, short = m.short, class = m.class,
            }
        end
    end

    self.current = {
        id         = id,
        initiator  = initiator,
        label      = label ~= "" and label or T:ContextLabel(),
        duration   = duration,
        startedAt  = GetTime(),
        endsAt     = GetTime() + duration,
        candidates = candidates,
        votes      = {},          -- [voterFull] = targetFull
        voterCount = 0,
        myVote     = nil,
        state      = "open",
        electorate = Comm:ReachableCount(),
    }

    self.lastCallBy[initiator] = GetTime()

    T:Sound("CourtCalled")
    T.Ballot:Open(self.current)

    if self.timer then self.timer:Cancel() end
    self.timer = C_Timer.NewTimer(duration, function() Session:Close() end)
end

--------------------------------------------------------------------------------
-- Casting
--------------------------------------------------------------------------------

function Session:Cast(targetFull)
    local s = self.current
    if not s or s.state ~= "open" then return end

    local valid = false
    for _, c in ipairs(s.candidates) do
        if c.full == targetFull then valid = true break end
    end
    if not valid then return end
    if s.myVote == targetFull then return end

    self:Record(T:FullName("player"), targetFull)
    s.myVote = targetFull

    Comm:Send(OP.CAST, s.id, targetFull)
    T:Sound("BallotCast")
    T.Ballot:OnVoteChanged()
end

-- Stores a vote and keeps the voter count honest when somebody changes theirs.
function Session:Record(voter, target)
    local s = self.current
    if not s then return end
    if s.votes[voter] == nil then s.voterCount = s.voterCount + 1 end
    s.votes[voter] = target
end

--------------------------------------------------------------------------------
-- Tally
--------------------------------------------------------------------------------

-- Deterministic on every client: count descending, then name ascending. Two
-- clients with the same votes table always name the same defendant.
function Session:Tally()
    local s = self.current
    if not s then return nil end

    local counts = {}
    for _, target in pairs(s.votes) do
        counts[target] = (counts[target] or 0) + 1
    end

    local list = {}
    for _, c in ipairs(s.candidates) do
        list[#list + 1] = {
            full = c.full, short = c.short, class = c.class,
            count = counts[c.full] or 0,
        }
    end

    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.full < b.full
    end)

    local total = 0
    for _, e in ipairs(list) do total = total + e.count end

    local top = list[1]
    local tied = top and list[2] and list[2].count == top.count

    return {
        list    = list,
        total   = total,
        winner  = (top and top.count > 0) and top.full or nil,
        count   = top and top.count or 0,
        tied    = tied and top.count > 0,
        hung    = total == 0,
        label   = s.label,
        id      = s.id,
    }
end

--------------------------------------------------------------------------------
-- Closing
--------------------------------------------------------------------------------

function Session:Close()
    local s = self.current
    if not s or s.state ~= "open" then return end

    s.state = "tallying"
    if self.timer then self.timer:Cancel(); self.timer = nil end

    T.Ballot:OnTallying()

    -- The initiator is authoritative. Everyone else holds on the tallying
    -- state briefly so a late vote or the authoritative result can land.
    if s.initiator == T:FullName("player") then
        local result = self:Tally()
        Comm:Send(OP.RESULT, s.id, result.winner or "", result.count, result.total)
        C_Timer.After(GRACE, function() Session:Reveal(result) end)
    else
        self.fallback = C_Timer.NewTimer(GRACE + 2.5, function()
            Session:Reveal(Session:Tally())
        end)
    end
end

function Session:Reveal(result)
    local s = self.current
    if not s or s.state == "done" then return end

    s.state = "done"
    if self.fallback then self.fallback:Cancel(); self.fallback = nil end

    self:Commit(result)
    T.Ballot:Close()
    T.Verdict:Show(result, s)
    T.Board:Refresh()

    if TribunalDB.settings.announceVerdict
       and s.initiator == T:FullName("player")
       and Comm.GroupChannel() then
        local msg
        if result.winner then
            local rec = TribunalDB.players[result.winner]
            msg = ("Tribunal: %s is found responsible (%d/%d). Career total: %d.")
                :format(T:ShortName(result.winner), result.count, result.total,
                        rec and rec.guilty or 1)
        else
            msg = "Tribunal: the jury is hung. No verdict recorded."
        end
        SendChatMessage(msg, Comm.GroupChannel())
    end
end

-- Writes the verdict into the permanent record. Called once per trial.
function Session:Commit(result)
    local s = self.current
    if not s or s.committed then return end
    s.committed = true

    if result.hung then return end

    TribunalDB.stats.trials = (TribunalDB.stats.trials or 0) + 1

    -- Everyone who stood trial gets a trial counted, which is what makes the
    -- conviction rate meaningful.
    for _, c in ipairs(s.candidates) do
        local rec = T:GetRecord(c.full, c.class)
        rec.trials = (rec.trials or 0) + 1
    end

    for voter, target in pairs(s.votes) do
        local vrec = T:GetRecord(voter)
        vrec.votesCast = (vrec.votesCast or 0) + 1
        local trec = T:GetRecord(target)
        trec.votesReceived = (trec.votesReceived or 0) + 1
    end

    if result.winner and not result.tied then
        local rec = T:GetRecord(result.winner)
        rec.guilty = (rec.guilty or 0) + 1
        rec.lastGuilty = time()
        rec.lastDungeon = s.label
    end

    local hist = TribunalDB.history
    table.insert(hist, 1, {
        time    = time(),
        label   = s.label,
        winner  = result.tied and nil or result.winner,
        count   = result.count,
        total   = result.total,
        tied    = result.tied,
        jury    = s.voterCount,
    })
    -- The docket is a rolling window; nobody needs the 201st verdict.
    for i = #hist, 201, -1 do hist[i] = nil end
end

--------------------------------------------------------------------------------
-- Aborting
--------------------------------------------------------------------------------

function Session:Abort(reason, silent)
    local s = self.current
    if not s or s.state == "done" then return end

    s.state = "done"
    if self.timer then self.timer:Cancel(); self.timer = nil end
    if self.fallback then self.fallback:Cancel(); self.fallback = nil end

    T.Ballot:Close()
    if not silent and reason then T:Print(reason) end
end

--------------------------------------------------------------------------------
-- Wipe detection
--------------------------------------------------------------------------------

-- Armed while anybody is alive; fires once when the whole group is down.
local wipeArmed = true

local function EveryoneDown()
    local roster = T:GetRoster()
    if #roster < 2 then return false end
    for _, m in ipairs(roster) do
        if not UnitIsDeadOrGhost(m.unit) then return false end
    end
    return true
end

local function CheckWipe()
    if not TribunalDB or not TribunalDB.settings.autoPrompt then return end

    local ctx = T:GetContext()
    if ctx.type ~= "party" and ctx.type ~= "raid" and ctx.type ~= "scenario" then
        return
    end

    if EveryoneDown() then
        if not wipeArmed then return end
        wipeArmed = false
        -- Let the release/run-back settle before offering the ballot.
        C_Timer.After(2.5, function()
            if Session.current and Session.current.state ~= "done" then return end
            if InCombatLockdown() then return end
            T.Ballot:OfferPrompt()
        end)
    else
        wipeArmed = true
    end
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------

function Session:OnInit()
    Comm:Listen(OP.OPEN, function(sender, id, duration, label)
        if not id or id == "" then return end
        if Session.current and Session.current.state ~= "done" then return end

        -- Same anti-spam rule applies to remote callers.
        local last = Session.lastCallBy[sender]
        if last and (GetTime() - last) < TribunalDB.settings.voteCooldown - 5 then
            return
        end
        Session:Begin(sender, id, duration, label)
    end)

    Comm:Listen(OP.CAST, function(sender, id, target)
        local s = Session.current
        if not s or s.id ~= id or s.state ~= "open" then return end
        if not target or target == "" then return end
        Session:Record(sender, target)
        T.Ballot:OnVoteChanged()
    end)

    Comm:Listen(OP.RESULT, function(sender, id, winner, count, total)
        local s = Session.current
        if not s or s.id ~= id or s.state == "done" then return end
        if sender ~= s.initiator then return end

        -- Adopt the initiator's tally so every client shows one verdict.
        local result = Session:Tally()
        result.winner = (winner ~= "" and winner) or nil
        result.count  = tonumber(count) or result.count
        result.total  = tonumber(total) or result.total
        result.hung   = result.winner == nil
        result.tied   = false

        if s.state == "open" then
            s.state = "tallying"
            if Session.timer then Session.timer:Cancel(); Session.timer = nil end
            T.Ballot:OnTallying()
        end
        if Session.fallback then Session.fallback:Cancel(); Session.fallback = nil end
        C_Timer.After(GRACE, function() Session:Reveal(result) end)
    end)

    Comm:Listen(OP.ABORT, function(sender, id, reason)
        local s = Session.current
        if not s or s.id ~= id then return end
        if sender ~= s.initiator then return end
        Session:Abort("The trial was withdrawn.")
    end)

    T:On("PLAYER_REGEN_DISABLED", function()
        Session:Abort("Combat began. The trial is adjourned.")
    end)

    T:On("GROUP_ROSTER_UPDATE", function()
        if not Comm.GroupChannel() then
            Session:Abort(nil, true)
            wipe(Session.lastCallBy)
        end
    end)

    T:On("PLAYER_DEAD", function() C_Timer.After(0.5, CheckWipe) end)
    T:On("PLAYER_UNGHOST", function() wipeArmed = true end)
    T:On("PLAYER_ALIVE", function() wipeArmed = true end)

    -- A periodic sweep catches party deaths without subscribing to unit health.
    C_Timer.NewTicker(3, function()
        if Comm.GroupChannel() then CheckWipe() end
    end)
end
