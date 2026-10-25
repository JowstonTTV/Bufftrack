--[[
    libs/profiles.lua

    Named snapshots of BuffTrack's configuration, saved to and loaded from
    plain local files. Nothing here touches the network, the game client, or
    anything outside the profiles folder.

    Where: <install>/config/addons/<addon>/profiles/<name>.lua -- shared by
    every character (deliberately NOT per-character like the main settings
    file, so a setup can be carried over to another character). One file per
    profile, human-readable (a Lua table literal), safe to copy / rename /
    back up / hand-edit.

    What a profile captures (see KeyGroups):
      Display  - scales, thresholds, panel toggles, Cures display aids, ...
      Audio    - per-tracker cues and volume
      Tracking - assigned buffs, Cures map + overrides, watch list, per-
                 player Cures sort priority
      Layout   - panel positions. OPTIONAL, chosen at save time (off by
                 default): positions depend on screen resolution / UI scale
                 and usually shouldn't move when swapping between setups.
    Not captured: Enabled (the master on/off switch is state, not setup).

    Safety:
      - Loading never executes arbitrary code: the file is parsed in an
        EMPTY environment (it can build a table and nothing else), and
        precompiled bytecode is rejected outright.
      - Every key is validated against an expected type/range, and every
        array entry for the fields the rest of the addon indexes directly
        (ActionId, TargetName, StatusId, ...) is checked -- an invalid value
        is skipped and reported, never applied, so a corrupted or hand-
        edited file can't crash the config window the way an unchecked nil
        in a string.format once did.
      - Loading first snapshots the CURRENT setup to a hidden "_previous"
        profile, so any load can be undone. Undo itself re-snapshots first,
        so undoing twice is a redo.
]]--

local exports = {};

local FormatVersion = 1;
local MaxFileBytes = 512 * 1024;
local MaxDepth = 8;
local PreviousName = '_previous';

local GroupOrder = { 'Display', 'Audio', 'Tracking', 'Layout' };
local KeyGroups = {
    Display = {
        'GridScale', 'CuresScale', 'WatchScale', 'UseTooltips',
        'HideWithPrimitives', 'ShowTenths', 'SnapEnabled', 'SnapDistance',
        'CuresShowEmpty', 'WatchShowEmpty', 'CuresGroupDivider',
        'CuresShowJobIcon', 'CuresColor', 'CuresFlash', 'AttentionThreshold',
        'AttentionGrace', 'GridGroupBy', 'JobIconStyle', 'GridClickToCast',
    },
    Audio = { 'GridSound', 'CuresSound', 'WatchSound', 'AlarmVolume' },
    Tracking = {
        'Assignments', 'CureMap', 'CureMapSeeded', 'EnemyBuffWatchList',
        'CureOverrides', 'PlayerPriority',
    },
    Layout = { 'Position', 'CuresPosition', 'WatchPosition', 'PlayerPositions' },
};

--Expected shape per key. 'array' = a list of entry tables (each checked by
--EntryValidators); 'table' = a table checked by TableValidators.
local Schema = {
    GridScale = 'number', CuresScale = 'number', WatchScale = 'number',
    UseTooltips = 'boolean', HideWithPrimitives = 'boolean', ShowTenths = 'boolean',
    SnapEnabled = 'boolean', SnapDistance = 'number',
    CuresShowEmpty = 'boolean', WatchShowEmpty = 'boolean',
    CuresGroupDivider = 'boolean', CuresShowJobIcon = 'boolean',
    CuresColor = 'number', CuresFlash = 'boolean',
    AttentionThreshold = 'number', AttentionGrace = 'number',
    GridGroupBy = 'string', JobIconStyle = 'string', GridClickToCast = 'boolean',
    GridSound = 'table', CuresSound = 'table', WatchSound = 'table', AlarmVolume = 'number',
    Assignments = 'array', CureMap = 'array', CureMapSeeded = 'boolean',
    EnemyBuffWatchList = 'array', CureOverrides = 'array', PlayerPriority = 'table',
    Position = 'table', CuresPosition = 'table', WatchPosition = 'table', PlayerPositions = 'table',
};

