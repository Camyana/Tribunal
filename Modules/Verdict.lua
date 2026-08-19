-- Tribunal :: Verdict
-- The reveal. Everything here is choreography; the result is already decided
-- by Session before this module is called.

local ADDON, T = ...
local Verdict = T:NewModule("Verdict")
local Theme, Anim = T.Theme, T.Anim

local PAD = 16
local BAR_H, BAR_GAP = 24, 8

-- The quiet stage is exactly one seal-diameter shorter than the guilty
-- one (56 - 40). Taking more than that pulls the detail line down through
-- the divider, because everything below the seal is anchored to it.
local STAGE_GUILTY, STAGE_QUIET = 176, 160
local SEAL_GUILTY, SEAL_QUIET = 56, 40

Verdict.bars = {}
Verdict.tweens = {}

-- The beat sheet. Retiming the reveal means editing this table and nothing
-- else.
local CUE = {
    sting   = 0.18,
    bloom   = 0.30,
    seal    = 0.46,
    kicker  = 0.78,
    name    = 0.98,
    detail  = 1.34,
    bars    = 1.58,
    barGap  = 0.09,
    footer  = 2.10,
}

-- The glow has exactly one owner. It rises into the name, flares once as the
-- name lands, then settles to a resting value -- it is never cut to zero,
-- because an audience that watched a light arrive notices it being deleted.
local RISE = CUE.name - CUE.bloom

