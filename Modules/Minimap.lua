-- Tribunal :: Minimap
-- A minimap button that opens a drawer rather than a dropdown menu: the items
-- slide out from under the button and stagger into place.

local ADDON, T = ...
local MM = T:NewModule("Minimap")
local Theme, Anim = T.Theme, T.Anim

local BUTTON_SIZE = 26
local ITEM_H, ITEM_GAP = 32, 4
-- Wide enough for the longest label: "CONVENE THE COURT" at 10px/1.6 tracking
-- measures ~136px, and the glyph column takes 37 before it starts.
local ITEM_W = 184

MM.items = {}
MM.open = false

--------------------------------------------------------------------------------
-- Glyphs
--------------------------------------------------------------------------------

-- Small geometric marks instead of icon art: they stay crisp at any size and
-- match the hairline language of the rest of the addon.
local function Glyph(parent, kind)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(14, 14)
    g.parts = {}

    local function part(w, h, point, x, y, rotate)
        local tex = g:CreateTexture(nil, "ARTWORK")
        tex:SetSize(w, h)
        tex:SetPoint(point or "CENTER", g, point or "CENTER", x or 0, y or 0)
        tex:SetColorTexture(Theme:Color("textMuted"))
        if rotate then tex:SetRotation(rotate) end
        g.parts[#g.parts + 1] = tex
        return tex
    end

    if kind == "convene" then
        part(6, 6, "CENTER", 0, 2, math.pi / 4)
        part(12, 1, "CENTER", 0, -5)
    elseif kind == "docket" then
        part(12, 1, "CENTER", 0, 4)
        part(12, 1, "CENTER", 0, 0)
        part(8, 1, "CENTER", -2, -4)
    else -- settings: two tracks with a marker on each
        part(12, 1, "CENTER", 0, 3)
        part(12, 1, "CENTER", 0, -3)
        part(3, 3, "CENTER", -3, 3)
        part(3, 3, "CENTER", 3, -3)
    end

    function g:SetColor(name, alpha)
        for _, tex in ipairs(self.parts) do
            tex:SetColorTexture(Theme:Color(name, alpha))
        end
    end

    return g
end

--------------------------------------------------------------------------------
-- The button
--------------------------------------------------------------------------------

local function CircleMask(frame)
    local mask = frame:CreateMaskTexture()
    mask:SetAllPoints(frame)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
                    "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    return mask
end

function MM:BuildButton()
    if self.button then return self.button end

    local b = CreateFrame("Button", "TribunalMinimapButton", Minimap)
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    local mask = CircleMask(b)

    -- Gold disc under a slightly smaller dark disc reads as a 1px ring
    -- without needing a ring texture.
    b.ring = b:CreateTexture(nil, "BACKGROUND")
    b.ring:SetAllPoints()
    b.ring:SetColorTexture(Theme:Color("gold", 0.85))
    b.ring:AddMaskTexture(mask)

    local innerHolder = CreateFrame("Frame", nil, b)
    innerHolder:SetPoint("CENTER")
    innerHolder:SetSize(BUTTON_SIZE - 2, BUTTON_SIZE - 2)
    local innerMask = CircleMask(innerHolder)

    b.disc = innerHolder:CreateTexture(nil, "BORDER")
    b.disc:SetAllPoints()
    b.disc:SetColorTexture(Theme:Color("panel", 1))
    b.disc:AddMaskTexture(innerMask)

    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    b.glow:SetSize(BUTTON_SIZE * 2.2, BUTTON_SIZE * 2.2)
    b.glow:SetPoint("CENTER")
    b.glow:SetBlendMode("ADD")
    b.glow:SetAlpha(0)
    if not Theme:Art(b.glow, "Bloom") then
        b.glow:SetTexture("Interface\\Cooldown\\star4")
    end
    b.glow:SetVertexColor(Theme:Color("gold"))

    -- On innerHolder, not on b. A child frame draws entirely above its
    -- parent's textures regardless of draw layer, so an icon on b would sit
    -- behind the disc and the button would render as an empty ring.
    b.icon = innerHolder:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(17, 17)
    b.icon:SetPoint("CENTER")
    if Theme:Art(b.icon, "MinimapIcon") or Theme:Art(b.icon, "Emblem") then
        b.icon:SetVertexColor(Theme:Color("gold"))
    else
        -- Last resort: the same diamond used by the convene glyph.
        b.icon:SetColorTexture(Theme:Color("gold"))
        b.icon:SetSize(8, 8)
        b.icon:SetRotation(math.pi / 4)
    end

    -- An unread-style pip when a trial is live and you have not voted.
    -- Inset so it sits on the button rather than off its edge, over a dark
    -- backing so it still reads against a bright minimap tile.
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints()
    top:SetFrameLevel(innerHolder:GetFrameLevel() + 1)

    b.pipHalo = top:CreateTexture(nil, "OVERLAY", nil, 1)
    b.pipHalo:SetSize(9, 9)
    b.pipHalo:SetPoint("TOPRIGHT", -1, -1)
    b.pipHalo:SetColorTexture(Theme:Color("void", 0.9))
    b.pipHalo:SetRotation(math.pi / 4)
    b.pipHalo:Hide()

    b.pip = top:CreateTexture(nil, "OVERLAY", nil, 2)
    b.pip:SetSize(6, 6)
    b.pip:SetPoint("CENTER", b.pipHalo, "CENTER", 0, 0)
    b.pip:SetColorTexture(Theme:Color("crimson"))
    b.pip:SetRotation(math.pi / 4)
    b.pip:Hide()

    b:SetScript("OnEnter", function(self)
        Anim:Tween({ duration = 0.18, from = self.glow:GetAlpha(), to = 0.4,
            onUpdate = function(v) self.glow:SetAlpha(v) end })
        self.ring:SetColorTexture(Theme:Color("goldLight", 1))
        MM:ShowTooltip()
    end)

    b:SetScript("OnLeave", function(self)
        if not MM.open then
            Anim:Tween({ duration = 0.24, from = self.glow:GetAlpha(), to = 0,
                onUpdate = function(v) self.glow:SetAlpha(v) end })
        end
        self.ring:SetColorTexture(Theme:Color("gold", 0.85))
        GameTooltip:Hide()
    end)

    b:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            MM:CloseDrawer()
            T.Board:Toggle()
        else
            MM:ToggleDrawer()
        end
    end)

    b:SetScript("OnDragStart", function(self)
        MM:CloseDrawer()
        GameTooltip:Hide()
        self.dragging = true
        self:SetScript("OnUpdate", function() MM:DragUpdate() end)
    end)

    b:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)

    self.button = b
    self:UpdatePosition()
    return b
