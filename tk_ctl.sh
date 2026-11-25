#!/system/bin/sh
# thermal_killer_z9(CN)_v1.1 - WebUI backend controller (zero background daemon)

MODDIR="${0%/*}"
LOCK="$MODDIR/.daemon.lock"
FLAG="$MODDIR/toggle_off"
ORIG="$MODDIR/orig_state"

alive() {
  [ -f "$LOCK" ] || return 1
  p=$(cat "$LOCK" 2>/dev/null); [ -n "$p" ] || return 1
  kill -0 "$p" 2>/dev/null || return 1
  tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q vivo_iqoo_thermal_killer
}

read_val() {
  _f="$MODDIR/$1"
  _def="$2"
  if [ -r "$_f" ]; then
    IFS= read -r _v < "$_f" 2>/dev/null
    [ -n "$_v" ] && { printf '%s' "$_v"; return 0; }
  fi
  printf '%s' "$_def"
}

restore_gpu_floor() {
  _stk=7
  [ -f "$ORIG" ] && . "$ORIG" 2>/dev/null
  [ -n "${KGSL_STOCK_MIN_PWR:-}" ] && _stk="$KGSL_STOCK_MIN_PWR"
  [ -e /sys/class/kgsl/kgsl-3d0/min_pwrlevel ] && printf '%s\n' "$_stk" > /sys/class/kgsl/kgsl-3d0/min_pwrlevel 2>/dev/null
}

restore_cpu_floor() {
  MIN_P0=614400; MIN_P4=652800; MIN_P7=652800
  [ -f "$ORIG" ] && . "$ORIG" 2>/dev/null
  [ -e /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq ] && printf '%s\n' "${MIN_P0:-614400}" > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq 2>/dev/null
  [ -e /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq ] && printf '%s\n' "${MIN_P4:-652800}" > /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq 2>/dev/null
  [ -e /sys/devices/system/cpu/cpufreq/policy7/scaling_min_freq ] && printf '%s\n' "${MIN_P7:-652800}" > /sys/devices/system/cpu/cpufreq/policy7/scaling_min_freq 2>/dev/null
}

restart_gamewatch() {
  _pids=$(pidof com.vivo.gamewatch 2>/dev/null)
  if [ -n "$_pids" ]; then
    for _gp in $_pids; do kill "$_gp" 2>/dev/null; done
  else
    am force-stop com.vivo.gamewatch 2>/dev/null
  fi
}

restore_fla() {
  RSC_FLA=1; RSC_MIN_CAP=850
  [ -f "$ORIG" ] && . "$ORIG" 2>/dev/null
  [ "${RSC_FLA:-0}" = "0" ] && RSC_FLA=1
  [ "${RSC_MIN_CAP:-1000}" = "1000" ] && RSC_MIN_CAP=850
  [ -e /sys/rsc/fas/fla_enable ] && printf '%s\n' "$RSC_FLA" > /sys/rsc/fas/fla_enable 2>/dev/null
  [ -e /sys/rsc/fas/fla_min_cap_guarantee ] && printf '%s\n' "$RSC_MIN_CAP" > /sys/rsc/fas/fla_min_cap_guarantee 2>/dev/null
}

apply_fps_off() {
  cmd thermalservice reset >/dev/null 2>&1
  _prev=$(getprop persist.debug.rms.thermal_fps_adjuster 2>/dev/null)
  setprop persist.debug.rms.thermal_fps_adjuster true 2>/dev/null
  [ "$_prev" != "true" ] && restart_gamewatch
  settings put system gamewatch_game_target_fps -1 >/dev/null 2>&1
  setprop persist.vendor.vperf_launch_thermal true 2>/dev/null
  setprop persist.vivo.benchmark_thermal.enable 0 2>/dev/null
}

apply_fps_on() {
  cmd thermalservice override-status 0 >/dev/null 2>&1
  cmd thermalservice inject-temperature SKIN NONE skin 30.0 >/dev/null 2>&1
  _prev=$(getprop persist.debug.rms.thermal_fps_adjuster 2>/dev/null)
  setprop persist.debug.rms.thermal_fps_adjuster false 2>/dev/null
  [ "$_prev" != "false" ] && restart_gamewatch
  settings put system gamewatch_game_target_fps 0 >/dev/null 2>&1
  setprop persist.vendor.vperf_launch_thermal false 2>/dev/null
  setprop persist.vivo.benchmark_thermal.enable 1 2>/dev/null
}

