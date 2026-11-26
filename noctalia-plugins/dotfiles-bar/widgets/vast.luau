--!nonstrict
-- VAST instance indicator: the Waybar `custom/vast` module.
-- `vast-waybar-status` caches its answer in /tmp/vast-waybar-status.json for 55s
-- and prints nothing at all when there is no instance — empty output is the
-- widget's "hidden" state, exactly as it was in Waybar.
local status = require("../lib/waybar_json.luau")

local CACHE = "/tmp/vast-waybar-status.json"

local COLORS = {
  ["vast-ready"] = "tertiary",
  ["vast-tunnel-up"] = "secondary",
  ["vast-tunnel-down"] = "error",
}

local polling = false

local function poll()
  if polling then
    return
  end
  polling = true
  noctalia.runAsync({ "vast-waybar-status" }, function(result)
    polling = false
    status.applyImperative(status.parse(result.stdout), COLORS, "on_surface", true)
  end)
end

function update()
  noctalia.setUpdateInterval(noctalia.getConfig("vast_interval"))
  poll()
end

function onIpc(event)
  if event == "refresh" then
    poll()
  end
end

-- Drop the helper's cache first, otherwise the immediate re-poll just replays the
-- answer the click was meant to invalidate.
function onClick()
  noctalia.removeFile(CACHE)
  poll()
end
