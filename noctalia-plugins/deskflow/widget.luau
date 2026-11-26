--!nonstrict
-- Deskflow server pill for the Noctalia bar.
--
-- Only the server summary is drawn here; the per-client rows, each with its
-- latency graph, live in the panel that right click opens. `deskflow-ctl`
-- (nixos/packages/deskflow-ctl.nix) is the data source, and the poller in
-- lib/ is shared with the panel: this entry publishes the whole poll result
-- through `noctalia.state` key `deskflow`, so an open panel follows it.
--
-- IPC: `noctalia msg plugin john/deskflow:bar all refresh|toggle`.

local deskflow = require("./lib/deskflow.luau")

-- `poll_ms` is declared by this widget, so only this entry may read it; the lib
-- only clamps what it is handed.
local pollMs = deskflow.clampPollMs(noctalia.getConfig("poll_ms"))
local render
local poller = deskflow.newPoller(function(state)
  render(state)
  noctalia.state.set("deskflow", {
    summary = state.summary,
    clients = state.clients,
    error = state.error,
    updated_ms = state.updated_ms,
  })
end)

render = function(state)
  local summary = state.summary
  local class = (summary ~= nil and summary.class ~= "") and summary.class or "stopped"
  local tone = deskflow.roleFor(class)

  local tip = "Deskflow: reading status…"
  if summary ~= nil and summary.tooltip ~= "" then
    tip = summary.tooltip
  elseif state.error ~= nil then
    tip = state.error
  end

  barWidget.render(ui.row({
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
end

function onClick()
  poller.toggle()
end

function onPrimaryClick()
  poller.toggle()
end

function onMiddleClick()
  poller.poll()
end

function onIpc(event)
  if event == "refresh" then
    poller.poll()
  elseif event == "toggle" then
    poller.toggle()
  end
end

function update()
  poller.poll()
end

noctalia.setUpdateInterval(pollMs)
render(poller)
poller.poll()