restore_extra_services() {
  for _s in android.thermal-hal vivo-vperf-hal-1-0 vendor.perfservice vendor.vivoperfservice; do
    start "$_s" 2>/dev/null
    setprop ctl.start "$_s" 2>/dev/null
  done
  setprop ctl.interface_start android.hardware.thermal@2.0::IThermal/default 2>/dev/null
  setprop ctl.interface_start vendor.vivo.hardware.vperf@1.0::IVPerf/default 2>/dev/null
}

emit_json() {
  _run=0
  _pid=""
  if alive && [ ! -f "$FLAG" ]; then
    _run=1
    _pid=$(cat "$LOCK" 2>/dev/null | tr -d '\r\n')
  fi
  _model=$(getprop ro.product.model 2>/dev/null | tr -d '\r\n"')
  _p0c=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null)
  _p0m=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 2>/dev/null)
  _p4c=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq 2>/dev/null)
  _p4m=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq 2>/dev/null)
  _p7c=$(cat /sys/devices/system/cpu/cpufreq/policy7/scaling_cur_freq 2>/dev/null)
  _p7m=$(cat /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq 2>/dev/null)
  _gc=$(cat /sys/class/kgsl/kgsl-3d0/clock_mhz 2>/dev/null)
  _gm=$(cat /sys/class/kgsl/kgsl-3d0/max_clock_mhz 2>/dev/null)
  _gb=$(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null | tr -dc '0-9')
  _gmp=$(cat /sys/class/kgsl/kgsl-3d0/min_pwrlevel 2>/dev/null | tr -dc '0-9')
  _gtp=$(cat /sys/class/kgsl/kgsl-3d0/thermal_pwrlevel 2>/dev/null | tr -dc '0-9')
  _bat=$(cat /sys/class/power_supply/battery/temp 2>/dev/null | tr -dc '0-9-')
  _skin=""
  _shell=""
  for z in /sys/class/thermal/thermal_zone*; do
    [ -r "$z/type" ] || continue
    IFS= read -r zt < "$z/type" 2>/dev/null
    case "$zt" in
      chg-skin-therm-usr) IFS= read -r _skin < "$z/temp" 2>/dev/null ;;
      tz_game_shell) IFS= read -r _shell < "$z/temp" 2>/dev/null ;;
    esac
  done
  _te=$(getprop init.svc.thermal-engine 2>/dev/null | tr -d '\r\n"')
  _fla=$(cat /sys/rsc/fas/fla_enable 2>/dev/null | tr -dc '0-9')
  _tfa=$(getprop persist.debug.rms.thermal_fps_adjuster 2>/dev/null | tr -d '\r\n"')

  _cap=$(read_val cap_mode force)
  _flam=$(read_val fla_mode disable)
  _ext=$(read_val extra_services on)
  _gpum=$(read_val gpu_mode unlock)
  _fpsm=$(read_val fps_mode unlock)
  _guard=$(read_val temp_guard off)
  _glock=$(read_val gpu_lock_max off)
  _clock=$(read_val cpu_lock_max off)

  printf '{"version":"v1.1","model":"%s","running":%s,"pid":"%s","cpu":{"p0":[%s,%s],"p4":[%s,%s],"p7":[%s,%s]},"gpu":{"cur":%s,"max":%s,"busy":%s,"minPwr":%s,"thermPwr":%s},"temp":{"bat":%s,"skin":%s,"shell":%s},"sys":{"te":"%s","fla":%s,"tfa":"%s"},"cfg":{"cap_mode":"%s","fla_mode":"%s","extra_services":"%s","gpu_mode":"%s","fps_mode":"%s","temp_guard":"%s","gpu_lock_max":"%s","cpu_lock_max":"%s"}}\n' \
    "${_model:-V2361A}" "$_run" "$_pid" \
    "${_p0c:-0}" "${_p0m:-0}" "${_p4c:-0}" "${_p4m:-0}" "${_p7c:-0}" "${_p7m:-0}" \
    "${_gc:-0}" "${_gm:-0}" "${_gb:-0}" "${_gmp:-7}" "${_gtp:-0}" \
    "${_bat:-0}" "${_skin:-0}" "${_shell:-0}" \
    "${_te:-stopped}" "${_fla:-0}" "${_tfa:-false}" \
    "$_cap" "$_flam" "$_ext" "$_gpum" "$_fpsm" "$_guard" "$_glock" "$_clock"
}

