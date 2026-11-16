# LiveKit Meet — hướng dẫn chạy

Dự án gồm giao diện họp Next.js trong `meet/` và LiveKit server chạy bằng Docker Compose. Hướng dẫn dưới đây chạy được trên máy phát triển; phần LAN ghi rõ cấu hình bổ sung cần có để thiết bị khác dùng camera và microphone.

## Yêu cầu

- Docker Engine và Docker Compose plugin.
- Node.js 18 trở lên.
- pnpm 10.18.2 (phiên bản được khai báo trong `meet/package.json`).
- `openssl` khi cần tạo lại chứng chỉ HTTPS nội bộ cho LAN.

## Khởi động nhanh trên LAN hiện tại

Cấu hình đang dùng trên máy này là IP `192.168.1.25`; nếu IP Wi-Fi đổi, thay IP trong `livekit.yaml`, `meet/.env.local` và các URL bên dưới. Chứng chỉ đã tạo được giữ trong `.local/lan-certs/`, nên không cần tạo lại khi chỉ khởi động lại dịch vụ.

Trước khi chạy, xác nhận `livekit.yaml` có `node_ip: 192.168.1.25` và `meet/.env.local` có `LIVEKIT_URL=wss://192.168.1.25:3000` cùng API key/secret khớp LiveKit dev server. Nếu chưa tạo `.env.local`, xem bước cấu hình trong mục LAN bên dưới.

1. Tại thư mục gốc repo, khởi động LiveKit:

   ```bash
   docker compose up -d livekit
   docker compose ps
   ```

2. Mở terminal thứ nhất tại thư mục gốc repo cho giao diện:

   ```bash
   cd meet
   pnpm install --frozen-lockfile
   pnpm exec next dev --hostname 127.0.0.1 --port 3001
   ```

3. Mở terminal thứ hai tại thư mục gốc repo cho HTTPS/WSS proxy:

   ```bash
   node scripts/lan-proxy.mjs
   ```

4. Trên điện thoại cùng Wi-Fi, mở `https://192.168.1.25:3000`. Nếu điện thoại chưa tin cậy CA của dự án, tải chứng chỉ tại `http://192.168.1.25:8085/livekit-meet-lan-ca.crt`, cài và bật trust cho chứng chỉ đó trước khi mở Meet.

