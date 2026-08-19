-- Tribunal :: Comm
-- Addon-channel transport. Messages are pipe-delimited with a one or two
-- character opcode; the sender is taken from the event, never the payload, so
-- votes cannot be attributed to somebody else.

local ADDON, T = ...
local Comm = T:NewModule("Comm")

Comm.peers = {}       -- [fullName] = { version, protocol, seen }
Comm.listeners = {}   -- [opcode] = { fn, ... }

local OP = {
    HELLO   = "HI",   -- HI|protocol|version
    HERE    = "YO",   -- YO|protocol|version
    OPEN    = "V",    -- V|sid|duration|label
    CAST    = "C",    -- C|sid|target
    ABORT   = "X",    -- X|sid|reason
    RESULT  = "R",    -- R|sid|winner|count|total
}
Comm.OP = OP

--------------------------------------------------------------------------------
-- Channel selection
--------------------------------------------------------------------------------

local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

Comm.GroupChannel = GroupChannel

--------------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------------

-- The delimiter must never appear inside a field. Names cannot contain it, but
-- zone labels and reasons can be arbitrary, so they get scrubbed.
local function Clean(s)
    return tostring(s or ""):gsub("|", "/"):gsub("[\r\n]", " ")
end

local function Encode(op, ...)
    local parts = { op }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = Clean((select(i, ...)))
    end
    return table.concat(parts, "|")
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

function Comm:Send(op, ...)
    local channel = GroupChannel()
    if not channel then return false end

    local msg = Encode(op, ...)
    if #msg > 250 then
        -- Nothing we send is legitimately this long; truncating beats a
        -- silently dropped message.
        msg = msg:sub(1, 250)
    end

    C_ChatInfo.SendAddonMessage(T.prefix, msg, channel)
    return true
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

function Comm:Listen(op, fn)
    local list = self.listeners[op]
    if not list then list = {}; self.listeners[op] = list end
    list[#list + 1] = fn
end

local function Dispatch(op, sender, args)
    local list = Comm.listeners[op]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], sender, unpack(args))
        if not ok then
            geterrorhandler()(("Tribunal: comm handler for %s failed: %s"):format(op, err))
        end
    end
end

--------------------------------------------------------------------------------
-- Peers
--------------------------------------------------------------------------------

function Comm:NotePeer(sender, protocol, version)
    self.peers[sender] = {
        protocol = tonumber(protocol) or 0,
        version  = version or "?",
        seen     = GetTime(),
    }
end

function Comm:PeerCount()
    local n = 0
    for _ in pairs(self.peers) do n = n + 1 end
    return n
end

-- How many people in the current group could actually receive a ballot,
-- counting yourself.
function Comm:ReachableCount()
    local n = 1
    for peer in pairs(self.peers) do
        if T:InGroup(peer) then n = n + 1 end
    end
    return n
end

function Comm:PrunePeers()
    for peer in pairs(self.peers) do
        if not T:InGroup(peer) then self.peers[peer] = nil end
    end
end

function Comm:Announce()
    if not GroupChannel() then return end
    self:Send(OP.HELLO, T.protocol, T.version)
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------

function Comm:OnInit()
    C_ChatInfo.RegisterAddonMessagePrefix(T.prefix)

    T:On("CHAT_MSG_ADDON", function(prefix, message, channel, sender)
        if prefix ~= T.prefix or not message then return end

        -- Only the group is allowed to talk to us, and never ourselves; our own
        -- state is applied locally at send time.
        if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then
            return
        end

        local full = T:Qualify(sender)
        if not full or full == T:FullName("player") then return end
        if not T:InGroup(full) then return end

        local args = {}
        for field in (message .. "|"):gmatch("([^|]*)|") do
            args[#args + 1] = field
        end

        local op = table.remove(args, 1)
        if not op then return end

        if op == OP.HELLO then
            Comm:NotePeer(full, args[1], args[2])
            Comm:Send(OP.HERE, T.protocol, T.version)
        elseif op == OP.HERE then
            Comm:NotePeer(full, args[1], args[2])
        end

        Dispatch(op, full, args)
    end)

    -- Re-introduce ourselves whenever the group changes shape.
    local function OnRosterUpdate()
        Comm:PrunePeers()
        if GroupChannel() then
            C_Timer.After(1, function() Comm:Announce() end)
        else
            wipe(Comm.peers)
        end
    end

    T:On("GROUP_ROSTER_UPDATE", OnRosterUpdate)
    T:On("PLAYER_ENTERING_WORLD", OnRosterUpdate)
end

function Comm:OnLogin()
    C_Timer.After(3, function() Comm:Announce() end)
end