case "$1" in
  status)
    emit_json
    ;;
  toggle)
    sh "$MODDIR/action.sh" >/dev/null 2>&1
    emit_json
    ;;
  set)
    _k="$2"
    _v="$3"
    case "$_k" in
      cap_mode)       case "$_v" in force|manual) ;; *) exit 1 ;; esac ;;
      fla_mode)       case "$_v" in disable|observe) ;; *) exit 1 ;; esac ;;
      extra_services) case "$_v" in on|off|all) ;; *) exit 1 ;; esac ;;
      gpu_mode)       case "$_v" in unlock|off) ;; *) exit 1 ;; esac ;;
      fps_mode)       case "$_v" in unlock|off) ;; *) exit 1 ;; esac ;;
      gpu_lock_max)   case "$_v" in on|off) ;; *) exit 1 ;; esac ;;
      cpu_lock_max)   case "$_v" in on|off) ;; *) exit 1 ;; esac ;;
      temp_guard)
        case "$_v" in
          off|65|70|75|80|85|90) ;;
          *) exit 1 ;;
        esac
        ;;
      *) exit 1 ;;
    esac
    printf '%s\n' "$_v" > "$MODDIR/$_k"
    chmod 0644 "$MODDIR/$_k" 2>/dev/null
    touch "$MODDIR/.reload" 2>/dev/null

    # Immediate apply/restore when toggled from WebUI (no OFF->ON or reboot needed)
    _active=0
    alive && [ ! -f "$FLAG" ] && _active=1
    case "$_k" in
      gpu_lock_max)
        if [ "$_v" = "on" ] && [ "$_active" = "1" ]; then
          printf '0\n' > /sys/class/kgsl/kgsl-3d0/min_pwrlevel 2>/dev/null
        else
          restore_gpu_floor
        fi
        ;;
      cpu_lock_max)
        if [ "$_v" = "on" ] && [ "$_active" = "1" ]; then
          for idx in 0 4 7; do
            _mx=$(cat "/sys/devices/system/cpu/cpufreq/policy$idx/cpuinfo_max_freq" 2>/dev/null)
            [ -n "$_mx" ] && printf '%s\n' "$_mx" > "/sys/devices/system/cpu/cpufreq/policy$idx/scaling_min_freq" 2>/dev/null
          done
        else
          restore_cpu_floor
        fi
        ;;
      fla_mode)
        if [ "$_v" = "disable" ] && [ "$_active" = "1" ]; then
          [ -e /sys/rsc/fas/fla_enable ] && printf '0\n' > /sys/rsc/fas/fla_enable 2>/dev/null
        else
          restore_fla
        fi
        ;;
      fps_mode)
        if [ "$_v" = "unlock" ] && [ "$_active" = "1" ]; then
          apply_fps_on
        else
          apply_fps_off
        fi
        ;;
      extra_services)
        if [ "$_v" = "off" ]; then
          restore_extra_services
        elif [ "$_v" = "on" ]; then
          start android.thermal-hal 2>/dev/null
          setprop ctl.start android.thermal-hal 2>/dev/null
          setprop ctl.interface_start android.hardware.thermal@2.0::IThermal/default 2>/dev/null
        fi
        ;;
    esac
    emit_json
    ;;
  reset)
    rm -f "$MODDIR/cap_mode" "$MODDIR/fla_mode" "$MODDIR/extra_services" \
          "$MODDIR/gpu_mode" "$MODDIR/fps_mode" "$MODDIR/temp_guard" \
          "$MODDIR/gpu_lock_max" "$MODDIR/cpu_lock_max"
    restore_gpu_floor
    restore_cpu_floor
    if alive && [ ! -f "$FLAG" ]; then
      [ -e /sys/rsc/fas/fla_enable ] && printf '0\n' > /sys/rsc/fas/fla_enable 2>/dev/null
      apply_fps_on
      start android.thermal-hal 2>/dev/null
      setprop ctl.start android.thermal-hal 2>/dev/null
    fi
    touch "$MODDIR/.reload" 2>/dev/null
    emit_json
    ;;
  *)
    echo "Usage: $0 {status|toggle|set <KEY> <VAL>|reset}"
    exit 1
    ;;
esac
exit 0
