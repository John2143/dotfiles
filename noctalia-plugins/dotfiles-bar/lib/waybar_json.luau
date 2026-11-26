--!nonstrict
-- Shared plumbing for the Waybar helpers this plugin kept.
--
-- Every wrapped script still prints the Waybar JSON contract
-- ({"text": ..., "class": ..., "tooltip": ...}), so nothing about the shell
-- side had to change when the bar moved to Noctalia: this module parses that
-- line and pushes it onto the bar widget.
--
-- Class strings from the helpers are not always a single token: ipad-display
-- emits a link class plus a state class ("usb streaming", "net clone"), and Css
-- matched them independently. colorForClass reproduces that by looking at every
-- token, with the LAST match winning - the state token is always appended after
-- the link token, so "usb streaming" resolves to streaming's color.

local M = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Last "{"-starting line that parses wins: a helper that prints one JSON object
-- per line (or a diagnostic before it) still yields the final state, and a
-- half-written line is simply skipped.
local function decodeObject(raw)
  local candidates = {}
  for line in raw:gmatch("[^\n]+") do
    if trim(line):sub(1, 1) == "{" then
      table.insert(candidates, trim(line))
    end
  end
  if #candidates == 0 then
    candidates = { trim(raw) }
  end

  for index = #candidates, 1, -1 do
    local ok, value = pcall(noctalia.json.decode, candidates[index])
    if ok and type(value) == "table" then
      return value
    end
  end
  return nil
end

--- Parses one Waybar status line.
-- Returns nil when stdout carries no usable object (an empty string is how
-- several of these helpers say "nothing to show").
function M.parse(stdout)
  if type(stdout) ~= "string" then
    return nil
  end
  local raw = trim(stdout)
  if raw == "" then
    return nil
  end

  local value = decodeObject(raw)
  if value == nil then
    return nil
  end

  return {
    text = type(value.text) == "string" and value.text or "",
    class = type(value.class) == "string" and value.class or "",
    tooltip = type(value.tooltip) == "string" and value.tooltip or "",
    alt = type(value.alt) == "string" and value.alt or "",
  }
end

--- Maps a Waybar class string onto a palette role.
-- `map` is token -> role. Later tokens win, which is what a multi-class string
-- needs; an unknown or empty class falls back to `fallback`.
function M.colorForClass(cls, map, fallback)
  if type(cls) ~= "string" or cls == "" then
    return fallback
  end
  local role = nil
  for token in cls:gmatch("%S+") do
    if map and map[token] then
      role = map[token]
    end
  end
  return role or fallback
end

-- hideEmpty is either a boolean (hide when there is no text) or a table
-- { classes = { "idle", ... }, empty = true }. The table form exists because
-- screenrec's resting state is a real object with an empty text and
-- class "idle" - both mean "nothing to show".
local function shouldHide(data, hideEmpty)
  if hideEmpty == nil or hideEmpty == false then
    return false
  end
  if hideEmpty == true then
    return data == nil or data.text == ""
  end

  local empty = hideEmpty.empty ~= false
  if empty and (data == nil or data.text == "") then
    return true
  end
  if data ~= nil and type(hideEmpty.classes) == "table" then
    for _, hidden in ipairs(hideEmpty.classes) do
      if data.class == hidden then
        return true
      end
      if (" " .. data.class .. " "):find(" " .. hidden .. " ", 1, true) then
        return true
      end
    end
  end
  return false
end

--- Pushes a parsed status onto the bar widget.
-- Returns true when the widget was updated, false when it was hidden or when
-- `data` was nil and the widget is not meant to hide on empty output - a failed
-- poll then leaves the previous reading on the bar instead of flickering.
function M.applyImperative(data, colorMap, fallbackColor, hideEmpty)
  local widget = barWidget
  if widget == nil then
    return false
  end

  if data == nil and not (hideEmpty == true or type(hideEmpty) == "table") then
    return false
  end

  if shouldHide(data, hideEmpty) then
    widget.setVisible(false)
    return false
  end

  widget.setVisible(true)
  widget.setText(data.text)

  local tooltip = data.tooltip
  if tooltip == "" then
    tooltip = data.alt
  end
  widget.setTooltip(tooltip ~= "" and tooltip or nil)

  local role = M.colorForClass(data.class, colorMap, fallbackColor)
  if role then
    widget.setColor(role)
    widget.setGlyphColor(role)
  end
  return true
end

return M
