--[[
    libs/uiskin.lua

    Config window theme (dark, cool-tinted, deep-blue accent) plus job icon
    helpers.

    The whole palette is derived from ONE accent color (ACCENT_HEX below):
    its hue is extracted and every other shade is generated from that hue at
    load, so re-theming means changing a single number. The raw accent is
    deliberately dark, so it is only used as a FILL (selected tab, active
    title bar, pressed button). Text, check marks and other small accents use
    a lighter tint of the same hue (accentBright/accentMid) -- the raw accent
    on the dark window background has a contrast ratio of only ~1.3:1 and
    would be invisible there.
]]--

local exports = {};
local imgui = require('imgui');
local ffi = require('ffi');

--The one input to the theme: 0xRRGGBB.
local ACCENT_HEX = 0x070980;

local function HexToRGB(hex)
    return { math.floor(hex / 65536) % 256 / 255, math.floor(hex / 256) % 256 / 255, hex % 256 / 255 };
end

--Hue only (0-1) -- saturation/value are chosen per shade below.
local function RGBToHue(c)
    local r, g, b = c[1], c[2], c[3];
    local mx, mn = math.max(r, g, b), math.min(r, g, b);
    local d = mx - mn;
    if (d == 0) then
        return 0;
    end
    local h;
    if (mx == r) then
        h = ((g - b) / d) % 6;
    elseif (mx == g) then
        h = ((b - r) / d) + 2;
    else
        h = ((r - g) / d) + 4;
    end
    return h / 6;
end

--h, s, v in 0-1 -> { r, g, b, a }.
local function HSV(h, s, v, a)
    local scaled = h * 6;
    local i = math.floor(scaled);
    local f = scaled - i;
    local p = v * (1 - s);
    local q = v * (1 - (f * s));
    local t = v * (1 - ((1 - f) * s));
    local r, g, b;
    i = i % 6;
    if (i == 0) then r, g, b = v, t, p;
    elseif (i == 1) then r, g, b = q, v, p;
    elseif (i == 2) then r, g, b = p, v, t;
    elseif (i == 3) then r, g, b = p, q, v;
    elseif (i == 4) then r, g, b = t, p, v;
    else r, g, b = v, p, q;
    end
    return { r, g, b, a or 1.0 };
end

--Palette, all generated from ACCENT_HEX's hue.
local rawAccent = HexToRGB(ACCENT_HEX);
local hue = RGBToHue(rawAccent);

local accent       = { rawAccent[1], rawAccent[2], rawAccent[3], 1.0 }; --fills only
local accentBright = HSV(hue, 0.38, 1.00);  --text accents, check marks
local accentMid    = HSV(hue, 0.55, 0.90);  --disabled text, slider grab
local accentDim    = HSV(hue, 0.80, 0.65);  --hover fills
local bgDark       = HSV(hue, 0.30, 0.07, 0.95);
local bgMedium     = HSV(hue, 0.28, 0.11);
local bgLight      = HSV(hue, 0.26, 0.16);
local bgLighter    = HSV(hue, 0.24, 0.22);
local borderColor  = HSV(hue, 0.35, 0.42);
local textColor    = HSV(hue, 0.05, 0.92);
local gripColor    = HSV(hue, 0.80, 0.65, 0.50);

--Exposed so config.lua can reuse the exact accent for
--imgui.TextColored(...) section headers -- one source of truth for "the
--accent color".
exports.HeaderColor = accentBright;
exports.TextColor = textColor;

--Job icon sets shipped in resources/jobs/<style>/<abbr>.png.
--Used by config.lua's Behavior tab picker.
exports.JobIconStyles = { 'Role', 'Outline' };
exports.DefaultJobIconStyle = 'Role';

--Maps any saved style name (including one from an older version whose icon
--set no longer ships) onto a style that exists.
function exports:ResolveJobIconStyle(style)
    for _,name in ipairs(self.JobIconStyles) do
        if (name == style) then
            return style;
        end
    end
    return self.DefaultJobIconStyle;
end