local function BloomAlpha(elapsed, rest, flarePeak)
    if elapsed <= 0 then return 0 end
    if elapsed < RISE then
        local t = elapsed / RISE
        return 0.46 * (1 - (1 - t) ^ 3)
    end
    local d = elapsed - RISE
    local decay = rest + (0.46 - rest) * math.exp(-d / 0.55)
    local flare = flarePeak * math.exp(-((d / 0.26) ^ 2))
    return math.min(1, decay + flare)
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function BuildBar(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(BAR_H)

    b.name = Theme:Text(b, 12, { color = "textMuted" })
    b.name:SetPoint("TOPLEFT", 0, 0)

    b.count = Theme:Text(b, 12, { color = "textMuted", justify = "RIGHT",
        font = Theme.FONT.narrow })
    b.count:SetPoint("TOPRIGHT", 0, 0)

    b.bar = Theme:Bar(b, { height = 3 })
    b.bar:SetPoint("BOTTOMLEFT", 0, 2)
    b.bar:SetPoint("BOTTOMRIGHT", 0, 2)

    return b
end

-- The seal is drawn rather than textured: it has to change colour with the
-- outcome, and a flat 1px ring is what the design language actually asks for.
local function BuildSeal(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(SEAL_GUILTY, SEAL_GUILTY)

    s.ring = s:CreateTexture(nil, "BACKGROUND")
    s.ring:SetAllPoints()
    Theme:Circle(s.ring, s)

    -- A disc two pixels smaller, knocked back to the panel colour, leaves the
    -- ring behind as a 1px stroke.
    local inner = CreateFrame("Frame", nil, s)
    inner:SetPoint("CENTER")
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    local innerMask = Theme:CircleMask(inner)

    s.well = inner:CreateTexture(nil, "BORDER")
    s.well:SetAllPoints()
    Theme:Circle(s.well, inner, innerMask)

    s.fill = inner:CreateTexture(nil, "BORDER", nil, 1)
    s.fill:SetAllPoints()
    Theme:Circle(s.fill, inner, innerMask)

    -- The convicted player's own face, struck into the seal. On a guilty
    -- verdict this screen is about one person, so the seal shows that person
    -- rather than the addon's mark.
    s.face = inner:CreateTexture(nil, "ARTWORK")
    s.face:SetAllPoints()
    Theme:Circle(s.face, inner, innerMask)
    s.face:Hide()

    -- On `inner`, not on `s`: a child frame draws entirely above its parent
    -- regardless of draw layer, so a glyph on `s` would sit behind the well.
    s.glyph = inner:CreateTexture(nil, "OVERLAY")
    s.glyph:SetPoint("CENTER")
    s.hasGlyph = Theme:Art(s.glyph, "Emblem")
    if not s.hasGlyph then s.glyph:Hide() end

    function s:SetTone(color)
        self.ring:SetColorTexture(Theme:Color(color, 0.9))
        -- Slightly transparent so the bloom behind bleeds through the disc.
        -- Fully opaque, it eclipses its own glow.
        self.well:SetColorTexture(Theme:Color("panel", 0.82))
        self.fill:SetColorTexture(Theme:Color(color, 0.14))
        self.glyph:SetVertexColor(Theme:Color(color == "crimson" and "gold" or color))
    end

    -- Put the accused's face in the seal. Returns what Theme:ResolvePortrait
    -- managed, so the caller can retry a player who is out of range.
    function s:SetAccused(unit, class)
        local mode = Theme:ResolvePortrait(self.face, unit, class)
        self.faceMode = mode
        if mode == "none" then
            self.face:Hide()
            self.glyph:SetShown(self.hasGlyph)
        else
            self.face:Show()
            self.glyph:Hide()
        end
        return mode
    end

    -- No verdict means nobody to show, so the mark comes back.
    function s:SetEmblem()
        self.faceMode = nil
        self.face:Hide()
        self.glyph:SetShown(self.hasGlyph)
    end

    function s:SetDiameter(d)
        self:SetSize(d, d)
        self.glyph:SetSize(d * 0.46, d * 0.46)
    end

    s:SetTone("crimson")
    s:SetDiameter(SEAL_GUILTY)
    return s
end

function Verdict:Build()
    if self.frame then return self.frame end

    -- Veiled for the same reason as the ballot: this window shows up on its
    -- own the moment the ballot closes, and the run has not stopped for it.
    local f = Theme:Panel(UIParent, {
        name = "TribunalVerdictFrame", width = 392, height = 424, chrome = "veil",
    })
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:Hide()

    self.header = Theme:Header(f, "TRIBUNAL", "Verdict")
    self.closeButton = Theme:CloseButton(f, function() Verdict:Close() end)
    Theme:MakeMovable(f, self.header, function() Verdict:SavePosition() end)
    Theme:MakeCloseable(f, "TribunalVerdictFrame")

    -- Stage ----------------------------------------------------------------
    local stage = CreateFrame("Frame", nil, f)
    stage:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, 0)
    stage:SetPoint("TOPRIGHT", self.header, "BOTTOMRIGHT", 0, 0)
    stage:SetHeight(STAGE_GUILTY)
    self.stage = stage

    self.seal = BuildSeal(stage)
    self.seal:SetPoint("TOP", stage, "TOP", 0, -22)

    -- Both glows centre on the seal, so the light has a source.
    self.rays = stage:CreateTexture(nil, "BACKGROUND", nil, 3)
    self.rays:SetPoint("CENTER", self.seal, "CENTER", 0, 0)
    self.rays:SetSize(104, 104)
    self.rays:SetBlendMode("ADD")
    self.rays:SetAlpha(0)
    if not Theme:Art(self.rays, "Rays") then self.rays:Hide() end
    self.rays:SetVertexColor(Theme:Color("gold"))

    self.bloom = Theme:Bloom(stage, 210, "gold", "BACKGROUND")
    self.bloom:SetPoint("CENTER", self.seal, "CENTER", 0, 0)

    self.kicker = Theme:Label(stage, "The court finds", { size = 10, spacing = 2.4 })
    self.kicker:SetPoint("TOP", self.seal, "BOTTOM", 0, -14)

    -- The accused. Its own frame so the entrance can scale it.
    self.nameFrame = CreateFrame("Frame", nil, stage)
    self.nameFrame:SetSize(320, 34)
    self.nameFrame:SetPoint("TOP", self.kicker, "BOTTOM", 0, -8)

    self.nameText = Theme:Text(self.nameFrame, 28, { justify = "CENTER" })
    self.nameText:SetPoint("CENTER")

    -- Class identity survives as a chip, the same mark used in every list,
    -- rather than as a name colour fighting the glow behind it.
    self.classChip = self.nameFrame:CreateTexture(nil, "OVERLAY")
    self.classChip:SetSize(6, 6)
    self.classChip:SetPoint("RIGHT", self.nameText, "LEFT", -12, 1)

    self.detail = Theme:Label(stage, "", { size = 10, spacing = 1.8 })
    self.detail:SetPoint("TOP", self.nameFrame, "BOTTOM", 0, -6)

    -- A plate under the written half of the stage only. The seal and its glow
    -- keep the air around them -- that is the ceremony -- but the kicker and
    -- the detail line are 10px tracked caps with nothing behind them, and they
    -- are the two lines that say what actually happened. It hangs off the
    -- kicker and the detail, so it follows the smaller stage a hung jury gets
    -- without a second set of constants to keep in step.

    self.divider = Theme:Divider(f, 200)
    self.divider:SetPoint("TOP", stage, "BOTTOM", 0, 0)

    -- Tally ----------------------------------------------------------------
    self.list = CreateFrame("Frame", nil, f)
    self.list:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", PAD, -16)
    self.list:SetPoint("TOPRIGHT", stage, "BOTTOMRIGHT", -PAD, -16)
    self.list:SetHeight(1)

    -- The tally is five lines of 12px muted type with only a 3px bar under
    -- each. Nothing in it can carry itself over bright ground, so the whole
    -- block sits on one plate rather than five.

    -- Footer ---------------------------------------------------------------

    local footLine = f:CreateTexture(nil, "ARTWORK")
    footLine:SetHeight(1)
    footLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 48)
    footLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 48)
    footLine:SetColorTexture(Theme:Color("hairline"))
    self.footLine = footLine

    -- Bounded against the docket button, which is 104 wide. Keystone labels
    -- like "Operation: Mechagon - Workshop +24" comfortably overrun this.
    self.footNote = Theme:Label(f, "", {
        size = 10, spacing = 1.6, color = "textDim",
        maxWidth = 392 - PAD * 2 - 104 - 16,
    })
    self.footNote:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 16)

    self.boardButton = Theme:Button(f, "The docket", {
        width = 104, height = 24,
        onClick = function() Verdict:Close(); T.Board:Show() end,
    })
    self.boardButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 16)

    self.frame = f
    self:RestorePosition()
    return f
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function Verdict:SavePosition()
    local p, _, rp, x, y = self.frame:GetPoint(1)
    TribunalDB.ui.verdict = { point = p, relPoint = rp, x = x, y = y }
