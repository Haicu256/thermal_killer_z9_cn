# thermal_killer_z9(CN)_v1.0

> **Module KernelSU tối ưu riêng cho vivo iQOO Z9 bản nội địa Trung Quốc (`V2361A` / `PD2361`)** — Tắt bóp nhiệt CPU/GPU + Chống khóa tụt 90/60 FPS khi nóng mà vẫn giữ tần số quét linh hoạt (60/90/120Hz) theo cài đặt trong game.
>
> **Dedicated KernelSU module for vivo iQOO Z9 China (`V2361A` / `PD2361`)** — Disables CPU/GPU thermal throttling & fixes thermal 90/60 FPS refresh-rate locks without forcing a fixed 120Hz display rate.

---

## 🇻🇳 Tiếng Việt

### 1. Thiết bị mục tiêu & Môi trường đã kiểm chứng
- **Thiết bị:** vivo iQOO Z9 CN (`V2361A` / `PD2361`, board `crow`)
- **SoC:** Qualcomm Snapdragon 7 Gen 3 (`SM7550` — `policy0` 1.80 GHz / `policy4` 2.40 GHz / `policy7` 2.63 GHz, GPU Adreno `975 MHz`)
- **Hệ điều hành:** OriginOS 5 (Android 15 / API 35, Kernel `5.15.178`)
- **Root:** KernelSU (bao gồm **Temp Root / Late-load trên máy khóa Bootloader**)
- **Kiến trúc an toàn:** **0 mount** (không có thư mục `system/` hay `vendor/`, không chạm phân vùng `EROFS`), an toàn tuyệt đối khi Soft Reboot.

### 2. Tính năng chính
- **Gỡ bóp xung CPU & GPU liên tục (vòng lặp 1s tối ưu, hạn chế fork):**
  - Dừng `thermal-engine` (`thermal-engine-v2`) và các dịch vụ phụ (`vivo-vperf-hal-1-0`, `vendor.perfservice`, `vendor.vivoperfservice`).
  - Xả `cur_state = 0` trên đúng 35 cooling device CPU/GPU/DDR/display-fps có thật trên `V2361A` (giữ nguyên bảo vệ cho `ufs`, `modem`, `wlan`, `cdsp`).
  - Khôi phục trần xung CPU (`policy0/4/7`) và mở trần GPU (`975 MHz`, `thermal_pwrlevel = 0`).
  - Tắt Vivo RSC **FLA** (`/sys/rsc/fas/fla_enable = 0`, `fla_min_cap_guarantee = 1000`) và **heatctl** (`/sys/rsc/svp/cpulimit` → `88000060 0`).
- **Chống khóa tụt 90/60 FPS khi nóng (KHÔNG ép cứng 120Hz):**
  - Gỡ vote `PRIORITY_SKIN_TEMPERATURE` của Android 15 `DisplayModeDirector` (`cmd thermalservice override-status 0` + `inject-temperature SKIN NONE skin 30.0`).
  - Tắt `ThermalFpsAdjuster` / `VSPA` của GameWatch (`persist.debug.rms.thermal_fps_adjuster = false` + tự khởi động lại tiến trình `persistent` `com.vivo.gamewatch` 1 lần khi bật).
  - Xả `display-fps` (`cooling_device28`) về `0` và đặt `gamewatch_game_target_fps = 0`.
  - **Không ép cứng `min_refresh_rate=120`:** Bạn chọn trong game **60, 90 hay 120 FPS** thì màn hình tự khớp đúng Hz đó và giữ ổn định khi nóng.
- **Thuần khiết riêng cho `V2361A` (Zero Bloat):**
  - Đã cắt bỏ ~790 dòng code chết của Neo10/Neo11/V2502/OriginOS 6/FuntouchOS 16 và 11 đường dẫn `/sys`, `/proc` không tồn tại trên Z9.
  - Rút gọn `sepolicy.rule` chỉ giữ đúng 5 nhãn SELinux thực tế trên `V2361A`.
- **Nút bấm Thao tác (`Action`) BẬT / TẮT tức thì — Trả zin 100%:**
  - Chuyển **ON ↔ OFF** có hiệu lực ngay sau ~2 giây **không cần Soft Reboot**.
  - Khi bấm **OFF** (hoặc khi gỡ module nhờ `uninstall.sh`), tự động khôi phục: `fla_enable = 1`, `fla_min_cap_guarantee = 850`, `sched_enable_tp`, `cmd thermalservice reset`, `persist.debug.rms.thermal_fps_adjuster = true` + khởi động lại `com.vivo.gamewatch`, `gamewatch_game_target_fps = -1`, bật lại `thermal-engine` và các dịch vụ phụ.

### 3. Hướng dẫn cài đặt & sử dụng
1. Tải `thermal_killer_z9(CN)_v1.0.zip` từ mục **[Releases](../../releases)**.
2. Mở **KernelSU → Module → Cài đặt** → chọn file ZIP → **Soft Reboot** 1 lần.
   *(Module dùng `id=vivo_iqoo_thermal_killer`, có thể nâng cấp đè lên các bản `v3.0.x` cũ; nếu bản cũ đang ở trạng thái OFF thì sau khi Soft Reboot bấm nút **Thao tác / Action** 1 lần để chuyển sang ON).*
3. **Bật / Tắt hàng ngày:** Bấm nút **Thao tác (`Action`)** trong KernelSU — đổi trạng thái ngay sau ~2 giây, không cần Soft Reboot.

### 4. Tùy chỉnh cấu hình (Tùy chọn)
Ghi 1 dòng vào file tương ứng trong `/data/adb/modules/vivo_iqoo_thermal_killer/` (tự nạp lại mỗi 5 giây):

