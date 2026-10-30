--[[
    helpers.lua

    Bootstrap helpers required by bufftrack.lua: chat output (Message /
    Error), resource-path lookup (GetFilePath / GetImagePath) and
    SnapPosition (panel snap-to-align, see below).

    Chat text can mark a highlighted span with braces: the text between
    { and } is drawn in the highlight color, e.g.
        Message(string.format('Now tracking {%s}.', name));
]]--

local chat = require('chat');

--FFXI chat color codes.
local COLOR_INFO      = 106;
local COLOR_ERROR     = 68;
local COLOR_HIGHLIGHT = 2;

local LOG_LEVEL_ERROR = 1;
local LOG_LEVEL_INFO  = 5;

--Turns "plain {highlighted} plain" into one chat string with the matching
--color codes, ending with a reset.
local function Colorize(text, baseColor)
    local pieces = {};
    local color = baseColor;
    local position = 1;
    while (position <= #text) do
        local braceStart, braceEnd = text:find('[{}]', position);
        local chunkEnd = (braceStart or (#text + 1)) - 1;
        if (chunkEnd >= position) then
            pieces[#pieces + 1] = ('\30%c'):format(color) .. text:sub(position, chunkEnd);
        end
        if (braceStart == nil) then
            break;
        end
        color = (text:sub(braceStart, braceStart) == '{') and COLOR_HIGHLIGHT or baseColor;
        position = braceEnd + 1;
    end
    return table.concat(pieces) .. '\30\01';
end

local function Say(text, baseColor, logLevel)
    LogManager:Log(logLevel, addon.name, (text:gsub('[{}]', '')));
    print(chat.header(addon.name) .. Colorize(text, baseColor));
end

function Message(text)
    Say(text, COLOR_INFO, LOG_LEVEL_INFO);
end

function Error(text)
    Say(text, COLOR_ERROR, LOG_LEVEL_ERROR);
end

--Finds a bundled resource: the path as given, then the user's config copy,
--then the addon's own resources folder. Returns nil if none exist.
local function ResolveResource(relativePath)
    if (relativePath == nil) or (relativePath == '') then
        return nil;
    end

    local installPath = AshitaCore:GetInstallPath();
    local candidates = {
        relativePath,
        string.format('%sconfig/addons/%s/resources/%s', installPath, addon.name, relativePath),
        string.format('%saddons/%s/resources/%s', installPath, addon.name, relativePath),
    };
    for _,candidate in ipairs(candidates) do
        if (ashita.fs.exists(candidate)) then
            return candidate;
        end
    end
    return nil;
end

function GetFilePath(path)
    return ResolveResource(path);
end

--Image keys of the form ITEM:<id> / STATUS:<id> name game resources, not
--files, and pass through untouched for texturecache.lua to handle.
function GetImagePath(image)
    if (image:find('^ITEM:')) or (image:find('^STATUS:')) then
        return image;
    end
    return ResolveResource(image);
end

--[[
    Snaps a moving panel's top-left position to the edges of another
    panel's bounds, when the gap between them is within `distance` pixels.
    Checks X and Y independently -- either, both, or neither axis may snap
    on a given call. Snap candidates per axis: aligned edges (left-to-left,
    right-to-right) and adjacency (left-to-right, right-to-left), same
    convention as OS-level window snapping. Shared by GridGroup and
    AlertsGroup (see gridgroup.lua/alertsgroup.lua's HandleMouse) rather
    than duplicated, since both need the identical check just against each
    other's bounds.

    myBounds/otherBounds(table) - { X, Y, Width, Height }, top-left + size.
    distance(number)            - max gap, in screen pixels, still "close".

    Returns the (possibly adjusted) X, Y for myBounds' top-left.
]]--
function SnapPosition(myBounds, otherBounds, distance)
    local x, y = myBounds.X, myBounds.Y;
    local myRight, myBottom = myBounds.X + myBounds.Width, myBounds.Y + myBounds.Height;
    local otherRight, otherBottom = otherBounds.X + otherBounds.Width, otherBounds.Y + otherBounds.Height;

    if (math.abs(myBounds.X - otherBounds.X) <= distance) then
        x = otherBounds.X;
    elseif (math.abs(myRight - otherBounds.X) <= distance) then
        x = otherBounds.X - myBounds.Width;
    elseif (math.abs(myBounds.X - otherRight) <= distance) then
        x = otherRight;
    elseif (math.abs(myRight - otherRight) <= distance) then
        x = otherRight - myBounds.Width;
    end

    if (math.abs(myBounds.Y - otherBounds.Y) <= distance) then
        y = otherBounds.Y;
    elseif (math.abs(myBottom - otherBounds.Y) <= distance) then
        y = otherBounds.Y - myBounds.Height;
    elseif (math.abs(myBounds.Y - otherBottom) <= distance) then
        y = otherBottom;
    elseif (math.abs(myBottom - otherBottom) <= distance) then
        y = otherBottom - myBounds.Height;
    end

    return x, y;
end
