# DESCRIPTION: Show system power draw from PSU, GPU, and CPU RAPL sensors
# Reads system power from Corsair PSU hwmon, nvidia-smi, and Intel RAPL.
# Shows a wall-power breakdown by rail and subsystem.
set -l psu_dir /sys/class/hwmon
set -l corsair_dir ""
for d in $psu_dir/hwmon*/
  if test "$(cat $d/name 2>/dev/null)" = "corsairpsu"
    set corsair_dir $d
    break
  end
end

# ── PSU (wall power) ──────────────────────────────────────────────
if test -n "$corsair_dir"
  set -l ac_in (math (cat $corsair_dir/power1_input) / 1000000)
  set -l v12  (math (cat $corsair_dir/power2_input) / 1000000)
  set -l v5   (math (cat $corsair_dir/power3_input) / 1000000)
  set -l v33  (math (cat $corsair_dir/power4_input) / 1000000)
  set -l psu_loss (math "$ac_in - $v12 - $v5 - $v33")

  set_color --bold
  echo "╔══════════════════════════════╗"
  echo "║   System Power (Corsair PSU) ║"
  echo "╚══════════════════════════════╝"
  set_color normal
  printf "  AC input (wall):  %5d W\n" $ac_in
  printf "    +12V rail:       %5d W\n" $v12
  printf "    +5V rail:        %5d W\n" $v5
  printf "    +3.3V rail:       %5d W\n" $v33
  set_color brblack
  printf "    PSU loss:        ~%3d W  (%.0f%%)\n" $psu_loss (math "100 - ($v12 + $v5 + $v33) / $ac_in * 100")
  set_color normal
else
  echo "Corsair PSU not found — is the USB cable connected?" >&2
end
echo ""

# ── Programmable rail breakdown ───────────────────────────────────
echo "╔══════════════════════════════╗"
echo "║   Component Estimates        ║"
echo "╚══════════════════════════════╝"

# GPU
set -l gpu_w (nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1)
if test -n "$gpu_w"
  printf "  GPU (NVIDIA):     %5.1f W\n" $gpu_w
end

# CPU + DRAM via RAPL (sample over 500ms)
set -l rapl_pkg /sys/class/powercap/intel-rapl:0
set -l rapl_core /sys/class/powercap/intel-rapl:0:0
set -l rapl_dram /sys/class/powercap/intel-rapl:0:1
if test -d "$rapl_pkg"
  set -l e_pkg_start (cat $rapl_pkg/energy_uj 2>/dev/null)
  set -l e_core_start (cat $rapl_core/energy_uj 2>/dev/null)
  set -l e_dram_start (cat $rapl_dram/energy_uj 2>/dev/null)
  sleep 0.5
  set -l e_pkg_end (cat $rapl_pkg/energy_uj 2>/dev/null)
  set -l e_core_end (cat $rapl_core/energy_uj 2>/dev/null)
  set -l e_dram_end (cat $rapl_dram/energy_uj 2>/dev/null)

  set -l pkg_power (math "($e_pkg_end - $e_pkg_start) * 2 / 1000000")
  set -l core_power (math "($e_core_end - $e_core_start) * 2 / 1000000")
  set -l dram_power (math "($e_dram_end - $e_dram_start) * 2 / 1000000")
  set -l uncore_power (math "$pkg_power - $core_power")

  printf "  CPU package:      %5.1f W\n" $pkg_power
  printf "    Cores:          %5.1f W\n" $core_power
  printf "    Uncore/LLC:     %5.1f W\n" $uncore_power
  printf "  DRAM (DIMMs):     %5.1f W\n" $dram_power
end

# Motherboard & rest (PSU +12V minus GPU minus CPU package)
if test -n "$corsair_dir" -a -n "$gpu_w" -a -n "$pkg_power"
  set -l mobo_rest (math "$v12 - $gpu_w - $pkg_power")
  printf "  Motherboard/etc:  ~%5.1f W\n" $mobo_rest
end
echo ""

# Temps (find coretemp dynamically — hwmon N varies)
set -l coretemp_dir ""
for d in /sys/class/hwmon/hwmon*/
  if test "$(cat $d/name 2>/dev/null)" = "coretemp"
    set coretemp_dir $d
    break
  end
end
set -l pkg_temp (cat $coretemp_dir/temp1_input 2>/dev/null | string sub -l 2)
set -l gpu_temp (nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
if test -n "$pkg_temp" -o -n "$gpu_temp"
  set -l temp_parts
  test -n "$pkg_temp"; and set -a temp_parts "CPU: ${pkg_temp}°C"
  test -n "$gpu_temp"; and set -a temp_parts "GPU: ${gpu_temp}°C"
  echo "  (temperatures: $(string join ' / ' $temp_parts))"
end
