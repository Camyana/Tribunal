-- Tribunal :: Anim
-- A small tween engine. One OnUpdate drives every animation in the addon, so
-- adding motion anywhere costs nothing extra in frame handlers.

local ADDON, T = ...
local A = T:NewModule("Anim")

--------------------------------------------------------------------------------
-- Easing
--------------------------------------------------------------------------------

-- All take t in 0..1 and return the eased 0..1. Deliberately no elastic or
-- bounce curves: the design language says nothing springs.
local Ease = {}
A.Ease = Ease

function Ease.linear(t)   return t end
function Ease.inQuad(t)   return t * t end
function Ease.outQuad(t)  return 1 - (1 - t) ^ 2 end
function Ease.outCubic(t) return 1 - (1 - t) ^ 3 end
function Ease.outQuart(t) return 1 - (1 - t) ^ 4 end
function Ease.outQuint(t) return 1 - (1 - t) ^ 5 end
function Ease.outExpo(t)  return t >= 1 and 1 or (1 - 2 ^ (-10 * t)) end

function Ease.inOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    return 1 - ((-2 * t + 2) ^ 3) / 2
end

function Ease.inOutSine(t)
    return -(math.cos(math.pi * t) - 1) / 2
end

--------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------

local active = {}
local driver = CreateFrame("Frame")
driver:Hide()

driver:SetScript("OnUpdate", function()
    local now = GetTime()
    local n = #active

    for i = n, 1, -1 do
        local tw = active[i]
        local elapsed = now - tw.start

        if elapsed < 0 then
            -- Still inside its delay; nothing to do yet.
        else
            local t = tw.duration > 0 and math.min(elapsed / tw.duration, 1) or 1
            local eased = tw.ease(t)
            local value = tw.from + (tw.to - tw.from) * eased

            if tw.onUpdate then
                local ok, err = pcall(tw.onUpdate, value, t, eased)
                if not ok then
                    geterrorhandler()(("Tribunal: tween update failed: %s"):format(err))
                    t = 1
                end
            end

            if t >= 1 then
                tw.done = true
                table.remove(active, i)
                if tw.onComplete then
                    local ok, err = pcall(tw.onComplete)
                    if not ok then
                        geterrorhandler()(("Tribunal: tween completion failed: %s"):format(err))
                    end
                end
            end
        end
    end

    if #active == 0 then driver:Hide() end
end)

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

-- opts = { duration, from, to, ease, delay, onUpdate(value, t), onComplete }
-- Returns a handle you can pass to A:Cancel.
function A:Tween(opts)
    local tw = {
        duration   = opts.duration or 0.3,
        from       = opts.from or 0,
        to         = opts.to or 1,
        ease       = type(opts.ease) == "function" and opts.ease
                     or Ease[opts.ease or "outCubic"] or Ease.outCubic,
        start      = GetTime() + (opts.delay or 0),
        onUpdate   = opts.onUpdate,
        onComplete = opts.onComplete,
    }

    active[#active + 1] = tw
    driver:Show()

    -- Push the starting value immediately so there is no one-frame flash of
    -- whatever the widget looked like before.
    if tw.onUpdate and (opts.delay or 0) <= 0 then
        pcall(tw.onUpdate, tw.from, 0, 0)
    end

    return tw
end

function A:Cancel(tw)
    if not tw or tw.done then return end
    for i = #active, 1, -1 do
        if active[i] == tw then
            table.remove(active, i)
            tw.done = true
            return
        end
    end
end

function A:CancelAll(list)
    if not list then return end
    for i = #list, 1, -1 do
        self:Cancel(list[i])
        list[i] = nil
    end
end

--------------------------------------------------------------------------------
-- Common recipes
--------------------------------------------------------------------------------

-- Fade a region's alpha. Shows it first if fading in, hides it after if out.
function A:Fade(region, to, duration, ease, onComplete)
    if not region then return end
    local from = region:GetAlpha()
    if to > 0 then region:Show() end

    return self:Tween({
        duration = duration or 0.22,
        from = from, to = to, ease = ease or "outCubic",
        onUpdate = function(v) region:SetAlpha(v) end,
        onComplete = function()
            if to <= 0 then region:Hide() end
            if onComplete then onComplete() end
        end,
    })
end

-- Slide a frame in from an offset while fading up. This is the entrance used
-- by every panel in the addon.
function A:SlideIn(frame, opts)
    opts = opts or {}
    local dx, dy = opts.x or 0, opts.y or -12
    local point, rel, relPoint, ox, oy = frame:GetPoint(1)
    if not point then return end

    frame:SetAlpha(0)
    frame:Show()

    return self:Tween({
        duration = opts.duration or 0.34,
        delay    = opts.delay or 0,
        ease     = opts.ease or "outQuint",
        onUpdate = function(v)
            frame:SetAlpha(v)
            frame:ClearAllPoints()
            frame:SetPoint(point, rel, relPoint, ox + dx * (1 - v), oy + dy * (1 - v))
        end,
        onComplete = opts.onComplete,
    })
end

-- Run fn(index, item) for each item, spaced `gap` seconds apart.
function A:Stagger(items, gap, fn)
    gap = gap or 0.045
    for i, item in ipairs(items) do
        if i == 1 then
            fn(i, item)
        else
            C_Timer.After(gap * (i - 1), function() fn(i, item) end)
        end
    end
end

-- Animate a StatusBar-like fill. `setter` receives the 0..1 progress.
function A:Sweep(setter, to, duration, delay, onComplete)
    return self:Tween({
        duration = duration or 0.9,
        delay = delay or 0,
        from = 0, to = to, ease = "outQuint",
        onUpdate = setter,
        onComplete = onComplete,
    })
end

-- A one-shot pulse: 0 -> 1 -> 0, for glows and flashes.
function A:Pulse(setter, peak, duration, delay)
    peak = peak or 1
    duration = duration or 0.6
    return self:Tween({
        duration = duration, delay = delay or 0,
        from = 0, to = 1, ease = "linear",
        onUpdate = function(t)
            -- Fast attack, slow release reads as a strike rather than a throb.
            local v = t < 0.18 and (t / 0.18) or (1 - (t - 0.18) / 0.82) ^ 2
            setter(v * peak)
        end,
        onComplete = function() setter(0) end,
    })
end
