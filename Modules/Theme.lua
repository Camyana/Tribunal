-- Tribunal :: Theme
-- The widget vocabulary. Every frame in the addon is built from these, so the
-- look is defined in exactly one place. See DESIGN.md for the rationale.

local ADDON, T = ...
local Theme = T:NewModule("Theme")
local Anim = T.Anim

--------------------------------------------------------------------------------
-- Palette
--------------------------------------------------------------------------------

local function hex(s)
    return tonumber(s:sub(1, 2), 16) / 255,
           tonumber(s:sub(3, 4), 16) / 255,
           tonumber(s:sub(5, 6), 16) / 255
end

local C = {
    void      = { hex("0B0D12") },
    panel     = { hex("12151D") },
    raised    = { hex("1A1E28") },
    raisedHi  = { hex("232833") },
    hairline  = { hex("2A303D") },
    gold      = { hex("E8B23A") },
    goldLight = { hex("FFD98A") },
    crimson   = { hex("C4383A") },
    jade      = { hex("3FBF8F") },
    text      = { hex("E8E4DA") },
    textMuted = { hex("8A8E9C") },
    textDim   = { hex("4A5162") },
}
Theme.C = C

-- Escape codes for use inside strings.
Theme.HEX = {
    gold = "|cffE8B23A", goldLight = "|cffFFD98A", crimson = "|cffC4383A",
    jade = "|cff3FBF8F", text = "|cffE8E4DA", muted = "|cff8A8E9C", r = "|r",
}

function Theme:Color(name, alpha)
    local c = C[name] or C.text
    return c[1], c[2], c[3], alpha or 1
end

function Theme:ClassColor(class)
    local t = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    if t then return t.r, t.g, t.b end
    return C.text[1], C.text[2], C.text[3]
end

function Theme:ClassHex(class)
    local t = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    if not t then return Theme.HEX.text end
    -- Blizzard's tables are ColorMixin; a class-colour addon's may be plain rgb.
    if t.GenerateHexColor then return "|cff" .. t:GenerateHexColor():sub(3) end
    return ("|cff%02x%02x%02x"):format(
        math.floor((t.r or 1) * 255), math.floor((t.g or 1) * 255), math.floor((t.b or 1) * 255))
end

--------------------------------------------------------------------------------
-- Fonts
--------------------------------------------------------------------------------

-- U+2026, built from bytes so no escape sequence has to survive an
-- editing round trip.
local ELLIPSIS = string.char(226, 128, 166)

Theme.FONT = {
    body   = "Fonts\\FRIZQT__.TTF",   -- everything
    narrow = "Fonts\\ARIALN.TTF",     -- numerals and dense labels
}

--------------------------------------------------------------------------------
-- Surface
--------------------------------------------------------------------------------

-- There are two surfaces, not one.
--
-- `solid` is the original slab, and it stays the treatment for the two windows
-- you deliberately opened: the docket and the settings. You asked for those,
-- so a surface you can read against is the right answer.
--
-- `veil` is for the two that arrive on their own in the middle of a pull -- the
-- ballot and the verdict. Those have to sit *in* the game rather than on top of
-- it, so the container all but disappears and only the blocks of type keep a
-- backing. It is still depth from value, exactly as DESIGN.md asks; there is
-- simply less of it, and what remains is spent on what has to be read.
--
-- The veil is drawn at 75%, so TribunalDB.settings.opacity reads as a plain
-- percentage of the intended look: 100% is as dense as the veil ever gets and
-- 40% is barely more than the type itself.
local VEIL_REF = 0.75

Theme.VEIL = {
    fill  = 0.26,   -- flat panel colour across the body
    grain = 0.40,   -- the tile is opaque, so its alpha *is* the surface
    fade  = 12,     -- px over which the top and bottom ends run to nothing
    edge  = 0.85,   -- corner ticks
    row   = 0.90,   -- a row is content, so it keeps its backing
    scrim = 0.32,   -- local backing under a block of type
    shade = 0.85,   -- see Theme:Text
}

function Theme:Opacity()
    local s = TribunalDB and TribunalDB.settings
    local k = s and s.opacity
    if type(k) ~= "number" then k = VEIL_REF end
    return math.max(0.4, math.min(1, k)) / VEIL_REF
end

function Theme:VeilAlpha(key)
    return math.min(1, (self.VEIL[key] or 1) * self:Opacity())
end

-- Everything whose alpha follows the setting registers here, so dragging the
-- slider repaints the open ballot instead of waiting for the next trial.
Theme.veiled = {}

