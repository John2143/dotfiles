--!nonstrict
-- Autoclicker indicator: the Waybar `custom/autoclicker` module.
-- `autoclicker watch` streams one Waybar JSON line per state change (the daemon
-- compares and emits on difference), and the text IS the mode glyph, so no bar
-- glyph is set here.
local status = require("./lib/waybar_json.luau")

local COLORS = {
  ["autoclicker-off"] = "on_surface_variant",
  ["autoclicker-scroll-left"] = "primary",
  ["autoclicker-scroll-right"] = "tertiary",
  ["autoclicker-timer"] = "secondary",
  ["autoclicker-error"] = "error",
}

local last = nil

local function apply(data)
  last = data
  status.applyImperative(data, COLORS, "on_surface", false)
end

noctalia.runStream("autoclicker watch", function(line)
  local data = status.parse(line)
  if data ~= nil then
    apply(data)
  end
end)

function onIpc(event)
  if event == "refresh" and last ~= nil then
    apply(last)
  end
end

function onClick()
  noctalia.runAsync({ "autoclicker", "toggle" })
end

-- middle = "none" in plugin.toml is what lets this fire at all.
function onMiddleClick()
  noctalia.runAsync({ "autoclicker", "cycle" })
end

function onRightClick()
  noctalia.togglePanel("john/dotfiles-bar:autoclicker-panel")
end