end

--------------------------------------------------------------------------------
-- Ring placement
--------------------------------------------------------------------------------

function MM:UpdatePosition()
    if not self.button then return end
    local angle = math.rad(TribunalDB.minimap.angle or 214)
    local radius = (Minimap:GetWidth() / 2) + 10

    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end

function MM:DragUpdate()
    local mx, my = Minimap:GetCenter()
    if not mx then return end

    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale

    TribunalDB.minimap.angle = math.deg(math.atan2(py - my, px - mx))
    self:UpdatePosition()
end

--------------------------------------------------------------------------------
-- The drawer
--------------------------------------------------------------------------------

local DRAWER = {
    { key = "convene",  label = "Convene the court", glyph = "convene",
      action = function() T.Session:Request() end },
    { key = "docket",   label = "The docket", glyph = "docket",
      action = function() T.Board:Show() end },
    { key = "settings", label = "Settings", glyph = "settings",
      action = function() T.Config:Open() end },
}

function MM:BuildDrawer()
    if self.drawer then return self.drawer end

    local d = CreateFrame("Frame", nil, UIParent)
    d:SetSize(ITEM_W, #DRAWER * ITEM_H + (#DRAWER - 1) * ITEM_GAP)
    d:SetFrameStrata("MEDIUM")
    d:SetFrameLevel(self.button:GetFrameLevel() + 2)
    d:Hide()

    for i, def in ipairs(DRAWER) do
        local item = CreateFrame("Button", nil, d)
        item:SetSize(ITEM_W, ITEM_H)

        item.bg = Theme:Fill(item, "panel", 0.98)
        Theme:Border(item, "hairline", 1)

        item.accent = item:CreateTexture(nil, "ARTWORK")
        item.accent:SetWidth(2)
        item.accent:SetPoint("TOPLEFT")
        item.accent:SetPoint("BOTTOMLEFT")
        item.accent:SetColorTexture(Theme:Color("hairline"))

        item.glyph = Glyph(item, def.glyph)
        item.glyph:SetPoint("LEFT", 13, 0)

        item.label = Theme:Label(item, def.label, { size = 10, spacing = 1.6 })
        item.label:SetPoint("LEFT", item.glyph, "RIGHT", 10, 0)

        item.def = def

        item:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(Theme:Color("raisedHi"))
            self.accent:SetColorTexture(Theme:Color("gold"))
            self.label:SetTextColor(Theme:Color("text"))
            self.glyph:SetColor("gold")
        end)

        item:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(Theme:Color("panel", 0.98))
            self.accent:SetColorTexture(Theme:Color("hairline"))
            self.label:SetTextColor(Theme:Color("textMuted"))
            self.glyph:SetColor("textMuted")
        end)

        item:SetScript("OnClick", function(self)
            MM:CloseDrawer()
            self.def.action()
        end)

        self.items[i] = item
    end

    self.drawer = d
    return d