function Theme:TrackVeil(obj)
    self.veiled[#self.veiled + 1] = obj
    return obj
end

function Theme:RefreshVeil()
    for _, obj in ipairs(self.veiled) do
        if type(obj.ApplyVeil) == "function" then obj:ApplyVeil() end
    end
end

-- Chrome is declared once, on the panel, and inherited by everything built
-- inside it. The alternative is every label in two modules remembering to ask
-- for the legibility treatment, which is exactly the kind of thing that gets
-- forgotten on the one label that needed it.
function Theme:ChromeOf(frame)
    for _ = 1, 12 do
        if not frame then break end
        if frame.tribunalChrome then return frame.tribunalChrome end
        frame = frame.GetParent and frame:GetParent() or nil
    end
    return "solid"
end

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

-- A flat fill. Used instead of backdrops so we control every pixel.
function Theme:Fill(parent, color, alpha, layer)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(self:Color(color, alpha))
    return tex
end

-- Four 1px edges. Crisper than a backdrop border and it never tiles oddly.
function Theme:Border(parent, color, alpha, inset)
    color, alpha, inset = color or "hairline", alpha or 1, inset or 0
    local r, g, b = self:Color(color)
    local edges = {}

    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local tex = parent:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(r, g, b, alpha)

        if side == "TOP" or side == "BOTTOM" then
            tex:SetHeight(1)
            tex:SetPoint("LEFT", parent, "LEFT", inset, 0)
            tex:SetPoint("RIGHT", parent, "RIGHT", -inset, 0)
            tex:SetPoint(side, parent, side, 0, side == "TOP" and -inset or inset)
        else
            tex:SetWidth(1)
            tex:SetPoint("TOP", parent, "TOP", 0, -inset)
            tex:SetPoint("BOTTOM", parent, "BOTTOM", 0, inset)
            tex:SetPoint(side, parent, side, side == "LEFT" and inset or -inset, 0)
        end
        edges[side] = tex
    end

    parent.borderEdges = edges
    return edges
end

-- The single place any of our art is loaded, so every caller can offer a
-- drawn fallback in one consistent way.
--
-- Note the client gives us no way to detect a texture that failed to load:
-- GetTexture echoes back whatever path was set, whether or not the file
-- exists. So this returns false only when art is switched off or the name is
-- blank. The fallbacks below it are what you get with Theme.useArt = false,
-- and they are what the test harness exercises.
Theme.useArt = true

function Theme:Art(tex, name, ...)
    if not tex or not name or not self.useArt then return false end
    tex:SetTexture(T.TEXTURE .. name, ...)
    return tex:GetTexture() ~= nil
end

-- Over a veil the type has no reliable backing, so it gets a 1px hard shadow.
--
-- This is not the drop shadow DESIGN.md bans. That one is a fake light source:
-- offset, soft, sitting under a whole panel to lift it off the screen, and
-- visible on the obsidian these windows normally sit on. This is a
-- single-pixel dark counter-edge with no blur that exists for one reason --
-- 10px tracked caps have to survive a snowfield -- and it is off entirely on
-- the solid windows, where value alone still does the work.
local function ShadeFor(parent, opts)
    if opts.shade ~= nil then return opts.shade and Theme.VEIL.shade or 0 end
    return Theme:ChromeOf(parent) == "veil" and Theme.VEIL.shade or 0
end

local function ApplyShade(fs, shade)
    if shade > 0 then
        fs:SetShadowColor(0, 0, 0, shade)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowColor(0, 0, 0, 0)  -- depth comes from value, never from shadow
    end
end

function Theme:Text(parent, size, opts)
    opts = opts or {}
    local fs = parent:CreateFontString(nil, opts.layer or "OVERLAY")
    fs:SetFont(opts.font or self.FONT.body, size or 12, opts.flags or "")
    fs:SetTextColor(self:Color(opts.color or "text", opts.alpha))
    fs:SetJustifyH(opts.justify or "LEFT")
    ApplyShade(fs, ShadeFor(parent, opts))
    if opts.text then fs:SetText(opts.text) end
    if opts.width then fs:SetWidth(opts.width) end
    return fs
end

-- FontStrings have no letter-spacing, so wordmarks and small caps labels get
-- one FontString per glyph. Returns a frame with :SetText / :SetTextColor.
function Theme:Spaced(parent, text, opts)
    opts = opts or {}
    local size    = opts.size or 12
    local spacing = opts.spacing or 3
    local font    = opts.font or self.FONT.body
    local flags   = opts.flags or ""

    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(size + 4)
    f.glyphs = {}
    -- Resolved once: glyphs are minted lazily as strings get longer, and a
    -- glyph born after the fact still has to carry the same treatment.
    f.shade = ShadeFor(parent, opts)

    function f:SetText(str)
        str = tostring(str or "")
        local limit = self.maxWidth or opts.maxWidth
        local i, x, clipped = 0, 0, false
        local starts = self._starts
        if not starts then starts = {}; self._starts = starts end
        -- Walk UTF-8 code points, not bytes, so accented names do not shatter.
        for ch in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            i = i + 1
            local g = self.glyphs[i]
            if not g then
                g = self:CreateFontString(nil, opts.layer or "OVERLAY")
                g:SetFont(font, size, flags)
                ApplyShade(g, self.shade or 0)
                self.glyphs[i] = g
            end
            -- Colour and alpha live on the frame, not on the glyphs, because
            -- a longer string later on mints new glyphs that would otherwise
            -- be born white.
            local c = self.color
            if c then g:SetTextColor(c[1], c[2], c[3], c[4]) end
            if self.glyphAlpha then g:SetAlpha(self.glyphAlpha) end
            g:SetText(ch)
            starts[i] = x

            -- Measure before committing. Testing after the fact overshoots by
            -- a whole glyph, which is exactly enough to clip the control next
            -- to it.
            local w = g:GetStringWidth()
            if limit and (x + w) > limit then
                -- The ellipsis needs room of its own, so walk back until it
                -- genuinely fits rather than appending past the limit.
                local j = i
                self.glyphs[j]:SetText(ELLIPSIS)
                local ew = self.glyphs[j]:GetStringWidth()
                while j > 1 and (starts[j] + ew) > limit do
                    j = j - 1
                    self.glyphs[j]:SetText(ELLIPSIS)
                    ew = self.glyphs[j]:GetStringWidth()
                end

                local tail = self.glyphs[j]
                tail:ClearAllPoints()
                tail:SetPoint("LEFT", self, "LEFT", starts[j], 0)
                tail:Show()
                x, i, clipped = starts[j] + ew, j, true
                break
            end

            g:ClearAllPoints()
            g:SetPoint("LEFT", self, "LEFT", x, 0)
            g:Show()
            x = x + w + (ch == " " and spacing * 0.4 or spacing)
        end
        for j = i + 1, #self.glyphs do self.glyphs[j]:Hide() end
        self.clipped = clipped
        self.textWidth = math.max(0, x - spacing)
        self:SetWidth(math.max(1, self.textWidth))
        self.value = str
    end

    function f:SetTextColor(r, g, b, a)
        self.color = { r, g, b, a }
        for _, glyph in ipairs(self.glyphs) do glyph:SetTextColor(r, g, b, a) end
    end

    function f:SetAlphaAll(a)
        self.glyphAlpha = a
        for _, glyph in ipairs(self.glyphs) do glyph:SetAlpha(a) end
    end

    f:SetText(text or "")
    f:SetTextColor(self:Color(opts.color or "text", opts.alpha))
    return f
end

-- A small uppercase tracked label. The workhorse of the whole UI.
function Theme:Label(parent, text, opts)
    opts = opts or {}
    opts.size    = opts.size or 10
    opts.spacing = opts.spacing or 2
    opts.color   = opts.color or "textMuted"
    return self:Spaced(parent, (text or ""):upper(), opts)
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

-- Four 1px corner marks instead of a box.
--
-- A closed border is the strongest "this is a window" signal a frame has: it
-- is the lid. Two short arms say where the corner is and let the eye close the
-- rectangle itself, which is all a veiled window needs.
function Theme:CornerTicks(parent, color, len)
    len = len or 14
    local r, g, b = self:Color(color or "hairline")
    local out = {}
    for _, point in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        -- One anchored point plus a size fixes the arm, so each corner needs
        -- no per-corner sign juggling.
        for _, size in ipairs({ { len, 1 }, { 1, len } }) do
            local t = parent:CreateTexture(nil, "BORDER")
            t:SetSize(size[1], size[2])
            t:SetPoint(point, parent, point, 0, 0)
            t:SetColorTexture(r, g, b, 1)
            out[#out + 1] = t
        end
    end
    return out
end

-- A soft-ended plate under a block of type.
--
-- The veil on its own cannot hold 10px tracked caps over a snowfield, so the
-- opacity that is left gets spent exactly where something has to be read. The
-- ends run to nothing, so it never reads as a second box inside the first.
function Theme:Scrim(parent, opts)
    opts = opts or {}
    local s = CreateFrame("Frame", nil, parent)
    -- Level with the parent's own layers rather than above its other children,
    -- so the seal, its bloom and the rows still draw over this.
    s:SetFrameLevel(parent:GetFrameLevel())
    if opts.height then s:SetHeight(opts.height) end

    local r, g, b = self:Color(opts.color or "void")
    local soft = opts.soft or 40

    local core = s:CreateTexture(nil, "BACKGROUND")
    core:SetPoint("TOPLEFT", soft, 0)
    core:SetPoint("BOTTOMRIGHT", -soft, 0)

    local function endCap(side)
        local t = s:CreateTexture(nil, "BACKGROUND")
        t:SetWidth(soft)
        t:SetPoint("TOP" .. side)
        t:SetPoint("BOTTOM" .. side)
        return t
    end
    local left, right = endCap("LEFT"), endCap("RIGHT")

    function s:ApplyVeil()
        local a = math.min(1, Theme:VeilAlpha("scrim") * (opts.strength or 1))
        core:SetColorTexture(r, g, b, a)
        if left.SetGradient then
            -- The gradient is a vertex colour and multiplies the texture, so
            -- the texture itself has to be white for the stops to land where
            -- they say they do.
            left:SetColorTexture(1, 1, 1, 1)
            right:SetColorTexture(1, 1, 1, 1)
            local clear, full = CreateColor(r, g, b, 0), CreateColor(r, g, b, a)
            left:SetGradient("HORIZONTAL", clear, full)
            right:SetGradient("HORIZONTAL", full, clear)
        else
            left:SetColorTexture(r, g, b, a * 0.5)
            right:SetColorTexture(r, g, b, a * 0.5)
        end
    end

    s:ApplyVeil()
    Theme:TrackVeil(s)
    return s
end

-- The base container: void backdrop, panel fill, optional grain, hairline edge.
-- `opts.chrome` picks the surface: "solid" (the default) or "veil".
function Theme:Panel(parent, opts)
    opts = opts or {}
    local veil = opts.chrome == "veil"
    local f = CreateFrame("Frame", opts.name, parent or UIParent)
    f:SetSize(opts.width or 380, opts.height or 240)
    f.tribunalChrome = veil and "veil" or "solid"

    local fade = self.VEIL.fade
    local pr, pg, pb = self:Color(opts.color or "panel")

    if veil then
        -- The body stops short of both ends, and the ends are gradients
        -- running to nothing, so the window has no top or bottom edge left to
        -- read as a lid.
        local body = f:CreateTexture(nil, "BACKGROUND")
        body:SetPoint("TOPLEFT", 0, -fade)
        body:SetPoint("BOTTOMRIGHT", 0, fade)
        f.bg = body

        local function endCap(side)
            local t = f:CreateTexture(nil, "BACKGROUND")
            t:SetHeight(fade)
            t:SetPoint(side .. "LEFT")
            t:SetPoint(side .. "RIGHT")
            return t
        end
        f.fadeTop, f.fadeBottom = endCap("TOP"), endCap("BOTTOM")
    else
        f.bg = self:Fill(f, opts.color or "panel", opts.alpha or 1, "BACKGROUND")
    end

    -- Grain sits just above the fill. It must BLEND, not ADD: the tile is a
    -- dark surface in its own right, so adding it lifts the panel most of the
    -- way to the row colour and the two stop reading as separate planes.
    --
    -- Under the veil that same opacity is the point: the tile is the only
    -- thing left with any body to it, so its alpha *is* the surface, and it
    -- is clipped to the same inset the fill uses so the ends still dissolve.
    if opts.grain ~= false then
        local grain = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        if veil then
            grain:SetPoint("TOPLEFT", 0, -fade)
            grain:SetPoint("BOTTOMRIGHT", 0, fade)
        else
            grain:SetAllPoints()
        end
        if self:Art(grain, "PanelTile", "REPEAT", "REPEAT") then
            grain:SetHorizTile(true)
            grain:SetVertTile(true)
            grain:SetBlendMode("BLEND")
            grain:SetAlpha(veil and self:VeilAlpha("grain") or 0.85)
            f.grain = grain
        end
    end

    -- No sheen and no drop shadow. A 1px highlight just inside the border is
    -- a bevel by another name, and a hard-edged dark rectangle behind the
    -- panel is a drop shadow. Separation here comes from value alone.
    if veil then
        f.ticks = self:CornerTicks(f, opts.border or "hairline")

        function f:ApplyVeil()
            local a = Theme:VeilAlpha("fill")
            self.bg:SetColorTexture(pr, pg, pb, a)
            local clear, full = CreateColor(pr, pg, pb, 0), CreateColor(pr, pg, pb, a)
            for side, t in pairs({ TOP = self.fadeTop, BOTTOM = self.fadeBottom }) do
                if t.SetGradient then
                    t:SetColorTexture(1, 1, 1, 1)
                    -- VERTICAL runs min at the bottom and max at the top.
                    if side == "TOP" then t:SetGradient("VERTICAL", full, clear)
                    else t:SetGradient("VERTICAL", clear, full) end
                else
                    t:SetColorTexture(pr, pg, pb, a * 0.5)
                end
            end
            if self.grain then self.grain:SetAlpha(Theme:VeilAlpha("grain")) end
            for _, t in ipairs(self.ticks) do t:SetAlpha(Theme:VeilAlpha("edge")) end
        end

        f:ApplyVeil()
        self:TrackVeil(f)
    else
        self:Border(f, opts.border or "hairline", opts.borderAlpha or 1)
    end

    return f
end

-- Title block shared by every window: emblem, tracked wordmark, subtitle, and
-- a gold hairline that fades out toward both ends.
function Theme:Header(parent, title, subtitle, opts)
    opts = opts or {}
    local h = CreateFrame("Frame", nil, parent)
    h:SetPoint("TOPLEFT")
    h:SetPoint("TOPRIGHT")
    h:SetHeight(opts.height or 56)

    -- The subtitle is 10px muted type, which is the single least survivable
    -- thing on either veiled window: on bare veil over a snowfield it lands at
    -- 1.5:1. So the title block gets the same plate every other block of type
    -- gets. It hangs off the panel rather than the header so it stays below
    -- the header's own layers, and stops 8px short of the top so the panel's
    -- end still dissolves.
    if parent and self:ChromeOf(parent) == "veil" then
        h.scrim = self:Scrim(parent, {})
        h.scrim:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -8)
        h.scrim:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, -(opts.height or 56))
    end

    local emblem = h:CreateTexture(nil, "ARTWORK")
    emblem:SetSize(20, 20)
    emblem:SetPoint("TOPLEFT", 16, -14)
    if self:Art(emblem, "Emblem") then
        emblem:SetVertexColor(self:Color("gold"))
        h.emblem = emblem
    else
        emblem:Hide()
    end

    local mark = self:Spaced(h, title or "TRIBUNAL", {
        size = 14, spacing = 5, color = "text",
    })
    mark:SetPoint("TOPLEFT", h, "TOPLEFT", h.emblem and 44 or 16, -14)
    h.mark = mark

    -- Bounded, so a long keystone label truncates instead of running out
    -- from under the close button.
    local textLeft = h.emblem and 44 or 16
    h.subtitle = self:Label(h, subtitle or "", {
        size = 10, spacing = 1.6,
        maxWidth = math.max(80, ((parent and parent:GetWidth()) or 380) - textLeft - 44),
    })
    h.subtitle:SetPoint("TOPLEFT", h, "TOPLEFT", textLeft, -34)

    -- Separator: a flat hairline, brightened toward the middle by a second
    -- gold strip so it reads as ornament rather than a rule.
    local line = h:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetColorTexture(self:Color("hairline"))

    -- Two mirrored halves: a single gradient texture can only fade one way,
    -- which left the rule stopping dead at full strength mid-panel.
    local function accentHalf(side)
        local t = h:CreateTexture(nil, "ARTWORK", nil, 1)
        t:SetHeight(1)
        t:SetWidth(96)
        -- Pinned at the centre line so each half can be struck outward.
        t:SetPoint(side < 0 and "BOTTOMRIGHT" or "BOTTOMLEFT", h, "BOTTOM", 0, 0)
        -- White base: the gradient multiplies against the texture's own
        -- colour, so setting gold here as well would square it and land on a
        -- burnt orange at 0.36 alpha instead of gold at 0.6.
        t:SetColorTexture(1, 1, 1, 1)
        if t.SetGradient then
            local out = CreateColor(C.gold[1], C.gold[2], C.gold[3], 0)
            local mid = CreateColor(C.gold[1], C.gold[2], C.gold[3], 0.6)
            t:SetGradient("HORIZONTAL", side < 0 and out or mid, side < 0 and mid or out)
        else
            t:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.6)
        end
        return t
    end
    h.accent = accentHalf(-1)
    h.accentRight = accentHalf(1)

    -- Called whenever the window opens, so the rule is struck rather than
    -- simply being there.
    function h:Strike()
        Theme:Strike(self.accent, "HORIZONTAL", 96, { duration = 0.42 })
        Theme:Strike(self.accentRight, "HORIZONTAL", 96, { duration = 0.42 })
    end

    function h:SetSubtitle(text)
        self.subtitle:SetText((text or ""):upper())
    end

    return h
