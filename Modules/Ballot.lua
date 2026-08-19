-- Tribunal :: Ballot
-- The voting window, the countdown, and the post-wipe prompt.

local ADDON, T = ...
local Ballot = T:NewModule("Ballot")
local Theme, Anim = T.Theme, T.Anim

-- Portraits need a 28px disc to read; without them the row can be tighter.
local ROW_H_PORTRAIT, ROW_H_PLAIN = 40, 32
local ROW_GAP = 8
local PAD = 16

Ballot.rows = {}
Ballot.tweens = {}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function BuildRow(parent, index)
    local row = Theme:Row(parent, { height = ROW_H_PORTRAIT })
    row:SetPoint("LEFT", parent, "LEFT", PAD, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)

    -- Two identity treatments: a portrait, or the original 6px class chip for
    -- anyone who wants the quieter list. Only one is ever shown.
    row.portrait = Theme:Portrait(row, 28)
    row.portrait:SetPoint("LEFT", 8, 0)

    row.chip = row:CreateTexture(nil, "ARTWORK")
    row.chip:SetSize(6, 6)
    row.chip:SetPoint("LEFT", 12, 0)

    row.name = Theme:Text(row, 13, { color = "text" })

    row.role = Theme:Label(row, "", { size = 10, spacing = 1.4 })
    row.role:SetPoint("RIGHT", row, "RIGHT", -30, 0)

    -- The tally chip on the right: hidden while the ballot is secret.
    row.tally = Theme:Text(row, 12, { color = "text", justify = "RIGHT" })
    row.tally:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.tally:Hide()

    row.seal = row:CreateTexture(nil, "OVERLAY")
    row.seal:SetSize(5, 5)
    row.seal:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.seal:SetColorTexture(Theme:Color("gold"))
    row.seal:SetRotation(math.pi / 4)
    row.seal:Hide()

    -- Floating, there is no rectangle to light up, so hover lives on the two
    -- things that are actually there: the name and the portrait's ring.
    row.OnEnterExtra = function(self)
        if not self.candidate or self.selected then return end
        self.name:SetTextColor(Theme:Color("text"))
        if Ballot.portraits then
            self.portrait:SetRingColor(Theme:Color("goldLight", 0.9))
        end
    end

    row.OnLeaveExtra = function(self)
        if not self.candidate or self.selected then return end
        self.name:SetTextColor(Theme:Color("text", 0.86))
        if Ballot.portraits then self.portrait:ResetRing() end
    end

    row:SetScript("OnClick", function(self)
        if not self.candidate then return end
        T.Session:Cast(self.candidate.full)
    end)

    return row
end

function Ballot:Build()
    if self.frame then return self.frame end

    -- Veiled: nobody opened this window. It arrives on its own while the party
    -- is still running back, so it holds its elements over the game rather
    -- than covering a fifth of the screen with a slab.
    local f = Theme:Panel(UIParent, {
        name = "TribunalBallotFrame", width = 392, height = 300, chrome = "veil",
    })
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 90)
    f:SetFrameStrata("DIALOG")
    f:Hide()

    self.header = Theme:Header(f, "TRIBUNAL", "Trial in session")
    self.closeButton = Theme:CloseButton(f, function() Ballot:Close() end)
    Theme:MakeMovable(f, self.header, function() Ballot:SavePosition() end)
    Theme:MakeCloseable(f, "TribunalBallotFrame")

    -- Question line -------------------------------------------------------
    local question = Theme:Label(f, "Who wiped us?", { size = 11, spacing = 2.2, color = "text" })
    question:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", PAD, -16)
    self.question = question

    -- The countdown is the number and nothing else. A cooldown swipe would be
    -- the only filled disc in a UI made of hairlines, and its mask does not
    -- apply to the swipe, so it drew as a blocky wedge.
    self.clock = Theme:Text(f, 20, { color = "gold", justify = "RIGHT",
        font = Theme.FONT.narrow })
    self.clock:SetPoint("TOPRIGHT", self.header, "BOTTOMRIGHT", -PAD, -12)

    -- Rows ----------------------------------------------------------------
    self.list = CreateFrame("Frame", nil, f)
    self.list:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, -40)
    self.list:SetPoint("TOPRIGHT", self.header, "BOTTOMRIGHT", 0, -40)
    self.list:SetHeight(1)

    -- Footer --------------------------------------------------------------
    local footLine = f:CreateTexture(nil, "ARTWORK")
    footLine:SetHeight(1)
    footLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 48)
    footLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 48)
    footLine:SetColorTexture(Theme:Color("hairline"))

    -- The two footer labels share one line; each gets half the room minus a
    -- gutter so they cannot meet in the middle.
    local footHalf = (392 - PAD * 2 - 16) / 2
    self.progressLabel = Theme:Label(f, "Awaiting ballots", {
        size = 10, spacing = 1.6, maxWidth = footHalf })
    self.progressLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 24)

    self.statusLabel = Theme:Label(f, "", {
        size = 10, spacing = 1.6, color = "text", maxWidth = footHalf })
    self.statusLabel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 26)
    -- SetText resizes the frame to the text, so the anchor stays correct and
    -- only needs re-applying after the width changes.
    self.statusLabel.SetRightText = function(s, str)
        s:SetText((str or ""):upper())
        s:ClearAllPoints()
        s:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 24)
    end

    self.progress = Theme:Bar(f, { height = 2, color = "textDim" })
    self.progress:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 16)
    self.progress:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 16)

    self.frame = f
    self:RestorePosition()
    return f
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function Ballot:SavePosition()
    local p, _, rp, x, y = self.frame:GetPoint(1)
    TribunalDB.ui.ballot = { point = p, relPoint = rp, x = x, y = y }
