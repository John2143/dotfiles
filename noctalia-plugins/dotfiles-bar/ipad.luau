--!nonstrict
-- iPad second display indicator: the Waybar `custom/ipad` module.
-- `ipad-display status --waybar` prints "iPad <USB|net> <●|○>" with a class of
-- "<link> <state>" ("usb streaming", "net clone", ...). colorForClass looks at
-- every token and lets the state win, which is how the old CSS stack behaved
-- (link = weight, state = color).
local status = require("./lib/waybar_json.luau")

local COLORS = {
  -- link: the cable is up, but that is not the interesting part
  usb = "on_surface_variant",
  net = "on_surface_variant",
  -- state
  streaming = "tertiary",
  clone = "error",
  stale = "secondary",
  idle = "outline_variant",
  off = "error",
}

local polling = false

local function poll()
  if polling then
    return
  end
  polling = true
  noctalia.runAsync({ "ipad-display", "status", "--waybar" }, function(result)
    polling = false
    status.applyImperative(status.parse(result.stdout), COLORS, "on_surface_variant", false)
  end)
end

function update()
  noctalia.setUpdateInterval(noctalia.getConfig("ipad_interval"))
  poll()
end

function onIpc(event)
  if event == "refresh" then
    poll()
  end
end

-- Left click is the repair path: drop a stale output, restart Sunshine.
function onClick()
  noctalia.runAsync({ "ipad-display", "recover" })
end

function onRightClick()
  noctalia.runAsync({ "ipad-display", "create" })
end
