--!nonstrict
-- Temporal reachability indicator: the Waybar `custom/temporal` module.
-- `temporal-status` probes 192.168.6.20:7233 over TCP and prints Waybar JSON.
local status = require("./lib/waybar_json.luau")

local COLORS = {
  connected = "tertiary",
  disconnected = "error",
}

local polling = false

local function poll()
  if polling then
    return
  end
  polling = true
  noctalia.runAsync({ "temporal-status" }, function(result)
    polling = false
    status.applyImperative(status.parse(result.stdout), COLORS, "on_surface", false)
  end)
end

function update()
  noctalia.setUpdateInterval(noctalia.getConfig("temporal_interval"))
  poll()
end

function onIpc(event)
  if event == "refresh" then
    poll()
  end
end

function onClick()
  noctalia.runAsync({ "xdg-open", "https://temporal.ts.2143.me:8443" })
end
