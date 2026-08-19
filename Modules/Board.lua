-- Tribunal :: Board
-- The permanent record. Standings by conviction, plus the recent docket.

local ADDON, T = ...
local Board = T:NewModule("Board")
local Theme, Anim = T.Theme, T.Anim

local PAD = 16
local ROW_H, ROW_GAP = 40, 8
local HIST_H = 40
local VIEW_H = 288

Board.rows = {}
Board.histRows = {}
Board.tweens = {}
Board.view = "standings"

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function BuildStandingRow(parent)
    local r = Theme:Row(parent, { height = ROW_H, interactive = true })

    r.rank = Theme:Text(r, 14, { color = "textMuted", justify = "CENTER",
        font = Theme.FONT.narrow })
    r.rank:SetPoint("LEFT", 12, 0)
    r.rank:SetWidth(20)

    r.chip = r:CreateTexture(nil, "ARTWORK")
    r.chip:SetSize(6, 6)
    r.chip:SetPoint("LEFT", r.rank, "RIGHT", 12, 0)

    -- Two lines centred on the row rather than hung off the chip's top edge.
    r.name = Theme:Text(r, 13, { color = "text" })
    r.name:SetPoint("BOTTOMLEFT", r.chip, "RIGHT", 10, 1)

    r.meta = Theme:Label(r, "", { size = 10, spacing = 1.2, color = "textDim" })
    r.meta:SetPoint("TOPLEFT", r.chip, "RIGHT", 10, -3)

    r.count = Theme:Text(r, 18, { color = "textMuted", justify = "RIGHT",
        font = Theme.FONT.narrow })
    r.count:SetPoint("RIGHT", r, "RIGHT", -14, 0)

    r.OnEnterExtra = function(self)
        if not self.entry then return end
        local e = self.entry
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -10, 0)
        GameTooltip:AddLine(Theme:ClassHex(e.class) .. e.short .. "|r")
        GameTooltip:AddDoubleLine("Wipes blamed on them",
            Theme.HEX.gold .. e.guilty .. "|r")
        GameTooltip:AddDoubleLine("Trials stood", tostring(e.trials))
        GameTooltip:AddDoubleLine("Conviction rate",
            ("%d%%"):format(math.floor(e.rate * 100 + 0.5)))
        GameTooltip:AddDoubleLine("Votes cast", tostring(e.votesCast))
        GameTooltip:AddDoubleLine("Votes received", tostring(e.votesReceived))
        if e.lastDungeon then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(Theme.HEX.muted .. "Last convicted in " .. e.lastDungeon .. "|r")
        end
        GameTooltip:Show()
    end
    r.OnLeaveExtra = function() GameTooltip:Hide() end

    return r
end

