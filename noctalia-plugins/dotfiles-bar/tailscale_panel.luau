--!nonstrict
-- Tailscale panel: the Eww `tailscale` window, rebuilt as a native Noctalia panel.
--
-- Data comes from `tailscale-panel-data` (modules/status-helpers.nix), which
-- flattens `tailscale status --json` into one object:
--   { tailnet, state, icon, self_name, self_ip, exit_name, exit_ip,
--     peers_online, peers_total, exit_count,
--     peers = [ { name, ip, online, os, exit_node, active } ] }
-- If that helper is missing the same object is assembled here from `tailscale
-- status --json`, so the renderer only ever sees one shape.
local data = {
  tailnet = "",
  state = "Unavailable",
  self_name = "",
  self_ip = "",
  exit_name = "None",
  exit_ip = "",
  peers_online = 0,
  peers_total = 0,
  exit_count = 0,
  peers = {},
}

local dirty = false
local ticks = 0

local render

local STATE_LABEL = {
  Running = "Connected",
  Stopped = "Stopped",
  NeedsLogin = "Needs Login",
  NeedsMachineAuth = "Needs Machine Auth",
  Starting = "Starting",
}

local function firstIp(list)
  if type(list) == "table" and type(list[1]) == "string" then
    return list[1]
  end
  return ""
end

-- Fallback only: `tailscale status --json` -> the helper's flat shape.
local function fromStatus(raw)
  local ok, value = pcall(noctalia.json.decode, raw or "")
  if not ok or type(value) ~= "table" then
    return nil
  end

  local peers = {}
  local peersOnline, peersTotal, exitCount = 0, 0, 0
  local exitName, exitIp = "None", ""
  if type(value.Peer) == "table" then
    for _, peer in pairs(value.Peer) do
      if type(peer) == "table" then
        local name = type(peer.HostName) == "string" and peer.HostName or ""
        if name == "" then
          local dns = type(peer.DNSName) == "string" and peer.DNSName or ""
          name = dns:match("^[^.]+") or dns
        end
        local ip = firstIp(peer.TailscaleIPs)
        local online = peer.Online == true
        local exitOption = peer.ExitNodeOption == true
        peersTotal = peersTotal + 1
        if online then
          peersOnline = peersOnline + 1
        end
        if exitOption then
          exitCount = exitCount + 1
        end
        -- A peer carrying ExitNode is the exit node in use.
        if peer.ExitNode == true then
          exitName = name
          exitIp = ip
        end
        peers[#peers + 1] = {
          name = name,
          ip = ip,
          online = online,
          os = type(peer.OS) == "string" and peer.OS or "",
          exit_node = exitOption,
          active = peer.Active == true or peer.ExitNode == true,
        }
      end
    end
  end
  table.sort(peers, function(a, b)
    return a.name < b.name
  end)

  local state = type(value.BackendState) == "string" and value.BackendState or "Stopped"
  local selfInfo = type(value.Self) == "table" and value.Self or {}
  local tailnet = ""
  if type(value.CurrentTailnet) == "table" and type(value.CurrentTailnet.Name) == "string" then
    tailnet = value.CurrentTailnet.Name
  end

  return {
    tailnet = tailnet,
    state = STATE_LABEL[state] or state,
    self_name = type(selfInfo.HostName) == "string" and selfInfo.HostName or "",
    self_ip = firstIp(selfInfo.TailscaleIPs),
    exit_name = exitName,
    exit_ip = exitIp,
    peers_online = peersOnline,
    peers_total = peersTotal,
    exit_count = exitCount,
    peers = peers,
  }
end

local function fetch()
  if noctalia.commandExists("tailscale-panel-data") then
    noctalia.runAsync({ "tailscale-panel-data" }, function(result)
      local ok, value = pcall(noctalia.json.decode, (result.stdout or ""):match("^%s*(.-)%s*$"))
      if ok and type(value) == "table" then
        data = value
        render()
      end
    end)
    return
  end
  noctalia.runAsync({ "tailscale", "status", "--json" }, function(result)
    local built = fromStatus(result.stdout)
    if built then
      data = built
      render()
    end
  end)
end

local function act(argv)
  noctalia.runAsync(argv)
  dirty = true
end

-- `tailscale-toggle` is the packaged helper; the Eww-era script stays the
-- fallback so the button works on a host that has not been switched over yet.
local function toggleConnect()
  if noctalia.commandExists("tailscale-toggle") then
    act({ "tailscale-toggle" })
  else
    act({ "tailscale-eww-toggle" })
  end
end

local function dot(color)
  return ui.box({ width = 8, height = 8, radius = 4, fill = color })
end

