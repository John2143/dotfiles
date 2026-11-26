--!nonstrict
-- Deskflow detail panel: server state, start/stop, and one row per connected
-- client with its route, address, latency and a graph of the last two minutes.
--
-- The data comes from the same poller as the bar widget (lib/deskflow.luau), so
-- the panel is useful even when the widget has never polled (it refreshes on
-- open) and follows the widget's later polls through `noctalia.state`.
--
-- IPC: `noctalia msg plugin john/deskflow:panel all refresh|toggle`.

local deskflow = require("./lib/deskflow.luau")

-- The panel is 420 wide (plugin.toml) with 16 padding, and a row adds 10 more;
-- a graph has to be told its width, so this is what fits inside a row.
local GRAPH_WIDTH = 360
local GRAPH_HEIGHT = 34

local isOpen = false
local render
local poller = deskflow.newPoller(function(state)
  if isOpen then
    render(state)
  end
end)

local function headline(state)
  if state.summary == nil then
    if state.error ~= nil then
      return noctalia.tr("panel.unknown")
    end
    return noctalia.tr("panel.checking")
  end
  local count = #state.clients
  if count > 0 then
    return noctalia.trp("panel.client_count", count)
  end
  if state.summary.class == "stopped" then
    return noctalia.tr("panel.stopped")
  end
  return noctalia.tr("panel.idle")
end

local function clientRow(index, client)
  local tone = deskflow.roleFor(client.class)
  local transport = client.class ~= "" and string.upper(client.class) or "?"
  local name = client.name ~= "" and client.name or client.ip

  -- The address sits beside the name instead of in the detail line: at this
  -- width "path · address" used to truncate mid-address. A client whose name
  -- never resolved already shows its address as the name.
  local titleChildren = {
    ui.label({ text = name, fontSize = 13, fontWeight = "bold" }),
  }
  if client.ip ~= "" and client.ip ~= name then
    table.insert(titleChildren, ui.label({ text = client.ip, fontSize = 11, color = "on_surface_variant" }))
  end

  local titleChildrenColumn = {
    ui.row({ gap = 8, align = "center" }, titleChildren),
  }
  if client.where ~= "" then
    table.insert(titleChildrenColumn, ui.label({
      text = client.where,
      fontSize = 11,
      color = "on_surface_variant",
      maxLines = 1,
    }))
  end

  local children = {
    ui.row({ gap = 10, align = "center" }, {
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
      ui.column({ gap = 2, flexGrow = 1 }, titleChildrenColumn),
      ui.label({ text = deskflow.formatLatency(client.rtt), fontSize = 12, fontWeight = "bold", color = tone }),
    }),
  }

  -- A single sample is not a line, and a client that just connected has none
  -- yet; the row then stands on its own without a graph or its caption.
  local values, ceiling = deskflow.graphSeries(client.history)
  if #values >= 2 then
    table.insert(children, ui.graph({
      values = values,
      color = tone,
      lineWidth = 1.5,
      fillOpacity = 0.18,
      width = GRAPH_WIDTH,
      height = GRAPH_HEIGHT,
    }))
    -- The min/avg/max summary the tooltip used to carry, plus the scale the
    -- linear graph is drawn against.
    table.insert(children, ui.row({ align = "center" }, {
      ui.label({
        text = deskflow.latencySummary(client.history) or "",
        fontSize = 10,
        color = "on_surface_variant",
      }),
      ui.spacer({ flexGrow = 1 }),
      ui.label({
        text = string.format("0–%d ms", ceiling),
        fontSize = 10,
        color = "on_surface_variant",
      }),
    }))
  end

  return ui.column({
    key = "deskflow-client-" .. tostring(index),
    fill = "surface_container",
    radius = 8,
    paddingH = 10,
    paddingV = 8,
    gap = 6,
  }, children)
end

local function clientRows(state)
  local rows = {}
  for index, client in ipairs(state.clients) do
    table.insert(rows, clientRow(index, client))
  end
  return rows
end

render = function(state)
  if not isOpen then
    return
  end

  local summary = state.summary
  local class = (summary ~= nil and summary.class ~= "") and summary.class or "stopped"
  local tone = deskflow.roleFor(class)
  local running = summary ~= nil and class ~= "stopped"

  local header = ui.row({ gap = 10, align = "center" }, {
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({ text = noctalia.tr("panel.title"), fontSize = 17, fontWeight = "bold" }),
      ui.label({
        text = (summary ~= nil and deskflow.serverLine(summary.tooltip)) or noctalia.tr("panel.unknown"),
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
      ui.label({ text = headline(state), fontSize = 12, fontWeight = "bold", color = tone }),
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
  if state.updated_ms ~= nil then
    table.insert(actionChildren, ui.spacer({ flexGrow = 1 }))
    table.insert(actionChildren, ui.label({
      text = os.date("%H:%M:%S", math.floor(state.updated_ms / 1000)),
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
  local rows = clientRows(state)
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
  if state.error ~= nil then
    table.insert(children, ui.label({ text = state.error, fontSize = 11, color = "error", maxLines = 2 }))
  end

  panel.render(ui.column({ gap = 14, padding = 16 }, children))
end

-- The widget publishes { summary, clients, updated_ms, error }; only a newer
-- snapshot replaces what this panel fetched itself.
noctalia.state.watch("deskflow", function(value)
  if deskflow.applySnapshot(poller, value) and isOpen then
    render(poller)
  end
end)

function onOpen()
  isOpen = true
  render(poller)
  poller.poll()
end

function onClose()
  isOpen = false
end

function onToggle()
  poller.toggle()
end

function onRefresh()
  poller.poll()
end

function onIpc(event)
  if event == "refresh" then
    poller.poll()
  elseif event == "toggle" then
    poller.toggle()
  end
end