local function BuildHistoryRow(parent)
    local r = Theme:Row(parent, { height = HIST_H, interactive = false })

    r.who = Theme:Text(r, 13, { color = "text" })
    r.who:SetPoint("BOTTOMLEFT", r, "LEFT", 12, 1)

    r.when = Theme:Label(r, "", { size = 9, spacing = 1, color = "textDim" })
    r.when:SetPoint("TOPLEFT", r, "LEFT", 12, -3)

    r.score = Theme:Text(r, 13, { color = "text", justify = "RIGHT",
        font = Theme.FONT.narrow })
    r.score:SetPoint("BOTTOMRIGHT", r, "RIGHT", -12, 1)

    -- Bounded: a long keystone name would otherwise run back into the name.
    r.where = Theme:Label(r, "", { size = 9, spacing = 1, color = "textDim",
        maxWidth = 200 })
    r.where:SetPoint("TOPRIGHT", r, "RIGHT", -12, -3)

    return r
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function Board:Build()
    if self.frame then return self.frame end

    local f = Theme:Panel(UIParent, {
        name = "TribunalBoardFrame", width = 424, height = 448,
    })
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:Hide()

    self.header = Theme:Header(f, "TRIBUNAL", "The docket")
    self.closeButton = Theme:CloseButton(f, function() Board:Close() end)
    Theme:MakeMovable(f, self.header, function() Board:SavePosition() end)
    Theme:MakeCloseable(f, "TribunalBoardFrame")

    -- View switch ---------------------------------------------------------
    self.tabs = {}
    local tabDefs = { { "standings", "Standings" }, { "history", "Recent verdicts" } }
    local x = PAD
    for _, def in ipairs(tabDefs) do
        local key, text = def[1], def[2]
        local tab = CreateFrame("Button", nil, f)
        tab:SetHeight(22)

        tab.label = Theme:Label(tab, text, { size = 10, spacing = 1.8 })
        tab.label:SetPoint("LEFT", 0, 0)
        tab:SetWidth((tab.label.textWidth or 40) + 4)

        tab.underline = tab:CreateTexture(nil, "ARTWORK")
        tab.underline:SetHeight(1)
        tab.underline:SetPoint("BOTTOMLEFT", 0, 0)
        tab.underline:SetPoint("BOTTOMRIGHT", 0, 0)
        tab.underline:SetColorTexture(Theme:Color("gold"))
        tab.underline:Hide()

        tab:SetPoint("TOPLEFT", f, "TOPLEFT", x, -64)
        x = x + tab:GetWidth() + 20

        tab:SetScript("OnClick", function() Board:SetView(key) end)
        tab:SetScript("OnEnter", function(self)
            if Board.view ~= key then self.label:SetTextColor(Theme:Color("text")) end
        end)
        tab:SetScript("OnLeave", function(self)
            if Board.view ~= key then self.label:SetTextColor(Theme:Color("textMuted")) end
        end)

        self.tabs[key] = tab
    end

    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -88)
    rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -88)
    rule:SetColorTexture(Theme:Color("hairline", 0.7))

    -- Scroll region -------------------------------------------------------
    self.scroll = Theme:ScrollArea(f)
    self.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -96)
    self.scroll:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD - 4, -96)
    self.scroll:SetHeight(VIEW_H)
    self.content = self.scroll.content
    self.content:SetWidth(424 - PAD * 2 - 4)

    -- Empty state ---------------------------------------------------------
    self.empty = CreateFrame("Frame", nil, f)
    self.empty:SetPoint("TOPLEFT", self.scroll)
    self.empty:SetPoint("BOTTOMRIGHT", self.scroll)
    self.empty:Hide()

    local emblem = self.empty:CreateTexture(nil, "ARTWORK")
    emblem:SetSize(46, 46)
    emblem:SetPoint("CENTER", self.empty, "CENTER", 0, 28)
    if Theme:Art(emblem, "Emblem") then
        emblem:SetVertexColor(Theme:Color("textDim"))
    else
        emblem:Hide()
    end

    self.emptyTitle = Theme:Label(self.empty, "The docket is clear", {
        size = 11, spacing = 2, color = "textMuted" })
    self.emptyTitle:SetPoint("TOP", emblem, "BOTTOM", 0, -14)

    local emptyBody = Theme:Text(self.empty, 12, { color = "textDim", justify = "CENTER" })
    emptyBody:SetPoint("TOP", self.emptyTitle, "BOTTOM", 0, -10)
    emptyBody:SetWidth(260)
    emptyBody:SetText("No verdicts have been recorded. Call the court after your next wipe.")

    -- Footer --------------------------------------------------------------
    local footLine = f:CreateTexture(nil, "ARTWORK")
    footLine:SetHeight(1)
    footLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 48)
    footLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 48)
    footLine:SetColorTexture(Theme:Color("hairline"))

    -- Bounded to the space left of the Convene button, which is 148 wide.
    self.footNote = Theme:Label(f, "", {
        size = 10, spacing = 1.4, color = "textDim",
        maxWidth = 424 - PAD * 2 - 156 - 16,
    })
    self.footNote:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 16)

    self.callButton = Theme:Button(f, "Convene the court", {
        width = 156, height = 24, accent = true,
        tooltip = "Open a ballot for everyone in your group who is running Tribunal.",
        onClick = function() T.Session:Request() end,
    })
    self.callButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 16)

    self.frame = f
    self:RestorePosition()
    self:SetView("standings")
    return f
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function Board:SavePosition()
    local p, _, rp, x, y = self.frame:GetPoint(1)
    TribunalDB.ui.board = { point = p, relPoint = rp, x = x, y = y }
