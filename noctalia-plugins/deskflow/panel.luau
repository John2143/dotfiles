--!nonstrict
-- Deskflow detail panel: server state, start/stop, and one row per connected
-- client with its route, address and latency history.
--
-- The data comes from the same `deskflow-ctl` JSON the bar widget reads, so the
-- panel is useful even when the widget has never polled (it refreshes on open)
-- and follows the widget's later polls through `noctalia.state`.
--
-- IPC: `noctalia msg plugin john/deskflow:panel all refresh|toggle`.

local MAX_SLOTS = 8

local ROLE_BY_CLASS = {
  wire = "tertiary",
  lan = "primary",
  idle = "on_surface_variant",
  stopped = "outline_variant",
}

local summary = nil
local clients = {}
local updatedMs = nil
local isOpen = false
local busy = false
local pending = false
local lastError = nil

local render
local poll

local function roleFor(class)
  return ROLE_BY_CLASS[class] or ROLE_BY_CLASS.stopped
end

local function splitLines(text)
  local lines = {}
  if type(text) ~= "string" then
    return lines
  end
  for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
    table.insert(lines, line)
  end
  return lines
end

local function decodePill(value)
  if type(value) ~= "table" then
    return nil
  end
  return {
    text = type(value.text) == "string" and value.text or "",
    class = type(value.class) == "string" and value.class or "",
    tooltip = type(value.tooltip) == "string" and value.tooltip or "",
  }
end

local function decodeResult(result)
  if result == nil or result.timedOut or result.exitCode ~= 0 then
    return nil
  end
  local raw = result.stdout
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  return decodePill(noctalia.json.decode(raw))
end

-- The tooltip's last line is the server description ("unit active on host");
-- the header shows it as the subtitle.
local function serverLine()
  if summary == nil then
    return nil
  end
  for _, line in ipairs(splitLines(summary.tooltip)) do
    local value = string.match(line, "^server:%s*(.+)$")
    if value ~= nil and value ~= "" then
      return value
    end
  end
  return nil
end

local function headline()
  if summary == nil then
    if lastError ~= nil then
      return noctalia.tr("panel.unknown")
    end
    return noctalia.tr("panel.checking")
  end
  local count = #clients
  if count > 0 then
    return noctalia.trp("panel.client_count", count)
  end
  if summary.class == "stopped" then
    return noctalia.tr("panel.stopped")
  end
  return noctalia.tr("panel.idle")
end

local function clientName(client)
  local first = splitLines(client.tooltip)[1]
  if first ~= nil then
    local name = string.match(first, "^Deskflow client:%s*(.+)$")
    if name ~= nil and name ~= "" then
      return name
    end
  end
  -- Fallback: "<label> <latency> ms", where the label is truncated upstream.
  local label = string.match(client.text, "^(.-)%s+%S+ ms$")
  return label or client.text
end

local function clientLatency(client)
  for _, line in ipairs(splitLines(client.tooltip)) do
    local value = string.match(line, "^latency:%s*(.+)$")
    if value ~= nil and value ~= "" then
      return value
    end
  end
  local rtt = string.match(client.text, "(%S+ ms)$")
  return rtt or ""
end

-- Everything the tooltip knows except the name (row title), the latency (row
-- value) and the server line (header subtitle): address, route and the
-- two-minute sparkline.
local function clientDetail(client)
  local parts = {}
  for index, line in ipairs(splitLines(client.tooltip)) do
    if index > 1 and line ~= "" and string.match(line, "^latency:") == nil and string.match(line, "^server:") == nil then
      table.insert(parts, noctalia.string.trim(line))
    end
  end
  return table.concat(parts, "  ·  ")
end

local function clientRows()
  local rows = {}
  for index, client in ipairs(clients) do
    local tone = roleFor(client.class)
    local transport = client.class ~= "" and string.upper(client.class) or "?"
    local detail = clientDetail(client)
    local titleChildren = {
      ui.label({ text = clientName(client), fontSize = 13, fontWeight = "bold" }),
    }
    if detail ~= "" then
      table.insert(titleChildren, ui.label({
        text = detail,
        fontSize = 11,
        color = "on_surface_variant",
        maxLines = 1,
      }))
    end
    table.insert(rows, ui.row({
      key = "deskflow-client-" .. tostring(index),
      fill = "surface_container",
      radius = 8,
      paddingH = 10,
      paddingV = 8,
      gap = 10,
      align = "center",
      tooltip = client.tooltip,
    }, {
      ui.row({
        fill = tone .. "/0.18",
        radius = 6,
        paddingH = 7,
        paddingV = 2,
        align = "center",
        justify = "center",
      }, {
        ui.label({ text = transport, fontSize = 10, fontWeight = "bold", color = tone }),
      }),
      ui.column({ gap = 2, flexGrow = 1 }, titleChildren),
      ui.label({ text = clientLatency(client), fontSize = 12, fontWeight = "bold", color = tone }),
    }))
  end
  return rows
end