end

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------

-- `onClose` is required in practice: the owning module holds the teardown
-- (fade, tween cancellation, stopping the ambient bed), and the frame itself
-- has no Close method to fall back on.
function Theme:CloseButton(parent, onClose)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 26)
    b:SetPoint("TOPRIGHT", -8, -8)
    -- The header spans the full width and is mouse-enabled for dragging, so
    -- the button has to sit above it explicitly rather than relying on
    -- creation order.
    b:SetFrameLevel(parent:GetFrameLevel() + 10)

    local x = self:Text(b, 15, { color = "textMuted", justify = "CENTER" })
    x:SetPoint("CENTER", 0, 0)
    x:SetText("\195\151")  -- multiplication sign: a cleaner X than the letter

    b:SetScript("OnEnter", function() x:SetTextColor(Theme:Color("crimson")) end)
    b:SetScript("OnLeave", function() x:SetTextColor(Theme:Color("textMuted")) end)
    b:SetScript("OnClick", function()
        if onClose then onClose() else parent:Hide() end
    end)
    return b
end

-- Flat button: hairline box, tracked caps, gold on hover. `accent` makes it the
-- one gold-filled control on screen.
function Theme:Button(parent, text, opts)
    opts = opts or {}
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(opts.width or 120, opts.height or 28)

    b.bg = self:Fill(b, opts.accent and "gold" or "raised", opts.accent and 0.14 or 1)
    self:Border(b, opts.accent and "gold" or "hairline", opts.accent and 0.7 or 1)

    b.label = self:Label(b, text, {
        size = opts.size or 10, spacing = 2,
        color = opts.accent and "gold" or "text",
    })
    local function place(dy)
        b.label:ClearAllPoints()
        b.label:SetPoint("CENTER", b, "CENTER", 0, dy or 0)
    end
    place()

    function b:SetLabel(str)
        self.label:SetText((str or ""):upper())
        place()
    end

    b:SetScript("OnEnter", function(self)
        Anim:Tween({ duration = 0.14, from = self.bg:GetAlpha(),
            to = opts.accent and 0.26 or 1, onUpdate = function(v)
                if opts.accent then self.bg:SetAlpha(v)
                else self.bg:SetColorTexture(Theme:Color("raisedHi")) end
            end })
        self.label:SetTextColor(Theme:Color(opts.accent and "goldLight" or "gold"))
        if opts.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(opts.tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    b:SetScript("OnLeave", function(self)
        if opts.accent then self.bg:SetAlpha(0.14)
        else self.bg:SetColorTexture(Theme:Color("raised")) end
        self.label:SetTextColor(Theme:Color(opts.accent and "gold" or "text"))
        GameTooltip:Hide()
    end)

    b:SetScript("OnMouseDown", function() place(-1) end)
    b:SetScript("OnMouseUp", function() place(0) end)

    if opts.onClick then b:SetScript("OnClick", opts.onClick) end
    return b
end

-- A list row with a left accent bar that lights up on hover or selection.
function Theme:Row(parent, opts)
    opts = opts or {}
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(opts.height or 34)

    -- Under the veil the container is what goes; a row is content, so it keeps
    -- nearly all of its backing. That inversion is the whole idea: a set of
    -- floating plates held by hairlines rather than a box with things in it.
    r.veiled = self:ChromeOf(parent) == "veil"
    r.bg = self:Fill(r, "raised", r.veiled and self:VeilAlpha("row") or 1)

    r.accent = r:CreateTexture(nil, "ARTWORK")
    r.accent:SetWidth(2)
    r.accent:SetPoint("TOPLEFT")
    r.accent:SetPoint("BOTTOMLEFT")
    r.accent:SetColorTexture(self:Color("hairline"))

    r.selected = false
    r.accentColor = opts.accentColor or "gold"

    function r:Highlight(on)
        local c = on and self.accentColor or "hairline"
        self.accent:SetColorTexture(Theme:Color(c))
        self.bg:SetColorTexture(Theme:Color(on and "raisedHi" or "raised",
            self.veiled and Theme:VeilAlpha("row") or 1))
    end

    if r.veiled then
        function r:ApplyVeil() self:Highlight(self.selected) end
        Theme:TrackVeil(r)
    end

    function r:SetSelected(on, instant)
        local was = self.selected
        self.selected = on
        self:Highlight(on)

        if on and not was and not instant then
            -- Re-pin to LEFT so the mark can open from the row's centre line.
            local h = self:GetHeight()
            self.accent:ClearAllPoints()
            self.accent:SetPoint("LEFT", self, "LEFT", 0, 0)
            self.accent:SetWidth(2)
            Theme:Strike(self.accent, "VERTICAL", h)
        elseif not on then
            self.accent:ClearAllPoints()
            self.accent:SetPoint("TOPLEFT")
            self.accent:SetPoint("BOTTOMLEFT")
        end
    end

    if opts.interactive ~= false then
        r:SetScript("OnEnter", function(self)
            if not self.selected then self:Highlight(true) end
            if self.OnEnterExtra then self:OnEnterExtra() end
        end)
        r:SetScript("OnLeave", function(self)
            if not self.selected then self:Highlight(false) end
            if self.OnLeaveExtra then self:OnLeaveExtra() end
        end)
    else
        r:EnableMouse(false)
    end

    return r
end

-- A progress bar with a bright leading edge that trails the fill.
function Theme:Bar(parent, opts)
    opts = opts or {}
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(opts.height or 6)

    b.track = self:Fill(b, "void", 1)

    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("TOPLEFT")
    b.fill:SetPoint("BOTTOMLEFT")
    b.fill:SetColorTexture(self:Color(opts.color or "gold"))
    b.fill:SetWidth(0.001)

    b.edge = b:CreateTexture(nil, "OVERLAY")
    b.edge:SetWidth(10)
    b.edge:SetPoint("TOP")
    b.edge:SetPoint("BOTTOM")
    b.edge:SetBlendMode("ADD")
    b.edge:SetAlpha(0)
    if b.edge.SetGradient then
        -- White base, as above: the gradient multiplies against it.
        b.edge:SetColorTexture(1, 1, 1, 1)
        b.edge:SetGradient("HORIZONTAL",
            CreateColor(C.goldLight[1], C.goldLight[2], C.goldLight[3], 0),
            CreateColor(C.goldLight[1], C.goldLight[2], C.goldLight[3], 1))
    else
        b.edge:SetColorTexture(self:Color("goldLight"))
    end

    b.value = 0

    function b:SetValue(v, showEdge)
        v = math.max(0, math.min(1, v or 0))
        self.value = v
        local w = self:GetWidth()
        if w <= 0 then w = opts.width or 100 end
        self.fill:SetWidth(math.max(0.001, w * v))
        if showEdge and v > 0.01 and v < 0.999 then
            self.edge:ClearAllPoints()
            self.edge:SetPoint("TOP")
            self.edge:SetPoint("BOTTOM")
            self.edge:SetPoint("RIGHT", self.fill, "RIGHT", 3, 0)
            self.edge:SetAlpha(0.5)
        else
            self.edge:SetAlpha(0)
        end
    end

    function b:SetColor(name)
        self.fill:SetColorTexture(Theme:Color(name))
    end

    -- Animate to a value with the leading edge lit, then let it fade.
    function b:AnimateTo(v, duration, delay, onComplete)
        return Anim:Sweep(function(x, t)
            self:SetValue(x, t < 0.98)
        end, v, duration, delay, function()
            self:SetValue(v, false)
            if onComplete then onComplete() end
        end)
    end

    return b
end

-- The centred diamond divider from the design language.
function Theme:Divider(parent, width)
    local d = CreateFrame("Frame", nil, parent)
    d:SetSize(width or 200, 8)

    local line = d:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT")
    line:SetPoint("RIGHT")
    line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.28)

    local tex = d:CreateTexture(nil, "OVERLAY")
    tex:SetSize(width or 200, 8)
    tex:SetPoint("CENTER")
    if self:Art(tex, "Divider") then
        tex:SetVertexColor(self:Color("gold"))
        line:Hide()
    else
        tex:SetSize(4, 4)
        tex:SetColorTexture(self:Color("gold"))
        tex:SetRotation(math.pi / 4)
    end

    return d
end

--------------------------------------------------------------------------------
-- Behaviour helpers
--------------------------------------------------------------------------------

-- The addon's signature gesture. Nothing gold fades in: it is struck, opening
-- outward from its own centre in a fast decelerating sweep. The gavel is the
-- metaphor and this is the only place it is spelled out.
--
-- `tex` must be anchored so that its growing edge is free -- a vertical mark
-- pinned by LEFT, a horizontal one pinned at its inner end.
function Theme:Strike(tex, axis, length, opts)
    opts = opts or {}
    if not tex or not length or length <= 0 then return end

    local setter = axis == "VERTICAL"
        and function(v) tex:SetHeight(math.max(0.1, v)) end
        or  function(v) tex:SetWidth(math.max(0.1, v)) end

    return Anim:Tween({
        duration = opts.duration or 0.22,
        delay    = opts.delay or 0,
        from = 0, to = length, ease = "outQuint",
        onUpdate = setter,
    })
end

function Theme:MakeMovable(frame, handle, onStop)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    handle = handle or frame
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() frame:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if onStop then onStop() end
    end)
