# LiveKit Meet — hướng dẫn chạy

Dự án gồm giao diện họp Next.js trong `meet/` và LiveKit server chạy bằng Docker Compose. Hướng dẫn dưới đây chạy được trên máy phát triển; phần LAN ghi rõ cấu hình bổ sung cần có để thiết bị khác dùng camera và microphone.

## Yêu cầu

- Docker Engine và Docker Compose plugin.
- Node.js 18 trở lên.
- pnpm 10.18.2 (phiên bản được khai báo trong `meet/package.json`).
- `openssl` khi cần tạo lại chứng chỉ HTTPS nội bộ cho LAN.

## Chạy trên chính máy này

### 1. Tạo file cấu hình ứng dụng

Từ thư mục gốc dự án:

```bash
cd meet
[ -f .env.local ] || cp .env.example .env.local
```

Mở `meet/.env.local` và đặt các biến sau cho LiveKit dev server trong Compose:

```dotenv
LIVEKIT_API_KEY=devkey
LIVEKIT_API_SECRET=secret
LIVEKIT_URL=ws://127.0.0.1:7880
```

Compose chạy LiveKit với `--dev`; API key và secret trong file này phải khớp với dev server. Không dùng các thông tin dev này cho dịch vụ đưa ra Internet. Không commit `meet/.env.local` vì file chứa secret.

### 2. Khởi động LiveKit

Mở terminal tại thư mục gốc dự án (thư mục có `docker-compose.yml`):

```bash
docker compose up -d
docker compose ps
docker compose logs -f livekit
```

Nhấn `Ctrl+C` để thoát xem log; container vẫn chạy nền. `docker-compose.yml` mount `livekit.yaml` vào container. Các cổng cấu hình là `7880` cho LiveKit, `7881/TCP` cho WebRTC TCP và `7882/UDP` cho WebRTC UDP. Compose hiện dùng host networking và bind LiveKit vào `127.0.0.1`, phù hợp cho truy cập từ chính máy.

### 3. Khởi động giao diện

Mở terminal thứ hai:

```bash
cd meet
pnpm install --frozen-lockfile
pnpm dev
```