| File cấu hình | Mặc định | Giá trị hỗ trợ | Tác dụng |
| :--- | :---: | :--- | :--- |
| `cap_mode` | `force` | `force` \| `manual` | `force`: tự nâng trần `scaling_max_freq` về tối đa; `manual`: nhường cho Scene/tool ngoài |
| `fla_mode` | `disable` | `disable` \| `observe` | Tắt hoặc chỉ quan sát `/sys/rsc/fas/fla_enable` |
| `heatctl_mode` | `auto` | `auto` \| `disable` \| `observe` | Ghi `88000060 0` vào `/sys/rsc/svp/cpulimit` |
| `extra_services` | `on` | `on` \| `off` \| `all` | `on`: dừng `vperf`/`perfservice`; `all`: dừng thêm `android.thermal-hal` |
| `gpu_mode` | `unlock` | `unlock` \| `off` | Mở trần GPU lên mức phần cứng cao nhất (`975 MHz`) |
| `fps_mode` | `unlock` | `unlock` \| `off` | Bật/tắt bộ chống khóa 90/60 FPS (`ThermalService` + `GameWatch` + `display-fps`) |
| `temp_guard` | `off` | `off` \| `60`..`100` (°C) | Van an toàn nhiệt CPU/GPU (vd: `echo 90 > temp_guard` — vượt ngưỡng tự trả điều khiển nhiệt cho vivo) |

### 5. Lệnh kiểm tra nhanh & hoàn tác thủ công
```bash
# Xem log snapshot mới nhất của Z9
su -c 'tail -n 10 /data/adb/modules/vivo_iqoo_thermal_killer/thermal_killer.log' </dev/null

# Kiểm tra trạng thái ThermalService & GameWatch
su -c 'dumpsys thermalservice | grep -E "IsStatusOverride|Thermal Status"; getprop persist.debug.rms.thermal_fps_adjuster; getprop init.svc.thermal-engine' </dev/null
```

### ⚠️ Cảnh báo an toàn nhiệt
- Module gỡ bỏ các tầng bóp hiệu năng sớm của hệ thống (vẫn giữ nguyên popup cảnh báo quá nhiệt mặc định `pem_htp_thred` của ROM làm mốc nhắc nhở).
- **Khuyến nghị sử dụng quạt tản nhiệt (sò lạnh)** khi chơi game kéo dài ở 120 FPS; tránh để nhiệt độ pin vượt quá `46–48°C` liên tục.
- Bạn tự chịu trách nhiệm khi sử dụng trên thiết bị của mình.

---

## 🇬🇧 English

### 1. Target Device & Verified Environment
- **Device:** vivo iQOO Z9 China (`V2361A` / `PD2361`, board `crow`)
- **SoC:** Qualcomm Snapdragon 7 Gen 3 (`SM7550` — `policy0` 1.80 GHz / `policy4` 2.40 GHz / `policy7` 2.63 GHz, Adreno GPU `975 MHz`)
- **OS:** OriginOS 5 (Android 15 / API 35, Kernel `5.15.178`)
- **Root:** KernelSU (fully safe for **Temp Root / Late-load with Locked Bootloader**)
- **Mount-Free:** Contains **no `system/` or `vendor/` overlay directories**, preventing EROFS mount conflicts or Soft Reboot loops.

### 2. Key Features
- **Tailored Zero-Bloat Core for `V2361A`:** Stripped ~790 lines of dead code from multi-device forks (Neo10, Neo11, V2502, OriginOS 6, FuntouchOS 16) and 11 non-existent `/sys` & `/proc` nodes. Trimmed `sepolicy.rule` strictly to the 5 verified SELinux labels on `V2361A`.
- **CPU / GPU Thermal Unthrottling:** Stops `thermal-engine-v2` and vivo perf services, clears 35 real CPU/GPU/DDR/`display-fps` cooling devices, restores `policy0/4/7` max clocks, unlocks GPU max clock (`975 MHz`, `thermal_pwrlevel=0`), disables RSC FLA (`fla_enable=0`, `fla_min_cap_guarantee=1000`), and disables RSC `heatctl` (`88000060 0`).
- **Thermal 90/60 FPS Lock Fix (Adaptive 60/90/120Hz):**
  - Clears Android 15 `DisplayModeDirector` `PRIORITY_SKIN_TEMPERATURE` vote via `cmd thermalservice override-status 0` + `inject-temperature SKIN NONE skin 30.0`.
  - Disables GameWatch `ThermalFpsAdjuster` (`persist.debug.rms.thermal_fps_adjuster=false`) and safely respawns the persistent `com.vivo.gamewatch` process.
  - Does **not** force `min_refresh_rate=120`, allowing games set to 60, 90, or 120 FPS to run natively at their target refresh rate.
- **Instant Action Button Toggle (No Soft Reboot Needed):** Toggle ON/OFF directly via KernelSU's Action button (~2 seconds). OFF mode and `uninstall.sh` cleanly restore all props, RSC values, `thermalservice`, `com.vivo.gamewatch`, and system services back to 100% stock.

### 3. Build from Source
```bash
./build.sh
```

---

## Credits
- Original `vivo_iqoo_thermal_killer` concept & Coolapk community base: **酷安 @怎又心存妄想**
- Pure `V2361A` rewrite, Android 15 `PRIORITY_SKIN_TEMPERATURE` + GameWatch `ThermalFpsAdjuster` integration, and live hardware verification on iQOO Z9 CN: **Haicu256**
