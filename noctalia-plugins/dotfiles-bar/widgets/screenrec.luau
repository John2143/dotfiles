--!nonstrict
-- Screen recording indicator: the Waybar `custom/screenrec` module.
-- `screenrec status --follow` is long-lived and prints one Waybar JSON line per
-- change, so this stays a stream rather than a poll; idle is a real object with
-- an empty text, so the widget hides on it instead of showing an empty capsule.
local status = require("../lib/waybar_json.luau")

local COLORS = {
  recording = "error",
  starting = "error",
  uploading = "secondary",
  processing = "secondary",
  done = "tertiary",
  error = "error",
}

local HIDE = { classes = { "idle" }, empty = true }

local last = nil

local function apply(data)
  last = data
  status.applyImperative(data, COLORS, "on_surface", HIDE)
end

noctalia.runStream("screenrec status --follow", function(line)
  local data = status.parse(line)
  if data ~= nil then
    apply(data)
  end
end)

-- IPC has nothing to re-read here (the stream owns the state), so a refresh just
-- re-applies the last line, which also un-hides the widget if something else
-- hid it.
function onIpc(event)
  if event == "refresh" and last ~= nil then
    apply(last)
  end
end

function onClick()
  noctalia.runAsync({ "screenrec", "toggle" })
end

function onRightClick()
  noctalia.runAsync({ "screenrec", "last" })
end
