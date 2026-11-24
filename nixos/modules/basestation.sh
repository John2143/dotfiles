# shellcheck shell=bash
# Valve Base Station 2.0 BLE power control; see basestation.nix.
# Stations are discovered by their LHB-* advertising name, so nothing here is
# tied to a particular unit, MAC address or GATT handle.

POWER_UUID=00001525-1212-efde-1523-785feabcd124
IDENTIFY_UUID=00008421-1212-efde-1523-785feabcd124
BLUEZ=org.bluez

usage() {
  echo "usage: basestation {status|standby|off|on|identify} [--if-idle]" >&2
  exit 2
}

# BlueZ forgets an idle LE device about 30 s after it was last seen, so a scan
# is held open for the whole run: it repopulates the list and keeps stations
# known while earlier ones are being handled.
start_scan() {
  bluetoothctl --timeout 280 scan on </dev/null >/dev/null 2>&1 &
  scan_pid=$!
  trap 'kill "$scan_pid" 2>/dev/null || true' EXIT
}

list_stations() {
  bluetoothctl devices | awk '$3 ~ /^LHB-/ {print $2 "\t" $3}' || true
}

# Prints "<mac>\t<name>" per station: polls for up to 15 s and stops once a
# non-empty list has been stable for 3 s.
discover() {
  local i found prev="" stable=0
  for ((i = 0; i < 15; i++)); do
    sleep 1
    found=$(list_stations)
    if [[ -n $found && $found == "$prev" ]]; then
      ((++stable >= 3)) && break
    else
      stable=0
    fi
    prev=$found
  done
  if [[ -n $found ]]; then
    printf '%s\n' "$found"
  fi
}

devpath_for() {
  busctl --system tree "$BLUEZ" | grep -oE "/org/bluez/hci[0-9]+/dev_${1//:/_}$" | head -1 || true
}

device_prop() {
  busctl --system get-property "$BLUEZ" "$1" org.bluez.Device1 "$2" 2>/dev/null | awk '{print $2}' || true
}

# Selecting a characteristic before services resolve fails silently, so wait.
# Gives up early if the link drops.
wait_resolved() {
  local i
  for ((i = 0; i < 20; i++)); do
    [[ $(device_prop "$1" ServicesResolved) == true ]] && return 0
    [[ $(device_prop "$1" Connected) == true ]] || return 1
    sleep 1
  done
  return 1
}

char_path() {
  busctl --system --json=short call "$BLUEZ" / org.freedesktop.DBus.ObjectManager GetManagedObjects |
    jq -r --arg d "$1/" --arg u "$2" '.data[0] | to_entries[]
      | select(.key | startswith($d))
      | select((.value["org.bluez.GattCharacteristic1"].UUID.data // "") == $u)
      | .key' | head -1 || true
}

# Prints the characteristic's single byte, normalised: no 0x, lowercase, no
# leading zeros ("02" and "2" both become "2").
read_state() {
  local raw
  raw=$(busctl --system call "$BLUEZ" "$1" org.bluez.GattCharacteristic1 ReadValue 'a{sv}' 0 | awk '{print $NF}') || return 1
  raw=${raw#0x}
  raw=${raw,,}
  while [[ $raw == 0?* ]]; do raw=${raw#0}; done
  [[ -n $raw ]] || raw=0
  printf '%s\n' "$raw"
}

state_name() {
  case $1 in
    0) echo sleep ;;
    2) echo standby ;;
    11 | b) echo on ;;
    1 | 8 | 9) echo booting ;;
    *) echo unknown ;;
  esac
}

# write_state <charpath> <decimal value> <accepted state names...>
# Writes, then reads back until the state is one of the accepted names.
write_state() {
  local path=$1 value=$2 i state
  shift 2
  busctl --system call "$BLUEZ" "$path" org.bluez.GattCharacteristic1 WriteValue 'aya{sv}' 1 "$value" 0 >/dev/null || return 1
  for ((i = 0; i < 5; i++)); do
    state=$(state_name "$(read_state "$path")") || state=unknown
    if [[ " $* " == *" $state "* ]]; then
      echo "$state"
      return 0
    fi
    sleep 1
  done
  echo "$state"
  return 1
}

