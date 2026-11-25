#!/system/bin/sh
# thermal_killer_z9(CN)_v1.1 - Pure build for vivo iQOO Z9 CN (V2361A / PD2361 / SM7550 / OriginOS 5)
# Zero dead code, zero non-existent nodes, zero system/vendor mounts.

MODDIR=${0%/*}
[ -f "$MODDIR/toggle_off" ] && [ -z "$1" ] && exit 0

LOG="$MODDIR/thermal_killer.log"
LOCK="$MODDIR/.daemon.lock"
ORIG="$MODDIR/orig_state"

INTERVAL=1
CYCLE=0
LOG_WRITE_COUNT=0
LAST_LOG_MESSAGE=

# Config defaults for iQOO Z9 CN (V2361A)
CAP_MODE=force          # force | manual
FLA_MODE=disable        # disable | observe
HEATCTL_MODE=auto       # auto | disable | observe
EXTRA_SERVICES=on       # on | off | all
GPU_MODE=unlock         # unlock | off
FPS_MODE=unlock         # unlock | off
GUARD_LIMIT=0           # 0 (off) or 60..100 (°C)
GPU_LOCK_MAX=off        # off | on (opt-in: lock GPU floor to 975MHz)
CPU_LOCK_MAX=off        # off | on (opt-in: lock CPU min_freq to max_freq)

CONFIG_LAST_CYCLE=-100
SERVICE_LAST_CYCLE=-100
DISCOVERY_LAST_CYCLE=-100
GPU_LAST_CYCLE=-100
FPS_LAST_CYCLE=-100
FPS_INIT_DONE=0
EXTRA_IFACE_DONE=0
EXTRA_LOGGED=
GPU_LOCK_APPLIED=0
CPU_LOCK_APPLIED=0

THERMAL_STATE_NODES=""
KGSL_PWRLEVEL="/sys/class/kgsl/kgsl-3d0/thermal_pwrlevel"
KGSL_MIN_PWR="/sys/class/kgsl/kgsl-3d0/min_pwrlevel"
KGSL_MAX_MHZ="/sys/class/kgsl/kgsl-3d0/max_clock_mhz"
KGSL_DEVFREQ_MAX="/sys/class/kgsl/kgsl-3d0/devfreq/max_freq"
KGSL_AVAIL_FREQ="/sys/class/kgsl/kgsl-3d0/gpu_available_frequencies"
KGSL_WRITE_FAILS=0
KGSL_STOCK_MIN_PWR=7

RSC_FLA="/sys/rsc/fas/fla_enable"
RSC_MIN_CAP="/sys/rsc/fas/fla_min_cap_guarantee"
RSC_QOS="/sys/rsc/fas/fla_freq_qos_req"
RSC_HEATCTL="/sys/rsc/svp/cpulimit"
WALT_TP="/proc/sys/walt/sched_enable_tp"

POLICIES="/sys/devices/system/cpu/cpufreq/policy0 /sys/devices/system/cpu/cpufreq/policy4 /sys/devices/system/cpu/cpufreq/policy7"
MIN_P0=614400
MIN_P4=652800
MIN_P7=652800
MAX_P0=1804800
MAX_P4=2400000
MAX_P7=2630400
GPU_HW_MAX_MHZ=975
GPU_HW_MAX_HZ=975000000

COOL_HITS=0
COOL_LAST=
HEATCTL_RESULT="unknown"
HEATCTL_LAST_STATE=""

GUARD_ON=0
GUARD_HYST=5000
GUARD_HOLD=60
GUARD_SINCE=0
GUARD_ZONES=""
ZONE_SKIN=""
ZONE_SHELL=""
ZONE_BAT=""

log() {
  msg="$*"
  [ "$msg" = "$LAST_LOG_MESSAGE" ] && return 0
  LAST_LOG_MESSAGE="$msg"
  LOG_WRITE_COUNT=$((LOG_WRITE_COUNT + 1))
  if [ "$LOG_WRITE_COUNT" -ge 200 ] && [ -f "$LOG" ]; then
    LOG_WRITE_COUNT=0
    sz=$(wc -c < "$LOG" 2>/dev/null)
    case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
    if [ "$sz" -gt 262144 ]; then
      tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
    fi
  fi
  printf '[%s] %s\n' "$(date '+%m-%d %H:%M:%S')" "$msg" >> "$LOG" 2>/dev/null
}

init_hw_caps() {
  v=
  [ -r /sys/devices/system/cpu/cpufreq/policy0/cpuinfo_max_freq ] && IFS= read -r v < /sys/devices/system/cpu/cpufreq/policy0/cpuinfo_max_freq 2>/dev/null
  case "$v" in ''|*[!0-9]*) ;; *) MAX_P0=$v ;; esac
  v=
  [ -r /sys/devices/system/cpu/cpufreq/policy4/cpuinfo_max_freq ] && IFS= read -r v < /sys/devices/system/cpu/cpufreq/policy4/cpuinfo_max_freq 2>/dev/null
  case "$v" in ''|*[!0-9]*) ;; *) MAX_P4=$v ;; esac
  v=
  [ -r /sys/devices/system/cpu/cpufreq/policy7/cpuinfo_max_freq ] && IFS= read -r v < /sys/devices/system/cpu/cpufreq/policy7/cpuinfo_max_freq 2>/dev/null
  case "$v" in ''|*[!0-9]*) ;; *) MAX_P7=$v ;; esac

  if [ -r "$KGSL_AVAIL_FREQ" ]; then
    gmax=0
    for gf in $(cat "$KGSL_AVAIL_FREQ" 2>/dev/null); do
      case "$gf" in ''|*[!0-9]*) continue ;; esac
      [ "$gf" -gt "$gmax" ] && gmax=$gf
    done
    if [ "$gmax" -ge 100000 ]; then
      GPU_HW_MAX_HZ=$gmax
      GPU_HW_MAX_MHZ=$((gmax / 1000000))
    elif [ "$gmax" -gt 0 ]; then
      GPU_HW_MAX_MHZ=$gmax
      GPU_HW_MAX_HZ=$((gmax * 1000000))
    fi
  fi

  if [ -r /sys/class/kgsl/kgsl-3d0/num_pwrlevels ]; then
    IFS= read -r _np < /sys/class/kgsl/kgsl-3d0/num_pwrlevels 2>/dev/null
    case "$_np" in ''|*[!0-9]*) ;; *) [ "$_np" -gt 1 ] && KGSL_STOCK_MIN_PWR=$((_np - 1)) ;; esac
  fi
  if [ -r "$ORIG" ]; then
    while IFS='=' read -r _ok _ov; do
      case "$_ok" in
        MIN_P0) case "$_ov" in ''|*[!0-9]*) ;; *) MIN_P0=$_ov ;; esac ;;
        MIN_P4) case "$_ov" in ''|*[!0-9]*) ;; *) MIN_P4=$_ov ;; esac ;;
        MIN_P7) case "$_ov" in ''|*[!0-9]*) ;; *) MIN_P7=$_ov ;; esac ;;
        KGSL_STOCK_MIN_PWR) case "$_ov" in ''|*[!0-9]*) ;; *) KGSL_STOCK_MIN_PWR=$_ov ;; esac ;;
      esac
    done < "$ORIG"
  fi

  # Discover thermal zones once for guard & snapshot
  GUARD_ZONES=""
  for z in /sys/class/thermal/thermal_zone*; do
    [ -r "$z/type" ] || continue
    zt=
    IFS= read -r zt < "$z/type" 2>/dev/null
    case "$zt" in
      cpu-*|cpuss-*|gpuss-*|gpu-*) GUARD_ZONES="$GUARD_ZONES $z" ;;
      chg-skin-therm-usr) ZONE_SKIN="$z" ;;
      tz_game_shell) ZONE_SHELL="$z" ;;
      battery) ZONE_BAT="$z" ;;
    esac
  done
}

read_config() {
  if [ -f "$MODDIR/.reload" ]; then
    rm -f "$MODDIR/.reload" 2>/dev/null
    CONFIG_LAST_CYCLE=-100
    DISCOVERY_LAST_CYCLE=-100
    SERVICE_LAST_CYCLE=-100
    GPU_LAST_CYCLE=-100
    FPS_LAST_CYCLE=-100
    EXTRA_IFACE_DONE=0
    FPS_INIT_DONE=0
  fi
  [ $((CYCLE - CONFIG_LAST_CYCLE)) -ge 5 ] || return 0
  CONFIG_LAST_CYCLE=$CYCLE

  CAP_MODE=force
  FLA_MODE=disable
  HEATCTL_MODE=auto
  EXTRA_SERVICES=on
  GPU_MODE=unlock
  FPS_MODE=unlock
  GUARD_LIMIT=0
  GPU_LOCK_MAX=off
  CPU_LOCK_MAX=off

  if [ -f "$MODDIR/cap_mode" ]; then
    IFS= read -r v < "$MODDIR/cap_mode" 2>/dev/null
    case "$v" in force|manual) CAP_MODE="$v" ;; esac
  fi
  if [ -f "$MODDIR/fla_mode" ]; then
    IFS= read -r v < "$MODDIR/fla_mode" 2>/dev/null
    case "$v" in disable|observe) FLA_MODE="$v" ;; esac
  fi
  if [ -f "$MODDIR/heatctl_mode" ]; then
    IFS= read -r v < "$MODDIR/heatctl_mode" 2>/dev/null
    case "$v" in auto|disable|observe) HEATCTL_MODE="$v" ;; esac
  fi
  if [ -f "$MODDIR/extra_services" ]; then
    IFS= read -r v < "$MODDIR/extra_services" 2>/dev/null
    case "$v" in on|off|all) EXTRA_SERVICES="$v" ;; esac
  fi
  if [ -f "$MODDIR/gpu_mode" ]; then
    IFS= read -r v < "$MODDIR/gpu_mode" 2>/dev/null
    case "$v" in unlock|off) GPU_MODE="$v" ;; esac
  fi
  if [ -f "$MODDIR/fps_mode" ]; then
    IFS= read -r v < "$MODDIR/fps_mode" 2>/dev/null
    case "$v" in unlock|off) FPS_MODE="$v" ;; esac
  fi
  if [ -f "$MODDIR/gpu_lock_max" ]; then
    IFS= read -r v < "$MODDIR/gpu_lock_max" 2>/dev/null
    case "$v" in on|off) GPU_LOCK_MAX="$v" ;; esac
  fi
  if [ -f "$MODDIR/cpu_lock_max" ]; then
    IFS= read -r v < "$MODDIR/cpu_lock_max" 2>/dev/null
    case "$v" in on|off) CPU_LOCK_MAX="$v" ;; esac
  fi
  if [ -f "$MODDIR/temp_guard" ]; then
    IFS= read -r v < "$MODDIR/temp_guard" 2>/dev/null
    case "$v" in
      off|'') GUARD_LIMIT=0 ;;
      *[!0-9]*) ;;
      *) [ "$v" -ge 60 ] && [ "$v" -le 100 ] && GUARD_LIMIT=$((v * 1000)) ;;
    esac
  fi
}

discover_cooling_nodes() {
  [ $((CYCLE - DISCOVERY_LAST_CYCLE)) -ge 30 ] || return 0
  DISCOVERY_LAST_CYCLE=$CYCLE
  nodes=""
  for d in /sys/class/thermal/cooling_device*; do
    [ -r "$d/type" ] && [ -e "$d/cur_state" ] || continue
    IFS= read -r t < "$d/type" 2>/dev/null
    case "$t" in
      cpufreq-cpu*|cpu-cluster*|thermal-cluster*|cpu-hotplug*|pause-cpu*|thermal-pause-*|gpu|devfreq-3d00000.qcom,kgsl-3d0|ddr-cdev)
        nodes="${nodes:+$nodes }$d/cur_state"
        ;;
      display-fps)
        [ "$FPS_MODE" = "unlock" ] && nodes="${nodes:+$nodes }$d/cur_state"
        ;;
    esac
  done
  THERMAL_STATE_NODES="$nodes"
}

guard_check() {
  if [ "$GUARD_LIMIT" -le 0 ]; then
    GUARD_ON=0
    return 0
  fi
  [ $((CYCLE % 2)) -eq 1 ] || return 0
  gtmax=0
  gtz=""
  for z in $GUARD_ZONES; do
    [ -r "$z/temp" ] || continue
    IFS= read -r t < "$z/temp" 2>/dev/null
    case "$t" in ''|*[!0-9]*) continue ;; esac
    if [ "$t" -gt "$gtmax" ]; then
      gtmax=$t
      gtz="$z"
    fi
  done
  if [ "$GUARD_ON" = "0" ]; then
    if [ "$gtmax" -ge "$GUARD_LIMIT" ]; then
      GUARD_ON=1
      GUARD_SINCE=$CYCLE
      zt=""
      [ -n "$gtz" ] && IFS= read -r zt < "$gtz/type" 2>/dev/null
      log "GUARD ON: tmax=${gtmax}(${zt:-?}) >= ${GUARD_LIMIT} -> tam tra dieu khien nhiet"
      release_clock_locks
      start thermal-engine 2>/dev/null
      setprop ctl.start thermal-engine 2>/dev/null
      cmd thermalservice reset >/dev/null 2>&1
    fi
  elif [ "$gtmax" -le $((GUARD_LIMIT - GUARD_HYST)) ] && [ $((CYCLE - GUARD_SINCE)) -ge "$GUARD_HOLD" ]; then
    GUARD_ON=0
    SERVICE_LAST_CYCLE=-100
    FPS_LAST_CYCLE=-100
    log "GUARD OFF: tmax=${gtmax} <= $((GUARD_LIMIT - GUARD_HYST))"
  fi
}

block_services() {
  [ $((CYCLE - SERVICE_LAST_CYCLE)) -ge 5 ] || return 0
  SERVICE_LAST_CYCLE=$CYCLE

  ts=$(getprop init.svc.thermal-engine 2>/dev/null)
  case "$ts" in
    running|restarting|stopping)
      stop thermal-engine 2>/dev/null
      setprop ctl.stop thermal-engine 2>/dev/null
      ;;
  esac

  # Zero-fork scan of /proc/PID/comm for thermal-engine-v2
  for proc in /proc/[0-9]*; do
    pid=${proc##*/}
    [ "$pid" = "$$" ] && continue
    [ -r "$proc/comm" ] || continue
    IFS= read -r comm < "$proc/comm" 2>/dev/null
    case "$comm" in
      thermal-engine*) kill -9 "$pid" 2>/dev/null ;;
    esac
  done

  [ "$EXTRA_SERVICES" = "off" ] && return 0
  svc_list="vivo-vperf-hal-1-0 vendor.perfservice vendor.vivoperfservice"
  [ "$EXTRA_SERVICES" = "all" ] && svc_list="android.thermal-hal $svc_list"

  stopped_now=""
  for s in $svc_list; do
    st=$(getprop init.svc.$s 2>/dev/null)
    case "$st" in
      running|restarting|stopping)
        stop "$s" 2>/dev/null
        setprop ctl.stop "$s" 2>/dev/null
        stopped_now="${stopped_now:+$stopped_now }$s($st)"
        ;;
    esac
  done
  if [ -n "$stopped_now" ] && [ "$stopped_now" != "$EXTRA_LOGGED" ]; then
    EXTRA_LOGGED="$stopped_now"
    log "Da dung dich vu phu: $stopped_now"
  fi
  if [ "$EXTRA_IFACE_DONE" = "0" ]; then
    EXTRA_IFACE_DONE=1
    [ "$EXTRA_SERVICES" = "all" ] && setprop ctl.interface_stop android.hardware.thermal@2.0::IThermal/default 2>/dev/null
    setprop ctl.interface_stop vendor.vivo.hardware.vperf@1.0::IVPerf/default 2>/dev/null
  fi
}

