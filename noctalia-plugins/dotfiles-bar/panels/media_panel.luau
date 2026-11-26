--!nonstrict
-- Media panel: the Eww `media-picker` window, rebuilt as a native Noctalia panel.
--
-- Two data sources, both already printed for the Eww version:
--   media-picker-data players  -> MPRIS players (pin, status, artist/title, volume)
--   media-picker-data tabs     -> Firefox-family sink inputs (title, volume, mute)
-- and one action helper, media-picker-action, which also refreshes the old bar.
--
-- media-picker-action only knows relative volume (up/down = 5%), so a slider
-- reports the delta from the value this row was rendered with and the panel
-- turns it into that many 5% steps.
local players = {}
local tabs = {}
local dirty = false
local ticks = 0

local VOLUME_STEP = 5

local function decodeArray(raw)
  if type(raw) ~= "string" then
    return nil
  end
  local text = raw:match("^%s*(.-)%s*$")
  if text == "" then
    return nil
  end
  local ok, value = pcall(noctalia.json.decode, text)
  if not ok or type(value) ~= "table" then
    return nil
  end
  return value
end

-- Forward declaration: fetch() renders from its completion callbacks.
local render

local function fetch()
  noctalia.runAsync({ "media-picker-data", "players" }, function(result)
    local list = decodeArray(result.stdout)
    if list then
      players = list
      render()
    end
  end)
  noctalia.runAsync({ "media-picker-data", "tabs" }, function(result)
    local list = decodeArray(result.stdout)
    if list then
      tabs = list
      render()
    end
  end)
end

-- Every action changes state the panel is showing, so mark it dirty instead of
-- polling immediately: the daemon ack and the pactl round trip land well inside
-- one second.
local function act(argv)
  noctalia.runAsync(argv)
  dirty = true
end

local function moveVolume(kind, id, from, to)
  local delta = math.floor((to - from) / VOLUME_STEP + 0.5)
  if delta == 0 then
    return
  end
  local verb = delta > 0 and "up" or "down"
  for _ = 1, math.abs(delta) do
    noctalia.runAsync({ "media-picker-action", kind, id, verb })
  end
  dirty = true
end

local function setPlayerVolume(player, value)
  local from = tonumber(player.volume) or 0
  local to = tonumber(value) or from
  if to == from then
    return
  end
  -- Move the rendered baseline first so a drag emits one delta per step rather
  -- than the whole distance on every event.
  player.volume = tostring(math.floor(to + 0.5))
  moveVolume("player-volume", player.id, from, to)
end

local function setTabVolume(tab, value)
  local from = tonumber(tab.volume) or 0
  local to = tonumber(value) or from
  if to == from then
    return
  end
  tab.volume = tostring(math.floor(to + 0.5))
  moveVolume("tab-volume", tab.index, from, to)
end

local function playerRow(player)
  local volume = tonumber(player.volume) or 0
  local playing = player.status == "Playing"
  local pinned = player.pin == "◉"
  local detail = player.detail or ""

  return ui.column({
    key = "player-" .. tostring(player.id),
    gap = 4,
    fill = "surface_container/0.5",
    radius = 8,
    padding = 8,
  }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.button({
        glyph = playing and "player-pause" or "player-play",
        variant = "ghost",
        controlSize = "sm",
        tooltip = playing and "Pause" or "Play",
        onClick = function()
          act({ "media-picker-action", "toggle", player.id })
        end,
      }),
      ui.label({
        text = detail ~= "" and (player.name .. "  " .. detail) or player.name,
        fontSize = 12,
        maxLines = 1,
        maxWidth = 300,
        flexGrow = 1,
      }),
      ui.label({ text = tostring(volume) .. "%", fontSize = 11, color = "on_surface_variant" }),
      ui.button({
        glyph = pinned and "pin-filled" or "pin",
        variant = "ghost",
        controlSize = "sm",
        tooltip = pinned and "Unpin from the bar" or "Pin to the bar",
        onClick = function()
          act({ "media-picker-action", "pin", player.id })
        end,
      }),
    }),
    ui.slider({
      min = 0,
      max = 100,
      step = VOLUME_STEP,
      value = volume,
      controlSize = "sm",
      onChange = function(value)
        setPlayerVolume(player, value)
      end,
    }),
  })
end

local function tabRow(tab)
  local volume = tonumber(tab.volume) or 0
  local muted = tab.muted == true

  return ui.column({
    key = "tab-" .. tostring(tab.index),
    gap = 4,
    fill = "surface_container/0.5",
    radius = 8,
    padding = 8,
  }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.button({
        glyph = muted and "volume-off" or "volume",
        variant = "ghost",
        controlSize = "sm",
        tooltip = muted and "Unmute tab" or "Mute tab",
        onClick = function()
          act({ "media-picker-action", "tab-mute", tab.index })
        end,
      }),
      ui.label({
        text = tab.title or "",
        fontSize = 12,
        maxLines = 1,
        maxWidth = 280,
        flexGrow = 1,
      }),
      ui.label({ text = tostring(volume) .. "%", fontSize = 11, color = "on_surface_variant" }),
      ui.button({
        glyph = "crosshair",
        variant = "ghost",
        controlSize = "sm",
        tooltip = "Focus the tab's window",
        onClick = function()
          act({ "media-picker-action", "tab-focus", tab.index })
        end,
      }),
    }),
    ui.slider({
      min = 0,
      max = 100,
      step = VOLUME_STEP,
      value = volume,
      controlSize = "sm",
      onChange = function(value)
        setTabVolume(tab, value)
      end,
    }),
  })
end

local function section(title, rows, emptyText)
  local children = {
    ui.label({ text = title, fontSize = 11, fontWeight = "bold", color = "on_surface_variant" }),
  }
  if #rows == 0 then
    children[#children + 1] = ui.label({ text = emptyText, fontSize = 12, color = "on_surface_variant" })
  else
    for _, row in ipairs(rows) do
      children[#children + 1] = row
    end
  end
  return ui.column({ gap = 6 }, children)
end

function render()
  local playerRows = {}
  for _, player in ipairs(players) do
    playerRows[#playerRows + 1] = playerRow(player)
  end
  local tabRows = {}
  for _, tab in ipairs(tabs) do
    tabRows[#tabRows + 1] = tabRow(tab)
  end

  panel.render(ui.column({ gap = 10, padding = 12 }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.glyph({ name = "music", size = 18, color = "primary" }),
      ui.label({ text = "Media", fontSize = 15, fontWeight = "bold", flexGrow = 1 }),
      ui.button({
        glyph = "x",
        variant = "ghost",
        controlSize = "sm",
        tooltip = "Close",
        onClick = function()
          panel.close()
        end,
      }),
    }),
    ui.scroll({ flexGrow = 1, gap = 12 }, {
      section("Players", playerRows, "No players"),
      section("Browser tabs", tabRows, "No audio tabs"),
    }),
    ui.label({ text = "drag a slider to set volume", fontSize = 11, color = "on_surface_variant" }),
  }))
end

function onOpen(_context)
  panel.setWantsSecondTicks(true)
  ticks = 0
  -- onOpen fetches anyway; a dirty flag left from the last session would only
  -- buy a second identical round of processes.
  dirty = false
  fetch()
end

function update()
  if dirty then
    dirty = false
    fetch()
    return
  end
  ticks = ticks + 1
  if ticks % 2 == 0 then
    fetch()
  end
end

function onIpc(event)
  if event == "refresh" then
    fetch()
  end
end