--Sanity bounds for numeric keys -- a scale of 0 (or 9000) from a bad file
--would divide by zero / draw nonsense rather than just look wrong.
local NumberRanges = {
    GridScale = { 0.25, 5 }, CuresScale = { 0.25, 5 }, WatchScale = { 0.25, 5 },
    SnapDistance = { 0, 200 }, AlarmVolume = { 0, 100 },
    AttentionThreshold = { 0, 3600 }, AttentionGrace = { 0, 3600 },
};

local function IsXY(t)
    return (type(t) == 'table') and (type(t.X) == 'number') and (type(t.Y) == 'number');
end

local function IsSound(t)
    return (type(t) == 'table') and (type(t.Enabled) == 'boolean') and (type(t.SoundId) == 'string');
end

local TableValidators = {
    GridSound = IsSound, CuresSound = IsSound, WatchSound = IsSound,
    Position = IsXY, CuresPosition = IsXY, WatchPosition = IsXY,
    PlayerPositions = function(t)
        for k,v in pairs(t) do
            if (type(k) ~= 'string') or (not IsXY(v)) then
                return false;
            end
        end
        return true;
    end,
    PlayerPriority = function(t)
        for k,v in pairs(t) do
            if (type(k) ~= 'string') or (type(v) ~= 'number') then
                return false;
            end
        end
        return true;
    end,
};

--Only the fields other code indexes unconditionally (a nil there is what
--crashes string.format('%u', ...) and friends) -- everything optional
--(Scale/Color/Sound/Flash overrides, ...) is already nil-tolerant.
local EntryValidators = {
    Assignments = function(e)
        return (type(e.ActionType) == 'string') and (type(e.ActionId) == 'number')
            and (type(e.BuffId) == 'number') and (type(e.TargetName) == 'string');
    end,
    CureMap = function(e)
        return (type(e.StatusId) == 'number') and (type(e.ActionType) == 'string')
            and (type(e.ActionId) == 'number');
    end,
    EnemyBuffWatchList = function(e)
        return (type(e.ActionType) == 'string') and (type(e.ActionId) == 'number')
            and (type(e.Label) == 'string');
    end,
    CureOverrides = function(e)
        return (type(e.TargetName) == 'string') and (type(e.StatusId) == 'number');
    end,
};

------------------------------------------------------------
-- Paths / names
------------------------------------------------------------
local ReservedNames = {
    con = true, prn = true, aux = true, nul = true,
    com1 = true, com2 = true, com3 = true, com4 = true, com5 = true,
    com6 = true, com7 = true, com8 = true, com9 = true,
    lpt1 = true, lpt2 = true, lpt3 = true, lpt4 = true, lpt5 = true,
    lpt6 = true, lpt7 = true, lpt8 = true, lpt9 = true,
};