end

function Ballot:RestorePosition()
    local pos = TribunalDB.ui and TribunalDB.ui.ballot
    if not pos or not pos.point then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

--------------------------------------------------------------------------------
-- Opening
--------------------------------------------------------------------------------

function Ballot:Open(session)
    local f = self:Build()
    self.session = session

    Anim:CancelAll(self.tweens)
    self:DismissPrompt()

    f:SetScale(TribunalDB.settings.scale or 1)
    self.header:SetSubtitle(("Trial in session  %s  %s")
        :format("\194\183", session.label))

    -- Size the panel to the number of defendants, and to whether the rows
    -- are carrying portraits.
    local portraits = TribunalDB.settings.portraits and true or false
    local rowH = portraits and ROW_H_PORTRAIT or ROW_H_PLAIN
    self.rowH, self.portraits = rowH, portraits

    local n = #session.candidates
    local listH = n * rowH + math.max(0, n - 1) * ROW_GAP
    self.list:SetHeight(listH)
    f:SetHeight(self.header:GetHeight() + 40 + listH + 16 + 48)

    -- Lay out and stagger the rows in.
    for i, cand in ipairs(session.candidates) do
        local row = self.rows[i]
        if not row then
            row = BuildRow(self.list, i)
            self.rows[i] = row
        end
        row:SetHeight(rowH)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.list, "TOPLEFT", PAD, -(i - 1) * (rowH + ROW_GAP))
        row:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", -PAD, -(i - 1) * (rowH + ROW_GAP))

        row.candidate = cand

        row.portrait:SetShown(portraits)
        row.chip:SetShown(not portraits)
        row.name:ClearAllPoints()
        if portraits then
            row.portrait:SetUnit(T:UnitFor(cand.full), cand.class)
            row.name:SetPoint("LEFT", row.portrait, "RIGHT", 12, 0)
        else
            row.chip:SetColorTexture(Theme:ClassColor(cand.class))
            row.name:SetPoint("LEFT", row.chip, "RIGHT", 10, 0)
        end

        row.name:SetText(cand.short .. (cand.full == T:FullName("player")
            and ("  |cff4A5162%s|r"):format("you") or ""))
        row.role:SetText((cand.class and LOCALIZED_CLASS_NAMES_MALE
            and LOCALIZED_CLASS_NAMES_MALE[cand.class] or cand.class or ""):upper())
        row.tally:Hide()
        row.seal:Hide()
        row:SetSelected(false)
        row:EnableMouse(true)
        row:SetAlpha(0)
        row:Show()
    end
    for i = n + 1, #self.rows do self.rows[i]:Hide() end

    Anim:Stagger(self.rows, 0.045, function(i, row)
        if i > n then return end
        self.tweens[#self.tweens + 1] = Anim:Tween({
            duration = 0.34, ease = "outQuint",
            onUpdate = function(v)
                row:SetAlpha(v)
                row:ClearAllPoints()
                local y = -(i - 1) * (Ballot.rowH + ROW_GAP)
                row:SetPoint("TOPLEFT", Ballot.list, "TOPLEFT", PAD + (1 - v) * 10, y)
                row:SetPoint("TOPRIGHT", Ballot.list, "TOPRIGHT", -PAD + (1 - v) * 10, y)
            end,
        })
    end)

    -- Countdown. The colour has to be reset here, not just in Build: the
    -- last five seconds turn the ring crimson and it would stay that way for
    -- every later ballot.
    self.clock:SetTextColor(Theme:Color("gold"))
    self.lastTick = nil
    f:SetScript("OnUpdate", function() Ballot:OnUpdate() end)

    self.progress:SetValue(0)
    self:OnVoteChanged()
    self:StartPortraitWatch()

    self.header:Strike()
    Anim:SlideIn(f, { y = -14, duration = 0.38 })
    self:StartAmbient()
