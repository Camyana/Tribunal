-- Tribunal :: Config
-- Settings, in the addon's own visual language rather than Blizzard's, plus a
-- stub in the interface options so the addon is discoverable from there.

local ADDON, T = ...
local Config = T:NewModule("Config")
local Theme, Anim = T.Theme, T.Anim

local PAD = 16
local WIDTH = 384
local VIEW_H = 400          -- the settings list is taller than this, so it scrolls

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

function Config:Build()
    if self.frame then return self.frame end

    local S = TribunalDB.settings
    local f = Theme:Panel(UIParent, {
        name = "TribunalConfigFrame", width = WIDTH, height = 64 + VIEW_H + 16,
    })
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:Hide()

    self.header = Theme:Header(f, "TRIBUNAL", "Settings")
    self.closeButton = Theme:CloseButton(f, function() Config:Close() end)
    Theme:MakeMovable(f, self.header, function() Config:SavePosition() end)
    Theme:MakeCloseable(f, "TribunalConfigFrame")

    -- The content is taller than any sane window, so it lives in a scroll
    -- region rather than growing the panel off the bottom of the screen.
    self.scroll = Theme:ScrollArea(f)
    self.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -64)
    self.scroll:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD - 4, -64)
    self.scroll:SetHeight(VIEW_H)

    local body = self.scroll.content
    body:SetWidth(WIDTH - PAD * 2 - 4)

    -- A running cursor keeps the layout declarative and easy to reorder.
    local y = 0
    local function place(widget, gap)
        y = y - (gap or 0)
        widget:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
        widget:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
        y = y - widget:GetHeight()
        return widget
    end

    -- The trial ------------------------------------------------------------
    place(Theme:Section(body, "The trial"), 0)

    self.duration = place(Theme:Slider(body, "Ballot stays open", {
        min = 10, max = 90, step = 5,
        hint = "How long the party has to vote before the verdict is read.",
        format = function(v) return ("%ds"):format(v) end,
        onChange = function(v) S.voteDuration = v end,
    }), 8)

    self.cooldown = place(Theme:Slider(body, "Cooldown between trials", {
        min = 0, max = 300, step = 15,
        hint = "Stops one person calling a vote every thirty seconds.",
        format = function(v) return v == 0 and "none" or ("%ds"):format(v) end,
        onChange = function(v) S.voteCooldown = v end,
    }), 8)

    self.anonymous = place(Theme:Check(body, "Secret ballot", {
        hint = "Hide who voted for whom until the verdict is read. Only the running total is shown while the ballot is open.",
        onChange = function(v) S.anonymous = v; T.Ballot:OnVoteChanged() end,
    }), 8)

    self.selfVote = place(Theme:Check(body, "You may convict yourself", {
        hint = "Includes you in the list of defendants. Honesty is optional.",
        onChange = function(v) S.selfVoteAllowed = v end,
    }), 0)

    -- Behaviour ------------------------------------------------------------
    place(Theme:Section(body, "Behaviour"), 24)

    self.autoPrompt = place(Theme:Check(body, "Offer a trial after a wipe", {
        hint = "When the whole party is dead, a small prompt asks whether to convene. It never opens a ballot on its own.",
        onChange = function(v) S.autoPrompt = v end,
    }), 8)

    self.announce = place(Theme:Check(body, "Announce the verdict in party chat", {
        hint = "Posts the result as a normal chat message so people without the addon can share in the shame.",
        onChange = function(v) S.announceVerdict = v end,
    }), 0)

    -- Sound ----------------------------------------------------------------
    place(Theme:Section(body, "Sound"), 24)

    self.sound = place(Theme:Check(body, "Play the court's sounds", {
        hint = "The gavel, the ballot taps, and the verdict bell.",
        onChange = function(v)
            S.soundEnabled = v
            if v then T:Sound("BallotCast", true) end
        end,
    }), 8)

    self.ambient = place(Theme:Check(body, "Ambient bed while voting", {
        hint = "A low drone underneath the ballot. Turn it off if you already run enough audio.",
        onChange = function(v) S.ambientEnabled = v end,
    }), 0)

    place(Theme:Label(body, "Output channel", { size = 10, spacing = 1.6 }), 16)

    self.channel = Theme:Segmented(body, {
        { "Master", "Master" }, { "SFX", "Effects" },
        { "Ambience", "Ambience" }, { "Dialog", "Dialogue" },
    }, {
        onChange = function(key) S.soundChannel = key; T:Sound("BallotCast", true) end,
    })
    self.channel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y - 8)
    y = y - 8 - self.channel:GetHeight()

    -- Display --------------------------------------------------------------
    place(Theme:Section(body, "Display"), 24)

    self.scale = place(Theme:Slider(body, "Window scale", {
        min = 0.8, max = 1.25, step = 0.05,
        hint = "Scales every Tribunal window.",
        format = function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end,
        onChange = function(v)
            S.scale = v
            for _, mod in ipairs({ T.Ballot, T.Verdict, T.Board, T.Config }) do
                if mod.frame then mod.frame:SetScale(v) end
            end
        end,
    }), 8)

    self.opacity = place(Theme:Slider(body, "Ballot and verdict backing", {
        min = 0, max = 1, step = 0.05,
        hint = "The ballot and the verdict open on their own mid-run, so by "
            .. "default they have no background at all - just their contents "
            .. "over the game. Raise this if you play somewhere bright enough "
            .. "to need a surface behind them. The docket and this window are "
            .. "always solid.",
        format = function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end,
        onChange = function(v)
            S.opacity = v
            Theme:RefreshVeil()
        end,
    }), 8)

    self.portraits = place(Theme:Check(body, "Portraits on the ballot", {
        hint = "Show each player's portrait instead of a class colour chip. "
            .. "Anyone out of range falls back to their class icon until they "
            .. "come back into view.",
        onChange = function(v) S.portraits = v end,
    }), 8)

    self.minimapShown = place(Theme:Check(body, "Show the minimap button", {
        hint = "You can always reach everything with /trib.",
        onChange = function(v)
            TribunalDB.minimap.hide = not v
            T.Minimap:Refresh()
        end,
    }), 8)

    -- The record -----------------------------------------------------------
    place(Theme:Section(body, "The record"), 24)

    self.recordNote = Theme:Text(body, 11, { color = "textDim" })
    self.recordNote:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y - 8)
    self.recordNote:SetWidth(WIDTH - PAD * 2 - 8)
    self.recordNote:SetJustifyH("LEFT")
    y = y - 8 - 28

    self.wipeButton = Theme:Button(body, "Expunge the docket", {
        width = 160, height = 24,
        tooltip = "Erases every verdict, every tally, and every trial. This cannot be undone.",
        onClick = function() Config:ConfirmWipe() end,
    })
    self.wipeButton:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    y = y - 24

    body.contentHeight = math.abs(y) + 8
    body:SetHeight(body.contentHeight)

    self.frame = f
    self:RestorePosition()
    return f