local function card(children)
  return ui.column({ gap = 4, fill = "surface_container/0.5", radius = 8, padding = 10 }, children)
end

local function sectionTitle(text)
  return ui.label({ text = text, fontSize = 11, fontWeight = "bold", color = "on_surface_variant" })
end

function render()
  local d = data
  local connected = d.state == "Connected"
  local peers = d.peers or {}

  local peerRows = {}
  for _, peer in ipairs(peers) do
    local name = peer.name or ""
    local children = {
      dot(peer.online and "tertiary" or "outline_variant"),
      ui.label({ text = name, fontSize = 12, maxLines = 1, maxWidth = 170, flexGrow = 1 }),
    }
    if peer.exit_node then
      children[#children + 1] = ui.label({ text = "exit", fontSize = 10, color = "secondary" })
    end
    children[#children + 1] = ui.label({ text = peer.ip or "", fontSize = 11, color = "on_surface_variant" })
    peerRows[#peerRows + 1] = ui.row({ key = "peer-" .. name, align = "center", gap = 8 }, children)
  end

  local peerChildren = {
    ui.row({ align = "center", gap = 8 }, {
      sectionTitle("Peers (" .. tostring(d.peers_online or 0) .. "/" .. tostring(d.peers_total or 0) .. ")"),
      ui.label({
        text = tostring(d.exit_count or 0) .. " exit nodes",
        fontSize = 10,
        color = "on_surface_variant",
        flexGrow = 1,
        textAlign = "end",
      }),
    }),
  }
  if #peerRows == 0 then
    peerChildren[#peerChildren + 1] = ui.label({ text = "No peers", fontSize = 12, color = "on_surface_variant" })
  else
    for _, row in ipairs(peerRows) do
      peerChildren[#peerChildren + 1] = row
    end
  end

  panel.render(ui.column({ gap = 10, padding = 12 }, {
    -- Header
    ui.row({ align = "center", gap = 8 }, {
      ui.glyph({ name = "network", size = 18, color = connected and "primary" or "on_surface_variant" }),
      ui.label({ text = "Tailscale", fontSize = 15, fontWeight = "bold" }),
      ui.label({ text = d.tailnet or "", fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
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

    -- Connection status
    card({
      ui.row({ align = "center", gap = 8 }, {
        dot(connected and "tertiary" or "outline_variant"),
        ui.label({
          text = d.state or "Unknown",
          fontSize = 12,
          fontWeight = "bold",
          color = connected and "tertiary" or "on_surface",
          flexGrow = 1,
        }),
        ui.label({ text = d.self_ip or "", fontSize = 11, color = "on_surface_variant" }),
      }),
    }),

    -- Your node
    card({
      sectionTitle("Your Node"),
      ui.row({ align = "center", gap = 8 }, {
        dot(connected and "tertiary" or "outline_variant"),
        ui.label({ text = d.self_name or "", fontSize = 12, flexGrow = 1, maxLines = 1, maxWidth = 200 }),
        ui.label({ text = d.self_ip or "", fontSize = 11, color = "on_surface_variant" }),
      }),
    }),

    -- Exit node
    card({
      sectionTitle("Exit Node"),
      ui.row({ align = "center", gap = 8 }, {
        ui.column({ gap = 2, flexGrow = 1 }, {
          ui.label({ text = d.exit_name or "None", fontSize = 12, maxLines = 1, maxWidth = 220 }),
          ui.label({
            text = (d.exit_ip ~= nil and d.exit_ip ~= "") and d.exit_ip or " ",
            fontSize = 10,
            color = "on_surface_variant",
          }),
        }),
        ui.button({
          text = "Change…",
          variant = "outline",
          controlSize = "sm",
          onClick = function()
            act({ "tailscale-exit-node" })
          end,
        }),
      }),
    }),

    -- Quick actions
    ui.row({ gap = 8 }, {
      ui.button({ text = "Toggle Connect", variant = "secondary", controlSize = "sm", flexGrow = 1, onClick = toggleConnect }),
      ui.button({ text = "Exit Nodes", variant = "outline", controlSize = "sm", flexGrow = 1, onClick = function()
        act({ "tailscale-exit-node" })
      end }),
      ui.button({ text = "Refresh", variant = "ghost", controlSize = "sm", flexGrow = 1, onClick = function()
        fetch()
      end }),
    }),

    ui.scroll({ flexGrow = 1, gap = 6 }, peerChildren),
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
  -- Peers come and go on their own; a slow poll keeps the list honest while the
  -- panel is up.
  ticks = ticks + 1
  if ticks % 30 == 0 then
    fetch()
  end
end

function onIpc(event)
  if event == "refresh" then
    fetch()
  end
end
