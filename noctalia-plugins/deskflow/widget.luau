--!nonstrict
-- Deskflow server pill for the Noctalia bar, plus one compact pill per
-- connected client.
--
-- `deskflow-ctl` (nixos/packages/deskflow-ctl.nix) is the source of truth:
-- `status` renders the summary pill and `client <slot>` the Nth client, both as
-- Waybar-shaped JSON ({ text, class, tooltip }). This script re-renders that
-- JSON as a declarative `ui.*` tree and mirrors the parsed result to the panel
-- through `noctalia.state`.
--
-- IPC: `noctalia msg plugin john/deskflow:bar all refresh|toggle`.

local DEFAULT_POLL_MS = 2000
local DEFAULT_MAX_SLOTS = 4

local pollMs = math.clamp(tonumber(noctalia.getConfig("poll_ms")) or DEFAULT_POLL_MS, 500, 30000)
local maxSlots = math.clamp(tonumber(noctalia.getConfig("max_slots")) or DEFAULT_MAX_SLOTS, 1, 8)

-- Status class -> palette role. `lan` wins over `wire` in deskflow-ctl, so the
-- summary pill already follows the weakest path; keep that mapping as-is.
local ROLE_BY_CLASS = {
  wire = "tertiary",
  lan = "primary",
  idle = "on_surface_variant",
  stopped = "outline_variant",
}

local summary = nil
local clients = {}
local busy = false
local pendingPoll = false
local lastError = nil
local warnedMissing = false

local poll

local function roleFor(class)
  return ROLE_BY_CLASS[class] or ROLE_BY_CLASS.stopped
end

local function decodePill(result)
  if result == nil or result.timedOut or result.exitCode ~= 0 then
    return nil
  end
  local raw = result.stdout
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  local value = noctalia.json.decode(raw)
  if type(value) ~= "table" then
    return nil
  end
  return {
    text = type(value.text) == "string" and value.text or "",
    class = type(value.class) == "string" and value.class or "",
    tooltip = type(value.tooltip) == "string" and value.tooltip or "",
  }
end

local function render()
  local vertical = barWidget.isVertical()
  local container = vertical and ui.column or ui.row
  local children = {}

  local class = (summary ~= nil and summary.class ~= "") and summary.class or "stopped"
  local tone = roleFor(class)

  local tip = "Deskflow: reading status…"
  if summary ~= nil and summary.tooltip ~= "" then
    tip = summary.tooltip
  elseif lastError ~= nil then
    tip = lastError
  end

  table.insert(children, ui.row({
    key = "deskflow-summary",
    fill = tone .. "/0.16",
    radius = 8,
    paddingH = 8,
    paddingV = 2,
    align = "center",
    justify = "center",
    tooltip = tip,
    onClick = "onPrimaryClick",
  }, {
    ui.label({
      text = (summary ~= nil and summary.text ~= "") and summary.text or "DF",
      fontSize = 12,
      fontWeight = "bold",
      color = tone,
    }),
  }))

  for _, client in ipairs(clients) do
    local clientTone = roleFor(client.class)
    table.insert(children, ui.row({
      key = "deskflow-client-" .. tostring(client.slot),
      fill = "surface_container",
      radius = 8,
      paddingH = 7,
      paddingV = 2,
      align = "center",
      justify = "center",
      tooltip = client.tooltip,
      onClick = "onClientClick",
    }, {
      ui.label({
        text = client.text,
        fontSize = 12,
        color = clientTone,
      }),
    }))
  end

  barWidget.render(container({ gap = 6, align = "center" }, children))
end

local function finishPoll()
  busy = false
  noctalia.state.set("deskflow", {
    summary = summary,
    clients = clients,
    error = lastError,
    poll_ms = pollMs,
    max_slots = maxSlots,
    updated_ms = noctalia.nowMs(),
  })
  render()
  if pendingPoll then
    pendingPoll = false
    poll()
  end
end

local function pollClients()
  local slots = {}
  local remaining = maxSlots

  local function finish()
    remaining -= 1
    if remaining > 0 then
      return
    end
    -- deskflow-ctl keeps a client in its slot for as long as it stays
    -- connected; an empty pill means the slot has no client, so drop it
    -- instead of leaving a gap in the bar.
    local compact = {}
    for slot = 1, maxSlots do
      local pill = slots[slot]
      if pill ~= nil and pill.text ~= "" then
        table.insert(compact, pill)
      end
    end
    clients = compact
    finishPoll()
  end

  for slot = 1, maxSlots do
    local index = slot
    local accepted = noctalia.runAsync({ "deskflow-ctl", "client", tostring(index) }, function(result)
      local pill = decodePill(result)
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
    pendingPoll = true
    return
  end
  busy = true
  pendingPoll = false
  lastError = nil

  if not noctalia.commandExists("deskflow-ctl") then
    summary = nil
    clients = {}
    lastError = "Deskflow: deskflow-ctl is not on PATH"
    if not warnedMissing then
      warnedMissing = true
      noctalia.log("deskflow: deskflow-ctl is not on PATH, cannot read the server state")
    end
    finishPoll()
    return
  end

  local accepted = noctalia.runAsync({ "deskflow-ctl", "status" }, function(result)
    local pill = decodePill(result)
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
  -- The switch takes a moment, so look once immediately (instant feedback when
  -- it really is instant) and once after systemctl has settled.
  poll()
  noctalia.runAsync("sleep 0.6", function()
    poll()
  end)
end

function onClick()
  toggleServer()
end

function onPrimaryClick()
  toggleServer()
end

function onClientClick()
  noctalia.togglePanel("john/deskflow:panel")
end

function onMiddleClick()
  poll()
end

function onIpc(event)
  if event == "refresh" then
    poll()
  elseif event == "toggle" then
    toggleServer()
  end
end

function update()
  poll()
end

noctalia.setUpdateInterval(pollMs)
render()
poll()