end

function Board:RestorePosition()
    local pos = TribunalDB.ui and TribunalDB.ui.board
    if not pos or not pos.point then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

--------------------------------------------------------------------------------
-- Views
--------------------------------------------------------------------------------

function Board:SetView(key)
    self.view = key
    for k, tab in pairs(self.tabs) do
        local on = (k == key)
        tab.label:SetTextColor(Theme:Color(on and "text" or "textMuted"))
        tab.underline:SetShown(on)
        if on then
            tab.underline:ClearAllPoints()
            tab.underline:SetPoint("BOTTOMLEFT", 0, 0)
            Theme:Strike(tab.underline, "HORIZONTAL", tab:GetWidth())
        end
    end
    self.scroll:SetVerticalScroll(0)
    self:Refresh(true)
end

local function RelativeTime(ts)
    local delta = time() - (ts or 0)
    if delta < 60 then return "just now" end
    if delta < 3600 then return ("%dm ago"):format(math.floor(delta / 60)) end
    if delta < 86400 then return ("%dh ago"):format(math.floor(delta / 3600)) end
    return ("%dd ago"):format(math.floor(delta / 86400))
end

function Board:RenderStandings(animate)
    local data = T:GetLeaderboard()

    -- Somebody with zero convictions and zero trials has no business here.
    local list = {}
    for _, e in ipairs(data) do
        if e.guilty > 0 or e.trials > 0 then list[#list + 1] = e end
    end

    for _, r in ipairs(self.histRows) do r:Hide() end

    if #list == 0 then
        for _, r in ipairs(self.rows) do r:Hide() end
        self.empty:Show()
        self.content.contentHeight = 1
        self.scroll:UpdateThumb()
        return
    end
    self.empty:Hide()

    for i, e in ipairs(list) do
        local r = self.rows[i]
        if not r then r = BuildStandingRow(self.content); self.rows[i] = r end

        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(i - 1) * (ROW_H + ROW_GAP))
        r:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -(i - 1) * (ROW_H + ROW_GAP))

        local lead = (i == 1 and e.guilty > 0)
        r.entry = e
        r.accentColor = lead and "gold" or "hairline"

        r.rank:SetText(tostring(i))
        r.rank:SetTextColor(Theme:Color(lead and "gold" or "textDim"))

        r.chip:SetColorTexture(Theme:ClassColor(e.class))
        r.name:SetText(e.short)
        r.name:SetTextColor(Theme:Color("text"))

        local rate = e.trials > 0 and math.floor(e.rate * 100 + 0.5) or 0
        r.meta:SetText(("%d %s  %s  %d%% convicted")
            :format(e.trials, e.trials == 1 and "trial" or "trials",
                    "\194\183", rate):upper())

        -- Gold marks one thing in this list: who is top of it. The rank
        -- numeral and the row accent carry that between them.
        r.count:SetText(tostring(e.guilty))
        r.count:SetTextColor(Theme:Color(lead and "text" or "textMuted"))

        r.bg:SetColorTexture(Theme:Color(lead and "raisedHi" or "raised"))
        r.accent:SetColorTexture(Theme:Color(lead and "gold" or "hairline"))
        r:Show()

        if animate then
            r:SetAlpha(0)
            self.tweens[#self.tweens + 1] = Anim:Tween({
                delay = (i - 1) * 0.04, duration = 0.3, ease = "outCubic",
                onUpdate = function(v) r:SetAlpha(v) end,
            })
        else
            r:SetAlpha(1)
        end
    end
    for i = #list + 1, #self.rows do self.rows[i]:Hide() end

    self.content.contentHeight = #list * (ROW_H + ROW_GAP)
    self.content:SetHeight(self.content.contentHeight)
    self.scroll:UpdateThumb()