handle_rsc_and_walt() {
  if [ "$FLA_MODE" = "disable" ] && [ -e "$RSC_FLA" ]; then
    IFS= read -r v < "$RSC_FLA" 2>/dev/null
    if [ "$v" != "0" ]; then
      chmod 0664 "$RSC_FLA" 2>/dev/null
      printf '0\n' > "$RSC_FLA" 2>/dev/null && log "RSC FLA: ${v:-?} -> 0"
    fi
  fi

  if [ "$CAP_MODE" = "force" ] && [ -e "$RSC_MIN_CAP" ]; then
    IFS= read -r v < "$RSC_MIN_CAP" 2>/dev/null
    if [ "$v" != "1000" ]; then
      chmod 0664 "$RSC_MIN_CAP" 2>/dev/null
      printf '1000\n' > "$RSC_MIN_CAP" 2>/dev/null && log "RSC FLA min_cap: ${v:-?} -> 1000"
    fi
  fi

  if [ -e "$WALT_TP" ]; then
    IFS= read -r v < "$WALT_TP" 2>/dev/null
    if [ -n "$v" ] && [ "$v" != "0" ]; then
      chmod 0644 "$WALT_TP" 2>/dev/null
      printf '0\n' > "$WALT_TP" 2>/dev/null
    fi
  fi

  if [ $((CYCLE % 5)) -eq 1 ] && [ -e "$RSC_HEATCTL" ]; then
    st=$(grep -m 1 -E 'enable cpulimit|disable cpulimit|halt_cpu' "$RSC_HEATCTL" 2>/dev/null | tr '\n\t\r' ' ')
    case "$st" in
      *"enable cpulimit"*)
        if [ "$HEATCTL_MODE" != "observe" ]; then
          chmod 0664 "$RSC_HEATCTL" 2>/dev/null
          printf '88000060 0\n' > "$RSC_HEATCTL" 2>/dev/null
          after=$(grep -m 1 -E 'enable cpulimit|disable cpulimit|halt_cpu' "$RSC_HEATCTL" 2>/dev/null | tr '\n\t\r' ' ')
          HEATCTL_RESULT="disabled"
          [ "$after" != "$HEATCTL_LAST_STATE" ] && { HEATCTL_LAST_STATE="$after"; log "RSC heatctl da tat: $after"; }
        else
          HEATCTL_RESULT="enabled(observe)"
        fi
        ;;
      *)
        HEATCTL_RESULT="inactive"
        ;;
    esac
  fi
}