end

-- Escape closes the frame, and it stops other UI stealing focus.
function Theme:MakeCloseable(frame, name)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    if name then
        _G[name] = frame
        tinsert(UISpecialFrames, name)
    end
end

-- A minimal scroll region: no Blizzard scrollbar art, just a hairline thumb.
function Theme:ScrollArea(parent, opts)
    opts = opts or {}
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll.content = content

    local track = parent:CreateTexture(nil, "ARTWORK")
    track:SetWidth(2)
    track:SetColorTexture(self:Color("hairline", 0.5))
    track:Hide()

    local thumb = parent:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(2)
    -- Structure, not state: a scrollbar is never the thing that matters.
    thumb:SetColorTexture(self:Color("textDim", 0.9))
    thumb:Hide()

    scroll.track, scroll.thumb = track, thumb

    function scroll:UpdateThumb()
        local viewH = self:GetHeight()
        local contentH = self.content.contentHeight or self.content:GetHeight()
        if contentH <= viewH + 1 then
            track:Hide(); thumb:Hide(); return
        end

        track:Show(); thumb:Show()
        track:ClearAllPoints()
        track:SetPoint("TOPRIGHT", self, "TOPRIGHT", 6, 0)
        track:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 6, 0)

        local ratio = viewH / contentH
        local thumbH = math.max(18, viewH * ratio)
        local maxScroll = contentH - viewH
        local pct = maxScroll > 0 and (self:GetVerticalScroll() / maxScroll) or 0

        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(viewH - thumbH) * pct)
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local viewH = self:GetHeight()
        local contentH = self.content.contentHeight or self.content:GetHeight()
        local maxScroll = math.max(0, contentH - viewH)
        local target = math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 40))
        self:SetVerticalScroll(target)
        self:UpdateThumb()
    end)

    return scroll
