--!nonstrict
-- Voxtype bar widget (replacement for the Waybar "custom/voxtype" module).
--
-- The widget mirrors `voxtype status --follow --format json`, which streams one
-- JSON object per status change:
--   {"text":"...","alt":"idle","class":"idle","tooltip":"Voxtype ready - hold hotkey to record"}
-- Classes seen in practice: idle, recording, transcribing, stopped (and error).
--
-- Rendering is imperative (setGlyph/setText/setColor/setGlyphColor/setTooltip/
-- setVisible), so the widget stays a single compact bar capsule:
--   idle          microphone, muted color, no label, optionally hidden
--   recording     microphone, error color, "REC"
--   transcribing  sparkles, secondary color, "..."
--   stopped/error microphone-off, dim (or error) color, no label
--
-- Drive it from the shell:
--   noctalia msg plugin john/voxtype:bar focused refresh

local hideWhenIdleSetting = noctalia.getConfig("hide_when_idle") == true
local showLabel = noctalia.getConfig("show_label") ~= false

local STREAM_CMD = "voxtype status --follow --format json"
local PROBE_ARGV = { "voxtype", "status", "--format", "json" }
local UPDATE_INTERVAL_MS = 5000
-- Never restart the stream more often than this; a dead stream is detected from
-- update(), so a tight loop would otherwise spawn processes every tick.
local RESTART_BACKOFF_MS = 15000
-- A live stream is silent while nothing changes, so silence alone proves nothing.
-- After this long without a line, reconcile with a one-shot status probe.
local STALE_PROBE_MS = 300000
-- The daemon needs a moment to answer after `voxtype daemon` starts.
local DAEMON_PROBE_DELAY_MS = 1500

local STATE_STYLES = {
  idle = { glyph = "microphone", color = "on_surface_variant", label = "" },
  recording = { glyph = "microphone", color = "error", label = "REC" },
  transcribing = { glyph = "sparkles", color = "secondary", label = "..." },
  stopped = { glyph = "microphone-off", color = "outline_variant", label = "" },
  error = { glyph = "microphone-off", color = "error", label = "" },
}
local FALLBACK_STYLE = { glyph = "microphone-off", color = "outline_variant", label = "" }

local state = "unknown"
local tooltip = noctalia.tr("tooltip.unknown")
local streamStartedMs = 0
local lastLineMs = 0
local lastProbeMs = 0
local probeInFlight = false
local pendingProbeMs = nil

-- Runtime-only override for the "hide when idle" behaviour: plugins read config
-- but cannot write it, so right click flips this for the current session and the
-- manifest setting stays authoritative on the next load.
local hideIdleOverride = nil

local function hidesWhenIdle()
  if hideIdleOverride ~= nil then
    return hideIdleOverride
  end
  return hideWhenIdleSetting
end

local function render()
  local style = STATE_STYLES[state] or FALLBACK_STYLE
  local label = ""
  if showLabel then
    label = style.label
  end

  barWidget.setGlyph(style.glyph)
  barWidget.setGlyphColor(style.color)
  barWidget.setColor(style.color)
  barWidget.setText(label)
  barWidget.setTooltip(tooltip)
  barWidget.setVisible(not (state == "idle" and hidesWhenIdle()))
end

local function applyStatus(payload)
  if type(payload) ~= "table" then
    return
  end

  local class = payload.class
  if type(class) == "string" and class ~= "" and STATE_STYLES[class] ~= nil then
    state = class
  else
    state = "unknown"
  end

  local reported = payload.tooltip
  if type(reported) == "string" and reported ~= "" then
    tooltip = reported
  else
    tooltip = noctalia.tr("tooltip.unknown")
  end

  render()
end

local function handleLine(line)
  if type(line) ~= "string" then
    return
  end
  local trimmed = noctalia.string.trim(line)
  if trimmed == "" then
    return
  end

  local payload, err = noctalia.json.decode(trimmed)
  if payload == nil then
    noctalia.log("voxtype: could not decode status line: " .. tostring(err))
    return
  end

  lastLineMs = noctalia.nowMs()
  applyStatus(payload)
end

local function probe()
  if probeInFlight then
    return
  end
  probeInFlight = true
  lastProbeMs = noctalia.nowMs()

  local accepted = noctalia.runAsync(PROBE_ARGV, function(result)
    probeInFlight = false
    if result == nil then
      return
    end
    if result.exitCode ~= 0 then
      state = "stopped"
      tooltip = noctalia.tr("tooltip.not_running")
      render()
      return
    end
    local line = tostring(result.stdout or ""):match("([^\r\n]+)")
    if line ~= nil then
      handleLine(line)
    end
  end)
  if not accepted then
    probeInFlight = false
    noctalia.log("voxtype: status probe was not accepted")
  end
end

local function startStream()
  streamStartedMs = noctalia.nowMs()
  local accepted = noctalia.runStream(STREAM_CMD, handleLine)
  if not accepted then
    noctalia.log("voxtype: could not start the status stream")
  end
end

-- Called on the widget's update interval. runStream has no exit callback, so the
-- only way to notice a dropped stream is to check for the process and start it
-- again.
function update()
  noctalia.setUpdateInterval(UPDATE_INTERVAL_MS)
  local now = noctalia.nowMs()

  if pendingProbeMs ~= nil and now >= pendingProbeMs then
    pendingProbeMs = nil
    probe()
  end

  if now - lastLineMs > STALE_PROBE_MS and now - lastProbeMs > STALE_PROBE_MS then
    probe()
  end

  local checked = noctalia.processMatches(function(matched)
    if matched == true then
      return
    end
    local checkedAt = noctalia.nowMs()
    if checkedAt - streamStartedMs < RESTART_BACKOFF_MS then
      return
    end
    probe()
    startStream()
  end, "voxtype", "--follow")
  if not checked then
    noctalia.log("voxtype: process scan unavailable, cannot watch the status stream")
  end
end

function onClick()
  if not noctalia.commandExists("voxtype") then
    noctalia.notifyError(noctalia.tr("title"), noctalia.tr("notify.missing"))
    return
  end

  if state == "stopped" or state == "error" then
    local accepted = noctalia.runAsync({ "voxtype", "daemon" })
    if not accepted then
      noctalia.notifyError(noctalia.tr("title"), noctalia.tr("notify.start_failed"))
      return
    end
    tooltip = noctalia.tr("tooltip.starting")
    render()
    pendingProbeMs = noctalia.nowMs() + DAEMON_PROBE_DELAY_MS
    return
  end

  if state == "unknown" then
    -- Nothing heard from the daemon yet; refresh once and let the stream report.
    probe()
    return
  end

  if not noctalia.runAsync({ "voxtype", "record", "toggle" }) then
    noctalia.notifyError(noctalia.tr("title"), noctalia.tr("notify.toggle_failed"))
  end
end

function onRightClick()
  hideIdleOverride = not hidesWhenIdle()
  render()
  if hideIdleOverride then
    noctalia.notify(noctalia.tr("title"), noctalia.tr("notify.hide_idle_on"))
  else
    noctalia.notify(noctalia.tr("title"), noctalia.tr("notify.hide_idle_off"))
  end
end

function onIpc(event, _payload)
  if event == "refresh" then
    probe()
  end
end

-- Load: start the stream once, then reconcile with a single status probe so the
-- widget is correct before the first stream line arrives.
if noctalia.commandExists("voxtype") then
  startStream()
else
  state = "stopped"
  tooltip = noctalia.tr("tooltip.missing")
end
render()
probe()