clear_cooling_and_caps() {
  for node in $THERMAL_STATE_NODES; do
    IFS= read -r st < "$node" 2>/dev/null
    if [ -n "$st" ] && [ "$st" != "0" ]; then
      COOL_HITS=$((COOL_HITS + 1))
      cdir=${node%/cur_state}
      IFS= read -r cname < "$cdir/type" 2>/dev/null
      COOL_LAST="${cdir##*/}:${cname:-?}=$st"
      chmod 0644 "$node" 2>/dev/null
      printf '0\n' > "$node" 2>/dev/null
    fi
  done

  if [ -f "$KGSL_PWRLEVEL" ] && [ "$KGSL_WRITE_FAILS" -lt 3 ]; then
    IFS= read -r gp < "$KGSL_PWRLEVEL" 2>/dev/null
    if [ -n "$gp" ] && [ "$gp" != "0" ]; then
      chmod 0644 "$KGSL_PWRLEVEL" 2>/dev/null
      printf '0\n' > "$KGSL_PWRLEVEL" 2>/dev/null
      IFS= read -r gp2 < "$KGSL_PWRLEVEL" 2>/dev/null
      [ "$gp2" = "0" ] || KGSL_WRITE_FAILS=$((KGSL_WRITE_FAILS + 1))
    fi
  fi

  if [ "$CAP_MODE" = "force" ]; then
    for pair in "0:$MAX_P0" "4:$MAX_P4" "7:$MAX_P7"; do
      idx=${pair%:*}
      mx=${pair#*:}
      snode="/sys/devices/system/cpu/cpufreq/policy$idx/scaling_max_freq"
      [ -r "$snode" ] || continue
      IFS= read -r cur < "$snode" 2>/dev/null
      if [ -n "$cur" ] && [ "$cur" != "$mx" ]; then
        chmod 0644 "$snode" 2>/dev/null
        printf '%s\n' "$mx" > "$snode" 2>/dev/null
      fi
    done
  fi
}

unlock_gpu_and_fps() {
  if [ "$GPU_MODE" = "unlock" ] && [ $((CYCLE - GPU_LAST_CYCLE)) -ge 30 ]; then
    GPU_LAST_CYCLE=$CYCLE
    if [ -r "$KGSL_MAX_MHZ" ]; then
      IFS= read -r gcur < "$KGSL_MAX_MHZ" 2>/dev/null
      case "$gcur" in ''|*[!0-9]*) gcur=0 ;; esac
      if [ "$gcur" -lt "$GPU_HW_MAX_MHZ" ]; then
        chmod 0644 "$KGSL_MAX_MHZ" 2>/dev/null
        printf '%s\n' "$GPU_HW_MAX_MHZ" > "$KGSL_MAX_MHZ" 2>/dev/null
        if [ -e "$KGSL_DEVFREQ_MAX" ]; then
          chmod 0644 "$KGSL_DEVFREQ_MAX" 2>/dev/null
          printf '%s\n' "$GPU_HW_MAX_HZ" > "$KGSL_DEVFREQ_MAX" 2>/dev/null
        fi
        log "GPU max_clock_mhz: $gcur -> $GPU_HW_MAX_MHZ MHz"
      fi
    fi
  fi

  if [ "$FPS_MODE" = "unlock" ] && [ $((CYCLE - FPS_LAST_CYCLE)) -ge 30 ]; then
    FPS_LAST_CYCLE=$CYCLE
    cmd thermalservice override-status 0 >/dev/null 2>&1
    cmd thermalservice inject-temperature SKIN NONE skin 30.0 >/dev/null 2>&1

    if [ "$FPS_INIT_DONE" = "0" ]; then
      FPS_INIT_DONE=1
      prev_tfa=$(getprop persist.debug.rms.thermal_fps_adjuster 2>/dev/null)
      setprop persist.debug.rms.thermal_fps_adjuster false 2>/dev/null
      if [ "$prev_tfa" != "false" ]; then
        for gwp in $(pidof com.vivo.gamewatch 2>/dev/null); do
          kill "$gwp" 2>/dev/null
        done
      fi
      settings put system gamewatch_game_target_fps 0 >/dev/null 2>&1
      setprop persist.vendor.vperf_launch_thermal false 2>/dev/null
      setprop persist.vivo.benchmark_thermal.enable 1 2>/dev/null
      log "FPS unlock ON: thermal_fps_adjuster=false (prev=${prev_tfa:-empty}), override-status=0, SKIN=NONE (tu khop 60/90/120Hz)"
    fi
  fi
}

