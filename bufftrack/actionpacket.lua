--[[
    actionpacket.lua

    Decodes the server's "action" packet (0x028: spell casts, abilities,
    weapon skills and their results) into a Lua table.

    The packet is a bit-packed stream, so decoding is a matter of reading
    fields of known widths in order. The layout below is the wire format;
    the output field names are what the trackers use:

        packet.UserId, packet.Type, packet.Id, packet.Recast
        packet.Targets[n].Id
        packet.Targets[n].Actions[m].Reaction / Animation / SpecialEffect /
            Knockback / Param / Message / Flags
            plus .AdditionalEffect and .SpikesEffect when present
            ({ Damage, Param, Message })
]]--

--Field lists: { name, width in bits }, read in order.
local HEADER_SKIP_BITS = 40;   --packet id/size/sync header

local actionFields = {
    { 'Reaction', 5 },
    { 'Animation', 12 },
    { 'SpecialEffect', 7 },
    { 'Knockback', 3 },
    { 'Param', 17 },
    { 'Message', 10 },
    { 'Flags', 31 },
};

local additionalEffectFields = {
    { 'Damage', 10 },
    { 'Param', 17 },
    { 'Message', 10 },
};

local spikesEffectFields = {
    { 'Damage', 10 },
    { 'Param', 14 },
    { 'Message', 10 },
};

--Sequential big-endian bit reader over the raw packet bytes.
local function NewReader(raw, startBit)
    local position = startBit;
    local reader = {};

    function reader.Read(width)
        local value = ashita.bits.unpack_be(raw, 0, position, width);
        position = position + width;
        return value;
    end

    function reader.Skip(width)
        position = position + width;
    end

    --Reads each { name, width } field into a new table.
    function reader.ReadFields(fields)
        local result = {};
        for _,field in ipairs(fields) do
            result[field[1]] = reader.Read(field[2]);
        end
        return result;
    end

    return reader;
end

local function ReadAction(reader)
    local action = reader.ReadFields(actionFields);
    if (reader.Read(1) == 1) then
        action.AdditionalEffect = reader.ReadFields(additionalEffectFields);
    end
    if (reader.Read(1) == 1) then
        action.SpikesEffect = reader.ReadFields(spikesEffectFields);
    end
    return action;
end

local function Parse(e)
    local reader = NewReader(e.data_raw, HEADER_SKIP_BITS);

    local packet = T{};
    packet.UserId = reader.Read(32);
    local targetCount = reader.Read(6);
    reader.Skip(4);
    packet.Type = reader.Read(4);
    packet.Id = reader.Read(17);
    reader.Skip(15);
    packet.Recast = reader.Read(32);

    packet.Targets = T{};
    for _ = 1, targetCount do
        local target = T{};
        target.Id = reader.Read(32);
        local actionCount = reader.Read(4);
        target.Actions = T{};
        for _ = 1, actionCount do
            target.Actions:append(ReadAction(reader));
        end
        packet.Targets:append(target);
    end

    return packet;
end

local exports = {};

function exports:parse(e)
    return Parse(e);
end

return exports;
