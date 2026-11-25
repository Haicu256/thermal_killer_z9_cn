#!/system/bin/sh
[ -e /sys/rsc/fas/fla_enable ] && echo 1 > /sys/rsc/fas/fla_enable 2>/dev/null
[ -e /sys/rsc/fas/fla_min_cap_guarantee ] && echo 850 > /sys/rsc/fas/fla_min_cap_guarantee 2>/dev/null
[ -e /proc/sys/walt/sched_enable_tp ] && echo 0 > /proc/sys/walt/sched_enable_tp 2>/dev/null
[ -e /sys/class/kgsl/kgsl-3d0/min_pwrlevel ] && echo 7 > /sys/class/kgsl/kgsl-3d0/min_pwrlevel 2>/dev/null
[ -e /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq ] && echo 614400 > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq 2>/dev/null
[ -e /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq ] && echo 652800 > /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq 2>/dev/null
[ -e /sys/devices/system/cpu/cpufreq/policy7/scaling_min_freq ] && echo 652800 > /sys/devices/system/cpu/cpufreq/policy7/scaling_min_freq 2>/dev/null
cmd thermalservice reset >/dev/null 2>&1
setprop persist.debug.rms.thermal_fps_adjuster true 2>/dev/null
for gp in $(pidof com.vivo.gamewatch 2>/dev/null); do kill "$gp" 2>/dev/null; done
settings delete system min_refresh_rate >/dev/null 2>&1
settings put system gamewatch_game_target_fps -1 >/dev/null 2>&1
setprop persist.vendor.vperf_launch_thermal true 2>/dev/null
setprop persist.vivo.benchmark_thermal.enable 0 2>/dev/null
start thermal-engine 2>/dev/null
for s in vivo-vperf-hal-1-0 vendor.perfservice vendor.vivoperfservice; do
  start "$s" 2>/dev/null
done
