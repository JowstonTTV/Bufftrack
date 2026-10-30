--[[
    durations/magic.lua

    Spell duration estimates for the buffs BuffTrack tracks, computed from
    the PhoenixXI server's own numbers (durations/serverdata.lua, generated
    by tools/gen_durations.py) rather than retail values.

    Covers: enhancing magic, bard songs, enhancing ninjutsu, blue magic
    buffs, and a few fixed-duration buffs (Reraise). Only spells a player can actually learn in the server's era are
    included (the generator prunes the rest). Anything not in the server
    tables returns nil here so include.lua can fall back to the older
    calculators while they're being retired.

    Everything is computed for the LOCAL player's own gear/buffs, which is
    what BuffTrack's assignment tracking assumes for casts it sees.

    Known simplifications (all small, all on the safe side):
      * Gear skill bonuses are not part of the client-side skill value, so
        skill-scaled durations (Bar-element) can run a little short.
      * Deodorize/Invisible/Sneak have a random base on this server; the
        midpoint of the range is used.
      * Job points and 99-era features are ignored (level cap is 75).
]]--

local loaded, server = pcall(require, 'durations.serverdata');
if (not loaded) then
    server = nil;
end

local magic = {};

local ENHANCING_SKILL = 34;
local JOB_RDM = 5;
local RANDOM_BASE_MIDPOINT = (30 + 300) / 2; --Deodorize/Invisible/Sneak

--Main job level of whoever the buff landed on, or nil if unknown.
local function ReadTargetLevel(data, targetId)
    if (targetId == data:GetPlayerId()) then
        return data:GetJobData().MainLevel;
    end
    local ok, level = pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        for i = 0, 17 do
            if (party:GetMemberIsActive(i) == 1) and (party:GetMemberServerId(i) == targetId) then
                return party:GetMemberMainJobLevel(i);
            end
        end
        return nil;
    end);
    if (ok) and (type(level) == 'number') and (level > 0) then
        return level;
    end
    return nil;
end

--Sum of a named server modifier across the player's equipped gear.
local function GearTotal(data, modName)
    local items = server.gear[modName];
    if (items == nil) or (modName == '') then
        return 0;
    end
    return data:EquipSum(items);
end

local function Between(value, low, high)
    return (value >= low) and (value <= high);
end

--Duration reduction when the target is below the spell's level.
local function ApplyLevelPenalty(duration, data, targetId, spellLevel)
    local targetLevel = ReadTargetLevel(data, targetId);
    if (targetLevel ~= nil) and (targetLevel < spellLevel) then
        return duration * targetLevel / spellLevel;
    end
    return duration;
end

local function EnhancingSpell(data, row, targetId)
    local fx = server.effects;
    local isSelf = (targetId == data:GetPlayerId());
    local effect = row.effect;
    local duration = row.base;

    --Sneak / Invisible / Deodorize: random base, no percentage bonuses.
    if (effect == fx.SNEAK) or (effect == fx.INVISIBLE) or (effect == fx.DEODORIZE) then
        duration = RANDOM_BASE_MIDPOINT;
        if (isSelf) then
            if (effect == fx.INVISIBLE) then
                duration = duration + GearTotal(data, 'INVISIBLE_DURATION');
            elseif (effect == fx.SNEAK) then
                duration = duration + GearTotal(data, 'SNEAK_DURATION');
            end
            if (row.composure) and (data:GetBuffActive(fx.COMPOSURE)) then
                duration = duration * 3;
            end
        end
        return ApplyLevelPenalty(duration, data, targetId, row.level);
    end

    --Bar-element: duration scales with enhancing skill on this server.
    if (Between(effect, fx.BARFIRE, fx.BARWATER)) then
        duration = 150 + (math.max(data:GetSkill(ENHANCING_SKILL) - 180, 0) * 0.8);
    end

    --Embolden halves white magic cast on yourself.
    if (isSelf) and (row.white) and (data:GetBuffActive(fx.EMBOLDEN)) then
        duration = duration * 0.5;
    end

    --Gear: percentage bonus.
    duration = duration + (duration * GearTotal(data, 'ENH_MAGIC_DURATION') / 100);

    --Red Mage merit (seconds per rank).
    if (data:GetJobData().Main == JOB_RDM) then
        local merit = server.merits.ENHANCING_MAGIC_DURATION;
        duration = duration + (data:GetMeritCount(merit.id) * merit.perRank);
    end

    --Spell-specific additions.
    if (effect == fx.REGEN) then
        duration = duration + GearTotal(data, 'REGEN_DURATION');
    elseif (isSelf) and (Between(effect, fx.ENFIRE, fx.ENWATER) or Between(effect, fx.ENFIRE_II, fx.ENWATER_II)) then
        duration = duration + GearTotal(data, 'ENSPELL_DURATION');
    end

    --Self-only multipliers.
    if (isSelf) and (row.composure) and (data:GetBuffActive(fx.COMPOSURE)) then
        duration = duration * 3;
    end
    if (row.white) and (data:GetBuffActive(fx.PERPETUANCE)) then
        duration = duration * 2;
    end

    return ApplyLevelPenalty(duration, data, targetId, row.level);
end

local function Song(data, row)
    local fx = server.effects;
    --Instrument boost: that song family's modifier plus the all-songs one.
    local boost = GearTotal(data, row.mod) + GearTotal(data, 'ALL_SONGS_EFFECT');
    local bonus = GearTotal(data, 'SONG_DURATION_BONUS');
    local duration = math.floor(120 * ((boost * 0.1) + (bonus / 100) + 1));

    --Soul Voice boosts potency for most songs, duration only for the rest.
    if (not row.soulVoicePower) and (data:GetBuffActive(fx.SOUL_VOICE)) then
        duration = duration * 2;
    end
    if (data:GetBuffActive(fx.TROUBADOUR)) then
        duration = duration * 2;
    end
    return duration;
end

--Blue magic buffs: fixed base duration, lengthened by the Diffusion merit.
local function BlueBuff(data, row)
    local fx = server.effects;
    local duration = row.base;
    if (data:GetBuffActive(fx.DIFFUSION)) then
        local rank = data:GetMeritCount(server.merits.DIFFUSION.id);
        if (rank > 1) then
            duration = duration + ((rank - 1) * 5 * duration / 100);
        end
    end
    return duration;
end

--Returns duration (seconds), status effect id -- or nil if this module
--has no data for the spell.
function magic.GetDuration(data, spellId, targetId)
    if (server == nil) then
        return nil;
    end

    local row = server.spells[spellId];
    if (row ~= nil) then
        return EnhancingSpell(data, row, targetId), row.effect;
    end

    row = server.songs[spellId];
    if (row ~= nil) then
        return Song(data, row), row.effect;
    end

    row = server.ninjutsu[spellId];
    if (row ~= nil) and (row.base > 0) then
        return row.base, row.effect;
    end

    row = server.blue[spellId];
    if (row ~= nil) then
        return BlueBuff(data, row), row.effect;
    end

    row = server.fixed[spellId];
    if (row ~= nil) then
        return row.base, row.effect;
    end

    return nil;
end

function magic.IsLoaded()
    return server ~= nil;
end

return magic;
