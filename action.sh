#!/system/bin/sh
# Action toggle ON/OFF for thermal_killer_z9(CN)_v1.0 (iQOO Z9 CN - V2361A)

MODDIR=${0%/*}
FLAG="$MODDIR/toggle_off"
ORIG="$MODDIR/orig_state"
LOCK="$MODDIR/.daemon.lock"

alive() {
  [ -f "$LOCK" ] || return 1
  p=$(cat "$LOCK" 2>/dev/null); [ -n "$p" ] || return 1
  kill -0 "$p" 2>/dev/null || return 1
  tr "\0" " " < "/proc/$p/cmdline" 2>/dev/null | grep -q vivo_iqoo_thermal_killer
}

desc() {
  sed -i "s|^description=.*|description=$1|" "$MODDIR/module.prop" 2>/dev/null
}

restart_gamewatch() {
  pids=$(pidof com.vivo.gamewatch 2>/dev/null)
  if [ -n "$pids" ]; then
    for gp in $pids; do kill "$gp" 2>/dev/null; done
  else
    am force-stop com.vivo.gamewatch 2>/dev/null
  fi
}

if alive && [ ! -f "$FLAG" ]; then
  # ---- ON -> OFF (100% Stock Restore for V2361A) ----
  touch "$FLAG"
  for proc in /proc/[0-9]*; do
    pid=${proc##*/}; [ "$pid" = "$$" ] && continue
    case "$(tr "\0" " " < "$proc/cmdline" 2>/dev/null)" in
      *"/vivo_iqoo_thermal_killer/service.sh --daemon-loop"*) kill "$pid" 2>/dev/null ;;
    esac
  done
  rm -f "$LOCK"

  WALT_TP=0
  RSC_FLA=1
  RSC_MIN_CAP=850
  [ -f "$ORIG" ] && . "$ORIG"
  [ -e /proc/sys/walt/sched_enable_tp ] && echo "${WALT_TP:-0}" > /proc/sys/walt/sched_enable_tp 2>/dev/null
  [ -e /sys/rsc/fas/fla_enable ] && echo "${RSC_FLA:-1}" > /sys/rsc/fas/fla_enable 2>/dev/null
  [ -e /sys/rsc/fas/fla_min_cap_guarantee ] && echo "${RSC_MIN_CAP:-850}" > /sys/rsc/fas/fla_min_cap_guarantee 2>/dev/null
  rm -f "$ORIG"

  cmd thermalservice reset >/dev/null 2>&1
  setprop persist.debug.rms.thermal_fps_adjuster true 2>/dev/null
  restart_gamewatch
  settings delete system min_refresh_rate >/dev/null 2>&1
  settings put system gamewatch_game_target_fps -1 >/dev/null 2>&1
  setprop persist.vendor.vperf_launch_thermal true 2>/dev/null
  setprop persist.vivo.benchmark_thermal.enable 0 2>/dev/null

  start thermal-engine 2>/dev/null; setprop ctl.start thermal-engine 2>/dev/null
  for s in android.thermal-hal vivo-vperf-hal-1-0 vendor.perfservice vendor.vivoperfservice; do
    start "$s" 2>/dev/null; setprop ctl.start "$s" 2>/dev/null
  done
  setprop ctl.interface_start android.hardware.thermal@2.0::IThermal/default 2>/dev/null
  setprop ctl.interface_start vendor.vivo.hardware.vperf@1.0::IVPerf/default 2>/dev/null

  sleep 2
  desc "[⚪ OFF · Đã trả zin 100%] Bấm Thao tác (Action) để BẬT tắt nhiệt + giữ FPS gốc."
  echo "thermal_killer_z9(CN)_v1.0: OFF (DA TRA ZIN 100%)"
  echo "- fla_enable / min_cap: $(cat /sys/rsc/fas/fla_enable 2>/dev/null) / $(cat /sys/rsc/fas/fla_min_cap_guarantee 2>/dev/null)"
  echo "- thermal_fps_adjuster: $(getprop persist.debug.rms.thermal_fps_adjuster)"
  echo "- thermal-engine:       $(getprop init.svc.thermal-engine)"
  echo "- gamewatch PID:        $(pidof com.vivo.gamewatch 2>/dev/null)"
  dumpsys thermalservice 2>/dev/null | grep -E "IsStatusOverride|Thermal Status" | sed "s/^/- /"
else
  # ---- OFF -> ON ----
  rm -f "$FLAG"
  sh "$MODDIR/service.sh" </dev/null >/dev/null 2>&1
  sleep 2
  if alive; then
    desc "[✅ ON · Đang chạy] Đã tắt bóp nhiệt CPU/GPU + giữ FPS gốc (60/90/120Hz). Bấm Action để tắt."
    echo "thermal_killer_z9(CN)_v1.0: ON"
    echo "- daemon PID:           $(cat "$LOCK")"
    echo "- fla_enable / min_cap: $(cat /sys/rsc/fas/fla_enable 2>/dev/null) / $(cat /sys/rsc/fas/fla_min_cap_guarantee 2>/dev/null)"
    echo "- thermal_fps_adjuster: $(getprop persist.debug.rms.thermal_fps_adjuster)"
    echo "- thermal-engine:       $(getprop init.svc.thermal-engine)"
    echo "- gamewatch PID:        $(pidof com.vivo.gamewatch 2>/dev/null)"
    dumpsys thermalservice 2>/dev/null | grep -E "IsStatusOverride|Thermal Status" | sed "s/^/- /"
  else
    touch "$FLAG"
    echo "Khong khoi dong duoc daemon - kiem tra $MODDIR/thermal_killer.log"
  fi
fi