end

function Board:RenderHistory(animate)
    for _, r in ipairs(self.rows) do r:Hide() end

    local hist = TribunalDB.history
    if #hist == 0 then
        for _, r in ipairs(self.histRows) do r:Hide() end
        self.empty:Show()
        self.content.contentHeight = 1
        self.scroll:UpdateThumb()
        return
    end
    self.empty:Hide()

    local shown = math.min(#hist, 60)
    for i = 1, shown do
        local h = hist[i]
        local r = self.histRows[i]
        if not r then r = BuildHistoryRow(self.content); self.histRows[i] = r end

        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(i - 1) * (HIST_H + ROW_GAP))
        r:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -(i - 1) * (HIST_H + ROW_GAP))

        r.when:SetText(RelativeTime(h.time):upper())
        r.where:SetText((h.label or ""):upper())

        if h.winner then
            local rec = TribunalDB.players[h.winner]
            r.who:SetText(Theme:ClassHex(rec and rec.class) .. T:ShortName(h.winner) .. "|r")
            r.score:SetText(("%d/%d"):format(h.count or 0, h.total or 0))
            r.score:SetTextColor(Theme:Color("text"))
            r.accent:SetColorTexture(Theme:Color("crimson", 0.7))
        else
            r.who:SetText("|cff8A8E9CHung jury|r")
            r.score:SetText("--")
            r.score:SetTextColor(Theme:Color("textDim"))
            r.accent:SetColorTexture(Theme:Color("hairline"))
        end
        r:Show()

        if animate then
            r:SetAlpha(0)
            self.tweens[#self.tweens + 1] = Anim:Tween({
                delay = math.min(0.4, (i - 1) * 0.03), duration = 0.28, ease = "outCubic",
                onUpdate = function(v) r:SetAlpha(v) end,
            })
        else
            r:SetAlpha(1)
        end
    end
    for i = shown + 1, #self.histRows do self.histRows[i]:Hide() end

    self.content.contentHeight = shown * (HIST_H + ROW_GAP)
    self.content:SetHeight(self.content.contentHeight)
    self.scroll:UpdateThumb()
end

function Board:Refresh(animate)
    if not self.frame then return end

    local trials = TribunalDB.stats.trials or 0
    self.header:SetSubtitle(("%d %s held"):format(trials, trials == 1 and "trial" or "trials"))

    local peers = T.Comm:PeerCount()
    local ok, reason = T.Session:CanCall()
    -- The enabled button already says "ready"; the footer is better spent on
    -- who can actually receive a ballot.
    local note
    if not ok then
        note = reason or ""
    elseif peers > 0 then
        note = ("%d others have Tribunal"):format(peers)
    else
        note = "Nobody else has Tribunal"
    end
    self.footNote:SetText(note:upper())

    Anim:CancelAll(self.tweens)
    if self.view == "history" then
        self:RenderHistory(animate)
    else
        self:RenderStandings(animate)
    end
end

--------------------------------------------------------------------------------
-- Show / hide
--------------------------------------------------------------------------------

function Board:Show()
    local f = self:Build()
    f:SetScale(TribunalDB.settings.scale or 1)
    self:Refresh(true)
    self.header:Strike()
    Anim:SlideIn(f, { y = -14, duration = 0.36 })
end

function Board:Close()
    if not self.frame or not self.frame:IsShown() then return end
    Anim:CancelAll(self.tweens)
    Anim:Fade(self.frame, 0, 0.2)
end

function Board:Toggle()
    if self.frame and self.frame:IsShown() then self:Close() else self:Show() end
end

function Board:IsShown()
    return self.frame and self.frame:IsShown()
end