log_z9_snapshot() {
  [ $((CYCLE % 30)) -eq 1 ] || return 0
  IFS= read -r c0 < /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null
  IFS= read -r m0 < /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 2>/dev/null
  IFS= read -r c4 < /sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq 2>/dev/null
  IFS= read -r m4 < /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq 2>/dev/null
  IFS= read -r c7 < /sys/devices/system/cpu/cpufreq/policy7/scaling_cur_freq 2>/dev/null
  IFS= read -r m7 < /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq 2>/dev/null
  IFS= read -r gmhz < "$KGSL_MAX_MHZ" 2>/dev/null
  IFS= read -r gpl < "$KGSL_PWRLEVEL" 2>/dev/null
  IFS= read -r fla < "$RSC_FLA" 2>/dev/null
  IFS= read -r mc < "$RSC_MIN_CAP" 2>/dev/null
  sk=""; sh_=""; bt=""
  [ -n "$ZONE_SKIN" ] && IFS= read -r sk < "$ZONE_SKIN/temp" 2>/dev/null
  [ -n "$ZONE_SHELL" ] && IFS= read -r sh_ < "$ZONE_SHELL/temp" 2>/dev/null
  [ -n "$ZONE_BAT" ] && IFS= read -r bt < "$ZONE_BAT/temp" 2>/dev/null
  te=$(getprop init.svc.thermal-engine 2>/dev/null)

  log "Z9 snapshot: p0=${c0:-?}/${m0:-?} p4=${c4:-?}/${m4:-?} p7=${c7:-?}/${m7:-?} gpu=${gmhz:-?}MHz(pwr=${gpl:-?}) cool_hits=${COOL_HITS}(${COOL_LAST:-none}) fla=${fla:-?}/${mc:-?} heatctl=${HEATCTL_RESULT} te=${te:-?} skin=${sk:-na} shell=${sh_:-na} bat=${bt:-na} fps=${FPS_MODE} guard=${GUARD_ON}/${GUARD_LIMIT}"
  COOL_HITS=0
  COOL_LAST=""
}