end

function Verdict:RestorePosition()
    local pos = TribunalDB.ui and TribunalDB.ui.verdict
    if not pos or not pos.point then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

--------------------------------------------------------------------------------
-- Copy
--------------------------------------------------------------------------------

local function Ordinal(n)
    local mod100, mod10 = n % 100, n % 10
    if mod100 < 11 or mod100 > 13 then
        if mod10 == 1 then return "st" end
        if mod10 == 2 then return "nd" end
        if mod10 == 3 then return "rd" end
    end
    return "th"
end

-- Returns kicker, name, detail.
local function Wording(result)
    if result.hung then
        return "The court is adjourned", "No verdict", "Not one ballot was cast"
    end
    if result.tied or not result.winner then
        return "The jury is hung", "No verdict",
               ("Deadlocked at %d votes each"):format(result.count or 0)
    end

    local rec = TribunalDB.players[result.winner]
    local nth = rec and rec.guilty or 1
    return "The court finds",
           T:ShortName(result.winner),
           ("Guilty  %s  %d of %d  %s  %d%s conviction")
               :format("\194\183", result.count, result.total, "\194\183",
                       nth, Ordinal(nth))
end

--------------------------------------------------------------------------------
-- Reveal
--------------------------------------------------------------------------------

function Verdict:Show(result, session)
    local f = self:Build()
    Anim:CancelAll(self.tweens)

    local guilty = result.winner and not result.tied and not result.hung
    local tone = guilty and "crimson" or "textDim"

    f:SetScale(TribunalDB.settings.scale or 1)
    self.header:SetSubtitle(("Verdict  %s  %s"):format("\194\183", result.label or ""))

    local kicker, name, detail = Wording(result)

    -- A no-verdict outcome gets a smaller ceremony, not the same one drained
    -- of colour.
    local stageH  = guilty and STAGE_GUILTY or STAGE_QUIET
    local sealTo  = guilty and SEAL_GUILTY or SEAL_QUIET
    local restAlpha = guilty and 0.30 or 0.10
    local flarePeak = guilty and 0.40 or 0

    self.stage:SetHeight(stageH)
    self.seal:SetTone(tone)
    self.seal:SetDiameter(sealTo - 6)

    self.kicker:SetText(kicker:upper())
    self.kicker:SetTextColor(Theme:Color("textMuted"))
    self.kicker:SetAlphaAll(0)

    -- Crimson is the design's colour for the accused; this is the loudest
    -- word on the screen, so it gets it.
    self.nameText:SetText(name)
    self.nameText:SetTextColor(Theme:Color(guilty and "crimson" or "textMuted"))

    local cls
    if guilty then
        for _, c in ipairs(session and session.candidates or {}) do
            if c.full == result.winner then cls = c.class end
        end
    end
    self.classChip:SetShown(guilty and cls ~= nil)
    if cls then self.classChip:SetColorTexture(Theme:ClassColor(cls)) end

    -- The seal carries the convicted player's face. On any other outcome
    -- there is nobody to show, so the mark comes back.
    if guilty then
        self.seal:SetAccused(T:UnitFor(result.winner), cls)
        self:StartFaceWatch(result.winner, cls)
    else
        self.seal:SetEmblem()
        self:StopFaceWatch()
    end

    self.nameFrame:SetAlpha(0)
    self.nameFrame:SetScale(0.93)

    self.detail:SetText(detail:upper())
    self.detail:SetTextColor(Theme:Color(guilty and "textMuted" or "textDim"))
    self.detail:SetAlphaAll(0)

    self.seal:SetAlpha(0)
    self.bloom:SetAlpha(0)
    self.rays:SetAlpha(0)
    self.rays:SetShown(guilty)
    self.divider:SetAlpha(0)
    self.footNote:SetAlphaAll(0)
    self.boardButton:SetAlpha(0)
    self.footLine:SetAlpha(0)

    -- Tally rows -----------------------------------------------------------
    local list = result.list or {}
    local shown = math.min(#list, 5)
    local maxCount = math.max(1, list[1] and list[1].count or 1)

    for i = 1, shown do
        local entry = list[i]
        local b = self.bars[i]
        if not b then b = BuildBar(self.list); self.bars[i] = b end

        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -(i - 1) * (BAR_H + BAR_GAP))
        b:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", 0, -(i - 1) * (BAR_H + BAR_GAP))

        local lead = guilty and entry.full == result.winner
        b.name:SetText(entry.short)
        b.name:SetTextColor(Theme:Color(lead and "text" or "textMuted"))
        b.count:SetText(tostring(entry.count))
        b.count:SetTextColor(Theme:Color(lead and "text" or "textMuted"))
        -- The tally is supporting evidence, not the headline: no gold here.
        b.bar:SetColor(lead and "crimson" or "hairline")
        b.bar:SetValue(0)
        b:SetAlpha(0)
        b:Show()

        b.target = entry.count / maxCount
    end
    for i = shown + 1, #self.bars do self.bars[i]:Hide() end
    -- A hung jury has no tally, and an empty plate is just a bar of shadow.

    local listH = shown > 0 and (shown * BAR_H + (shown - 1) * BAR_GAP) or 0
    self.list:SetHeight(math.max(1, listH))
    f:SetHeight(self.header:GetHeight() + stageH
        + (shown > 0 and (16 + listH) or 0) + 16 + 48)

    self.footNote:SetText((session and session.label or ""):upper())

    -- Choreography ---------------------------------------------------------
    local tw = self.tweens
    self.header:Strike()
    Anim:SlideIn(f, { y = -16, duration = 0.44, ease = "outQuint" })

    C_Timer.After(CUE.sting, function() T:Sound("Verdict") end)

    tw[#tw + 1] = Anim:Tween({
        delay = CUE.bloom, duration = RISE + 2.2, ease = "linear",
        from = 0, to = RISE + 2.2,
        onUpdate = function(elapsed)
            local a = BloomAlpha(elapsed, restAlpha, flarePeak)
            Verdict.bloom:SetAlpha(a)
            Verdict.rays:SetAlpha(a * 0.45)
            local grow = math.min(elapsed / RISE, 1)
            Verdict.rays:SetSize(104 + grow * 10, 104 + grow * 10)
        end,
        onComplete = function()
            -- Rest, do not extinguish.
            Verdict.bloom:SetAlpha(restAlpha)
            Verdict.rays:SetAlpha(restAlpha * 0.45)
        end,
    })

    tw[#tw + 1] = Anim:Tween({
        delay = CUE.seal, duration = 0.5, ease = "outQuint",
        onUpdate = function(v)
            Verdict.seal:SetAlpha(v)
            Verdict.seal:SetDiameter(sealTo - 6 + v * 6)
        end,
    })

    tw[#tw + 1] = Anim:Tween({
        delay = CUE.kicker, duration = 0.32, ease = "outCubic",
        onUpdate = function(v) Verdict.kicker:SetAlphaAll(v) end,
    })

    tw[#tw + 1] = Anim:Tween({
        delay = CUE.name, duration = 0.52, ease = "outQuint",
        onUpdate = function(v)
            Verdict.nameFrame:SetAlpha(v)
            Verdict.nameFrame:SetScale(0.93 + v * 0.07)
        end,
    })
    if guilty then
        C_Timer.After(CUE.name + 0.05, function() T:Sound("Guilty") end)
    end

    tw[#tw + 1] = Anim:Tween({
        delay = CUE.detail, duration = 0.32, ease = "outCubic",
        onUpdate = function(v)
            Verdict.detail:SetAlphaAll(v)
            Verdict.divider:SetAlpha(v * 0.9)
        end,
    })

    for i = 1, shown do
        local b = self.bars[i]
        local delay = CUE.bars + (i - 1) * CUE.barGap
        tw[#tw + 1] = Anim:Tween({
            delay = delay, duration = 0.3, ease = "outCubic",
            onUpdate = function(v) b:SetAlpha(v) end,
        })
        tw[#tw + 1] = b.bar:AnimateTo(b.target, 0.85, delay + 0.06)
    end

    tw[#tw + 1] = Anim:Tween({
        delay = CUE.footer, duration = 0.36, ease = "outCubic",
        onUpdate = function(v)
            Verdict.footNote:SetAlphaAll(v * 0.9)
            Verdict.boardButton:SetAlpha(v)
            Verdict.footLine:SetAlpha(v)
        end,
    })

    -- The window lingers, then leaves on its own if nobody touches it.
    if self.autoClose then self.autoClose:Cancel() end
    self.autoClose = C_Timer.NewTimer(CUE.footer + 16, function()
        if Verdict.frame and Verdict.frame:IsMouseOver() then return end
        Verdict:Close()
    end)
end

--------------------------------------------------------------------------------
-- Face watch
--------------------------------------------------------------------------------

-- The convicted player is frequently a corpse somewhere else on the map when
-- the verdict lands, and a portrait only exists for a unit the client can see.
-- Retry for as long as the window is up so the face fills in the moment they
-- come back into view.
function Verdict:StartFaceWatch(full, class)
    self:StopFaceWatch()
    if self.seal.faceMode == "portrait" then return end

    self.faceTicker = C_Timer.NewTicker(2, function()
        if not Verdict.frame or not Verdict.frame:IsShown() then
            Verdict:StopFaceWatch()
            return
        end
        if Verdict.seal:SetAccused(T:UnitFor(full), class) == "portrait" then
            Verdict:StopFaceWatch()
        end
    end, 9)
end

function Verdict:StopFaceWatch()
    if self.faceTicker then
        self.faceTicker:Cancel()
        self.faceTicker = nil
    end
end

function Verdict:Close()
    self:StopFaceWatch()
    if self.autoClose then self.autoClose:Cancel(); self.autoClose = nil end
    if not self.frame or not self.frame:IsShown() then return end
    Anim:CancelAll(self.tweens)
    Anim:Fade(self.frame, 0, 0.26, "outCubic")
end