Mở [http://localhost:3000](http://localhost:3000), rồi tạo phòng hoặc nhập tên phòng để tham gia. `localhost` được xem là secure context trong trình duyệt, vì vậy có thể cấp quyền camera/microphone khi trình duyệt và hệ điều hành cho phép.

### 4. Dừng dịch vụ

- Dừng Next.js bằng `Ctrl+C` trong terminal chạy `pnpm dev`.
- Nếu đang chạy HTTPS/WSS proxy LAN, dừng tiến trình Node proxy bằng `Ctrl+C` trong terminal của proxy để giải phóng cổng `3000`.
- Dừng LiveKit và xóa container bằng lệnh sau tại thư mục gốc:

```bash
docker compose down
```

## Truy cập từ thiết bị cùng mạng LAN

### Cách mạng LAN hiện tại hoạt động

Repo không chứa Caddy hay cấu hình reverse proxy. Setup đã dùng trong phiên này là một proxy HTTPS/WSS viết bằng Node.js, nằm ngoài repo tại `/tmp/livekit-meet-lan-proxy.mjs`. Proxy nghe HTTPS ở `3000`, chuyển `/rtc` tới LiveKit `127.0.0.1:7880`, chuyển giao diện tới Next.js `127.0.0.1:3001`, và phục vụ CA nội bộ ở `8085`.

Vì proxy chạy trực tiếp trên cùng máy, nó truy cập được `127.0.0.1:7880`; do đó LiveKit có thể giữ `--bind 127.0.0.1` trong `docker-compose.yml`. Bind đó không làm giao diện Next.js mất khả năng truy cập LAN, và cũng không thay thế cấu hình IP/cổng media WebRTC.

Các helper và chứng chỉ hiện nằm trong `/tmp`, không được lưu trong repo và có thể bị xóa khi máy dọn thư mục tạm. Trên một checkout mới, proxy/chứng chỉ cần được tạo hoặc khôi phục trước khi làm theo bước chạy proxy dưới đây.

### 1. Xác định IP LAN

```bash
ip -br -4 addr
ip route
```

Chọn IPv4 trên card Wi-Fi/Ethernet cùng mạng với điện thoại, ví dụ `192.168.1.25`. Nên đặt DHCP reservation trên router để IP ổn định. Thay IP/subnet mẫu bên dưới bằng giá trị thực tế của nhà bạn.

### 2. Cấu hình LiveKit cho media LAN

Trong `livekit.yaml`, đặt IP mà LiveKit cần quảng bá cho ICE media. Ví dụ:

```yaml
port: 7880

rtc:
  tcp_port: 7881
  udp_port: 7882
  use_external_ip: false
  node_ip: 192.168.1.25

logging:
  level: debug
```

Giữ `--bind 127.0.0.1` trong `docker-compose.yml` khi proxy Node chạy trên cùng host. Khởi động lại LiveKit sau khi cập nhật `livekit.yaml`:

```bash
docker compose up -d --force-recreate livekit
```

Cổng `7880` là signaling/API nội bộ mà proxy chuyển tiếp. Media đi trực tiếp giữa thiết bị và IP `node_ip` qua `7881/TCP` hoặc `7882/UDP`. Nếu muốn kiểm tra bind thật của container (có thể khác file gốc nếu lần trước dùng Compose override), chạy:

```bash
docker inspect --format '{{json .Config.Cmd}}' livekit-server-local
```

### 3. Đặt URL WSS và chạy giao diện nội bộ

Trong `meet/.env.local`, đặt URL WSS mà điện thoại truy cập được. API key/secret phải trùng credentials LiveKit dev:

```dotenv
LIVEKIT_API_KEY=devkey
LIVEKIT_API_SECRET=secret
LIVEKIT_URL=wss://192.168.1.25:3000
```

Chạy Next.js chỉ trên loopback cổng `3001`; proxy sẽ chuyển giao diện và API tới đây:

```bash
cd meet
pnpm install --frozen-lockfile
pnpm exec next dev --hostname 127.0.0.1 --port 3001
```

Nếu chỉ muốn xem giao diện mà chưa cần gọi, có thể dừng proxy và chạy Next.js trực tiếp trên LAN bằng `pnpm exec next dev --hostname 0.0.0.0 --port 3000`; mở `http://<IP-LAN>:3000`. Trang HTTP trên IP LAN thường không được cấp quyền camera/microphone, nên đây chỉ là kiểm tra giao diện.

### 4. Chạy HTTPS/WSS proxy Node đang có

Trên máy đã được setup trước đó, kiểm tra helper và chứng chỉ:

```bash
ls -l /tmp/livekit-meet-lan-proxy.mjs
ls -l /tmp/livekit-meet-lan/server.crt /tmp/livekit-meet-lan/server.key /tmp/livekit-meet-lan/ca.crt
```

Mở terminal mới và chạy proxy:

```bash
node /tmp/livekit-meet-lan-proxy.mjs
```

Proxy dùng thư viện HTTPS/HTTP tích hợp sẵn của Node.js; không cần cài Caddy. Giữ terminal này mở trong lúc test. Mở `https://192.168.1.25:3000` để vào Meet.

### 5. Cài CA trên điện thoại

Proxy dùng CA nội bộ để ký chứng chỉ cho IP LAN. Khi điện thoại cùng Wi-Fi, tải CA tại:

```text
http://192.168.1.25:8085/livekit-meet-lan-ca.crt
```

Cài file tải về dưới dạng CA certificate. Trên iPhone/iPad, sau khi cài profile, bật trust tại **Settings → General → About → Certificate Trust Settings**. Apple lưu ý profile cài thủ công chưa tự bật trust SSL/TLS: [hướng dẫn Apple](https://support.apple.com/en-ie/102390). Trên Android, cài từ phần Security/Credentials rồi xác nhận trình duyệt báo kết nối HTTPS an toàn.

Nếu IP LAN đổi, cần cập nhật `node_ip` trong `livekit.yaml`, `LIVEKIT_URL` trong `meet/.env.local`, và cấp lại chứng chỉ máy chủ để SAN khớp IP mới. CA chỉ cần cài lại nếu CA gốc được tạo mới.

### 6. Mở firewall và kiểm tra cuộc gọi

Nếu UFW đang bật, cho phép các cổng cần thiết từ subnet Wi-Fi. Ví dụ với `192.168.1.0/24`:

```bash
LAN_SUBNET=192.168.1.0/24
sudo ufw allow from "$LAN_SUBNET" to any port 3000 proto tcp
sudo ufw allow from "$LAN_SUBNET" to any port 8085 proto tcp
sudo ufw allow from "$LAN_SUBNET" to any port 7881 proto tcp
sudo ufw allow from "$LAN_SUBNET" to any port 7882 proto udp
sudo ufw deny from "$LAN_SUBNET" to any port 7880 proto tcp
sudo ufw status
```

Không cấu hình port forwarding trên router. Trên điện thoại cùng Wi-Fi, mở `https://192.168.1.25:3000`, tạo hoặc tham gia phòng, rồi cấp quyền camera/microphone. Nếu trang mở nhưng không vào phòng, kiểm tra `LIVEKIT_URL` và xem log proxy/LiveKit. Nếu vào phòng nhưng không có media, kiểm tra `node_ip`, firewall `7881/TCP`, `7882/UDP` và tắt AP/client isolation trên router.

Tham khảo: [LiveKit local deployment](https://docs.livekit.io/transport/self-hosting/local/), [cổng và firewall LiveKit](https://docs.livekit.io/transport/self-hosting/ports-firewall/), [Next.js bind host](https://nextjs.org/docs/app/api-reference/cli/next), [điều kiện secure context cho camera/microphone](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia).

## Xử lý lỗi thường gặp

| Triệu chứng | Kiểm tra |
|---|---|
| `navigator.mediaDevices` không tồn tại hoặc không bật được camera | Dùng `https://` với chứng chỉ được thiết bị tin cậy; `http://localhost` chỉ phù hợp khi mở trên chính máy chủ. |
| Trang mở được nhưng LiveKit báo connection error | Kiểm tra `LIVEKIT_URL`, WSS/WebSocket proxy, chứng chỉ, firewall và các cổng media. Mở `docker compose logs -f livekit` để xem log server. |
| Không lấy được token hoặc API trả lỗi | Kiểm tra `LIVEKIT_API_KEY` và `LIVEKIT_API_SECRET` trong `meet/.env.local` có khớp cấu hình LiveKit không; sau khi đổi env, khởi động lại Next.js. |
| HTTPS/WSS proxy không phản hồi | Kiểm tra tiến trình `node /tmp/livekit-meet-lan-proxy.mjs`, chứng chỉ trong `/tmp/livekit-meet-lan/`, và cổng `3000`/`8085`. |
| Cổng đã được sử dụng | Dừng tiến trình đang giữ cổng `3000`, `3001`, `7880`, `7881`, `7882` hoặc `8085`, hoặc chỉnh cấu hình cổng tương ứng. |

## Tệp cấu hình

| Tệp | Vai trò |
|---|---|
| `docker-compose.yml` | Khởi động LiveKit server trong Docker. |
| `livekit.yaml` | Cổng LiveKit/WebRTC và mức log. Tên tệp trong repo dùng đuôi `.yaml`. |
| `meet/.env.local` | URL, API key và secret ứng dụng dùng để tạo token/kết nối LiveKit. |
| `meet/package.json` | Lệnh Next.js, phiên bản Node tối thiểu và phiên bản pnpm. |

Hướng dẫn chạy benchmark nằm trong [`PERFORMANCE_README.md`](PERFORMANCE_README.md); kết quả đo trên máy phát triển nằm trong [`meet/LIVEKIT_PERFORMANCE_REPORT.md`](meet/LIVEKIT_PERFORMANCE_REPORT.md).