end

--------------------------------------------------------------------------------
-- Decoration
--------------------------------------------------------------------------------

-- A soft radial glow behind something important. Returns the texture so
-- callers can animate its alpha.
function Theme:Bloom(parent, size, color, layer)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND", nil, 2)
    tex:SetSize(size or 200, size or 200)
    tex:SetBlendMode("ADD")
    tex:SetAlpha(0)
    if not self:Art(tex, "Bloom") then
        -- Without the art, fall back to Blizzard's generic glow so the reveal
        -- still has a bloom rather than nothing at all.
        tex:SetTexture("Interface\\Cooldown\\star4")
    end
    tex:SetVertexColor(self:Color(color or "gold"))
    return tex
end

-- Hairline corner accents on a panel, one per corner, mirrored.

--------------------------------------------------------------------------------
-- Form controls
--------------------------------------------------------------------------------

-- A 14px hairline box with a gold diamond struck into it when set.
function Theme:Check(parent, text, opts)
    opts = opts or {}
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(22)

    local box = CreateFrame("Frame", nil, c)
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 0, 0)
    self:Fill(box, "void", 1)
    self:Border(box, "hairline", 1)
    c.box = box

    c.tick = box:CreateTexture(nil, "OVERLAY")
    c.tick:SetSize(7, 7)
    c.tick:SetPoint("CENTER")
    c.tick:SetColorTexture(self:Color("gold"))
    c.tick:SetRotation(math.pi / 4)
    c.tick:SetAlpha(0)

    c.label = self:Text(c, 12, { color = "text" })
    c.label:SetPoint("LEFT", box, "RIGHT", 10, 0)
    c.label:SetText(text or "")

    c.hint = opts.hint

    function c:SetChecked(on, instant)
        self.checked = on and true or false
        if instant then
            self.tick:SetAlpha(on and 1 or 0)
        else
            Anim:Tween({ duration = 0.16, ease = "outCubic",
                from = self.tick:GetAlpha(), to = on and 1 or 0,
                onUpdate = function(v) c.tick:SetAlpha(v) end })
        end
        for _, e in pairs(self.box.borderEdges) do
            e:SetColorTexture(Theme:Color(on and "gold" or "hairline", on and 0.6 or 1))
        end
    end

    c:SetScript("OnEnter", function(self)
        self.label:SetTextColor(Theme:Color("goldLight"))
        if self.hint then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 20, 0)
            GameTooltip:AddLine(self.hint, 0.55, 0.56, 0.61, true)
            GameTooltip:Show()
        end
    end)
    c:SetScript("OnLeave", function(self)
        self.label:SetTextColor(Theme:Color("text"))
        GameTooltip:Hide()
    end)
    c:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if opts.onChange then opts.onChange(self.checked) end
    end)

    -- Clicking the label should toggle too; size the hit area to match.
    c:SetWidth(24 + (c.label:GetStringWidth() or 80))
    return c