--Running counts of how many pushes ACTUALLY succeeded this call to
--PushTheme -- PopTheme pops exactly these counts, never a hardcoded
--number, so a partial failure (some colors/vars push fine, others don't)
--can never leave ImGui's style stack unbalanced. Module-level, not
--per-call-local, since PopTheme needs to read what PushTheme last wrote.
local pushedColorCount = 0;
local pushedVarCount = 0;

--Safe wrapper around a single PushStyleColor/PushStyleVar call, so one
--rejected enum/value can't throw out of PushTheme and unload the addon.
--Reports the real error text once per distinct label (not once total, and
--not every frame), so several different failing pushes are each visible
--without spamming the chat log.
local warnedLabels = {};
local function TryPush(label, fn, a, b)
    local ok, err = pcall(fn, a, b);
    if (not ok) and (not warnedLabels[label]) then
        warnedLabels[label] = true;
        Error(string.format('BuffTrack: theme push failed for %s (%s) -- that element will use its default ImGui color/value instead of the theme.', label, tostring(err)));
    end
    return ok;
end

--Pushes the full theme -- MUST be paired with a PopTheme() call, always,
--even on an early-out path (same always-call-End() reasoning as
--imgui.End()). Call this BEFORE SetNextWindowSize/Begin.
function exports:PushTheme()
    pushedColorCount = 0;
    pushedVarCount = 0;

    --NOTE: ChildBg/FrameBg*/Header* are deliberately NOT themed here -- the
    --Buffs tab's spell list is built from exactly those widget groups
    --(Selectable, InputText, BeginChild), and an earlier theme pass that
    --touched them broke that list. They stay at ImGui's defaults until
    --they're added back one group at a time and tested.
    local colors = {
        --Window chrome
        { 'WindowBg', ImGuiCol_WindowBg, bgDark },
        { 'PopupBg', ImGuiCol_PopupBg, bgMedium },
        { 'Border', ImGuiCol_Border, borderColor },
        { 'Separator', ImGuiCol_Separator, borderColor },
        { 'TitleBg', ImGuiCol_TitleBg, bgMedium },
        { 'TitleBgActive', ImGuiCol_TitleBgActive, accent },
        { 'TitleBgCollapsed', ImGuiCol_TitleBgCollapsed, bgDark },
        --Text
        { 'Text', ImGuiCol_Text, textColor },
        { 'TextDisabled', ImGuiCol_TextDisabled, accentMid },
        --Buttons / inputs
        { 'Button', ImGuiCol_Button, bgLight },
        { 'ButtonHovered', ImGuiCol_ButtonHovered, accentDim },
        { 'ButtonActive', ImGuiCol_ButtonActive, accent },
        { 'CheckMark', ImGuiCol_CheckMark, accentBright },
        { 'SliderGrab', ImGuiCol_SliderGrab, accentMid },
        { 'SliderGrabActive', ImGuiCol_SliderGrabActive, accentBright },
        --Scrollbars
        { 'ScrollbarBg', ImGuiCol_ScrollbarBg, bgMedium },
        { 'ScrollbarGrab', ImGuiCol_ScrollbarGrab, bgLighter },
        { 'ScrollbarGrabHovered', ImGuiCol_ScrollbarGrabHovered, borderColor },
        { 'ScrollbarGrabActive', ImGuiCol_ScrollbarGrabActive, accentDim },
        --Tabs. Dear ImGui v1.90.9 renamed TabActive->TabSelected,
        --TabUnfocused->TabDimmed, TabUnfocusedActive->TabDimmedSelected;
        --the new names are the ones that resolve in this environment.
        { 'Tab', ImGuiCol_Tab, bgMedium },
        { 'TabHovered', ImGuiCol_TabHovered, accentDim },
        { 'TabSelected', ImGuiCol_TabSelected, accent },
        { 'TabDimmed', ImGuiCol_TabDimmed, bgDark },
        { 'TabDimmedSelected', ImGuiCol_TabDimmedSelected, bgLight },
        --Resize grip
        { 'ResizeGrip', ImGuiCol_ResizeGrip, gripColor },
        { 'ResizeGripHovered', ImGuiCol_ResizeGripHovered, accentMid },
        { 'ResizeGripActive', ImGuiCol_ResizeGripActive, accentBright },
    };
    for _,c in ipairs(colors) do
        if (TryPush('Color:' .. c[1], imgui.PushStyleColor, c[2], c[3])) then
            pushedColorCount = pushedColorCount + 1;
        end
    end

    local vars = {
        { 'WindowPadding', ImGuiStyleVar_WindowPadding, { 10, 10 } },
        { 'FramePadding', ImGuiStyleVar_FramePadding, { 5, 3 } },
        { 'ItemSpacing', ImGuiStyleVar_ItemSpacing, { 6, 5 } },
        { 'WindowRounding', ImGuiStyleVar_WindowRounding, 3.0 },
        { 'ChildRounding', ImGuiStyleVar_ChildRounding, 2.0 },
        { 'FrameRounding', ImGuiStyleVar_FrameRounding, 2.0 },
        { 'PopupRounding', ImGuiStyleVar_PopupRounding, 2.0 },
        { 'ScrollbarRounding', ImGuiStyleVar_ScrollbarRounding, 2.0 },
        { 'GrabRounding', ImGuiStyleVar_GrabRounding, 2.0 },
    };
    for _,v in ipairs(vars) do
        if (TryPush('Var:' .. v[1], imgui.PushStyleVar, v[2], v[3])) then
            pushedVarCount = pushedVarCount + 1;
        end
    end
end

--Pops EXACTLY as many as PushTheme actually pushed this time -- never a
--hardcoded count -- so a partial push failure can't unbalance ImGui's
--style stack.
function exports:PopTheme()
    if (pushedVarCount > 0) then
        imgui.PopStyleVar(pushedVarCount);
    end
    if (pushedColorCount > 0) then
        imgui.PopStyleColor(pushedColorCount);
    end
end

--Texture loads are cached by gTextureCache itself (keyed by path); this is
--just a safe wrapper so a missing file degrades to "draw nothing" rather
--than erroring.
local function LoadTexture(path)
    local ok, texture = pcall(function() return gTextureCache:GetTexture(path); end);
    if (ok) then
        return texture;
    end
    return nil;
end

--Converts a raw D3D texture handle into the numeric texture id
--draw_list:AddImage expects.
local function ToTextureId(textureHandle)
    if (textureHandle == nil) then
        return nil;
    end
    local ok, id = pcall(function() return tonumber(ffi.cast('uint32_t', textureHandle)); end);
    if (ok) then
        return id;
    end
    return nil;
end

--Job icon for the current gSettings.JobIconStyle (or an explicit override,
--for a style picker's own preview). jobAbbr is the 3-letter code (e.g.
--'WAR') -- files are lowercase (resources/jobs/<style>/war.png etc), so
--this lowercases for the lookup. Returns nil if the job/style/file
--doesn't resolve to anything -- callers should skip drawing an icon
--rather than treat nil as an error.
function exports:GetJobIcon(jobAbbr, styleOverride)
    if (jobAbbr == nil) then
        return nil;
    end
    local style = self:ResolveJobIconStyle(styleOverride or gSettings.JobIconStyle);
    return LoadTexture(string.format('jobs/%s/%s.png', style, string.lower(jobAbbr)));
end

--Draws an arbitrary loaded texture inline in normal ImGui widget flow --
--e.g. `imgui.SameLine(); uiskin:DrawInlineIcon(tex, 32, 32);`. Uses
--draw_list:AddImage (absolute screen coordinates; imgui.Image does not
--take the texture-id format used here) and manually advances the layout
--cursor afterward via a same-sized Dummy, since AddImage never touches
--layout on its own -- so subsequent SameLine()/normal layout calls behave
--as if a regular widget had been drawn.
function exports:DrawInlineIcon(texture, width, height)
    if (texture == nil) then
        return;
    end
    local id = ToTextureId(texture);
    if (id == nil) then
        return;
    end
    local ok, screenX, screenY = pcall(imgui.GetCursorScreenPos);
    if (not ok) or (type(screenX) ~= 'number') then
        return;
    end
    pcall(function()
        local draw_list = imgui.GetWindowDrawList();
        draw_list:AddImage(id, { screenX, screenY }, { screenX + width, screenY + height }, { 0, 0 }, { 1, 1 }, IM_COL32_WHITE);
    end);
    pcall(imgui.Dummy, { width, height });
end

return exports;
