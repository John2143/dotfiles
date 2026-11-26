--!nonstrict
-- Bedroom thermostat indicator: the Waybar `custom/thermostat` module.
-- Waybar refreshed it on SIGRTMIN+8 (the HA notify hook poked the bar); here the
-- widget polls and also answers an explicit `refresh` IPC event, which is what
-- the hook sends now.
local status = require("./lib/waybar_json.luau")

local COLORS = {
  heating = "secondary",
  cooling = "primary",
  off = "outline_variant",
  error = "error",
}

local polling = false

local function poll()
  if polling then
    return
  end
  polling = true
  noctalia.runAsync({ "hass-thermostat-status" }, function(result)
    polling = false
    status.applyImperative(status.parse(result.stdout), COLORS, "on_surface", false)
  end)
end

function update()
  noctalia.setUpdateInterval(noctalia.getConfig("thermostat_interval"))
  poll()
end

function onIpc(event)
  if event == "refresh" then
    poll()
  end
end

function onRightClick()
  noctalia.runAsync({ "hass-macro", "ac-toggle" })
end

-- middle = "none" in plugin.toml frees the button for this.
function onMiddleClick()
  noctalia.runAsync({ "hass-macro", "thermostat-toggle" })
end

-- One detent is one degree: Waybar fired on-scroll-up/-down once per notch, and
-- acting only on the first step of a gesture keeps a trackpad flick from running
-- the setpoint away.
function onScroll(axis, steps, startsGesture)
  if axis ~= "vertical" or not startsGesture or steps == 0 then
    return
  end
  local macro = steps < 0 and "thermostat-up" or "thermostat-down"
  local count = math.min(math.abs(steps), 5)
  for _ = 1, count do
    noctalia.runAsync({ "hass-macro", macro })
  end
end
