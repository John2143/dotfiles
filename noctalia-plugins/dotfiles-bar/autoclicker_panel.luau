--!nonstrict
-- Autoclicker panel: the Eww `autoclicker-menu` window, rebuilt as a native
-- Noctalia panel. The daemon is the state; this panel reads it back with
-- `autoclicker get <field>` and writes with `autoclicker mode|set`, the same
-- calls the Eww sync script made.
local mode = "off"
local interval = "500"
local button = "left"
local target = "any"
local summary = ""
local dirty = false
local ticks = 0

local render

-- One process for the four settings rather than four: nothing here is user input,
-- and the fields are fixed.
local PROBE = [[for f in mode interval button target; do printf '%s\t%s\n' "$f" "$(autoclicker get $f 2>/dev/null)"; done]]

local function fetch()
  noctalia.runAsync(PROBE, function(result)
    for line in (result.stdout or ""):gmatch("[^\n]+") do
      local field, value = line:match("^([^\t]+)\t(.*)$")
      if field == "mode" and value ~= "" then
        mode = value
      elseif field == "interval" and value ~= "" then
        interval = value
      elseif field == "button" and value ~= "" then
        button = value
      elseif field == "target" and value ~= "" then
        target = value
      end
    end
    render()
  end)

  -- The live counters only exist in the status tooltip ("Clicks: 12",
  -- "Notches: 3", "Target: …"), so that line doubles as the summary.
  noctalia.runAsync({ "autoclicker", "status" }, function(result)
    local ok, value = pcall(noctalia.json.decode, (result.stdout or ""):match("^%s*(.-)%s*$"))
    if ok and type(value) == "table" and type(value.tooltip) == "string" then
      local parts = {}
      for line in value.tooltip:gmatch("[^\n]+") do
        if line:match("^%s*$") == nil then
          parts[#parts + 1] = line
        end
      end
      summary = table.concat(parts, " · ")
      render()
    end
  end)
end

local function act(argv)
  noctalia.runAsync(argv)
  dirty = true
end

local MODES = {
  { value = "off", label = "Off" },
  { value = "scroll-left", label = "Scroll → Left click" },
  { value = "scroll-right", label = "Scroll → Right click" },
  { value = "timer", label = "Timer (auto-click)" },
}

local INTERVALS = { "100", "250", "500", "1000" }
local BUTTONS = { "left", "middle", "right" }

local function sectionTitle(text)
  return ui.label({ text = text, fontSize = 11, fontWeight = "bold", color = "on_surface_variant" })
end

local function choiceButton(selected, label, onClick)
  return ui.button({
    text = label,
    variant = selected and "primary" or "ghost",
    selected = selected,
    contentAlign = "start",
    controlSize = "sm",
    onClick = onClick,
  })
end

function render()
  local modeChildren = {}
  for _, entry in ipairs(MODES) do
    modeChildren[#modeChildren + 1] = choiceButton(mode == entry.value, entry.label, function()
      act({ "autoclicker", "mode", entry.value })
    end)
  end

  local intervalChildren = {}
  for _, ms in ipairs(INTERVALS) do
    intervalChildren[#intervalChildren + 1] = ui.button({
      text = ms .. " ms",
      variant = interval == ms and "primary" or "ghost",
      selected = interval == ms,
      controlSize = "sm",
      flexGrow = 1,
      onClick = function()
        act({ "autoclicker", "set", "interval", ms })
      end,
    })
  end

  local buttonChildren = {}
  for _, name in ipairs(BUTTONS) do
    buttonChildren[#buttonChildren + 1] = ui.button({
      text = name:sub(1, 1):upper() .. name:sub(2),
      variant = button == name and "primary" or "ghost",
      selected = button == name,
      controlSize = "sm",
      flexGrow = 1,
      onClick = function()
        act({ "autoclicker", "set", "button", name })
      end,
    })
  end

  panel.render(ui.column({ gap = 10, padding = 12 }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.glyph({ name = "hand-click", size = 18, color = "primary" }),
      ui.label({ text = "Autoclicker", fontSize = 15, fontWeight = "bold", flexGrow = 1 }),
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

    ui.column({ gap = 6, fill = "surface_container/0.5", radius = 8, padding = 10 }, {
      sectionTitle("Mode"),
      ui.column({ gap = 4 }, modeChildren),
    }),

    ui.column({ gap = 6, fill = "surface_container/0.5", radius = 8, padding = 10 }, {
      sectionTitle("Timer interval"),
      ui.row({ gap = 6 }, intervalChildren),
      sectionTitle("Timer button"),
      ui.row({ gap = 6 }, buttonChildren),
    }),

    ui.column({ gap = 6, fill = "surface_container/0.5", radius = 8, padding = 10 }, {
      sectionTitle("Scroll target window"),
      ui.row({ gap = 6 }, {
        ui.button({
          text = "Any window",
          variant = target == "any" and "primary" or "ghost",
          selected = target == "any",
          controlSize = "sm",
          flexGrow = 1,
          onClick = function()
            act({ "autoclicker-target", "any" })
          end,
        }),
        ui.button({
          text = "Focused window",
          variant = "ghost",
          controlSize = "sm",
          flexGrow = 1,
          onClick = function()
            act({ "autoclicker-target", "focused" })
          end,
        }),
      }),
      ui.row({ gap = 6 }, {
        -- slurp needs the pointer, so the panel gets out of the way first; the
        -- Eww menu did the same by closing on hover-out.
        ui.button({
          text = "Pick with mouse…",
          variant = "outline",
          controlSize = "sm",
          flexGrow = 1,
          onClick = function()
            panel.close()
            noctalia.runAsync({ "autoclicker-target", "pick" })
          end,
        }),
        ui.button({
          text = "Clear",
          variant = "ghost",
          controlSize = "sm",
          flexGrow = 1,
          onClick = function()
            act({ "autoclicker-target", "clear" })
          end,
        }),
      }),
      ui.label({ text = "Target: " .. target, fontSize = 11, color = "on_surface_variant" }),
    }),

    ui.label({ text = summary ~= "" and summary or "Reading the daemon…", fontSize = 11, color = "on_surface_variant", maxLines = 4 }),
    ui.label({
      text = "left-click bar icon = on/off, middle = left/right, right = this menu",
      fontSize = 10,
      color = "on_surface_variant",
      maxLines = 2,
    }),
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
  -- The click counters move while the panel is open, so keep the summary live.
  if ticks % 2 == 0 then
    fetch()
  end
end

function onIpc(event)
  if event == "refresh" then
    fetch()
  end
end