--Returns the cleaned name, or nil + a user-facing reason. Names become file
--names, so this is also the path-traversal guard (no separators, no dots).
--allowInternal permits the reserved leading-underscore names (_previous).
local function CleanName(name, allowInternal)
    if (type(name) ~= 'string') then
        return nil, 'No profile name given.';
    end
    name = name:gsub('^%s+', ''):gsub('%s+$', '');
    if (#name == 0) then
        return nil, 'No profile name given.';
    end
    if (#name > 40) then
        return nil, 'Profile names are limited to 40 characters.';
    end
    if (not name:match('^[%w _%-]+$')) then
        return nil, 'Profile names may only contain letters, numbers, spaces, hyphens and underscores.';
    end
    if (name:sub(1, 1) == '_') and (not allowInternal) then
        return nil, 'Names starting with an underscore are reserved.';
    end
    if (ReservedNames[string.lower(name)]) then
        return nil, 'That name is reserved by Windows -- pick another.';
    end
    return name;
end

local function GetDirectory()
    return string.format('%sconfig/addons/%s/profiles', AshitaCore:GetInstallPath(), addon.name);
end

local function GetPath(name)
    return string.format('%s/%s.lua', GetDirectory(), name);
end

local function EnsureDirectory()
    --Parent first, then the profiles folder itself -- create_dir isn't
    --confirmed to create intermediate folders, and the parent is only
    --guaranteed to exist once the main settings file has been saved once.
    local root = string.format('%sconfig/addons/%s', AshitaCore:GetInstallPath(), addon.name);
    for _,dir in ipairs({ root, GetDirectory() }) do
        if (not ashita.fs.exists(dir)) then
            pcall(ashita.fs.create_dir, dir);
        end
    end
    return ashita.fs.exists(GetDirectory()) == true;
end

------------------------------------------------------------
-- Serialization (Lua table literal, deterministic key order)
------------------------------------------------------------
local LuaKeywords = {
    ['and'] = true, ['break'] = true, ['do'] = true, ['else'] = true,
    ['elseif'] = true, ['end'] = true, ['false'] = true, ['for'] = true,
    ['function'] = true, ['if'] = true, ['in'] = true, ['local'] = true,
    ['nil'] = true, ['not'] = true, ['or'] = true, ['repeat'] = true,
    ['return'] = true, ['then'] = true, ['true'] = true, ['until'] = true,
    ['while'] = true,
};

local function IsIdentifier(s)
    return (type(s) == 'string') and (s:match('^[%a_][%w_]*$') ~= nil) and (not LuaKeywords[s]);
end

--Returns the literal text for value, or nil if it can't/shouldn't be saved
--(functions, userdata, NaN/inf, anything nested past MaxDepth).
local function Serialize(value, depth)
    local t = type(value);
    if (t == 'number') then
        if (value ~= value) or (value == math.huge) or (value == -math.huge) then
            return nil;
        end
        if (value == math.floor(value)) and (math.abs(value) < 1e15) then
            return string.format('%d', value);
        end
        return string.format('%.14g', value);
    elseif (t == 'boolean') then
        return tostring(value);
    elseif (t == 'string') then
        return string.format('%q', value);
    elseif (t ~= 'table') or (depth > MaxDepth) then
        return nil;
    end

    local count = 0;
    for _ in pairs(value) do
        count = count + 1;
    end
    if (count == 0) then
        return '{}';
    end

    local pad = string.rep('    ', depth + 1);
    local closePad = string.rep('    ', depth);
    local lines = {};

    if (#value == count) then
        for i = 1,count do
            local s = Serialize(value[i], depth + 1);
            if (s ~= nil) then
                lines[#lines + 1] = pad .. s .. ',';
            end
        end
    else
        local keys = {};
        for k in pairs(value) do
            if (type(k) == 'string') or (type(k) == 'number') then
                keys[#keys + 1] = k;
            end
        end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b);
            if (ta ~= tb) then
                return ta == 'number';
            end
            return a < b;
        end);
        for _,k in ipairs(keys) do
            local s = Serialize(value[k], depth + 1);
            if (s ~= nil) then
                local keyText;
                if (type(k) == 'number') then
                    keyText = string.format('[%s]', Serialize(k, depth + 1));
                elseif (IsIdentifier(k)) then
                    keyText = k;
                else
                    keyText = string.format('[%q]', k);
                end
                lines[#lines + 1] = string.format('%s%s = %s,', pad, keyText, s);
            end
        end
    end

    if (#lines == 0) then
        return '{}';
    end
    return '{\n' .. table.concat(lines, '\n') .. '\n' .. closePad .. '}';
end

------------------------------------------------------------
-- Reading
------------------------------------------------------------
local function ReadFile(path)
    local f = io.open(path, 'rb');
    if (not f) then
        return nil, 'Could not open the profile file.';
    end
    local size = f:seek('end');
    if (size) and (size > MaxFileBytes) then
        f:close();
        return nil, 'That profile file is too large to be a BuffTrack profile.';
    end
    f:seek('set', 0);
    local text = f:read('*a');
    f:close();
    return text;
end

--Returns the parsed profile table, or nil + a user-facing reason.
local function ReadProfile(name, allowInternal)
    local clean, err = CleanName(name, allowInternal);
    if (not clean) then
        return nil, err;
    end
    local path = GetPath(clean);
    if (not ashita.fs.exists(path)) then
        return nil, string.format('No profile named "%s".', clean);
    end

    local text, readErr = ReadFile(path);
    if (not text) then
        return nil, readErr;
    end
    if (text:byte(1) == 27) then
        return nil, 'That file contains compiled code, not a profile -- refusing to load it.';
    end

    local chunk, parseErr = loadstring(text, '=profile');
    if (not chunk) then
        return nil, string.format('Profile "%s" is damaged (%s).', clean, tostring(parseErr));
    end
    --Empty environment: the chunk can construct a table and nothing else
    --(no require, no io, no os, no globals at all).
    setfenv(chunk, {});
    local ok, result = pcall(chunk);
    if (not ok) or (type(result) ~= 'table') then
        return nil, string.format('Profile "%s" is damaged.', clean);
    end
    if (result.Format ~= FormatVersion) then
        return nil, string.format('Profile "%s" was saved in an unsupported format.', clean);
    end
    if (type(result.Settings) ~= 'table') then
        return nil, string.format('Profile "%s" has no settings in it.', clean);
    end
    return result;
end

------------------------------------------------------------
-- Applying
------------------------------------------------------------
local function DeepCopy(v, depth)
    if (type(v) ~= 'table') then
        return v;
    end
    depth = depth or 0;
    if (depth > MaxDepth) then
        return nil;
    end
    local out = {};
    for k,val in pairs(v) do
        out[k] = DeepCopy(val, depth + 1);
    end
    return out;
end

--Writes profile.Settings into the live gSettings, key by key. Returns a
--(possibly empty) warning suffix describing anything that was skipped.
local function Apply(profile)
    local skipped = {};
    local dropped = 0;

    local function ApplyKey(key)
        local expected = Schema[key];
        local value = profile.Settings[key];

        --Missing from the file (older profile, hand-edited): fall back to
        --the shipped default so a profile always fully defines its keys.
        if (value == nil) then
            local default = DeepCopy(gDefaultSettings[key]);
            if (expected == 'array') then
                default = T(default or {});
            end
            gSettings[key] = default;
            return;
        end

        local ok = false;
        if (expected == 'array') then
            if (type(value) == 'table') then
                local kept = {};
                for _,entry in ipairs(value) do
                    if (type(entry) == 'table') and (EntryValidators[key](entry)) then
                        kept[#kept + 1] = entry;
                    else
                        dropped = dropped + 1;
                    end
                end
                value = T(kept);
                ok = true;
            end
        elseif (expected == 'table') then
            ok = (type(value) == 'table') and ((TableValidators[key] == nil) or (TableValidators[key](value) == true));
        else
            ok = (type(value) == expected);
            if (ok) and (expected == 'number') then
                local range = NumberRanges[key];
                if (value ~= value) or (range ~= nil and (value < range[1] or value > range[2])) then
                    ok = false;
                end
            end
            if (ok) and (key == 'GridGroupBy') and (value ~= 'Buff') and (value ~= 'Player') then
                ok = false;
            end
        end

        if (ok) then
            gSettings[key] = value;
        else
            skipped[#skipped + 1] = key;
        end
    end

    for _,groupName in ipairs(GroupOrder) do
        --Layout only applies if the profile was saved WITH positions;
        --otherwise the current positions are left exactly as they are.
        if (groupName ~= 'Layout') or (profile.IncludesPositions == true) then
            for _,key in ipairs(KeyGroups[groupName]) do
                ApplyKey(key);
            end
        end
    end

    settings.save();

    --A profile saved before the Cures defaults had finished seeding (empty
    --CureMap, CureMapSeeded=false) would leave the Cures list empty for the
    --rest of the session: trackers/curable.lua only seeds once per session.
    --Its own reset re-arms that, so the defaults appear on the next tick.
    if (#gSettings.CureMap == 0) and (not gSettings.CureMapSeeded) then
        pcall(function() require('trackers.curable').ResetCureMapToDefaults(); end);
    end

    --Panels keep a working copy of their position (see
    --initializer.lua's RefreshPanelsFromSettings) -- re-sync it, and tear
    --down per-player panels so they rebuild from the new settings.
    if (RefreshPanelsFromSettings ~= nil) then
        pcall(RefreshPanelsFromSettings);
    end

    local notes = {};
    if (dropped > 0) then
        notes[#notes + 1] = string.format('%u invalid entr%s dropped', dropped, (dropped == 1) and 'y' or 'ies');
    end
    if (#skipped > 0) then
        notes[#notes + 1] = string.format('skipped invalid setting%s: %s', (#skipped == 1) and '' or 's', table.concat(skipped, ', '));
    end
    if (#notes == 0) then
        return '';
    end
    return ' (' .. table.concat(notes, '; ') .. ')';
end

------------------------------------------------------------
-- Public API -- every call returns ok(bool), message(string)
------------------------------------------------------------
exports.GetDirectory = GetDirectory;

--Saved profile names (hidden internal ones excluded), sorted.
function exports:List()
    local names = {};
    local ok, files = pcall(ashita.fs.get_dir, GetDirectory(), '.*.lua', false);
    if (ok) and (type(files) == 'table') then
        for _,file in ipairs(files) do
            local base = tostring(file):match('([^/\\]+)%.[Ll][Uu][Aa]$');
            if (base) and (base:sub(1, 1) ~= '_') then
                names[#names + 1] = base;
            end
        end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b); end);
    return names;
end

function exports:HasUndo()
    return ashita.fs.exists(GetPath(PreviousName)) == true;
end

--Third return value (Save only): the cleaned name actually used.
function exports:Save(name, includePositions, internal)
    local clean, err = CleanName(name, internal);
    if (not clean) then
        return false, err;
    end
    if (not EnsureDirectory()) then
        return false, 'Could not create the profiles folder.';
    end

    local data = {
        Format = FormatVersion,
        Name = clean,
        Saved = os.date('%Y-%m-%d %H:%M:%S'),
        BuffTrackVersion = addon.version,
        IncludesPositions = includePositions and true or false,
        Settings = {},
    };
    for _,groupName in ipairs(GroupOrder) do
        if (groupName ~= 'Layout') or (data.IncludesPositions) then
            for _,key in ipairs(KeyGroups[groupName]) do
                if (gSettings[key] ~= nil) then
                    data.Settings[key] = gSettings[key];
                end
            end
        end
    end

    local text = Serialize(data, 0);
    if (text == nil) then
        return false, 'Could not serialize the current settings.';
    end

    local path = GetPath(clean);
    local existed = ashita.fs.exists(path) == true;
    local f, openErr = io.open(path, 'wb');
    if (not f) then
        return false, string.format('Could not write the profile file (%s).', tostring(openErr));
    end
    f:write('-- BuffTrack profile. Safe to copy/rename/edit; loaded in a sandbox (data only).\nreturn ', text, '\n');
    f:close();

    return true, string.format('%s profile "%s".', existed and 'Overwrote' or 'Saved', clean), clean;
end

--allowInternal lets Undo load the hidden "_previous" snapshot.
function exports:Load(name, allowInternal)
    --Read FIRST: the undo snapshot below overwrites _previous, which would
    --clobber the very file being loaded when this IS the undo.
    local profile, err = ReadProfile(name, allowInternal);
    if (not profile) then
        return false, err;
    end

    local snapshotOk = self:Save(PreviousName, true, true);
    local warnings = Apply(profile);

    local message;
    if (allowInternal) and (string.lower(tostring(name)) == PreviousName) then
        message = 'Restored your setup from before the last profile load';
    else
        message = string.format('Loaded profile "%s"', tostring(profile.Name or name));
    end
    message = message .. warnings .. '.';
    if (not snapshotOk) then
        message = message .. ' (Could not save an undo snapshot first.)';
    end
    return true, message;
end

function exports:Undo()
    if (not self:HasUndo()) then
        return false, 'Nothing to undo.';
    end
    return self:Load(PreviousName, true);
end

function exports:Delete(name)
    local clean, err = CleanName(name, false);
    if (not clean) then
        return false, err;
    end
    local path = GetPath(clean);
    if (not ashita.fs.exists(path)) then
        return false, string.format('No profile named "%s".', clean);
    end
    local removed, removeErr = os.remove(path);
    if (not removed) then
        return false, string.format('Could not delete "%s" (%s).', clean, tostring(removeErr));
    end
    return true, string.format('Deleted profile "%s".', clean);
end

return exports;
