--[[
    durations/data.lua

    Live view of the local player's state for the duration calculators:
    identity, jobs and levels, active buffs, equipped gear, merit ranks and
    combat skills.

    Almost everything is read straight from Ashita's memory managers at the
    moment it's asked for, so there is no packet bookkeeping to keep in sync.
    The one exception is merit ranks, which the client only exposes through a
    memory table we read lazily and refresh from the server's merit packet.

    Nothing here sends packets.
]]--

local tracker = {};

local GEAR_SLOTS = 16;           --equipment slots 0-15
local ICON_EMPTY = 255;          --status icon value meaning "no buff in this slot"
local PACKET_MERITS = 0x08C;

local function Memory()
    return AshitaCore:GetMemoryManager();
end

------------------------------------------------------------
-- Identity and jobs
------------------------------------------------------------
function tracker:GetPlayerId()
    local ok, id = pcall(function() return Memory():GetParty():GetMemberServerId(0); end);
    if (ok) and (type(id) == 'number') then
        return id;
    end
    return 0;
end

--Returns { Main, MainLevel, Sub, SubLevel }.
function tracker:GetJobData()
    local ok, jobs = pcall(function()
        local player = Memory():GetPlayer();
        return {
            Main = player:GetMainJob(),
            MainLevel = player:GetMainJobLevel(),
            Sub = player:GetSubJob(),
            SubLevel = player:GetSubJobLevel(),
        };
    end);
    if (ok) then
        return jobs;
    end
    return { Main = 0, MainLevel = 0, Sub = 0, SubLevel = 0 };
end

------------------------------------------------------------
-- Buffs
------------------------------------------------------------
function tracker:GetBuffCount(buffId)
    local count = 0;
    local ok, icons = pcall(function() return Memory():GetPlayer():GetStatusIcons(); end);
    if (ok) and (icons ~= nil) then
        for i = 1, 32 do
            if (icons[i] ~= nil) and (icons[i] ~= ICON_EMPTY) and (icons[i] == buffId) then
                count = count + 1;
            end
        end
    end
    return count;
end

function tracker:GetBuffActive(buffId)
    return self:GetBuffCount(buffId) > 0;
end

------------------------------------------------------------
-- Gear
------------------------------------------------------------
--Ids of everything currently worn that the wearer is high enough level to
--benefit from: { [slot] = itemId }.
local function WornItems(mainLevel)
    local worn = {};
    local ok = pcall(function()
        local inventory = Memory():GetInventory();
        local resources = AshitaCore:GetResourceManager();
        for slot = 0, GEAR_SLOTS - 1 do
            local equipped = inventory:GetEquippedItem(slot);
            local index = bit.band(equipped.Index, 0x00FF);
            if (index > 0) then
                local container = bit.rshift(bit.band(equipped.Index, 0xFF00), 8);
                local item = inventory:GetContainerItem(container, index);
                if (item ~= nil) and (item.Id > 0) then
                    local resource = resources:GetItemById(item.Id);
                    if (resource == nil) or (mainLevel >= resource.Level) then
                        worn[slot] = item.Id;
                    end
                end
            end
        end
    end);
    if (not ok) then
        return {};
    end
    return worn;
end

--values: { [itemId] = amount }. Adds up the amount for every worn item that
--has an entry.
function tracker:EquipSum(values)
    local total = 0;
    for _,itemId in pairs(WornItems(self:GetJobData().MainLevel)) do
        local amount = values[itemId];
        if (amount ~= nil) then
            total = total + amount;
        end
    end
    return total;
end

------------------------------------------------------------
-- Skills
------------------------------------------------------------
--Combat/magic skill level as the client reports it (base skill, without
--gear bonuses). 0 if it can't be read.
function tracker:GetSkill(skillId)
    local ok, value = pcall(function()
        local skill = Memory():GetPlayer():GetCombatSkill(skillId);
        if (type(skill) == 'number') then
            return skill;
        end
        if (skill.GetSkill ~= nil) then
            return skill:GetSkill();
        end
        return skill.Skill;
    end);
    if (ok) and (type(value) == 'number') then
        return value;
    end
    return 0;
end

------------------------------------------------------------
-- Merits
------------------------------------------------------------
local meritRanks = {};
local meritsLoaded = false;

--The client keeps its merit table (4 bytes per merit: id, then rank) behind
--the inventory pointer.
local function LoadMeritsFromMemory()
    meritsLoaded = true;
    pcall(function()
        local base = AshitaCore:GetPointerManager():Get('inventory');
        if (base <= 0) then
            return;
        end
        local ptr = ashita.memory.read_uint32(base);
        if (ptr == 0) then
            return;
        end
        ptr = ashita.memory.read_uint32(ptr);
        if (ptr == 0) then
            return;
        end
        ptr = ptr + 0x2CFF4;
        local count = ashita.memory.read_uint16(ptr + 2);
        local entry = ashita.memory.read_uint32(ptr + 4);
        for _ = 1, count do
            meritRanks[ashita.memory.read_uint16(entry)] = ashita.memory.read_uint8(entry + 3);
            entry = entry + 4;
        end
    end);
end

function tracker:GetMeritCount(meritId)
    if (not meritsLoaded) then
        LoadMeritsFromMemory();
    end
    return meritRanks[meritId] or 0;
end

--The server resends merit ranks whenever they change.
ashita.events.register('packet_in', 'bufftrack_data_merits_cb', function (e)
    if (e.id == PACKET_MERITS) then
        local count = struct.unpack('B', e.data, 0x04 + 1);
        for i = 1, count do
            local meritId = struct.unpack('H', e.data, 0x04 + (4 * i) + 1);
            meritRanks[meritId] = struct.unpack('B', e.data, 0x04 + (4 * i) + 0x03 + 1);
        end
        meritsLoaded = true;
    end
end);

------------------------------------------------------------
-- Job points: not tracked (level cap here is 75).
------------------------------------------------------------
function tracker:GetJobPointCount() return 0; end
function tracker:GetJobPointTotal() return 0; end

return tracker;
