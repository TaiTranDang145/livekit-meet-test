# LiveKit Meet — product deployment

Nhánh `product` đóng gói giao diện Next.js trong `meet/`, LiveKit Server và Nginx reverse proxy trong Docker Compose. Sơ đồ chạy trên một máy Linux có IP công khai. Khi deploy product, dùng chứng chỉ TLS được CA và trình duyệt người dùng tin cậy. Để test trên các thiết bị do bạn quản lý, repo có script tạo CA nội bộ và chứng chỉ cho IP. Repo không chứa khóa/chứng chỉ được tạo.

## Kiến trúc

| Thành phần | Vai trò | Địa chỉ/cổng |
|---|---|---|
| `nginx` | TLS, HTTPS cho Meet và WSS signaling cho LiveKit | `8443/TCP`; `/rtc` → `127.0.0.1:7880`; các đường dẫn khác → `127.0.0.1:3001` |
| `meet` | Next.js production server, tạo token LiveKit | Docker publish loopback `127.0.0.1:3001` |
| `livekit` | Signaling và SFU media trong cùng một server | Signaling `127.0.0.1:7880`; ICE UDP mux `8443`; ICE/TCP fallback tắt |
| Người tham gia | Trình duyệt tải Meet và gửi/nhận WebRTC media | HTTPS/WSS qua `8443/TCP`; media trực tiếp tới `8443/UDP` |

Nginx và LiveKit dùng host networking trên Linux. Nginx chỉ nhận TCP; UDP `8443` đi thẳng tới LiveKit. Cùng số cổng `8443` nhưng TCP và UDP cần hai rule firewall riêng. Cấu hình này chạy một node; cần thêm Redis và nhiều node LiveKit để triển khai distributed/HA.

## Điều kiện trước khi deploy product

- Máy Linux có IP công khai ổn định, Docker Engine và Docker Compose plugin v2.
- Một DNS A record trỏ về máy, ví dụ `meet.example.com`.
- Chứng chỉ TLS hợp lệ cho domain, lưu tại `.local/nginx-certs/fullchain.pem` và `.local/nginx-certs/privkey.pem`.
- Firewall cho phép TCP `8443` tới Nginx và UDP `8443` tới LiveKit.

Nếu truy cập bằng IP, không cần DNS; chứng chỉ được cấp phải có IP đó trong SAN. Nếu chứng chỉ do CA nội bộ ký, các thiết bị truy cập cần tin cậy CA nội bộ.

Public endpoint của giao diện và signaling dùng chung một domain/port:

- `https://meet.example.com:8443` → Nginx → Meet `127.0.0.1:3001`
- `wss://meet.example.com:8443/rtc` → Nginx → LiveKit signaling `127.0.0.1:7880`
- WebRTC UDP → LiveKit `IP-công-khai:8443/UDP`