Proxy và Next.js cần tiếp tục chạy trong terminal. Để dừng, nhấn `Ctrl+C` ở hai terminal; dừng LiveKit bằng `docker compose down` tại thư mục gốc. Các bước cấu hình IP, CA, firewall và kiểm tra media được trình bày trong mục [Truy cập từ thiết bị cùng mạng LAN](#truy-cập-từ-thiết-bị-cùng-mạng-lan).

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

Repo có proxy HTTPS/WSS Node.js tại `scripts/lan-proxy.mjs` và script tạo chứng chỉ tại `scripts/generate-lan-certs.sh`. Chứng chỉ và CA riêng được lưu bền vững trong `.local/lan-certs/`; thư mục `.local/` đã được Git bỏ qua, nên khóa riêng không được đẩy lên remote.

Proxy nghe HTTPS/WSS trên cổng `3000`, chuyển `/rtc` tới LiveKit `127.0.0.1:7880`, chuyển giao diện và API tới Next.js `127.0.0.1:3001`, và phục vụ CA nội bộ qua HTTP cổng `8085`. Vì proxy chạy trên cùng máy với LiveKit, Compose có thể giữ `--bind 127.0.0.1`.

### 1. Xác định IP LAN

```bash
ip -br -4 addr
ip route
```

Chọn IPv4 trên card Wi-Fi/Ethernet cùng mạng với điện thoại, ví dụ `192.168.1.25`. Nên đặt DHCP reservation trên router để IP ổn định. Thay IP/subnet mẫu trong các bước dưới đây bằng giá trị thực tế của mạng nhà bạn.

### 2. Tạo chứng chỉ và đặt URL WSS

Tại thư mục gốc repo, tạo CA và chứng chỉ TLS cho IP LAN:

```bash
LAN_IP=192.168.1.25
scripts/generate-lan-certs.sh "$LAN_IP"
```

Script dùng lại CA đã có trong `.local/lan-certs/` và cấp lại chứng chỉ máy chủ theo IP mới. Nếu `.local/lan-certs/` chưa có CA, script sẽ tạo CA mới; mỗi điện thoại cần cài và tin cậy `ca.crt` một lần.

Trong `meet/.env.local`, đặt URL WSS công khai với API key/secret khớp LiveKit dev server:

```dotenv
LIVEKIT_API_KEY=devkey
LIVEKIT_API_SECRET=secret
LIVEKIT_URL=wss://192.168.1.25:3000
```

Không dùng dev credentials trên mạng công cộng. Không commit nội dung `.local/lan-certs/` hoặc `meet/.env.local`.

### 3. Cấu hình và chạy LiveKit

Trong `livekit.yaml`, quảng bá địa chỉ LAN cho ICE media:

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

Giữ `--bind 127.0.0.1` trong `docker-compose.yml`; proxy cùng máy sẽ chuyển WSS tới LiveKit qua loopback. Khởi động lại dịch vụ sau khi đổi cấu hình:

```bash
docker compose up -d --force-recreate livekit
docker compose ps
```

Media đi trực tiếp giữa điện thoại và `node_ip` qua `7881/TCP` hoặc `7882/UDP`. Nếu cần xác nhận bind thật của container, chạy:

```bash
docker inspect --format '{{json .Config.Cmd}}' livekit-server-local
```

### 4. Chạy Next.js và proxy LAN

Mở terminal thứ nhất:

```bash
cd meet
pnpm install --frozen-lockfile
pnpm exec next dev --hostname 127.0.0.1 --port 3001
```

Mở terminal thứ hai tại thư mục gốc repo:

```bash
node scripts/lan-proxy.mjs
```

Giữ cả hai tiến trình chạy trong lúc test. Trên máy chủ, trang Meet được phục vụ từ Next.js; proxy nhận HTTPS/WSS từ thiết bị trên cổng `3000`.

Nếu chỉ cần xem giao diện mà chưa cần gọi, dừng proxy và chạy Next.js trực tiếp trên LAN bằng `pnpm exec next dev --hostname 0.0.0.0 --port 3000`; mở `http://<IP-LAN>:3000`. Trình duyệt thường không cấp camera/microphone cho HTTP trên IP LAN, nên để gọi đầy đủ hãy dùng HTTPS/WSS qua proxy.

### 5. Cài CA trên điện thoại

Trên điện thoại cùng Wi-Fi, mở URL tải CA:

```text
http://192.168.1.25:8085/livekit-meet-lan-ca.crt
```

Cài file tải xuống dưới dạng CA certificate. Trên iPhone/iPad, sau khi cài profile, bật trust tại **Settings → General → About → Certificate Trust Settings**. Profile cài thủ công chưa tự bật trust SSL/TLS theo [hướng dẫn Apple](https://support.apple.com/en-ie/102390). Trên Android, cài CA trong phần Security/Credentials và kiểm tra trình duyệt báo HTTPS an toàn.

Không chia sẻ `.local/lan-certs/ca.key` hoặc `.local/lan-certs/server.key`. Chỉ cài `ca.crt` trên thiết bị.

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

Không cấu hình port forwarding trên router. Trên điện thoại, mở `https://192.168.1.25:3000`, tạo hoặc tham gia phòng và cấp quyền camera/microphone. Nếu vào phòng nhưng không có media, kiểm tra `node_ip`, firewall `7881/TCP`, `7882/UDP` và AP/client isolation trên router.

Khi IP LAN đổi, chạy lại `scripts/generate-lan-certs.sh <IP-mới>`, cập nhật `LIVEKIT_URL` và `node_ip`, rồi khởi động lại proxy và LiveKit. CA hiện tại được giữ nên không cần cài lại nếu `.local/lan-certs/ca.crt` không đổi.

Tham khảo: [LiveKit local deployment](https://docs.livekit.io/transport/self-hosting/local/), [cổng và firewall LiveKit](https://docs.livekit.io/transport/self-hosting/ports-firewall/), [Next.js bind host](https://nextjs.org/docs/app/api-reference/cli/next), [điều kiện secure context cho camera/microphone](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia).

## Xử lý lỗi thường gặp

| Triệu chứng | Kiểm tra |
|---|---|
| `navigator.mediaDevices` không tồn tại hoặc không bật được camera | Dùng `https://` với chứng chỉ được thiết bị tin cậy; `http://localhost` chỉ phù hợp khi mở trên chính máy chủ. |
| Trang mở được nhưng LiveKit báo connection error | Kiểm tra `LIVEKIT_URL`, WSS/WebSocket proxy, chứng chỉ, firewall và các cổng media. Mở `docker compose logs -f livekit` để xem log server. |
| Không lấy được token hoặc API trả lỗi | Kiểm tra `LIVEKIT_API_KEY` và `LIVEKIT_API_SECRET` trong `meet/.env.local` có khớp cấu hình LiveKit không; sau khi đổi env, khởi động lại Next.js. |
| HTTPS/WSS proxy không phản hồi | Kiểm tra tiến trình `node scripts/lan-proxy.mjs`, chứng chỉ trong `.local/lan-certs/`, và cổng `3000`/`8085`. |
| Cổng đã được sử dụng | Dừng tiến trình đang giữ cổng `3000`, `3001`, `7880`, `7881`, `7882` hoặc `8085`, hoặc chỉnh cấu hình cổng tương ứng. |

## Tệp cấu hình

| Tệp | Vai trò |
|---|---|
| `docker-compose.yml` | Khởi động LiveKit server trong Docker. |
| `livekit.yaml` | Cổng LiveKit/WebRTC và mức log. Tên tệp trong repo dùng đuôi `.yaml`. |
| `meet/.env.local` | URL, API key và secret ứng dụng dùng để tạo token/kết nối LiveKit. |
| `meet/package.json` | Lệnh Next.js, phiên bản Node tối thiểu và phiên bản pnpm. |

Hướng dẫn chạy benchmark nằm trong [`PERFORMANCE_README.md`](PERFORMANCE_README.md); kết quả đo trên máy phát triển nằm trong [`meet/LIVEKIT_PERFORMANCE_REPORT.md`](meet/LIVEKIT_PERFORMANCE_REPORT.md).
