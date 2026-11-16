# Hướng dẫn test hiệu năng LiveKit Meet

Tài liệu này hướng dẫn hai kiểu đo: bài đơn giản bằng `lk perf load-test` và bài nhiều phòng giống kịch bản đã dùng cho dự án này — mỗi phòng có 10 client giả lập, mỗi client publish audio/video và subscribe track của những người còn lại.

## 1. Chuẩn bị

Chạy các lệnh từ thư mục gốc repo, trừ khi có ghi chú khác.

- Khởi động LiveKit: `docker compose up -d`.
- Kiểm tra container: `docker compose ps`.
- CLI `lk` đã cài và có thể kết nối tới `ws://127.0.0.1:7880`. Cài theo [hướng dẫn LiveKit CLI](https://docs.livekit.io/reference/developer-tools/livekit-cli/) và kiểm tra bằng `lk --version`.
- LiveKit trong Compose chạy chế độ dev; lệnh bên dưới dùng `--dev` với credentials mặc định `devkey` / `secret`. Chỉ dùng trên máy test, không đưa cổng dev ra Internet.
- Với bài đo giống báo cáo, để Meet và HTTPS/WSS proxy chạy trong lúc đo. Tải của các tiến trình giả lập cũng được tính vào CPU/RAM toàn máy.

Tạo thư mục lưu log và file audio tổng hợp:

```bash
mkdir -p /tmp/livekit-perf
```

Trên Ubuntu, nếu thiếu GStreamer, cài các plugin cần thiết rồi tạo audio Opus 48 kHz dài khoảng 60 phút:

```bash
sudo apt-get update
sudo apt-get install -y gstreamer1.0-tools gstreamer1.0-plugins-good
gst-launch-1.0 -e audiotestsrc wave=sine samplesperbuffer=960 num-buffers=180000 ! audio/x-raw,rate=48000,channels=1 ! audioconvert ! audioresample ! opusenc bitrate=32000 ! oggmux ! filesink location=/tmp/livekit-perf/audio-60m.ogg
```

`lk room join --publish-demo` tạo video demo lặp; file Ogg ở trên cung cấp audio liên tục để bài đo không hết media giữa chừng.

## 2. Bài nhanh: tải trong một phòng

Lệnh LiveKit CLI sau tạo tải trong một phòng, với 10 publisher audio/video và 10 subscriber giả lập trong 2 phút:

```bash
lk --url ws://127.0.0.1:7880 --dev perf load-test \
  --room perf-single-room \
  --video-publishers 10 \
  --audio-publishers 10 \
  --subscribers 10 \
  --layout 3x3 \
  --num-per-second 2 \
  --duration 2m
```

Khi đặt cả `--video-publishers` và `--audio-publishers`, LiveKit CLI ghép audio và video trên các publisher đầu tiên. Đây là bài đo **một phòng**; 10 subscriber là client bổ sung, nên kết quả không tương đương kịch bản chính xác 10 người hai chiều trong từng phòng. Xem đầy đủ các tùy chọn trong [LiveKit CLI load testing](https://docs.livekit.io/reference/developer-tools/livekit-cli/perf/).

## 3. Bài nhiều phòng: 10 người hai chiều mỗi phòng

Bài này chạy 5 hoặc 10 phòng. Mỗi phòng có 10 tiến trình CLI. Mỗi tiến trình publish video demo, audio Ogg và bật `--auto-subscribe` để nhận track trong phòng.

### Tạo runner

Lưu nội dung sau thành `/tmp/livekit-perf/run-target.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

ROOMS="${1:-5}"
HOLD_SECONDS="${2:-60}"
AUDIO="${AUDIO_FILE:-/tmp/livekit-perf/audio-60m.ogg}"

if [[ "$ROOMS" != 5 && "$ROOMS" != 10 ]]; then
  echo "Dùng: $0 5|10 [thời_gian_giữ_giây]" >&2
  exit 2
fi
if [[ ! -f "$AUDIO" ]]; then
  echo "Không tìm thấy audio: $AUDIO" >&2
  exit 2
fi

EXPECTED=$((ROOMS * 10))
LOG_DIR="/tmp/livekit-perf/run-${ROOMS}rooms-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"
PIDS=()

stop_clients() {
  local pid
  for pid in "${PIDS[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
}
trap stop_clients EXIT
trap 'exit 130' INT TERM

echo "Khởi chạy $ROOMS phòng, $EXPECTED client; log: $LOG_DIR"
for r in $(seq 1 "$ROOMS"); do
  printf -v ROOM 'perf-%02dr-room-%02d' "$ROOMS" "$r"
  for p in $(seq 1 10); do
    printf -v ID 'r%02d-p%02d' "$r" "$p"
    lk --url ws://127.0.0.1:7880 --dev room join \
      --identity "$ID" \
      --publish-demo \
      --publish "$AUDIO" \
      --auto-subscribe \
      "$ROOM" >"$LOG_DIR/${ROOM}-${ID}.log" 2>&1 &
    PIDS+=("$!")
    sleep 0.5
  done
done

# Chờ kết nối và đăng ký track sau khi hoàn tất ramp-up.
sleep 25
count_logs() {
  local pattern="$1"
  (grep -l "$pattern" "$LOG_DIR"/*.log 2>/dev/null || true) | wc -l
}
CONNECTED="$(count_logs 'connected to room')"
VIDEO="$(count_logs 'published simulcast track')"
AUDIO_PUBLISHED="$(count_logs 'source.*MICROPHONE')"
printf 'Kiểm tra log: kết nối=%s/%s, video=%s/%s, audio=%s/%s\n' \
  "$CONNECTED" "$EXPECTED" "$VIDEO" "$EXPECTED" "$AUDIO_PUBLISHED" "$EXPECTED"
if [[ "$CONNECTED" -ne "$EXPECTED" || "$VIDEO" -ne "$EXPECTED" || "$AUDIO_PUBLISHED" -ne "$EXPECTED" ]]; then
  echo "Chưa đủ client/track; xem log trong $LOG_DIR. Dừng bài đo để tránh ghi nhận kết quả thiếu tải."
  exit 3
fi

echo "Giữ tải trong $HOLD_SECONDS giây. Nhấn Ctrl+C để dừng sớm; client sẽ được gửi SIGTERM."
sleep "$HOLD_SECONDS"
echo "Hoàn thành. Log: $LOG_DIR"
```

Cho phép chạy:

```bash
chmod +x /tmp/livekit-perf/run-target.sh
```

### Ghi CPU và RAM toàn máy

Mở terminal khác. Collector Python dưới đây lấy mẫu gần mỗi 2 giây, ghi CPU toàn máy, RAM dùng/khả dụng và swap vào CSV:

```bash
python3 - <<'PY' | tee /tmp/livekit-perf/host-metrics.csv
import time
from datetime import datetime

def cpu_snapshot():
    with open('/proc/stat') as f:
        values = list(map(int, f.readline().split()[1:8]))
    return sum(values), values[3] + values[4]

def memory_snapshot():
    values = {}
    with open('/proc/meminfo') as f:
        for line in f:
            key, rest = line.split(':', 1)
            if key in ('MemTotal', 'MemAvailable', 'SwapTotal', 'SwapFree'):
                values[key] = int(rest.split()[0]) / 1024
    return (values['MemTotal'] - values['MemAvailable'], values['MemAvailable'],
            values['SwapTotal'] - values['SwapFree'])

print('time,cpu_host_pct,ram_used_mib,ram_available_mib,swap_used_mib', flush=True)
previous_total, previous_idle = cpu_snapshot()
while True:
    time.sleep(2)
    total, idle = cpu_snapshot()
    delta_total, delta_idle = total - previous_total, idle - previous_idle
    cpu = 100 * (delta_total - delta_idle) / delta_total if delta_total else 0
    previous_total, previous_idle = total, idle
    used, available, swap = memory_snapshot()
    print(f'{datetime.now().astimezone().isoformat(timespec="seconds")},{cpu:.2f},'
          f'{used:.1f},{available:.1f},{swap:.1f}', flush=True)
PY
```

Ở terminal thứ ba, theo dõi riêng container LiveKit:

```bash
docker stats --format 'CPU={{.CPUPerc}} RAM={{.MemUsage}}' livekit-server-local
```

Lệnh này cập nhật liên tục; thêm `| tee /tmp/livekit-perf/container-stats.txt` nếu muốn lưu lại các mẫu trong lúc chạy.

### Chạy từng mốc

Chạy 5 phòng trước, để runner kết thúc và gửi SIGTERM tới toàn bộ client; sau đó chạy 10 phòng:

```bash
/tmp/livekit-perf/run-target.sh 5 60
/tmp/livekit-perf/run-target.sh 10 60
```

Đối chiếu log cuối mỗi lệnh với số client mong đợi. Trong từng phòng, kiểm tra có 10 participant và mỗi người có audio/video; log `track subscribed` phải xuất hiện sau khi track được đăng ký. CLI có lệnh xem participant:

```bash
lk --url ws://127.0.0.1:7880 --dev room participants list perf-10r-room-01
```

Đổi tên phòng cho khớp mốc đang kiểm tra (`perf-05r-room-01` hoặc `perf-10r-room-01`). Mỗi client trong cùng phòng cần nhận audio/video của 9 người còn lại; các log subscribe của CLI là bằng chứng kiểm tra bổ sung.

### Tính số đỉnh từ CSV

Sau khi đã dừng collector bằng `Ctrl+C`, lấy CPU toàn máy cao nhất, RAM dùng cao nhất, RAM khả dụng thấp nhất và swap cao nhất:

```bash
python3 - <<'PY'
import csv

with open('/tmp/livekit-perf/host-metrics.csv', newline='') as f:
    rows = list(csv.DictReader(f))
for key, title, unit, fn in [
    ('cpu_host_pct', 'CPU toàn máy cao nhất', '%', max),
    ('ram_used_mib', 'RAM dùng cao nhất', 'MiB', max),
    ('ram_available_mib', 'RAM khả dụng thấp nhất', 'MiB', min),
    ('swap_used_mib', 'Swap dùng cao nhất', 'MiB', max),
]:
    value = fn(float(row[key]) for row in rows)
    print(f'{title}: {value:.1f} {unit}')
PY
```

Ghi lại phiên bản `lk`, cấu hình máy, số phòng/người, thời gian giữ tải, kết quả xác nhận track, CPU/RAM/swap đỉnh và hiện tượng disconnect. Báo cáo lần chạy trước nằm ở [`meet/LIVEKIT_PERFORMANCE_REPORT.md`](meet/LIVEKIT_PERFORMANCE_REPORT.md).

## Dọn dẹp và lưu ý khi đọc số liệu

- Runner tự gửi `SIGTERM` đến các client khi hết thời gian hoặc khi bạn nhấn `Ctrl+C`. Kiểm tra các room đã rỗng bằng `lk --dev room list`; nếu còn room test, xóa từng room bằng `lk --dev room delete <tên-room>`.
- `docker stats` hiển thị CPU container theo mức dùng một lõi; con số có thể lớn hơn 100%. CSV collector đo CPU toàn máy trên thang 0–100% tổng công suất máy.
- Bài nhiều phòng chạy load generator cùng máy LiveKit; CPU/RAM toàn máy bao gồm cả generator. Máy có thể chậm mạnh khi swap gần đầy. Lưu công việc trước khi chạy và dừng bằng `Ctrl+C` nếu máy mất phản hồi.
- Video demo và audio sine là media tổng hợp, không mô phỏng camera điện thoại, bitrate mạng Wi-Fi hay khử ồn. Mỗi lần giữ tải 60 giây là stress test ngắn, không phải soak test production.
- Không chạy bài này trên LiveKit Cloud hoặc server production. Chỉ dùng server dev cục bộ với dữ liệu test.

## Tài liệu LiveKit

- [Cài đặt LiveKit CLI](https://docs.livekit.io/reference/developer-tools/livekit-cli/)
- [LiveKit CLI load testing](https://docs.livekit.io/reference/developer-tools/livekit-cli/perf/)
- [LiveKit CLI rooms and participants](https://docs.livekit.io/reference/developer-tools/livekit-cli/rooms/)
- [Benchmark self-hosted LiveKit](https://docs.livekit.io/transport/self-hosting/benchmark/)