end

-- A hairline slider: 1px track, gold fill, a 3x10 bar for a thumb.
function Theme:Slider(parent, text, opts)
    opts = opts or {}
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(38)

    s.label = self:Label(s, text, { size = 10, spacing = 1.6 })
    s.label:SetPoint("TOPLEFT", 0, 0)

    s.value = self:Text(s, 12, { color = "gold", justify = "RIGHT", font = self.FONT.narrow })
    s.value:SetPoint("TOPRIGHT", 0, -1)

    local slider = CreateFrame("Slider", nil, s)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("BOTTOMLEFT", 0, 6)
    slider:SetPoint("BOTTOMRIGHT", 0, 6)
    slider:SetHeight(14)
    slider:SetMinMaxValues(opts.min or 0, opts.max or 1)
    slider:SetValueStep(opts.step or 1)
    slider:SetObeyStepOnDrag(true)
    s.slider = slider

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(1)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetColorTexture(self:Color("hairline"))

    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(1)
    fill:SetPoint("LEFT")
    fill:SetColorTexture(self:Color("gold", 0.8))
    s.fill = fill

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(3, 12)
    thumb:SetColorTexture(self:Color("gold"))
    slider:SetThumbTexture(thumb)

    local function Sync(v)
        local min, max = slider:GetMinMaxValues()
        local pct = max > min and ((v - min) / (max - min)) or 0
        fill:SetWidth(math.max(0.001, slider:GetWidth() * pct))
        s.value:SetText(opts.format and opts.format(v) or tostring(v))
    end

    slider:SetScript("OnValueChanged", function(self, v, byUser)
        v = opts.step and (math.floor(v / opts.step + 0.5) * opts.step) or v
        Sync(v)
        if byUser and opts.onChange then opts.onChange(v) end
    end)

    slider:SetScript("OnEnter", function()
        thumb:SetColorTexture(Theme:Color("goldLight"))
        if opts.hint then
            GameTooltip:SetOwner(slider, "ANCHOR_RIGHT", 20, 0)
            GameTooltip:AddLine(opts.hint, 0.55, 0.56, 0.61, true)
            GameTooltip:Show()
        end
    end)
    slider:SetScript("OnLeave", function()
        thumb:SetColorTexture(Theme:Color("gold"))
        GameTooltip:Hide()
    end)

    function s:SetValue(v)
        slider:SetValue(v)
        Sync(v)
    end

    return s