`7880/TCP` và Meet `3001/TCP` chỉ truy cập nội bộ. ICE/TCP fallback được tắt (`tcp_port: 0`), vì vậy nếu mạng client chặn UDP `8443`, client có thể vào phòng nhưng không truyền được media. LiveKit dùng `udp_port` làm UDP mux nên không cần dải UDP. Xem [tài liệu cổng LiveKit](https://docs.livekit.io/transport/self-hosting/ports-firewall/).

## 1. Clone repo và checkout nhánh `product`

```bash
git clone https://github.com/TaiTranDang145/livekit-meet-test.git
cd livekit-meet-test
git fetch origin
git checkout product
```

Lệnh checkout chuyển sang nhánh `product` trên GitHub (và tạo nhánh local theo dõi `origin/product` nếu chưa có).

## 2. Tạo và cài chứng chỉ TLS

Cách dưới đây tạo CA nội bộ và chứng chỉ dùng IP công khai của VM, với thời hạn tối đa khoảng 50 năm. Dùng cho test trên các thiết bị bạn quản lý; không dùng cho người dùng product công khai vì họ không tin cậy CA nội bộ mặc định. Cần OpenSSL `1.1.1+` và `curl`.

Lấy IPv4 public của VM trong cùng phiên terminal:

```bash
PUBLIC_IP="$(curl -4fsS https://api.ipify.org)"
printf 'Public IPv4: %s\n' "$PUBLIC_IP"
```

Nếu VM dùng NAT hoặc ánh xạ IP, đối chiếu giá trị này với IP inbound trong bảng điều khiển nhà cung cấp. Nếu khác, đặt lại biến `PUBLIC_IP` bằng IP inbound chính xác trước khi tạo chứng chỉ.

Sinh chứng chỉ cho IP đã xác nhận:

```bash
bash scripts/generate-self-signed-tls.sh "$PUBLIC_IP"
```

Script tạo các file trung gian tại `.local/generated-tls/` và CA nội bộ tại `.local/tls-ca/`. Chép chứng chỉ và private key vào đúng thư mục Nginx đang mount; `.local/` nằm cùng cấp với `meet/` và `docker-compose.yml`:

```bash
mkdir -p .local/nginx-certs
install -m 0644 .local/generated-tls/fullchain.pem .local/nginx-certs/fullchain.pem
install -m 0600 .local/generated-tls/privkey.pem .local/nginx-certs/privkey.pem
```

Kiểm tra các file đã được cài:

```bash
test -s .local/nginx-certs/fullchain.pem && test -s .local/nginx-certs/privkey.pem
```

Nginx đọc `.local/nginx-certs/fullchain.pem` và `.local/nginx-certs/privkey.pem` theo cấu hình `nginx/livekit-meet.conf`. Cài `.local/tls-ca/rootCA.crt` vào kho tin cậy trên từng thiết bị test. Trên iPhone/iPad, sau khi cài profile, bật tin cậy SSL/TLS tại **Settings → General → About → Certificate Trust Settings**; xem [hướng dẫn của Apple](https://support.apple.com/en-ie/102390). Không gửi `.local/tls-ca/rootCA.key` cho thiết bị; file này là private key của CA.

Chứng chỉ máy chủ và CA gốc có thời hạn tối đa khoảng 50 năm (`18.250` ngày); không có tác vụ gia hạn tự động. Nếu IP thay đổi, chạy lại script với IP mới rồi chép lại hai file vào `.local/nginx-certs/`. Nếu private key CA gốc bị lộ, tạo CA mới và cài lại `rootCA.crt` trên mọi thiết bị.

Tạo file env, sau đó chạy script với cùng IP đã dùng để cấp chứng chỉ. Script sẽ lưu URL WSS theo IP đó cùng API key và secret:

```bash
cp meet/.env.production.example meet/.env.production
python3 scripts/generate-livekit-keys.py "$PUBLIC_IP"
```

Script chạy container LiveKit tạm để sinh key/secret rồi cập nhật `LIVEKIT_URL=wss://<IP>:8443`, `LIVEKIT_API_KEY` và `LIVEKIT_API_SECRET` trong file hiện có. Chạy một lần khi cấu hình môi trường; chạy lại sẽ thay cặp key/secret cũ. Các service trong `docker-compose.yml` chưa cần chạy; Docker Engine phải hoạt động và máy cần có Python 3. Nếu image chưa có, Docker sẽ tải image trước. Secret không được in ra terminal; script đặt quyền file env thành `0600`. Không commit hoặc chia sẻ file này.

## 3. Khởi động dịch vụ

Kiểm tra cấu hình Compose rồi build và chạy Meet, LiveKit cùng Nginx:

```bash
docker compose --env-file meet/.env.production config --quiet
docker compose --env-file meet/.env.production up -d --build
docker compose --env-file meet/.env.production ps
```

Xem log các service:

```bash
docker compose --env-file meet/.env.production logs -f meet livekit nginx
```

Next.js chạy trong container production từ `meet/Dockerfile`, được publish loopback `127.0.0.1:3001`. Nginx xử lý HTTPS/WSS trên `8443/TCP`. LiveKit chạy không có `--dev`; khóa API được cấp qua `LIVEKIT_KEYS`. Cấu hình media nằm trong `livekit.yml` với `udp_port: 8443`.

## 4. Kiểm tra cuộc gọi

1. Mở endpoint đã cấu hình ở bước 2 (`https://meet.example.com:8443` hoặc `https://<IP_CÔNG_KHAI>:8443`), tạo phòng và cấp quyền camera/microphone.
2. Mở cùng phòng trên thiết bị thứ hai.
3. Kiểm tra log `livekit` để xác nhận participant kết nối; xác nhận audio/video hai chiều.
4. Nếu signaling thành công nhưng không có media, kiểm tra IP công khai LiveKit được quảng bá, rule UDP `8443` ở host/cloud firewall và chính sách NAT của máy chủ.

Mạng client hạn chế UDP cần TURN để có đường media dự phòng. TURN chưa được cấu hình trong file này; bổ sung TURN cần thêm cấu hình/domain và có thể mở thêm cổng, nên sẽ thay đổi kiến trúc chỉ dùng số cổng `8443`.

## 5. Cập nhật phiên bản từ GitHub

Giữ `meet/.env.production` và chứng chỉ trong `.local/nginx-certs/` trên máy chủ. Khi có commit mới trên nhánh `product`:

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
├── scripts/
│   ├── generate-livekit-keys.py
│   └── generate-self-signed-tls.sh
├── nginx/
│   └── livekit-meet.conf
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