end

-- Anchors the drawer to whichever side of the button has room, and returns the
-- direction the items should slide from.
function MM:PlaceDrawer()
    local d, b = self.drawer, self.button
    local bx, by = b:GetCenter()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if not bx then return 1 end

    local toLeft = bx > sw * 0.6
    local toBottom = by > sh * 0.5

    d:ClearAllPoints()
    if toLeft then
        d:SetPoint(toBottom and "TOPRIGHT" or "BOTTOMRIGHT", b,
            toBottom and "BOTTOMLEFT" or "TOPLEFT", 2, toBottom and -2 or 2)
    else
        d:SetPoint(toBottom and "TOPLEFT" or "BOTTOMLEFT", b,
            toBottom and "BOTTOMRIGHT" or "TOPRIGHT", -2, toBottom and -2 or 2)
    end

    for i, item in ipairs(self.items) do
        item:ClearAllPoints()
        local y = -(i - 1) * (ITEM_H + ITEM_GAP)
        if not toBottom then y = (i - 1) * (ITEM_H + ITEM_GAP) end
        item:SetPoint(toBottom and "TOPLEFT" or "BOTTOMLEFT", d,
            toBottom and "TOPLEFT" or "BOTTOMLEFT", 0, y)
    end

    return toLeft and -1 or 1
end

function MM:OpenDrawer()
    if self.open then return end
    self:BuildDrawer()
    self.open = true

    local dir = self:PlaceDrawer()
    self.drawer:Show()
    T:Sound("Drawer")

    Anim:Tween({ duration = 0.18, from = self.button.glow:GetAlpha(), to = 0.45,
        onUpdate = function(v) MM.button.glow:SetAlpha(v) end })

    -- Each item slides out from under the button, offset by its index.
    for i, item in ipairs(self.items) do
        item:SetAlpha(0)
        local baseX = select(4, item:GetPoint(1)) or 0
        local baseY = select(5, item:GetPoint(1)) or 0
        local point, rel, relPoint = item:GetPoint(1)

        Anim:Tween({
            delay = (i - 1) * 0.045, duration = 0.3, ease = "outQuint",
            onUpdate = function(v)
                item:SetAlpha(v)
                item:ClearAllPoints()
                item:SetPoint(point, rel, relPoint,
                    baseX - dir * 16 * (1 - v), baseY)
            end,
        })
    end

    if not self.closer then
        -- A full-screen invisible catcher so clicking away closes the drawer.
        local c = CreateFrame("Button", nil, UIParent)
        c:SetAllPoints(UIParent)
        c:SetFrameStrata("LOW")
        c:SetScript("OnClick", function() MM:CloseDrawer() end)
        c:Hide()
        self.closer = c
    end
    self.closer:Show()
