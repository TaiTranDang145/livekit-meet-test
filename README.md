# LiveKit Meet — product deployment

Nhánh `product` đóng gói giao diện Next.js trong `meet/` và LiveKit Server trong Docker Compose để triển khai thử trên một máy Linux có IP công khai. TLS ingress/reverse proxy cần có sẵn trên máy triển khai; repo không tạo proxy hay chứng chỉ production.

## Kiến trúc

| Thành phần | Vai trò | Địa chỉ/cổng |
|---|---|---|
| `meet` | Next.js production server, tạo token LiveKit | Docker publish loopback `127.0.0.1:3001` |
| `livekit` | Signaling và SFU media | HTTP/WebSocket `7880`; ICE TCP `7881`; ICE UDP `50000–60000` |
| TLS ingress | HTTPS cho Meet và WSS cho LiveKit | `meet.example.com` → `127.0.0.1:3001`; `livekit.example.com` → `127.0.0.1:7880` |
| Người tham gia | Trình duyệt tải Meet, rồi gửi/nhận WebRTC media trực tiếp với LiveKit | HTTPS/WSS qua ingress; media tới IP công khai của LiveKit |

Compose dùng host networking cho LiveKit để các cổng media WebRTC được xử lý trực tiếp trên máy Linux. Cấu hình này chạy một node; cần thiết kế thêm Redis và các node LiveKit riêng nếu triển khai nhiều node hoặc cần HA.

## Điều kiện trước khi deploy

- Máy Linux có IP công khai ổn định, Docker Engine và Docker Compose plugin v2.
- Hai DNS A record trỏ về máy: một domain cho Meet, một domain cho LiveKit.
- TLS ingress/reverse proxy trên cùng máy, có chứng chỉ được trình duyệt tin cậy và hỗ trợ WebSocket. Chứng chỉ tự ký không phù hợp cho client production.
- Firewall cho phép TCP `80/443` tới ingress, TCP `7881` và UDP `50000–60000` tới LiveKit. Chỉ ingress được phép truy cập TCP `7880`; không mở cổng này trực tiếp cho client.

Trong ví dụ bên dưới, thay `meet.example.com`, `livekit.example.com` và IP mẫu bằng thông tin môi trường product của bạn. Ingress cần chuyển tiếp:

- `https://meet.example.com` → `http://127.0.0.1:3001`
- `wss://livekit.example.com` → `http://127.0.0.1:7880`, bật WebSocket upgrade

Trình duyệt cần truy cập trực tiếp tới IP công khai của LiveKit qua cổng media. TLS trên signaling không thay thế firewall hoặc cấu hình ICE cho media. LiveKit mặc định trong repo tự phát hiện IP ngoài qua STUN; xác nhận IP được quảng bá trong log sau khi khởi động.

## 1. Lấy nhánh `product` trên máy chủ

```bash
git clone --branch product --single-branch https://github.com/TaiTranDang145/livekit-meet-test.git livekit-meet
cd livekit-meet
```

## 2. Cấu hình API key và domain

Tạo API key và secret riêng cho môi trường này. Có thể dùng LiveKit Server CLI:

```bash
docker run --rm livekit/livekit-server:v1.13.11 generate-keys
```

Sao chép mẫu env vào file riêng trên máy chủ:

```bash
cp meet/.env.production.example meet/.env.production
```

Điền giá trị thật vào `meet/.env.production`:

```dotenv
LIVEKIT_API_KEY=<API_KEY>
LIVEKIT_API_SECRET=<API_SECRET>
LIVEKIT_URL=wss://livekit.example.com
```

`LIVEKIT_API_KEY` và `LIVEKIT_API_SECRET` phải cùng cặp với `LIVEKIT_KEYS` mà Compose truyền vào LiveKit. `LIVEKIT_URL` là domain WSS mà trình duyệt dùng. File `.env.production` bị Git bỏ qua; không commit hoặc ghi secret vào log/issue.

## 3. Khởi động dịch vụ

Kiểm tra cấu hình Compose rồi build và chạy Meet cùng LiveKit:

```bash
docker compose --env-file meet/.env.production config --quiet
docker compose --env-file meet/.env.production up -d --build
docker compose --env-file meet/.env.production ps
```

Xem log khi khởi động:

```bash
docker compose --env-file meet/.env.production logs -f meet livekit
```

Next.js chạy trong container production từ Dockerfile ở `meet/Dockerfile`. LiveKit chạy không có `--dev`; khóa API được cấp qua `LIVEKIT_KEYS`. Cấu hình LiveKit nằm trong `livekit.yml`.

## 4. Kiểm tra cuộc gọi

1. Mở `https://meet.example.com`, tạo phòng và cấp quyền camera/microphone.
2. Mở cùng phòng trên thiết bị thứ hai.
3. Kiểm tra log `livekit` để xác nhận participant kết nối; xác nhận audio/video hai chiều.
4. Nếu signaling thành công nhưng không có media, kiểm tra IP công khai LiveKit được quảng bá, firewall TCP `7881`, UDP `50000–60000` và chính sách NAT của máy chủ.

Mạng client hạn chế UDP có thể cần TURN. TURN chưa được cấu hình trong file này; cần domain, chứng chỉ và firewall riêng trước khi bật cho môi trường product.

## 5. Cập nhật phiên bản từ GitHub

Giữ `meet/.env.production` trên máy chủ. Khi có commit mới trên nhánh `product`:

```bash
git fetch origin
git switch product
git pull --ff-only origin product
docker compose --env-file meet/.env.production up -d --build
```

Compose khởi động lại các container theo image mới. Dùng `docker compose --env-file meet/.env.production logs -f` để theo dõi sau cập nhật.

## Cấu trúc repo

```text
.
├── docker-compose.yml
├── livekit.yml
├── README.md
└── meet/
    ├── Dockerfile
    ├── .env.production.example
    ├── package.json
    └── app/
```

## Tham khảo

- [LiveKit: Deploying](https://docs.livekit.io/transport/self-hosting/deployment/)
- [LiveKit: Ports and firewall](https://docs.livekit.io/transport/self-hosting/ports-firewall/)
- [Next.js: Deploying](https://nextjs.org/docs/app/getting-started/deploying)
