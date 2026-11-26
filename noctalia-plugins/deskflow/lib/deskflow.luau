--!nonstrict
-- Shared guts of the `john/deskflow` plugin: decoding what `deskflow-ctl` prints,
-- the palette role for each transport class, and the one poller both entries
-- drive.
--
-- `deskflow-ctl` (nixos/packages/deskflow-ctl.nix) is the only data source:
--   status   -> { text, class, tooltip }                    (Waybar-shaped pill)
--   clients  -> [{ name, ip, class, where, rtt, history }]  (history in ms)
--   client N -> { text, class, tooltip }                    (legacy per-slot pill)
--
-- Required as `require("./lib/deskflow.luau")` from the entry files at the
-- plugin root. Every entry gets its own module instance, so the bar widget and
-- the panel share the code, not the state: the only channel between them is
-- `noctalia.state` key `deskflow`.

local M = {}

M.DEFAULT_POLL_MS = 2000
M.MIN_POLL_MS = 500
M.MAX_POLL_MS = 30000

-- Status class -> palette role. `lan` wins over `wire` in deskflow-ctl, so the
-- summary pill already follows the weakest path; keep that mapping as-is.
M.ROLE_BY_CLASS = {
  wire = "tertiary",
  lan = "primary",
  idle = "on_surface_variant",
  stopped = "outline_variant",
}

function M.roleFor(class)
  return M.ROLE_BY_CLASS[class] or M.ROLE_BY_CLASS.stopped
end

-- Seconds-free: the widget owns the `poll_ms` setting (a `[[widget.setting]]`
-- may only be read from the entry that declares it), so the lib just clamps
-- whatever it is given to the documented range.
function M.clampPollMs(value)
  return math.clamp(tonumber(value) or M.DEFAULT_POLL_MS, M.MIN_POLL_MS, M.MAX_POLL_MS)
end

function M.splitLines(text)
  local lines = {}
  if type(text) ~= "string" then
    return lines
  end
  for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
    table.insert(lines, line)
  end
  return lines
end

-- The summary tooltip's last line is the server description ("unit active on
-- host"); the panel shows it as the header subtitle.
function M.serverLine(tooltip)
  for _, line in ipairs(M.splitLines(tooltip)) do
    local value = string.match(line, "^server:%s*(.+)$")
    if value ~= nil and value ~= "" then
      return value
    end
  end
  return nil
end

-- Matches the wording deskflow-ctl prints: a decimal below 10 ms, a whole
-- number above, and "?" for a client whose socket has no RTT yet.
function M.formatLatency(rtt)
  local value = tonumber(rtt)
  if value == nil then
    return "?"
  end
  if value < 10 then
    return string.format("%.1f ms", value)
  end
  return string.format("%.0f ms", value)
end

-- `ui.graph` takes 0–1 values; the samples are milliseconds. The scale is
-- linear under an adaptive ceiling: the smallest of these round steps that
-- covers the window's largest sample, or the largest sample itself above 1000.
-- A wire client then uses the full height instead of hugging the baseline the
-- way a fixed 100 ms log curve made it, while the caption prints the ceiling so
-- the height stays readable.
local GRAPH_CEILING_STEPS = { 2, 5, 10, 20, 50, 100, 200, 500, 1000 }

-- Returns the 0–1 series and the ceiling in ms (nil when there is nothing to
-- draw). Samples are already numbers; a caller with junk in the history gets an
-- empty series rather than an error.
function M.graphSeries(history)
  local samples = {}
  local maxMs = 0
  if type(history) == "table" then
    for _, sample in ipairs(history) do
      local ms = tonumber(sample)
      if ms ~= nil then
        ms = math.max(ms, 0)
        table.insert(samples, ms)
        maxMs = math.max(maxMs, ms)
      end
    end
  end
  if #samples == 0 then
    return {}, nil
  end

  local ceiling = math.ceil(maxMs)
  for _, step in ipairs(GRAPH_CEILING_STEPS) do
    if maxMs <= step then
      ceiling = step
      break
    end
  end

  local values = {}
  for index, ms in ipairs(samples) do
    values[index] = math.clamp(ms / ceiling, 0, 1)
  end
  return values, ceiling
end

-- "min 1.19 · avg 1.27 · max 1.38 ms", the summary the old tooltip carried, or
-- nil when there is no sample to summarise.
function M.latencySummary(history)
  local count, sum, minMs, maxMs = 0, 0, nil, nil
  if type(history) == "table" then
    for _, sample in ipairs(history) do
      local ms = tonumber(sample)
      if ms ~= nil then
        count = count + 1
        sum = sum + ms
        minMs = (minMs == nil or ms < minMs) and ms or minMs
        maxMs = (maxMs == nil or ms > maxMs) and ms or maxMs
      end
    end
  end
  if count == 0 then
    return nil
  end
  return string.format("min %.2f  ·  avg %.2f  ·  max %.2f ms", minMs, sum / count, maxMs)