end

-- A row of mutually exclusive options. Cheaper to read than a dropdown.
function Theme:Segmented(parent, options, opts)
    opts = opts or {}
    local g = CreateFrame("Frame", nil, parent)
    g:SetHeight(24)
    g.buttons = {}

    local x = 0
    for _, def in ipairs(options) do
        local key, text = def[1], def[2]
        local b = CreateFrame("Button", nil, g)
        b:SetHeight(24)

        b.bg = self:Fill(b, "raised", 1)
        self:Border(b, "hairline", 1)

        b.label = self:Label(b, text, { size = 9, spacing = 1.4 })
        b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
        b:SetWidth((b.label.textWidth or 20) + 22)
        b:SetPoint("LEFT", g, "LEFT", x, 0)
        x = x + b:GetWidth() - 1

        b.key = key
        b:SetScript("OnClick", function(self)
            g:SetValue(self.key)
            if opts.onChange then opts.onChange(self.key) end
        end)
        b:SetScript("OnEnter", function(self)
            if g.selected ~= self.key then self.label:SetTextColor(Theme:Color("text")) end
        end)
        b:SetScript("OnLeave", function(self)
            if g.selected ~= self.key then self.label:SetTextColor(Theme:Color("textMuted")) end
        end)

        g.buttons[#g.buttons + 1] = b
    end
    g:SetWidth(x + 1)

    function g:SetValue(key)
        self.selected = key
        for _, b in ipairs(self.buttons) do
            local on = b.key == key
            b.bg:SetColorTexture(Theme:Color(on and "raisedHi" or "raised"))
            b.label:SetTextColor(Theme:Color(on and "gold" or "textMuted"))
            for _, e in pairs(b.borderEdges) do
                e:SetColorTexture(Theme:Color(on and "gold" or "hairline", on and 0.55 or 1))
            end
        end
    end

    return g
end

-- A small caps section heading with a hairline running to the right margin.
function Theme:Section(parent, text)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(18)

    s.label = self:Label(s, text, { size = 10, spacing = 2.2, color = "text" })
    s.label:SetPoint("LEFT", 0, 0)

    local line = s:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", s.label, "RIGHT", 10, 0)
    line:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    line:SetColorTexture(self:Color("hairline", 0.8))

    return s
end

--------------------------------------------------------------------------------
-- Portraits
--------------------------------------------------------------------------------

-- Every disc in the addon is cut with the same mask: the seal, the minimap
-- button, and portraits.
--
-- We ship our own. Blizzard's Interface\CharacterFrame\TempPortraitAlphaMask
-- was removed in 12.1, and because a mask texture that fails to load masks
-- everything away rather than nothing, that single dead path silently erased
-- every circular element at once. Owning the file removes the dependency; the
-- Blizzard paths stay as fallbacks in case ours is ever missing.
local MASK_PATH

function Theme:MaskPath()
    if MASK_PATH ~= nil then return MASK_PATH or nil end

    local probe = UIParent:CreateTexture()
    for _, path in ipairs({
        T.TEXTURE .. "CircleMask",
        "Interface\\Masks\\CircleMaskScalable",
        "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    }) do
        probe:SetTexture(path)
        if probe:GetTexture() then MASK_PATH = path break end
    end
    probe:SetTexture(nil)

    if MASK_PATH == nil then MASK_PATH = false end
    return MASK_PATH or nil
end

function Theme:CircleMask(frame)
    local path = self:MaskPath()
    if not path then return nil end
    local m = frame:CreateMaskTexture()
    m:SetAllPoints(frame)
    m:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    return m
end

-- Cut a texture to a circle. Does nothing at all if no mask is available, so
-- a missing file costs us round corners rather than the whole element.
function Theme:Circle(tex, frame, mask)
    mask = mask or self:CircleMask(frame)
    if mask and tex then tex:AddMaskTexture(mask) end
    return mask
end

-- Point a texture at a player's face, degrading as far as the client allows:
-- the real portrait, then the class icon, then nothing. Returns which landed
-- so callers can retry the ones that fell short.
--
-- A portrait only exists for a unit the client can currently see, which is
-- rarely true of somebody running back from a wipe. Shared by the ballot rows
-- and the verdict seal so both degrade identically.
function Theme:ResolvePortrait(tex, unit, class)
    if not tex then return "none" end

    if unit and UnitExists(unit) and UnitIsConnected(unit) and UnitIsVisible(unit) then
        tex:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(tex, unit)
        tex:SetDesaturated(false)
        tex:Show()
        return "portrait"
    end

    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        tex:Show()
        return "class"
    end

    tex:Hide()
    return "none"
end

-- A unit portrait in the addon's language: circular, cut with the same mask as
-- the seal, and ringed with a 1px stroke that carries the class colour.
--
-- Portraits are only available for units the client can actually see. Someone
-- running back after a wipe is out of range and has no portrait, which is
-- exactly when a ballot is most likely to be open -- so this degrades through
-- the class icon to a flat class-coloured disc rather than showing Blizzard's
-- question mark.
function Theme:Portrait(parent, size)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(size, size)

    p.ring = p:CreateTexture(nil, "BACKGROUND")
    p.ring:SetAllPoints()
    self:Circle(p.ring, p)

    -- A disc one pixel smaller on every side leaves the ring as a 1px stroke.
    local inner = CreateFrame("Frame", nil, p)
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    local innerMask = self:CircleMask(inner)

    p.fill = inner:CreateTexture(nil, "BORDER")
    p.fill:SetAllPoints()
    self:Circle(p.fill, inner, innerMask)

    p.icon = inner:CreateTexture(nil, "ARTWORK")
    p.icon:SetAllPoints()
    self:Circle(p.icon, inner, innerMask)

    function p:SetRingColor(r, g, b, a)
        self.ring:SetColorTexture(r, g, b, a or 1)
    end

    -- Selection borrows the ring; this hands it back to the class colour.
    function p:ResetRing()
        local c = self.classColor
        if c then self:SetRingColor(c[1], c[2], c[3], 0.85)
        else self:SetRingColor(Theme:Color("hairline")) end
    end

    -- Returns "portrait", "class", or "none" so callers can tell what landed.
    function p:SetUnit(unit, class)
        local r, g, b = Theme:ClassColor(class)
        self.classColor = { r, g, b }
        -- A dark wash of the class colour, so the disc still reads as that
        -- player even before any art resolves.
        self.fill:SetColorTexture(r * 0.22, g * 0.22, b * 0.22, 1)
        self:SetRingColor(r, g, b, 0.85)

        self.mode = Theme:ResolvePortrait(self.icon, unit, class)
        return self.mode
    end

    p:SetRingColor(self:Color("hairline"))
    return p
end
