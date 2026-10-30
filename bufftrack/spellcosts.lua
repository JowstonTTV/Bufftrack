--[[
    spellcosts.lua

    MP-cost lookup for tracked buffs, shown in the grid header next to each
    buff's icon/name.

    Backed by libs/spellcosts_data.lua, generated from the PhoenixXI server's
    spell data (era-adjusted) by tools/gen_libs.py. Spells with no cost on
    record (songs, ninjutsu, abilities) have no entry and GetCost returns
    nil -- "nil means show a placeholder".
]]--

local costData = require('libs.spellcosts_data');

local exports = {};

--Returns a number, or nil if this buff has no baked cost (non-Enhancing
--spell, an Ability, or genuinely just not in the source data) -- callers
--should show a placeholder ("--") rather than treat nil as zero.
function exports:GetCost(actionType, actionId)
    if (actionType ~= 'Spell') then
        return nil;
    end
    return costData[actionId];
end

return exports;
