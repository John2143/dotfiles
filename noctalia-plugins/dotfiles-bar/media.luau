--!nonstrict
-- Media widget: the Waybar `custom/media` module, unchanged on the shell side.
-- `media-player status` prints the player the bar should show (pin, else last
-- active, else a fresh pick) as Waybar JSON, including the state icon at the
-- front of `text`; the icon becomes the bar glyph here so the two never double
-- up.
local status = require("./lib/waybar_json.luau")

-- playing (green), paused (yellow), stopped (dim) in the old bar.
local COLORS = {
  playing = "tertiary",
  paused = "secondary",
  stopped = "on_surface_variant",
}

local GLYPHS = {
  playing = "player-play",
  paused = "player-pause",
  stopped = "music",
}

-- The helper prefixes text with ▶ / ⏸ / ♫ / ■ (bytes, so an explicit prefix
-- compare is the only portable way to drop it).
local ICONS = { "▶", "⏸", "♫", "■" }

local function stripIcon(text)
  for _, icon in ipairs(ICONS) do
    if text:sub(1, #icon) == icon then
      return (text:sub(#icon + 1):gsub("^%s+", ""))
    end
  end
  return text
end

-- A poll can outlive the interval it was started on; without this the slower
-- the playerctl call gets, the more of them stack up.
local polling = false

local function poll()
  if polling then
    return
  end
  polling = true
  noctalia.runAsync({ "media-player", "status" }, function(result)
    polling = false
    local data = status.parse(result.stdout)
    if data == nil then
      return
    end
    data.text = stripIcon(data.text)
    barWidget.setGlyph(GLYPHS[data.class] or "music")
    status.applyImperative(data, COLORS, "on_surface", false)
  end)
end

function update()
  noctalia.setUpdateInterval(noctalia.getConfig("media_interval"))
  poll()
end

function onIpc(event)
  if event == "refresh" then
    poll()
  end
end

function onClick()
  noctalia.runAsync({ "media-player", "toggle" })
end

function onRightClick()
  noctalia.togglePanel("john/dotfiles-bar:media-panel")
end

function onMiddleClick()
  noctalia.runAsync({ "media-player", "focus" })
end

-- Waybar stepped one 5% notch per wheel detent; `steps` counts whole detents, so
-- a fast flick issues one command per notch exactly as before.
function onScroll(axis, steps, _startsGesture)
  if axis ~= "vertical" or steps == 0 then
    return
  end
  local delta = steps > 0 and "0.05-" or "0.05+"
  for _ = 1, math.abs(steps) do
    noctalia.runAsync({ "media-player", "volume", delta })
  end
end