render = function()
  if not isOpen then
    return
  end

  local class = (summary ~= nil and summary.class ~= "") and summary.class or "stopped"
  local tone = roleFor(class)
  local running = summary ~= nil and class ~= "stopped"

  local header = ui.row({ gap = 10, align = "center" }, {
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({ text = noctalia.tr("panel.title"), fontSize = 17, fontWeight = "bold" }),
      ui.label({
        text = serverLine() or noctalia.tr("panel.unknown"),
        fontSize = 11,
        color = "on_surface_variant",
        maxLines = 1,
      }),
    }),
    ui.row({
      fill = tone .. "/0.16",
      radius = 8,
      paddingH = 9,
      paddingV = 3,
      align = "center",
      justify = "center",
      tooltip = (summary ~= nil and summary.tooltip ~= "") and summary.tooltip or nil,
    }, {
      ui.label({ text = headline(), fontSize = 12, fontWeight = "bold", color = tone }),
    }),
  })

  local actionChildren = {
    ui.button({
      text = running and noctalia.tr("panel.stop") or noctalia.tr("panel.start"),
      glyph = running and "player-stop" or "player-play",
      variant = running and "destructive" or "primary",
      onClick = "onToggle",
    }),
    ui.button({
      text = noctalia.tr("panel.refresh"),
      glyph = "refresh",
      variant = "secondary",
      onClick = "onRefresh",
    }),
  }
  if updatedMs ~= nil then
    table.insert(actionChildren, ui.spacer({ flexGrow = 1 }))
    table.insert(actionChildren, ui.label({
      text = os.date("%H:%M:%S", math.floor(updatedMs / 1000)),
      fontSize = 11,
      color = "on_surface_variant",
    }))
  end

  local sectionChildren = {
    ui.label({
      text = noctalia.tr("panel.clients"),
      fontSize = 11,
      fontWeight = "bold",
      color = "on_surface_variant",
    }),
  }
  local rows = clientRows()
  if #rows == 0 then
    table.insert(sectionChildren, ui.label({
      text = noctalia.tr("panel.no_clients"),
      fontSize = 12,
      color = "on_surface_variant",
    }))
  else
    -- `height = "content"` follows the tree up to max_height; a scroll with
    -- flexGrow is how the list keeps scrolling past that instead of clipping.
    table.insert(sectionChildren, ui.scroll({ gap = 6, flexGrow = 1 }, rows))
  end

  local children = {
    header,
    ui.separator({}),
    ui.row({ gap = 8, align = "center" }, actionChildren),
    ui.column({ gap = 8 }, sectionChildren),
  }
  if lastError ~= nil then
    table.insert(children, ui.label({ text = lastError, fontSize = 11, color = "error", maxLines = 2 }))
  end

  panel.render(ui.column({ gap = 14, padding = 16 }, children))
end

local function finishPoll()
  busy = false
  updatedMs = noctalia.nowMs()
  render()
  if pending then
    pending = false
    poll()
  end
end

local function pollClients()
  local slots = {}
  local remaining = MAX_SLOTS

  local function finish()
    remaining -= 1
    if remaining > 0 then
      return
    end
    local compact = {}
    for slot = 1, MAX_SLOTS do
      local pill = slots[slot]
      if pill ~= nil and pill.text ~= "" then
        table.insert(compact, pill)
      end
    end
    clients = compact
    finishPoll()
  end

  for slot = 1, MAX_SLOTS do
    local index = slot
    local accepted = noctalia.runAsync({ "deskflow-ctl", "client", tostring(index) }, function(result)
      local pill = decodeResult(result)
      if pill ~= nil then
        pill.slot = index
        slots[index] = pill
      end
      finish()
    end)
    if not accepted then
      finish()
    end
  end
end

poll = function()
  if busy then
    pending = true
    return
  end
  busy = true
  pending = false
  lastError = nil

  if not noctalia.commandExists("deskflow-ctl") then
    summary = nil
    clients = {}
    lastError = "Deskflow: deskflow-ctl is not on PATH"
    finishPoll()
    return
  end

  local accepted = noctalia.runAsync({ "deskflow-ctl", "status" }, function(result)
    local pill = decodeResult(result)
    if pill ~= nil then
      summary = pill
    else
      summary = nil
      lastError = "Deskflow: could not read the server status"
    end
    pollClients()
  end)

  if not accepted then
    summary = nil
    clients = {}
    lastError = "Deskflow: could not run deskflow-ctl"
    finishPoll()
  end
end

local function toggleServer()
  noctalia.runAsync({ "deskflow-ctl", "toggle" })
  -- The switch takes a moment, so look once immediately and once after
  -- systemctl has settled.
  poll()
  noctalia.runAsync("sleep 0.6", function()
    poll()
  end)
end

-- The widget publishes { summary, clients, updated_ms }; only a newer snapshot
-- replaces what this panel fetched itself.
local function applySnapshot(value)
  if type(value) ~= "table" then
    return
  end
  local incoming = tonumber(value.updated_ms) or 0
  if updatedMs ~= nil and incoming <= updatedMs then
    return
  end

  summary = decodePill(value.summary)
  clients = {}
  if type(value.clients) == "table" then
    for index, client in ipairs(value.clients) do
      local pill = decodePill(client)
      if pill ~= nil and pill.text ~= "" then
        pill.slot = tonumber(client.slot) or index
        table.insert(clients, pill)
      end
    end
  end
  updatedMs = incoming
  lastError = type(value.error) == "string" and value.error or nil
  render()
end

noctalia.state.watch("deskflow", applySnapshot)

function onOpen(_context)
  isOpen = true
  render()
  poll()
end

function onClose()
  isOpen = false
end

function onToggle()
  toggleServer()
end

function onRefresh()
  poll()
end

function onIpc(event)
  if event == "refresh" then
    poll()
  elseif event == "toggle" then
    toggleServer()
  end
end