end

function Ballot:Focus()
    if self.frame and self.session and self.session.state == "open" then
        self.frame:Show()
        Anim:SlideIn(self.frame, { y = -8, duration = 0.24 })
    end
end

function Ballot:Close()
    self:StopAmbient()
    self:StopPortraitWatch()
    if not self.frame or not self.frame:IsShown() then return end
    self.frame:SetScript("OnUpdate", nil)
    self.frame:SetScript("OnUpdate", nil)
    Anim:CancelAll(self.tweens)
    Anim:Fade(self.frame, 0, 0.2, "outCubic")
end

--------------------------------------------------------------------------------
-- Live state
--------------------------------------------------------------------------------

function Ballot:OnUpdate()
    local s = self.session
    if not s or s.state ~= "open" then return end

    local left = math.max(0, s.endsAt - GetTime())
    local whole = math.ceil(left)
    self.clock:SetText(tostring(whole))

    if whole <= 5 then
        self.clock:SetTextColor(Theme:Color("crimson"))
        if whole ~= self.lastTick and whole > 0 then
            self.lastTick = whole
            T:Sound("Tick")
        end
    else
        self.clock:SetTextColor(Theme:Color("gold"))
    end
end

function Ballot:OnVoteChanged()
    local s = self.session
    if not s or not self.frame then return end

    local secret = TribunalDB.settings.anonymous

    -- Live per-candidate counts, only when the ballot is open.
    local counts = {}
    if not secret then
        for _, target in pairs(s.votes) do
            counts[target] = (counts[target] or 0) + 1
        end
    end

    for i, row in ipairs(self.rows) do
        if row.candidate then
            local chosen = s.myVote == row.candidate.full
            row:SetSelected(chosen)
            row.seal:SetShown(chosen)
            if self.portraits then
                if chosen then row.portrait:SetRingColor(Theme:Color("gold"))
                else row.portrait:ResetRing() end
            end
            if secret then
                row.tally:Hide()
            else
                local c = counts[row.candidate.full] or 0
                row.tally:SetText(c > 0 and tostring(c) or "")
                row.tally:SetShown(c > 0 and not chosen)
            end
            row.name:SetTextColor(Theme:Color(chosen and "text" or "text",
                chosen and 1 or 0.86))
        end
    end

    local electorate = math.max(s.electorate or 1, s.voterCount)
    self.progressLabel:SetText(("%d of %d %s cast")
        :format(s.voterCount, electorate,
                electorate == 1 and "ballot" or "ballots"):upper())
    self.statusLabel:SetRightText(s.myVote and "Your ballot is sealed" or "You have not voted")
    self.statusLabel:SetTextColor(Theme:Color(s.myVote and "text" or "textDim"))

    self.progress:AnimateTo(electorate > 0 and (s.voterCount / electorate) or 0, 0.5, 0)
end

function Ballot:OnTallying()
    if not self.frame or not self.frame:IsShown() then return end

    self.frame:SetScript("OnUpdate", nil)
    self.clock:SetText("")
    self:StopAmbient()

    self.progressLabel:SetText("Counting the ballots")
    self.statusLabel:SetRightText("")

    for _, row in ipairs(self.rows) do
        row:EnableMouse(false)
        if row:IsShown() and not row.selected then
            self.tweens[#self.tweens + 1] = Anim:Fade(row, 0.35, 0.4)
        end
    end

    -- The progress bar drains as a "thinking" beat before the verdict lands.
    self.tweens[#self.tweens + 1] = Anim:Tween({
        duration = 1.1, from = self.progress.value, to = 0, ease = "inOutSine",
        onUpdate = function(v) Ballot.progress:SetValue(v, true) end,
    })