end

local function asString(value)
  return type(value) == "string" and value or ""
end

-- One summary/client pill, from an already-decoded table.
local function asPill(value)
  if type(value) ~= "table" then
    return nil
  end
  return {
    text = asString(value.text),
    class = asString(value.class),
    tooltip = asString(value.tooltip),
  }
end

-- One entry of `deskflow-ctl clients`.
local function asClient(entry)
  if type(entry) ~= "table" then
    return nil
  end
  local history = {}
  if type(entry.history) == "table" then
    for _, sample in ipairs(entry.history) do
      local ms = tonumber(sample)
      if ms ~= nil then
        table.insert(history, ms)
      end
    end
  end
  return {
    name = asString(entry.name),
    ip = asString(entry.ip),
    class = asString(entry.class),
    where = asString(entry.where),
    rtt = tonumber(entry.rtt),
    history = history,
  }
end

local function asClients(value)
  if type(value) ~= "table" then
    return nil
  end
  local clients = {}
  for _, entry in ipairs(value) do
    local client = asClient(entry)
    if client ~= nil then
      table.insert(clients, client)
    end
  end
  return clients
end

local function decodeJson(result)
  if result == nil or result.timedOut or result.exitCode ~= 0 then
    return nil
  end
  local raw = result.stdout
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  return noctalia.json.decode(raw)
end

function M.decodeSummary(result)
  return asPill(decodeJson(result))
end

-- nil when the command failed, an empty list when no client is connected.
function M.decodeClients(result)
  return asClients(decodeJson(result))
end

-- A `noctalia.state` snapshot from the widget replaces the poller's state, but
-- only when it is newer than the last poll here. Returns whether it applied.
function M.applySnapshot(state, value)
  if type(value) ~= "table" then
    return false
  end
  local incoming = tonumber(value.updated_ms) or 0
  if state.updated_ms ~= nil and incoming <= state.updated_ms then
    return false
  end
  state.summary = asPill(value.summary)
  state.clients = asClients(value.clients) or {}
  state.error = type(value.error) == "string" and value.error or nil
  state.updated_ms = incoming
  return true
end

-- The polling state machine, one per entry. The returned table is also the
-- state (summary / clients / error / updated_ms), so a render can be handed it
-- directly. `onUpdate` runs after every poll, changed or not.
function M.newPoller(onUpdate)
  local state = {
    summary = nil,
    clients = {},
    error = nil,
    updated_ms = nil,
    busy = false,
    pending = false,
    warned_missing = false,
  }

  local poll

  local function finish()
    state.busy = false
    state.updated_ms = noctalia.nowMs()
    onUpdate(state)
    if state.pending then
      state.pending = false
      poll()
    end
  end

  local function pollClients()
    local accepted = noctalia.runAsync({ "deskflow-ctl", "clients" }, function(result)
      state.clients = M.decodeClients(result) or {}
      finish()
    end)
    if not accepted then
      state.clients = {}
      finish()
    end
  end

  poll = function()
    if state.busy then
      state.pending = true
      return
    end
    state.busy = true
    state.pending = false
    state.error = nil

    if not noctalia.commandExists("deskflow-ctl") then
      state.summary = nil
      state.clients = {}
      state.error = "Deskflow: deskflow-ctl is not on PATH"
      if not state.warned_missing then
        state.warned_missing = true
        noctalia.log("deskflow: deskflow-ctl is not on PATH, cannot read the server state")
      end
      finish()
      return
    end

    local accepted = noctalia.runAsync({ "deskflow-ctl", "status" }, function(result)
      local summary = M.decodeSummary(result)
      if summary ~= nil then
        state.summary = summary
      else
        state.summary = nil
        state.error = "Deskflow: could not read the server status"
      end
      pollClients()
    end)

    if not accepted then
      state.summary = nil
      state.clients = {}
      state.error = "Deskflow: could not run deskflow-ctl"
      finish()
    end
  end

  -- The switch takes a moment, so look once immediately (instant feedback when
  -- it really is instant) and once after systemctl has settled.
  state.toggle = function()
    noctalia.runAsync({ "deskflow-ctl", "toggle" })
    poll()
    noctalia.runAsync({ "sleep", "0.6" }, poll)
  end

  state.poll = poll
  return state
end

return M
