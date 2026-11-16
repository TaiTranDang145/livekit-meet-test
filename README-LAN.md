# Chạy LiveKit Meet trên mạng LAN

Hướng dẫn này dùng cùng mã nguồn nhánh `product`, nhưng tạo cấu hình chạy thử riêng trong `.local/`. Không cần sửa `livekit.yml` product. Máy chủ và thiết bị tham gia cần cùng mạng Wi‑Fi/LAN.

## Khởi động

Từ thư mục gốc repo, chạy script để tự nhận IP LAN, tạo chứng chỉ và cấu hình LiveKit riêng, rồi dựng các service:

```bash
bash scripts/start-lan.sh
```

Nếu máy có nhiều card mạng hoặc VPN, truyền trực tiếp IPv4 của Wi‑Fi mà điện thoại/máy tính đang dùng:

```bash
bash scripts/start-lan.sh 192.168.1.25
```

Trước lần chạy đầu tiên, cho phép `8443/TCP` và `8443/UDP` từ subnet Wi‑Fi trên firewall máy chủ. Script tạo `.local/.env.lan` và sinh API key nếu chưa có; các lần chạy sau giữ nguyên key. Khi IP LAN đổi, chạy lại lệnh để cập nhật URL, chứng chỉ và cấu hình LiveKit. Script sẽ dựng lại các container để nạp cấu hình mới.

## Kết nối thiết bị

Script in URL Meet và đường dẫn tới CA nội bộ. Cài `.local/tls-ca/rootCA.crt` trên điện thoại/máy tính test và bật trust cho CA, sau đó mở URL được in ra, ví dụ `https://192.168.1.25:8443`. Trên iPhone/iPad, sau khi cài profile, bật tin cậy SSL/TLS tại **Settings → General → About → Certificate Trust Settings**.

Meet và signaling đi qua Nginx ở `8443/TCP`; media WebRTC đi thẳng tới LiveKit ở `8443/UDP`. Cổng `3001` và `7880` chỉ dùng nội bộ qua loopback/Nginx. Không cần cấu hình port forwarding cho thiết bị cùng LAN.

## Chuyển lại cấu hình product

LAN và product dùng chung tên service nên chỉ chạy một cấu hình tại một thời điểm. Để chuyển lại product, bảo đảm `.local/nginx-certs/` và `meet/.env.production` đã được cấu hình, rồi chạy từ thư mục gốc repo:

```bash
docker compose --env-file meet/.env.production up -d --build
```

Compose sẽ thay các container LAN bằng cấu hình product. Cấu hình product vẫn dùng `livekit.yml`, env `meet/.env.production` và chứng chỉ tại `.local/nginx-certs/`.
