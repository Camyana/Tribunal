-- Loads Tribunal against the mock and drives real scenarios through it.
-- Run with:  python Tools/runsim.py

-- Keep the real print: the mock replaces the global one with a collector.
local say = print

local mock = dofile("Tools/wowmock.lua")
mock.Install(_G)

--------------------------------------------------------------------------------
-- Pump OnUpdate handlers so animations actually run
--------------------------------------------------------------------------------

local frames = {}
local rawCreate = CreateFrame
CreateFrame = function(...)
    local f = rawCreate(...)
    frames[#frames + 1] = f
    return f
end

mock.onTick = function()
    for i = 1, #frames do
        local f = frames[i]
        if rawget(f, "__shown") then
            local fn = rawget(f, "__OnUpdate")
            if fn then
                local ok, err = pcall(fn, f, 0.05)
                if not ok then mock.Error("OnUpdate: " .. tostring(err)) end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Test harness
--------------------------------------------------------------------------------

local pass, fail = 0, 0
local function check(label, cond, detail)
    if cond then
        pass = pass + 1
        say(("  PASS  %s"):format(label))
    else
        fail = fail + 1
        say(("  FAIL  %s%s"):format(label, detail and ("  -> " .. tostring(detail)) or ""))
    end
end

local function section(name)
    say("\n== " .. name .. " ==")
end

--------------------------------------------------------------------------------
-- Load the addon
--------------------------------------------------------------------------------

local T = {}
local FILES = {
    "Core.lua", "Modules/Anim.lua", "Modules/Theme.lua", "Modules/Comm.lua",
    "Modules/Session.lua", "Modules/Ballot.lua", "Modules/Verdict.lua",
    "Modules/Board.lua", "Modules/Minimap.lua", "Modules/Config.lua",
}

section("Load")
for _, file in ipairs(FILES) do
    local chunk, err = loadfile(file)
    if not chunk then
        check("load " .. file, false, err)
    else
        local ok, rerr = pcall(chunk, "Tribunal", T)
        check("load " .. file, ok, rerr)
    end
end

mock.Fire("ADDON_LOADED", "Tribunal")
check("saved variables created", type(TribunalDB) == "table")
check("defaults applied", TribunalDB.settings.voteDuration == 30)

mock.Fire("PLAYER_LOGIN")
mock.Advance(4)
check("minimap button built", T.Minimap.button ~= nil)
check("no errors during boot", #mock.errors == 0, mock.errors[1])

--------------------------------------------------------------------------------
-- Peers
--------------------------------------------------------------------------------

section("Handshake")

local PEERS = {
    "Thornhide-Ravencrest", "Morgrath-Ravencrest",
    "Sylvenne-Ravencrest", "Kazrul-Ravencrest",
}

for _, peer in ipairs(PEERS) do
    mock.Fire("CHAT_MSG_ADDON", "TRIBUNAL", "HI|1|1.0.0", "PARTY", peer)
end
check("four peers registered", T.Comm:PeerCount() == 4, T.Comm:PeerCount())
check("reachable count includes us", T.Comm:ReachableCount() == 5, T.Comm:ReachableCount())

mock.Fire("CHAT_MSG_ADDON", "TRIBUNAL", "HI|1|1.0.0", "PARTY", "Stranger-Elsewhere")
check("non-group sender ignored", T.Comm:PeerCount() == 4, T.Comm:PeerCount())

--------------------------------------------------------------------------------
-- A full trial
--------------------------------------------------------------------------------

section("Trial: clear majority")

mock.inCombat = true
check("cannot convene in combat", select(1, T.Session:CanCall()) == false)
mock.inCombat = false

local ok = T.Session:Request()
check("trial opened", ok == true)
check("session is open", T.Session.current and T.Session.current.state == "open")
check("five defendants", #T.Session.current.candidates == 5,
      T.Session.current and #T.Session.current.candidates)

local sid = T.Session.current.id
local sentOpen = false
for _, m in ipairs(mock.sent) do
    if m.msg:match("^V|" .. sid) then sentOpen = true end
end
check("open broadcast on the wire", sentOpen)

-- The player votes, then changes their mind.
T.Session:Cast("Sylvenne-Ravencrest")
T.Session:Cast("Morgrath-Ravencrest")
check("vote change does not double count", T.Session.current.voterCount == 1,
      T.Session.current.voterCount)
check("own vote recorded", T.Session.current.myVote == "Morgrath-Ravencrest")

-- Three peers convict Morgrath, one votes elsewhere.
mock.Fire("CHAT_MSG_ADDON", "TRIBUNAL", "C|" .. sid .. "|Morgrath-Ravencrest", "PARTY", "Thornhide-Ravencrest")
mock.Fire("CHAT_MSG_ADDON", "TRIBUNAL", "C|" .. sid .. "|Morgrath-Ravencrest", "PARTY", "Sylvenne-Ravencrest")
mock.Fire("CHAT_MSG_ADDON", "TRIBUNAL", "C|" .. sid .. "|Vaelorin-Ravencrest",  "PARTY", "Kazrul-Ravencrest")
check("four ballots cast", T.Session.current.voterCount == 4, T.Session.current.voterCount)

-- A vote for somebody outside the group must not count.
mock.Fire("CHAT_MSG_ADDON", "TRIBUNAL", "C|" .. sid .. "|Morgrath-Ravencrest", "PARTY", "Stranger-Elsewhere")
check("outsider ballot rejected", T.Session.current.voterCount == 4, T.Session.current.voterCount)

local tally = T.Session:Tally()
check("tally names Morgrath", tally.winner == "Morgrath-Ravencrest", tally.winner)
check("tally counts three", tally.count == 3, tally.count)
check("tally total is four", tally.total == 4, tally.total)
check("not tied", tally.tied == false)

mock.Advance(35)
check("session resolved", T.Session.current.state == "done", T.Session.current.state)

local rec = TribunalDB.players["Morgrath-Ravencrest"]
check("conviction recorded", rec and rec.guilty == 1, rec and rec.guilty)
check("dungeon label stored", rec and rec.lastDungeon == "Ara-Kara, City of Echoes +18",
      rec and rec.lastDungeon)
check("every defendant stood trial",
      TribunalDB.players["Vaelorin-Ravencrest"].trials == 1,
      TribunalDB.players["Vaelorin-Ravencrest"].trials)
check("voter credited", TribunalDB.players["Thornhide-Ravencrest"].votesCast == 1)
check("votes received tallied", rec.votesReceived == 3, rec.votesReceived)
check("trial counted", TribunalDB.stats.trials == 1, TribunalDB.stats.trials)
check("history written", #TribunalDB.history == 1, #TribunalDB.history)
check("verdict window shown", T.Verdict.frame ~= nil and T.Verdict.frame:IsShown())

--------------------------------------------------------------------------------
-- Cooldown
--------------------------------------------------------------------------------

section("Cooldown")

local can, why = T.Session:CanCall()
check("blocked by cooldown", can == false, why)
mock.Advance(TribunalDB.settings.voteCooldown + 1)
check("free after cooldown", (T.Session:CanCall()) == true)

--------------------------------------------------------------------------------
-- Hung jury
--------------------------------------------------------------------------------

section("Trial: nobody votes")

T.Session:Request()
mock.Advance(35)
local hist = TribunalDB.history[1]
check("no conviction recorded", TribunalDB.stats.trials == 1, TribunalDB.stats.trials)
check("history unchanged for a hung jury", #TribunalDB.history == 1, #TribunalDB.history)
check("session closed cleanly", T.Session.current.state == "done")

--------------------------------------------------------------------------------
-- Tie
--------------------------------------------------------------------------------

section("Trial: deadlock")

mock.Advance(TribunalDB.settings.voteCooldown + 1)
T.Session:Request()
local sid2 = T.Session.current.id
T.Session:Cast("Sylvenne-Ravencrest")
mock.Fire("CHAT_MSG_ADDON", "TRIBUNAL", "C|" .. sid2 .. "|Kazrul-Ravencrest", "PARTY", "Thornhide-Ravencrest")

local tie = T.Session:Tally()
check("deadlock detected", tie.tied == true)
mock.Advance(35)
check("no conviction from a deadlock",
      (TribunalDB.players["Sylvenne-Ravencrest"].guilty or 0) == 0,
      TribunalDB.players["Sylvenne-Ravencrest"].guilty)
-- Two trials so far for Sylvenne: the majority verdict and this deadlock. The
-- hung jury in between is not a trial, because nobody actually voted.
check("a deadlock still counts as a trial",
      TribunalDB.players["Sylvenne-Ravencrest"].trials == 2,
      TribunalDB.players["Sylvenne-Ravencrest"].trials)

--------------------------------------------------------------------------------
-- Remote-initiated trial
--------------------------------------------------------------------------------

section("Trial called by somebody else")

mock.Advance(TribunalDB.settings.voteCooldown + 1)
mock.Fire("CHAT_MSG_ADDON", "TRIBUNAL", "V|777777|30|Dawnbreaker +12", "PARTY", "Kazrul-Ravencrest")
check("remote trial opened", T.Session.current and T.Session.current.id == "777777",
      T.Session.current and T.Session.current.id)
check("initiator attributed", T.Session.current.initiator == "Kazrul-Ravencrest")

T.Session:Cast("Thornhide-Ravencrest")
mock.Fire("CHAT_MSG_ADDON", "TRIBUNAL", "C|777777|Thornhide-Ravencrest", "PARTY", "Kazrul-Ravencrest")

-- The initiator's authoritative result wins over our local tally.
mock.Fire("CHAT_MSG_ADDON", "TRIBUNAL", "R|777777|Thornhide-Ravencrest|2|2", "PARTY", "Kazrul-Ravencrest")
mock.Advance(4)
check("remote verdict applied",
      TribunalDB.players["Thornhide-Ravencrest"].guilty == 1,
      TribunalDB.players["Thornhide-Ravencrest"].guilty)

-- A result from an impostor must be ignored.
mock.Advance(TribunalDB.settings.voteCooldown + 1)
mock.Fire("CHAT_MSG_ADDON", "TRIBUNAL", "V|888888|30|Somewhere", "PARTY", "Kazrul-Ravencrest")
mock.Fire("CHAT_MSG_ADDON", "TRIBUNAL", "R|888888|Vaelorin-Ravencrest|5|5", "PARTY", "Sylvenne-Ravencrest")
mock.Advance(2)
check("spoofed result rejected", T.Session.current.state == "open",
      T.Session.current.state)
T.Session:Abort(nil, true)

--------------------------------------------------------------------------------
-- Combat interruption
--------------------------------------------------------------------------------

section("Combat adjourns the court")

mock.Advance(TribunalDB.settings.voteCooldown + 1)
T.Session:Request()
check("trial open", T.Session.current.state == "open")
mock.Fire("PLAYER_REGEN_DISABLED")
check("trial adjourned by combat", T.Session.current.state == "done")

--------------------------------------------------------------------------------
-- UI surfaces
--------------------------------------------------------------------------------

section("Windows")

T.Board:Show()
check("board opens", T.Board.frame:IsShown())
T.Board:SetView("history")
check("history view renders", T.Board.view == "history")
T.Board:SetView("standings")
T.Board:Toggle()
mock.Advance(1)

T.Config:Open()
check("settings open", T.Config.frame:IsShown())
T.Config:Refresh()

T.Minimap:OpenDrawer()
check("drawer opens", T.Minimap.open == true)
check("drawer has three items", #T.Minimap.items == 3, #T.Minimap.items)
T.Minimap:CloseDrawer()
mock.Advance(1)
check("drawer closes", T.Minimap.open == false)
T.Minimap:ShowTooltip()
T.Minimap:UpdatePip()

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

section("Slash commands")

local slash = SlashCmdList.TRIBUNAL
check("slash handler registered", type(slash) == "function")
for _, cmd in ipairs({ "", "board", "who", "config", "minimap", "minimap", "help", "reset" }) do
    local sok, serr = pcall(slash, cmd)
    check(("/trib %s"):format(cmd == "" and "(no args)" or cmd), sok, serr)
end

--------------------------------------------------------------------------------
-- Leaving the group
--------------------------------------------------------------------------------

section("Group teardown")

mock.Advance(TribunalDB.settings.voteCooldown + 1)
T.Session:Request()
mock.inGroup = false
mock.Fire("GROUP_ROSTER_UPDATE")
check("trial aborted on leaving", T.Session.current.state == "done")
check("peers cleared", T.Comm:PeerCount() == 0, T.Comm:PeerCount())
local solo, soloWhy = T.Session:CanCall()
check("cannot convene alone", solo == false, soloWhy)

--------------------------------------------------------------------------------
-- Wipe detection
--------------------------------------------------------------------------------

section("Wipe detection")

mock.inGroup = true
mock.Fire("GROUP_ROSTER_UPDATE")
mock.Advance(2)
for _, m in ipairs(mock.group) do m.dead = true end
mock.Advance(1)
mock.Fire("PLAYER_DEAD")
mock.Advance(6)
check("prompt offered after a wipe", T.Ballot.prompt ~= nil and T.Ballot.prompt:IsShown())
T.Ballot:DismissPrompt()
for _, m in ipairs(mock.group) do m.dead = false end

--------------------------------------------------------------------------------
-- Open ballot rendering
--------------------------------------------------------------------------------

section("Ballot display modes")

mock.Advance(TribunalDB.settings.voteCooldown + 1)
TribunalDB.settings.anonymous = false
T.Session:Request()
local sid3 = T.Session.current.id
mock.Fire("CHAT_MSG_ADDON", "TRIBUNAL", "C|" .. sid3 .. "|Kazrul-Ravencrest", "PARTY", "Thornhide-Ravencrest")
local visible = false
for _, row in ipairs(T.Ballot.rows) do
    if row.candidate and row.candidate.full == "Kazrul-Ravencrest" then
        visible = row.tally:IsShown()
    end
end
check("open ballot shows a running tally", visible == true)

TribunalDB.settings.anonymous = true
T.Ballot:OnVoteChanged()
local hidden = true
for _, row in ipairs(T.Ballot.rows) do
    if row.tally:IsShown() then hidden = false end
end
check("secret ballot hides the tally", hidden == true)
T.Session:Abort(nil, true)

--------------------------------------------------------------------------------
-- The docket is a rolling window
--------------------------------------------------------------------------------

section("History cap")

for i = 1, 260 do
    table.insert(TribunalDB.history, 1, { time = 1, label = "x", winner = nil, count = 0, total = 0 })
end
T.Session.current = { candidates = {}, votes = {}, label = "x", id = "z", state = "done" }
T.Session:Commit({ hung = false, tied = true, winner = nil, count = 0, total = 0 })
check("docket capped at 200", #TribunalDB.history == 200, #TribunalDB.history)
T.Session.current = nil

--------------------------------------------------------------------------------
-- Saved-variable migration
--------------------------------------------------------------------------------

section("Migration")

-- DeepFill only fills in what is missing, so changing a default does nothing
-- for anyone who already has the old value written to disk. This is exactly
-- how a shipped build kept drawing a surface after the default said not to.
local function loadWith(saved)
    _G.TribunalDB = saved
    local T2 = {}
    for _, file in ipairs(FILES) do
        local chunk = assert(loadfile(file))
        chunk("Tribunal", T2)
    end
    mock.Fire("ADDON_LOADED", "Tribunal")
    return _G.TribunalDB
end

local keep = _G.TribunalDB

local old = loadWith({ version = 1, settings = { opacity = 0.75 } })
check("the stale setting is cleared out", old.settings.opacity == nil,
      tostring(old.settings.opacity))
check("and the version moves on", old.version == 2, old.version)

local chosen = loadWith({ version = 1, settings = { opacity = 0.55 } })
check("any stored value is cleared, not just the old default",
      chosen.settings.opacity == nil, tostring(chosen.settings.opacity))

local fresh = loadWith(nil)
check("a fresh install has no such setting", fresh.settings.opacity == nil,
      tostring(fresh.settings.opacity))

local current = loadWith({ version = 2, settings = { opacity = 0.75 } })
check("an already-migrated database is not touched again",
      current.settings.opacity == 0.75, current.settings.opacity)
check("and the version stays put", current.version == 2, current.version)

_G.TribunalDB = keep

--------------------------------------------------------------------------------
-- The verdict seal carries the convicted player's face
--------------------------------------------------------------------------------

section("Verdict seal portrait")

mock.inGroup = true
mock.Fire("GROUP_ROSTER_UPDATE")
mock.Advance(2)
T.Session.current = nil
wipe(T.Session.lastCallBy)
mock.outOfRange = {}

local guiltyResult = {
    list = { { full = "Morgrath-Ravencrest", short = "Morgrath",
               class = "DEATHKNIGHT", count = 2 } },
    total = 2, winner = "Morgrath-Ravencrest", count = 2,
    hung = false, tied = false, label = "Ara-Kara +18",
}
local guiltySession = {
    label = "Ara-Kara +18",
    candidates = { { full = "Morgrath-Ravencrest", short = "Morgrath",
                     class = "DEATHKNIGHT" } },
}

T.Verdict:Show(guiltyResult, guiltySession)
mock.Advance(1)
check("seal shows the accused, not the emblem",
      T.Verdict.seal.faceMode == "portrait", T.Verdict.seal.faceMode)
check("the mark is hidden while a face is shown",
      T.Verdict.seal.glyph:IsShown() == false)
check("no face watch needed once resolved", T.Verdict.faceTicker == nil)
T.Verdict:Close()
mock.Advance(1)

-- The convicted player is usually a corpse elsewhere when the verdict lands.
mock.outOfRange["Morgrath"] = true
T.Verdict:Show(guiltyResult, guiltySession)
mock.Advance(1)
check("out-of-range accused falls back to a class icon",
      T.Verdict.seal.faceMode == "class", T.Verdict.seal.faceMode)
check("face watch armed while unresolved", T.Verdict.faceTicker ~= nil)

mock.outOfRange["Morgrath"] = nil
mock.Advance(3)
check("face fills in once they are visible again",
      T.Verdict.seal.faceMode == "portrait", T.Verdict.seal.faceMode)
check("watch stops once the face resolves", T.Verdict.faceTicker == nil)
T.Verdict:Close()
mock.Advance(1)

-- Nobody was convicted, so there is nobody to show.
T.Verdict:Show({ list = {}, total = 0, winner = nil, count = 0, hung = true,
                 label = "Somewhere" }, { candidates = {}, label = "Somewhere" })
mock.Advance(1)
check("a hung jury shows the mark, not a face",
      T.Verdict.seal.faceMode == nil and T.Verdict.seal.face:IsShown() == false)
check("no face watch on a hung jury", T.Verdict.faceTicker == nil)
T.Verdict:Close()
mock.Advance(1)
check("face watch stopped on close", T.Verdict.faceTicker == nil)

--------------------------------------------------------------------------------
-- Portraits on the ballot
--------------------------------------------------------------------------------

section("Ballot portraits")

mock.inGroup = true
mock.Fire("GROUP_ROSTER_UPDATE")
mock.Advance(2)
T.Session.current = nil
wipe(T.Session.lastCallBy)

local function goldish(c)
    return c and math.abs(c[1] - 0.909) < 0.02 and math.abs(c[2] - 0.698) < 0.02
end

TribunalDB.settings.portraits = true
T.Session:Request()
mock.Advance(1)

local row = T.Ballot.rows[1]
check("portrait shown", row.portrait:IsShown() == true)
check("class chip hidden", row.chip:IsShown() == false)
check("portrait resolved for a visible unit", row.portrait.mode == "portrait",
      row.portrait.mode)
check("row is 40px tall for portraits", T.Ballot.rowH == 40, T.Ballot.rowH)

-- Selecting a row borrows the ring.
T.Session:Cast(row.candidate.full)
check("selected portrait ring turns gold",
      goldish(rawget(row.portrait.ring, "__color")))
T.Session:Cast(T.Ballot.rows[2].candidate.full)
check("deselected ring returns to the class colour",
      not goldish(rawget(row.portrait.ring, "__color")))
T.Session:Abort(nil, true)

-- Somebody running back after a wipe has no portrait.
mock.Advance(TribunalDB.settings.voteCooldown + 1)
for _, m in ipairs(mock.group) do mock.outOfRange[m.name] = true end
T.Session:Request()
mock.Advance(1)
check("out-of-range player falls back to a class icon",
      T.Ballot.rows[1].portrait.mode == "class", T.Ballot.rows[1].portrait.mode)
check("portrait watcher armed while any row is unresolved",
      T.Ballot.portraitTicker ~= nil)

-- They come back into view; the watcher upgrades them.
for _, m in ipairs(mock.group) do mock.outOfRange[m.name] = nil end
mock.Advance(3)
check("portrait resolves once the player is visible again",
      T.Ballot.rows[1].portrait.mode == "portrait", T.Ballot.rows[1].portrait.mode)
check("watcher stops once every row has resolved", T.Ballot.portraitTicker == nil)
T.Session:Abort(nil, true)
check("watcher stopped on close", T.Ballot.portraitTicker == nil)

-- The quieter list is still available.
mock.Advance(TribunalDB.settings.voteCooldown + 1)
TribunalDB.settings.portraits = false
T.Session:Request()
mock.Advance(1)
check("chip mode shows the chip", T.Ballot.rows[1].chip:IsShown() == true)
check("chip mode hides the portrait", T.Ballot.rows[1].portrait:IsShown() == false)
check("row is 32px tall without portraits", T.Ballot.rowH == 32, T.Ballot.rowH)
check("no portrait watcher in chip mode", T.Ballot.portraitTicker == nil)
T.Session:Abort(nil, true)
TribunalDB.settings.portraits = true

--------------------------------------------------------------------------------
-- Footer text must never reach the control beside it
--------------------------------------------------------------------------------

section("Footer bounds")

-- Panel geometry, mirroring the constants in each module.
local BOARD_W, VERDICT_W, BALLOT_W, PAD = 424, 392, 392, 16
local BOARD_BTN, VERDICT_BTN, GUTTER = 148, 104, 16

local function fits(label, avail, what)
    local w = label.textWidth or 0
    check(("%s fits (%d <= %d)"):format(what, math.floor(w + 0.5), avail),
          w <= avail + 0.5, w)
end

-- Solo: this is the state that produced the overlap.
mock.inGroup = false
mock.Fire("GROUP_ROSTER_UPDATE")
T.Session.current = nil
T.Board:Show()
mock.Advance(1)

say("        footer reads: " .. tostring(T.Board.footNote.value))
fits(T.Board.footNote, BOARD_W - PAD * 2 - BOARD_BTN - GUTTER, "board footer, solo")
check("board footer not truncated when solo", T.Board.footNote.clipped ~= true)

-- Every other reason CanCall can return has to fit the same slot.
mock.inGroup = true
mock.Fire("GROUP_ROSTER_UPDATE")
mock.Advance(2)
for _, setup in ipairs({
    { "in combat",   function() mock.inCombat = true end,  function() mock.inCombat = false end },
    { "mid-trial",   function() T.Session:Request() end,   function() T.Session:Abort(nil, true) end },
}) do
    setup[2]()
    T.Board:Refresh()
    fits(T.Board.footNote, BOARD_W - PAD * 2 - BOARD_BTN - GUTTER, "board footer, " .. setup[1])
    setup[3]()
end

-- Cooldown wording, which carries a number.
mock.Advance(1)
T.Session:Request()
T.Session:Abort(nil, true)
T.Board:Refresh()
fits(T.Board.footNote, BOARD_W - PAD * 2 - BOARD_BTN - GUTTER, "board footer, cooldown")

-- The verdict footer carries the dungeon label, which can be very long.
mock.Advance(TribunalDB.settings.voteCooldown + 1)
T.Verdict:Show({ list = {}, total = 0, winner = nil, count = 0, hung = true,
                 label = "Operation: Mechagon - Workshop +24" },
               { candidates = {}, label = "Operation: Mechagon - Workshop +24" })
mock.Advance(1)
fits(T.Verdict.footNote, VERDICT_W - PAD * 2 - VERDICT_BTN - GUTTER, "verdict footer, long keystone")
T.Verdict:Close()

-- The ballot's two footer labels share one line.
mock.Advance(2)
T.Session:Request()
mock.Advance(1)
T.Session:Cast("Kazrul-Ravencrest")
local half = (BALLOT_W - PAD * 2 - GUTTER) / 2
fits(T.Ballot.progressLabel, half, "ballot left label")
fits(T.Ballot.statusLabel, half, "ballot right label")
check("ballot footer labels cannot meet",
      (T.Ballot.progressLabel.textWidth or 0) + (T.Ballot.statusLabel.textWidth or 0)
      <= BALLOT_W - PAD * 2 - GUTTER)
T.Session:Abort(nil, true)

-- A header subtitle long enough to reach the close button. The ballot's header
-- is bare now, so the docket is where a subtitle still renders.
T.Board:Show()
mock.Advance(1)
T.Board.header:SetSubtitle("The docket - Operation: Mechagon - Workshop +24")
fits(T.Board.header.subtitle, BOARD_W - 44 - 44, "docket header subtitle")
T.Board:Close()
mock.Advance(1)

check("a veiled window's header draws nothing",
      T.Ballot.header.bare == true and T.Ballot.header.subtitle == nil)
check("but can still be dragged and closed",
      T.Ballot.header:GetHeight() > 0 and T.Ballot.closeButton ~= nil)

--------------------------------------------------------------------------------
-- The close button on every window
--------------------------------------------------------------------------------

section("Close buttons")

local function clickClose(mod, label)
    local btn = mod.closeButton
    if not btn then check(label .. ": has a close button", false); return end
    local fn = rawget(btn, "__OnClick")
    if not fn then check(label .. ": close button is clickable", false); return end
    check(label .. ": close button is clickable", true)
    local ok, err = pcall(fn, btn)
    check(label .. ": click handled", ok, err)
    mock.Advance(1)
    check(label .. ": window hidden", mod.frame:IsShown() == false)
end

T.Board:Show();   mock.Advance(1); clickClose(T.Board, "board")
T.Config:Open();  mock.Advance(1); clickClose(T.Config, "settings")

-- The ballot also has to stop its ambient bed when dismissed by hand, even
-- though the trial keeps running in the background.
mock.Advance(TribunalDB.settings.voteCooldown + 1)
TribunalDB.settings.ambientEnabled = true
TribunalDB.settings.soundEnabled = true
T.Session:Request()
mock.Advance(1)
check("ballot: ambient bed running", T.Ballot.ambientTicker ~= nil)
clickClose(T.Ballot, "ballot")
check("ballot: ambient bed stopped on close", T.Ballot.ambientTicker == nil)
T.Session:Abort(nil, true)

T.Verdict:Show({ list = {}, total = 0, winner = nil, count = 0, hung = true,
                 label = "Somewhere" }, { candidates = {}, label = "Somewhere" })
mock.Advance(1)
check("verdict: auto-close timer armed", T.Verdict.autoClose ~= nil)
clickClose(T.Verdict, "verdict")
check("verdict: auto-close timer cancelled", T.Verdict.autoClose == nil)

--------------------------------------------------------------------------------
-- Two surfaces: the windows you open stay solid, the ones that arrive do not
--------------------------------------------------------------------------------

section("Chrome")

-- A veiled window has no bg texture whatsoever, so absence is the pass
-- condition rather than an alpha of zero.
local function fillAlpha(frame)
    if not frame then return nil end
    if not frame.bg then return 0 end
    local c = rawget(frame.bg, "__color")
    return c and c[4] or 0
end

local function shadowAlpha(obj)
    local fs = (obj.glyphs and obj.glyphs[1]) or obj
    return select(4, fs:GetShadowColor())
end

T.Ballot:Build(); T.Verdict:Build(); T.Ballot:BuildPrompt()
T.Board:Show(); T.Config:Open()
mock.Advance(1)

check("ballot is veiled", T.Ballot.frame.tribunalChrome == "veil",
      T.Ballot.frame.tribunalChrome)
check("verdict is veiled", T.Verdict.frame.tribunalChrome == "veil")
check("the wipe prompt is veiled", T.Ballot.prompt.tribunalChrome == "veil")
check("the docket stays solid", T.Board.frame.tribunalChrome == "solid",
      T.Board.frame.tribunalChrome)
check("settings stay solid", T.Config.frame.tribunalChrome == "solid")

-- Chrome is declared on the panel and inherited, so nothing built inside one
-- has to ask for it.
check("chrome is inherited down the parent chain",
      T.Theme:ChromeOf(T.Verdict.list) == "veil", T.Theme:ChromeOf(T.Verdict.list))
check("and a solid window's contents stay solid",
      T.Theme:ChromeOf(T.Config.scroll.content) == "solid")

check("a veiled window builds no surface texture at all",
      T.Ballot.frame.bg == nil and T.Verdict.frame.bg == nil)

local ballotFill, rowAlpha = fillAlpha(T.Ballot.frame), fillAlpha(T.Ballot.rows[1])
check("the container draws nothing at all", ballotFill == 0, ballotFill)
-- The container goes; the players do not. A row is a player, and a player is
-- a solid element that floats on the game rather than sitting in a box.
check("but the rows are solid", rowAlpha == 1, rowAlpha)
check("solid on the veiled window and the solid one alike",
      fillAlpha(T.Board.rows[1]) == 1, fillAlpha(T.Board.rows[1]))

-- Dialled up, the old relationship has to reappear: a row is content and
-- carries more than the container it sits in.
check("the docket's surface is untouched", fillAlpha(T.Board.frame) == 1,
      fillAlpha(T.Board.frame))
check("the settings' surface is untouched", fillAlpha(T.Config.frame) == 1,
      fillAlpha(T.Config.frame))

-- Not a lid, not corner ticks, not a faint anything. Nothing is built.
check("a veiled window has no edge of any kind",
      T.Ballot.frame.ticks == nil and T.Ballot.frame.borderEdges == nil)
check("and no grain either", T.Ballot.frame.grain == nil)
check("while a solid window keeps its border",
      T.Board.frame.borderEdges ~= nil and T.Board.frame.grain ~= nil)
check("a solid window keeps its border box",
      T.Board.frame.borderEdges ~= nil and T.Board.frame.ticks == nil)

-- The legibility shadow: on over the veil, off everywhere else.
check("veiled type carries the legibility shadow",
      shadowAlpha(T.Ballot.progressLabel) > 0, shadowAlpha(T.Ballot.progressLabel))
check("so does the verdict's kicker", shadowAlpha(T.Verdict.kicker) > 0)
check("solid windows still take their depth from value alone",
      shadowAlpha(T.Board.footNote) == 0, shadowAlpha(T.Board.footNote))
check("including their plain FontStrings",
      shadowAlpha(T.Config.recordNote) == 0, shadowAlpha(T.Config.recordNote))

--------------------------------------------------------------------------------
-- The whole UI must still build with the art switched off
--------------------------------------------------------------------------------

section("Art-free fallbacks")

T.Theme.useArt = false
for _, mod in ipairs({ T.Ballot, T.Verdict, T.Board, T.Config, T.Minimap }) do
    mod.frame, mod.button, mod.drawer, mod.prompt = nil, nil, nil, nil
    mod.rows, mod.histRows, mod.bars, mod.items = {}, {}, {}, {}
end

local errorsBefore = #mock.errors
local built = pcall(function()
    T.Minimap:BuildButton()
    T.Minimap:OpenDrawer()
    T.Minimap:CloseDrawer()
    T.Board:Show()
    T.Config:Open()
    T.Session:Request()
    T.Session:Cast("Kazrul-Ravencrest")
end)
mock.Advance(40)
check("every window builds without art", built, "build raised an error")
check("no new errors with art disabled", #mock.errors == errorsBefore,
      mock.errors[errorsBefore + 1])
T.Theme.useArt = true

--------------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------------

section("Errors raised during the run")
if #mock.errors == 0 then
    say("  none")
else
    for i, e in ipairs(mock.errors) do say(("  [%d] %s"):format(i, e)) end
end

say(("\n%d passed, %d failed, %d runtime errors"):format(pass, fail, #mock.errors))
if fail > 0 or #mock.errors > 0 then os.exit(1) end