release_clock_locks() {
  if [ "$GPU_LOCK_APPLIED" = "1" ] && [ -e "$KGSL_MIN_PWR" ]; then
    chmod 0644 "$KGSL_MIN_PWR" 2>/dev/null
    printf '%s\n' "${KGSL_STOCK_MIN_PWR:-7}" > "$KGSL_MIN_PWR" 2>/dev/null
    GPU_LOCK_APPLIED=0
  fi
  if [ "$CPU_LOCK_APPLIED" = "1" ]; then
    for pair in "0:${MIN_P0:-614400}" "4:${MIN_P4:-652800}" "7:${MIN_P7:-652800}"; do
      idx=${pair%:*}
      mn=${pair#*:}
      snode="/sys/devices/system/cpu/cpufreq/policy$idx/scaling_min_freq"
      [ -e "$snode" ] || continue
      chmod 0644 "$snode" 2>/dev/null
      printf '%s\n' "$mn" > "$snode" 2>/dev/null
    done
    CPU_LOCK_APPLIED=0
  fi
}

apply_clock_locks() {
  if [ "$GPU_LOCK_MAX" = "on" ]; then
    if [ -e "$KGSL_MIN_PWR" ]; then
      IFS= read -r _mp < "$KGSL_MIN_PWR" 2>/dev/null
      if [ "$_mp" != "0" ]; then
        chmod 0644 "$KGSL_MIN_PWR" 2>/dev/null
        printf '0\n' > "$KGSL_MIN_PWR" 2>/dev/null
      fi
      GPU_LOCK_APPLIED=1
    fi
  elif [ "$GPU_LOCK_APPLIED" = "1" ]; then
    if [ -e "$KGSL_MIN_PWR" ]; then
      chmod 0644 "$KGSL_MIN_PWR" 2>/dev/null
      printf '%s\n' "${KGSL_STOCK_MIN_PWR:-7}" > "$KGSL_MIN_PWR" 2>/dev/null
    fi
    GPU_LOCK_APPLIED=0
  fi

  if [ "$CPU_LOCK_MAX" = "on" ]; then
    for pair in "0:$MAX_P0" "4:$MAX_P4" "7:$MAX_P7"; do
      idx=${pair%:*}
      mx=${pair#*:}
      snode="/sys/devices/system/cpu/cpufreq/policy$idx/scaling_min_freq"
      [ -r "$snode" ] || continue
      IFS= read -r cur < "$snode" 2>/dev/null
      if [ "$cur" != "$mx" ]; then
        chmod 0644 "$snode" 2>/dev/null
        printf '%s\n' "$mx" > "$snode" 2>/dev/null
      fi
    done
    CPU_LOCK_APPLIED=1
  elif [ "$CPU_LOCK_APPLIED" = "1" ]; then
    for pair in "0:${MIN_P0:-614400}" "4:${MIN_P4:-652800}" "7:${MIN_P7:-652800}"; do
      idx=${pair%:*}
      mn=${pair#*:}
      snode="/sys/devices/system/cpu/cpufreq/policy$idx/scaling_min_freq"
      [ -e "$snode" ] || continue
      chmod 0644 "$snode" 2>/dev/null
      printf '%s\n' "$mn" > "$snode" 2>/dev/null
    done
    CPU_LOCK_APPLIED=0
  fi
}

run_cycle() {
  CYCLE=$((CYCLE + 1))
  read_config
  discover_cooling_nodes
  guard_check
  if [ "$GUARD_ON" = "1" ]; then
    log_z9_snapshot
    return 0
  fi
  block_services
  handle_rsc_and_walt
  clear_cooling_and_caps
  unlock_gpu_and_fps
  apply_clock_locks
  log_z9_snapshot
}

kill_existing_daemons() {
  for proc in /proc/[0-9]*; do
    pid=${proc##*/}
    [ "$pid" = "$$" ] && continue
    case "$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null)" in
      *"/vivo_iqoo_thermal_killer/service.sh --daemon-loop"*) kill "$pid" 2>/dev/null ;;
    esac
  done
}

if [ "$1" = "--once" ]; then
  init_hw_caps
  run_cycle
  exit 0
fi

if [ "$1" = "--daemon-loop" ]; then
  echo -1000 > /proc/self/oom_score_adj 2>/dev/null
  init_hw_caps
  read_config
  log "thermal_killer_z9(CN)_v1.1 daemon started PID=$$ cap=${CAP_MODE} fla=${FLA_MODE} heatctl=${HEATCTL_MODE} extra=${EXTRA_SERVICES} gpu=${GPU_MODE} fps=${FPS_MODE} guard=${GUARD_LIMIT} glock=${GPU_LOCK_MAX} clock=${CPU_LOCK_MAX}"
  while :; do
    [ -f "$MODDIR/toggle_off" ] && exit 0
    run_cycle
    sleep "$INTERVAL"
  done
fi

if [ -f "$LOCK" ]; then
  old=$(cat "$LOCK" 2>/dev/null)
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    case "$(tr '\0' ' ' < /proc/$old/cmdline 2>/dev/null)" in
      *vivo_iqoo_thermal_killer*) exit 0 ;;
    esac
  fi
fi

# Backup stock RSC/WALT & CPU/GPU min values once before touching
if [ ! -f "$ORIG" ]; then
  {
    [ -r "$WALT_TP" ] && echo "WALT_TP=$(cat "$WALT_TP" 2>/dev/null)"
    [ -r "$RSC_FLA" ] && echo "RSC_FLA=$(cat "$RSC_FLA" 2>/dev/null)"
    [ -r "$RSC_MIN_CAP" ] && echo "RSC_MIN_CAP=$(cat "$RSC_MIN_CAP" 2>/dev/null)"
    _m0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq 2>/dev/null)
    _m4=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq 2>/dev/null)
    _m7=$(cat /sys/devices/system/cpu/cpufreq/policy7/scaling_min_freq 2>/dev/null)
    [ -n "$_m0" ] && [ "$_m0" -lt "$MAX_P0" ] && echo "MIN_P0=$_m0"
    [ -n "$_m4" ] && [ "$_m4" -lt "$MAX_P4" ] && echo "MIN_P4=$_m4"
    [ -n "$_m7" ] && [ "$_m7" -lt "$MAX_P7" ] && echo "MIN_P7=$_m7"
    _np=$(cat /sys/class/kgsl/kgsl-3d0/num_pwrlevels 2>/dev/null)
    case "$_np" in ''|*[!0-9]*) echo "KGSL_STOCK_MIN_PWR=7" ;; *) echo "KGSL_STOCK_MIN_PWR=$((_np - 1))" ;; esac
  } > "$ORIG" 2>/dev/null
fi

kill_existing_daemons
nohup sh "$0" --daemon-loop </dev/null >/dev/null 2>&1 &
echo $! > "$LOCK"
log "Daemon launched in background PID=$(cat "$LOCK" 2>/dev/null)"