end

--------------------------------------------------------------------------------
-- Portrait watch
--------------------------------------------------------------------------------

-- A portrait only exists for a unit the client can currently see, and a ballot
-- is most likely to be open while people are running back. Rows that fell back
-- to a class icon are retried until they resolve.
function Ballot:StartPortraitWatch()
    self:StopPortraitWatch()
    if not self.portraits then return end

    self.portraitTicker = C_Timer.NewTicker(2, function()
        local s = Ballot.session
        if not s or s.state ~= "open" then Ballot:StopPortraitWatch() return end

        local pending = 0
        for _, row in ipairs(Ballot.rows) do
            if row:IsShown() and row.candidate and row.portrait.mode ~= "portrait" then
                row.portrait:SetUnit(T:UnitFor(row.candidate.full), row.candidate.class)
                if row.portrait.mode ~= "portrait" then pending = pending + 1 end
                if row.selected then row.portrait:SetRingColor(Theme:Color("gold")) end
            end
        end
        if pending == 0 then Ballot:StopPortraitWatch() end
    end)
end

function Ballot:StopPortraitWatch()
    if self.portraitTicker then
        self.portraitTicker:Cancel()
        self.portraitTicker = nil
    end
end

--------------------------------------------------------------------------------
-- Ambient bed
--------------------------------------------------------------------------------

function Ballot:StartAmbient()
    local s = TribunalDB.settings
    if not s.soundEnabled or not s.ambientEnabled then return end

    local function play()
        local ok, handle = T:Sound("Chamber")
        Ballot.ambientHandle = ok and handle or nil
    end
    play()
    -- Chamber.ogg is ~24s; re-trigger just under that to cover a long ballot.
    self.ambientTicker = C_Timer.NewTicker(23.5, play)
end

function Ballot:StopAmbient()
    if self.ambientTicker then self.ambientTicker:Cancel(); self.ambientTicker = nil end
    if self.ambientHandle then
        StopSound(self.ambientHandle, 400)
        self.ambientHandle = nil
    end
end

--------------------------------------------------------------------------------
-- Post-wipe prompt
--------------------------------------------------------------------------------

-- A small unobtrusive toast; it never steals the mouse or blocks anything.
function Ballot:BuildPrompt()
    if self.prompt then return self.prompt end

    -- Veiled like the ballot it leads to. The grain that used to be switched
    -- off here is now the surface, so it has to stay: without it a toast this
    -- small has nothing left to sit on.
    local p = Theme:Panel(UIParent, { width = 272, height = 96, chrome = "veil" })
    p:SetPoint("TOP", UIParent, "TOP", 0, -180)
    p:SetFrameStrata("HIGH")
    p:Hide()

    -- The toast is 96px tall and every line in it matters, so the plate runs
    -- the whole body rather than banding it.

    local accent = p:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(2)
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetColorTexture(Theme:Color("crimson"))

    local title = Theme:Label(p, "The party has fallen", { size = 10, spacing = 1.8, color = "crimson" })
    title:SetPoint("TOPLEFT", 16, -16)

    local body = Theme:Text(p, 12, { color = "text" })
    body:SetPoint("TOPLEFT", 16, -34)
    body:SetText("Call the court to order?")

    local yes = Theme:Button(p, "Convene", { width = 84, height = 22, accent = true,
        onClick = function() Ballot:DismissPrompt(); T.Session:Request() end })
    yes:SetPoint("BOTTOMRIGHT", -16, 16)

    local no = Theme:Button(p, "Let it go", { width = 74, height = 22,
        onClick = function() Ballot:DismissPrompt() end })
    no:SetPoint("RIGHT", yes, "LEFT", -8, 0)

    self.prompt = p
    return p
end

function Ballot:OfferPrompt()
    local ok = T.Session:CanCall()
    if not ok then return end

    local p = self:BuildPrompt()
    p:SetScale(TribunalDB.settings.scale or 1)
    Anim:SlideIn(p, { y = 10, duration = 0.4 })

    if self.promptTimer then self.promptTimer:Cancel() end
    self.promptTimer = C_Timer.NewTimer(20, function() Ballot:DismissPrompt() end)
end

function Ballot:DismissPrompt()
    if self.promptTimer then self.promptTimer:Cancel(); self.promptTimer = nil end
    if self.prompt and self.prompt:IsShown() then
        Anim:Fade(self.prompt, 0, 0.2)
    end
end