disconnect() {
  busctl --system call "$BLUEZ" "$1" org.bluez.Device1 Disconnect >/dev/null 2>&1 || true
}

# Two attempts at connect + service resolution. A failed attempt is explicitly
# disconnected: bluetoothd keeps a timed-out Connect pending otherwise.
connect() {
  local devpath=$1 i err
  for ((i = 0; i < 2; i++)); do
    if err=$(timeout 25 busctl --system call "$BLUEZ" "$devpath" org.bluez.Device1 Connect 2>&1) ||
      [[ $err == *"Already Connected"* ]]; then
      wait_resolved "$devpath" && return 0
      err="GATT services never resolved"
    elif [[ -z $err ]]; then
      err="timed out"
    fi
    disconnect "$devpath"
  done
  echo "$err"
  return 1
}

fail() {
  echo "FAIL $1 ($2): $3" >&2
  rc=1
}

# handle_station <mac> <name>: connect, act, and drop only our own connection.
handle_station() {
  local mac=$1 name=$2 devpath charpath state err connected_here=0
  devpath=$(devpath_for "$mac")
  if [[ -z $devpath ]]; then
    fail "$name" "$mac" "not known to BlueZ"
    return
  fi
  if [[ $(device_prop "$devpath" Connected) == true ]]; then
    if ! wait_resolved "$devpath"; then
      fail "$name" "$mac" "GATT services never resolved"
      return
    fi
  elif err=$(connect "$devpath"); then
    connected_here=1
  else
    fail "$name" "$mac" "connect failed: $err"
    return
  fi

  if [[ $action == identify ]]; then
    charpath=$(char_path "$devpath" "$IDENTIFY_UUID")
    if [[ -z $charpath ]]; then
      fail "$name" "$mac" "identify characteristic not found"
    elif busctl --system call "$BLUEZ" "$charpath" org.bluez.GattCharacteristic1 WriteValue 'aya{sv}' 1 0 0 >/dev/null; then
      echo "$name $mac identify"
    else
      fail "$name" "$mac" "identify write failed"
    fi
  else
    charpath=$(char_path "$devpath" "$POWER_UUID")
    if [[ -z $charpath ]]; then
      fail "$name" "$mac" "power characteristic not found"
    elif [[ $action == status ]]; then
      if state=$(read_state "$charpath"); then
        echo "$name $mac $(state_name "$state")"
      else
        fail "$name" "$mac" "read failed"
      fi
    elif state=$(write_state "$charpath" "$value" "${expect[@]}"); then
      echo "$name $mac $state"
    else
      fail "$name" "$mac" "wrote $value but state is ${state:-unreadable}"
    fi
  fi

  if ((connected_here)); then
    disconnect "$devpath"
  fi
}

action=""
if_idle=0
for arg in "$@"; do
  case $arg in
    --if-idle) if_idle=1 ;;
    status | standby | off | on | identify)
      [[ -z $action ]] || usage
      action=$arg
      ;;
    *) usage ;;
  esac
done

value=""
expect=()
case $action in
  status | identify) ;;
  standby) value=2; expect=(standby) ;;
  off) value=0; expect=(sleep) ;;
  on) value=1; expect=(booting on) ;;
  *) usage ;;
esac

# pgrep takes an ERE: a bare | is alternation.
if ((if_idle)) && pgrep -f 'vrmonitor|vrserver' >/dev/null; then
  echo "skipping: SteamVR is running"
  exit 0
fi

start_scan
mapfile -t stations < <(discover)
if ((${#stations[@]} == 0)); then
  echo "no LHB stations found"
  exit 0
fi

rc=0
for line in "${stations[@]}"; do
  handle_station "${line%%$'\t'*}" "${line#*$'\t'}"
done
exit "$rc"
