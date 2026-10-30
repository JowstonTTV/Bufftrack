--[[
    durations/include.lua

    Entry point for buff-duration lookups used by the assignment tracker.

        GetSpellDuration(spellId, targetId)    -> seconds, status effect id | nil
        GetAbilityDuration(abilityId, targetId) -> seconds, status effect id | nil
        GetDataTracker()                        -> the player-state tracker (data.lua)

    Both lookups are backed by data generated from the server tables
    (serverdata.lua): magic.lua for spells, jobs.lua for job abilities,
    blood pacts and Corsair rolls.
]]--

local thisFile = debug.getinfo(1, 'S').source:sub(2);
local data = dofile((string.gsub(thisFile, 'include%.lua$', 'data.lua')));
local magic = require('durations.magic');
local jobs = require('durations.jobs');

if (not magic.IsLoaded()) then
    print('BuffTrack: durations/serverdata.lua is missing -- duration lookups are unavailable.');
end

local exports = {};

function exports:GetDataTracker()
    return data;
end

function exports:GetSpellDuration(spellId, targetId)
    return magic.GetDuration(data, spellId, targetId);
end

function exports:GetAbilityDuration(abilityId, targetId)
    return jobs.GetDuration(data, abilityId);
end

--Not used by BuffTrack; kept so any stray caller gets "no duration" rather
--than an error.
function exports:GetMobAbilityDuration() return nil; end
function exports:GetPetAbilityDuration() return nil; end
function exports:GetWeaponskillDuration() return nil; end

return exports;
