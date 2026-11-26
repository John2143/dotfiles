--!nonstrict
-- flake.lock age indicator: the Waybar `custom/updates` module.
-- `nix-update-status` prints an empty text while the lockfile is fresh, so the
-- widget is hidden most of the time and only appears once it is worth running
-- `nix flake update`.
local status = require("../lib/waybar_json.luau")

local COLORS = {
  ["pending-updates"] = "secondary",
  updated = "on_surface_variant",
}

local UPDATE = "cd ~/dotfiles && nix flake update"

local polling = false

local function poll()
  if polling then
    return
  end
  polling = true
  noctalia.runAsync({ "nix-update-status" }, function(result)
    polling = false
    status.applyImperative(status.parse(result.stdout), COLORS, "on_surface", true)
  end)
end

function update()
  noctalia.setUpdateInterval(noctalia.getConfig("updates_interval"))
  poll()
end

function onIpc(event)
  if event == "refresh" then
    poll()
  end
end

-- Waybar ran `alacritty -e fish -c '…'`; the terminal is a setting now so the
-- widget does not pin one. Empty means let Noctalia choose.
function onClick()
  local terminal = noctalia.getConfig("terminal")
  if type(terminal) == "string" and terminal ~= "" then
    noctalia.runAsync({ terminal, "-e", "fish", "-c", UPDATE })
  else
    noctalia.runInTerminal("fish -c '" .. UPDATE .. "'")
  end
end