end

function MM:CloseDrawer()
    if not self.open then return end
    self.open = false
    if self.closer then self.closer:Hide() end

    if not self.button:IsMouseOver() then
        Anim:Tween({ duration = 0.24, from = self.button.glow:GetAlpha(), to = 0,
            onUpdate = function(v) MM.button.glow:SetAlpha(v) end })
    end

    for i, item in ipairs(self.items) do
        Anim:Tween({
            delay = (#self.items - i) * 0.02, duration = 0.15, ease = "outCubic",
            from = item:GetAlpha(), to = 0,
            onUpdate = function(v) item:SetAlpha(v) end,
        })
    end
    C_Timer.After(0.26, function()
        if not MM.open and MM.drawer then MM.drawer:Hide() end
    end)
end

function MM:ToggleDrawer()
    if self.open then self:CloseDrawer() else self:OpenDrawer() end
end

--------------------------------------------------------------------------------
-- Tooltip
--------------------------------------------------------------------------------

function MM:ShowTooltip()
    GameTooltip:SetOwner(self.button, "ANCHOR_LEFT")
    GameTooltip:AddLine("Tribunal")

    local s = T.Session.current
    if s and s.state == "open" then
        GameTooltip:AddLine(Theme.HEX.crimson .. "A trial is in session." .. "|r")
        GameTooltip:AddLine(Theme.HEX.muted ..
            (s.myVote and "Your ballot is sealed." or "You have not voted yet.") .. "|r")
    else
        local board = T:GetLeaderboard()
        local top = board[1]
        if top and top.guilty > 0 then
            GameTooltip:AddDoubleLine("Most convicted",
                Theme:ClassHex(top.class) .. top.short .. "|r")
            GameTooltip:AddDoubleLine("Wipes",
                Theme.HEX.gold .. top.guilty .. "|r")
        else
            GameTooltip:AddLine(Theme.HEX.muted .. "No verdicts on record." .. "|r")
        end
        GameTooltip:AddDoubleLine("Trials held",
            tostring(TribunalDB.stats.trials or 0))
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(Theme.HEX.muted .. "Left-click for the drawer" .. "|r")
    GameTooltip:AddLine(Theme.HEX.muted .. "Right-click for the docket" .. "|r")
    GameTooltip:AddLine(Theme.HEX.muted .. "Drag to move" .. "|r")
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

function MM:Refresh()
    if not self.button then return end
    self.button:SetShown(not TribunalDB.minimap.hide)
    self:UpdatePosition()
    self:UpdatePip()
end

function MM:UpdatePip()
    if not self.button then return end
    local s = T.Session.current
    local live = s and s.state == "open" and not s.myVote
    self.button.pip:SetShown(live and true or false)
    self.button.pipHalo:SetShown(live and true or false)

    if live and not self.pipTween then
        self.pipTween = Anim:Tween({
            duration = 1.6, from = 0, to = 1, ease = "linear",
            onUpdate = function(t)
                MM.button.pip:SetAlpha(0.45 + 0.55 * math.abs(math.sin(t * math.pi * 2)))
            end,
            onComplete = function()
                MM.pipTween = nil
                MM:UpdatePip()
            end,
        })
    end
end

function MM:OnLogin()
    self:BuildButton()
    self:Refresh()

    -- Keep the pip honest as the trial progresses.
    C_Timer.NewTicker(1, function() MM:UpdatePip() end)
end
