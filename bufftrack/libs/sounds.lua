--[[
    libs/sounds.lua

    Audio-cue playback for BuffTrack's alerts.

    Volume control (gSettings.AlarmVolume, 0-100) is done in software: each
    sound's PCM samples are scaled by a gain factor, and the scaled WAV image
    is handed to the Windows PlaySound API straight from memory (winmm).
    No audio device or COM objects are created, so there is nothing to set
    up per window and nothing to release on unload beyond the cached images.

    Only one cue plays at a time: starting a new one cuts off the previous
    one. That suits alerts (the newest one is the one that matters).

    Falls back to ashita.misc.play_sound (system volume, no attenuation) if
    winmm can't be loaded or a file isn't plain 8/16-bit PCM.

    File resolution goes through helpers.lua's GetFilePath (this project's
    resource-path convention -- see texturecache.lua's GetImagePath usage).
]]--

require('common');
local chat = require('chat');
local ffi  = require('ffi');

--Wrapped in pcall so a duplicate declaration from another module can never
--stop the addon from loading.
pcall(ffi.cdef, [[
int __stdcall PlaySoundA(const char* pszSound, void* hmod, uint32_t fdwSound);
]]);

local winmm;
do
    local ok, lib = pcall(ffi.load, 'winmm');
    if (ok) then
        winmm = lib;
    end
end

local SND_ASYNC     = 0x0001; --return immediately, play in the background
local SND_NODEFAULT = 0x0002; --stay silent rather than beep if playback fails
local SND_MEMORY    = 0x0004; --the first argument is a WAV image, not a path
local PLAY_FLAGS    = SND_ASYNC + SND_NODEFAULT + SND_MEMORY;

------------------------------------------------------------
-- WAV handling
------------------------------------------------------------

--Little-endian unsigned integer of n bytes starting at 1-based position pos.
local function ReadLE(s, pos, n)
    local value = 0;
    for i = n - 1, 0, -1 do
        value = (value * 256) + s:byte(pos + i);
    end
    return value;
end