end

--------------------------------------------------------------------------------
-- Destructive action
--------------------------------------------------------------------------------

StaticPopupDialogs["TRIBUNAL_WIPE_DOCKET"] = {
    text = "Erase every verdict Tribunal has recorded?\n\nThis cannot be undone.",
    button1 = "Expunge",
    button2 = CANCEL,
    OnAccept = function()
        wipe(TribunalDB.players)
        wipe(TribunalDB.history)
        TribunalDB.stats.trials = 0
        T.Board:Refresh()
        T.Config:Refresh()
        T:Print("The docket has been expunged.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    preferredIndex = 3,
}

function Config:ConfirmWipe()
    StaticPopup_Show("TRIBUNAL_WIPE_DOCKET")
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function Config:SavePosition()
    local p, _, rp, x, y = self.frame:GetPoint(1)
    TribunalDB.ui.config = { point = p, relPoint = rp, x = x, y = y }
end

function Config:RestorePosition()
    local pos = TribunalDB.ui and TribunalDB.ui.config
    if not pos or not pos.point then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

--------------------------------------------------------------------------------
-- Sync
--------------------------------------------------------------------------------

function Config:Refresh()
    if not self.frame then return end
    local S = TribunalDB.settings

    self.duration:SetValue(S.voteDuration)
    self.cooldown:SetValue(S.voteCooldown)
    self.scale:SetValue(S.scale)
    self.opacity:SetValue(S.opacity)

    self.anonymous:SetChecked(S.anonymous, true)
    self.selfVote:SetChecked(S.selfVoteAllowed, true)
    self.autoPrompt:SetChecked(S.autoPrompt, true)
    self.announce:SetChecked(S.announceVerdict, true)
    self.sound:SetChecked(S.soundEnabled, true)
    self.ambient:SetChecked(S.ambientEnabled, true)
    self.portraits:SetChecked(S.portraits, true)
    self.minimapShown:SetChecked(not TribunalDB.minimap.hide, true)

    self.channel:SetValue(S.soundChannel)

    local players, trials = 0, TribunalDB.stats.trials or 0
    for _ in pairs(TribunalDB.players) do players = players + 1 end
    self.recordNote:SetText(("%d %s on record across %d %s.")
        :format(players, players == 1 and "player" or "players",
                trials, trials == 1 and "trial" or "trials"))

    self.scroll:UpdateThumb()
end

--------------------------------------------------------------------------------
-- Show / hide
--------------------------------------------------------------------------------

function Config:Open()
    local f = self:Build()
    f:SetScale(TribunalDB.settings.scale or 1)
    self:Refresh()
    self.header:Strike()
    Anim:SlideIn(f, { y = -12, duration = 0.34 })
end

function Config:Close()
    if not self.frame or not self.frame:IsShown() then return end
    Anim:Fade(self.frame, 0, 0.2)
end

function Config:Toggle()
    if self.frame and self.frame:IsShown() then self:Close() else self:Open() end
end

--------------------------------------------------------------------------------
-- Interface options stub
--------------------------------------------------------------------------------

function Config:OnLogin()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then return end

    local panel = CreateFrame("Frame")
    panel.name = "Tribunal"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Tribunal")

    local body = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    body:SetWidth(520)
    body:SetJustifyH("LEFT")
    body:SetText("Tribunal keeps its settings in its own window so they match the "
        .. "rest of the addon.\n\nYou can also reach it with /trib config.")

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(180, 24)
    open:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -20)
    open:SetText("Open Tribunal settings")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        Config:Open()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Tribunal")
    category.ID = "Tribunal"
    Settings.RegisterAddOnCategory(category)
    self.category = category
end
