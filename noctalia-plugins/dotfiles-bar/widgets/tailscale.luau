--!nonstrict
-- Tailscale indicator: the Waybar `custom/tailscale` module.
-- Left opens the panel that replaced the Eww `tailscale` window; right keeps the
-- old picker shortcut.
local status = require("../lib/waybar_json.luau")

local COLORS = {
  connected = "tertiary",
  disconnected = "outline_variant",
  ["needs-login"] = "secondary",
}

local polling = false

local function poll()
  if polling then
    return
  end
  polling = true
  noctalia.runAsync({ "tailscale-status" }, function(result)
    polling = false
    status.applyImperative(status.parse(result.stdout), COLORS, "on_surface_variant", false)
  end)
end

function update()
  noctalia.setUpdateInterval(noctalia.getConfig("tailscale_interval"))
  poll()
end

function onIpc(event)
  if event == "refresh" then
    poll()
  end
end

function onClick()
  noctalia.togglePanel("john/dotfiles-bar:tailscale-panel")
end

function onRightClick()
  noctalia.runAsync({ "tailscale-exit-node" })
end