--Walks the RIFF chunks of a WAV file image. Returns bitsPerSample, the
--0-based byte offset of the sample data inside the image, and the sample
--data's length in bytes -- or nil if this isn't plain integer PCM.
local function LocatePcm(wav)
    if (#wav < 12) or (wav:sub(1, 4) ~= 'RIFF') or (wav:sub(9, 12) ~= 'WAVE') then
        return nil;
    end

    local pos = 13;
    local formatTag, bits;
    while ((pos + 7) <= #wav) do
        local id = wav:sub(pos, pos + 3);
        local size = ReadLE(wav, pos + 4, 4);
        if (id == 'fmt ') and (size >= 16) then
            formatTag = ReadLE(wav, pos + 8, 2);
            bits = ReadLE(wav, pos + 22, 2);
        elseif (id == 'data') then
            if (formatTag ~= 1) or (bits == nil) then
                return nil;
            end
            local start = pos + 7;
            return bits, start, math.min(size, #wav - start);
        end
        pos = pos + 8 + size + (size % 2); --chunks are padded to even sizes
    end
    return nil;
end

--Returns a fresh in-memory copy of the WAV with its samples scaled for the
--given volume (0-100). Gain is volume squared, which tracks perceived
--loudness better than a straight linear scale.
local function BuildImage(wav, volume)
    local image = ffi.new('uint8_t[?]', #wav);
    ffi.copy(image, wav, #wav);

    local gain = (volume / 100) ^ 2;
    local bits, start, length = LocatePcm(wav);
    if (bits == 16) then
        local samples = ffi.cast('int16_t*', image + start);
        for i = 0, math.floor(length / 2) - 1 do
            samples[i] = math.floor(samples[i] * gain);
        end
    elseif (bits == 8) then
        --8-bit WAV samples are unsigned, centered on 128.
        for i = start, start + length - 1 do
            image[i] = math.floor(128 + ((image[i] - 128) * gain) + 0.5);
        end
    end
    --Any other format is left unscaled (it still plays, just at full level).

    return image;
end

------------------------------------------------------------
-- Public sounds module
------------------------------------------------------------
local sounds = {};

--Matches whatever .wav files actually ship in resources/Sounds/ (note the
--capital S -- GetFilePath below is case-sensitive on the filesystems that
--matter here).
sounds.Available = {
    { id = 'chime',    label = 'Chime',       file = 'chime.wav'    },
    { id = 'bell',     label = 'Bell',        file = 'bell.wav'     },
    { id = 'bellx2',   label = 'Double Bell', file = 'bellx2.wav'   },
    { id = 'alert',    label = 'Alert Beep',  file = 'alert.wav'    },
    { id = 'alarm',    label = 'Alarm',       file = 'alarm.wav'    },
    { id = 'eggtimer', label = 'Egg Timer',   file = 'eggtimer.wav' },
    { id = 'ping',     label = 'Ping',        file = 'ping.wav'     },
};

sounds._paths   = {};  --sound id -> filesystem path (also the fallback player's input)
sounds._entries = {};  --sound id -> { Wav = raw file bytes, Image = scaled copy, Volume = volume Image was built for }
sounds._playing = nil; --the image most recently handed to PlaySound

--Called once at addon load (see initializer.lua). Resolves every Available
--entry's path and reads its file into memory, so missing-file warnings show
--up immediately rather than at a random moment mid-session.
function sounds:Initialize()
    for _,s in ipairs(self.Available) do
        local path = GetFilePath('Sounds/' .. s.file);
        self._paths[s.id] = path;
        if not path then
            print(chat.header(addon.name) .. chat.message('Sound missing: resources/Sounds/' .. s.file));
        else
            local f = io.open(path, 'rb');
            local wav = f and f:read('*all');
            if f then
                f:close();
            end
            if (wav) and (#wav > 0) then
                self._entries[s.id] = { Wav = wav };
            else
                print(chat.header(addon.name) .. chat.message('Sound unreadable: resources/Sounds/' .. s.file));
            end
        end
    end

    if not winmm then
        print(chat.header(addon.name) .. chat.message('winmm unavailable -- volume control disabled, using system audio.'));
    end
end

--Plays sound_id (an Available[].id) at gSettings.AlarmVolume. Silent no-op
--for an unknown id, a missing file, or AlarmVolume<=0 (muted) -- never
--errors out into the caller, since a bad sound choice shouldn't take down
--whatever tracker triggered it.
function sounds:Play(sound_id)
    local volume = (gSettings and gSettings.AlarmVolume) or 100;
    if (volume <= 0) then
        return;
    end
    volume = math.min(volume, 100);

    local entry = self._entries[sound_id];
    if (entry) and (winmm) then
        --Rebuilt only when the volume setting changed since last time.
        if (entry.Volume ~= volume) then
            entry.Image = BuildImage(entry.Wav, volume);
            entry.Volume = volume;
        end

        --The image must stay alive while it plays in the background, so
        --it's held in self._playing until the next sound replaces it.
        local ok, result = pcall(winmm.PlaySoundA, ffi.cast('const char*', entry.Image), nil, PLAY_FLAGS);
        if (ok) and (result ~= 0) then
            self._playing = entry.Image;
            return;
        end
    end

    local path = self._paths[sound_id];
    if path then
        pcall(ashita.misc.play_sound, path);
    end
end

function sounds:GetLabel(sound_id)
    for _,s in ipairs(self.Available) do
        if (s.id == sound_id) then
            return s.label;
        end
    end
    return sound_id;
end

function sounds:Cleanup()
    --Stop anything still playing from memory before the buffer goes away.
    if (winmm) then
        pcall(winmm.PlaySoundA, nil, nil, 0);
    end
    self._playing = nil;
    self._entries = {};
end

return sounds;
