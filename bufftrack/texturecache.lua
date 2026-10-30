--[[
    texturecache.lua

    Loads D3D textures on demand and keeps them, so the same icon isn't
    re-read every frame. Callers ask by key:

        'ITEM:<id>'    an item icon from the game's resources
        'STATUS:<id>'  a status-effect icon from the game's resources
        anything else  an image file, resolved through helpers.lua's
                       GetImagePath

    GetTexture returns { Texture, Width, Height }, or nil if it can't be
    loaded.
]]--

local d3d8 = require('d3d8');
local ffi = require('ffi');

local device = d3d8.get_device();

local cache = { Entries = {} };

--Wraps a freshly created texture pointer with its dimensions.
local function Describe(texturePtr)
    local texture = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', texturePtr[0]));
    local result, desc = texture:GetLevelDesc(0);
    if (result ~= 0) then
        return nil;
    end
    return { Texture = texture, Width = desc.Width, Height = desc.Height };
end

--Texture from an image held in memory (the game's icon bitmaps).
local function FromMemory(bitmap, size)
    local out = ffi.new('IDirect3DTexture8*[1]');
    local status = ffi.C.D3DXCreateTextureFromFileInMemoryEx(
        device, bitmap, size,
        0xFFFFFFFF, 0xFFFFFFFF,       --width/height: take them from the image
        1, 0,                         --one mip level, no usage flags
        ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED,
        ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT,
        0xFF000000,                   --black is the transparent color key
        nil, nil, out);
    if (status ~= ffi.C.S_OK) then
        return nil;
    end
    return Describe(out);
end

--Texture from an image file on disk.
local function FromFile(path)
    local out = ffi.new('IDirect3DTexture8*[1]');
    if (ffi.C.D3DXCreateTextureFromFileA(device, path, out) ~= ffi.C.S_OK) then
        return nil;
    end
    return Describe(out);
end

local function LoadItemIcon(itemId)
    local item = AshitaCore:GetResourceManager():GetItemById(itemId);
    if (item == nil) then
        return nil;
    end
    return FromMemory(item.Bitmap, item.ImageSize);
end

local function LoadStatusIcon(statusId)
    local icon = AshitaCore:GetResourceManager():GetStatusIconByIndex(statusId);
    if (icon == nil) then
        return nil;
    end
    return FromMemory(icon.Bitmap, -1);
end

--Prefix -> loader for resource-backed icons.
local iconLoaders = {
    ITEM = LoadItemIcon,
    STATUS = LoadStatusIcon,
};

function cache:GetTexture(key)
    local entry = self.Entries[key];
    if (entry ~= nil) then
        return entry;
    end

    local kind, argument = key:match('^(%u+):(%d+)$');
    if (kind ~= nil) and (iconLoaders[kind] ~= nil) then
        entry = iconLoaders[kind](tonumber(argument));
    elseif (kind == nil) then
        local path = GetImagePath(key);
        if (path ~= nil) then
            entry = FromFile(path);
        end
    end

    self.Entries[key] = entry;
    return entry;
end

function cache:Clear()
    self.Entries = {};
end

return cache;
