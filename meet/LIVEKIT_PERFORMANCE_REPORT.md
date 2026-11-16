# Báo cáo benchmark LiveKit Meet

**Ngày đo:** 16/11/2026 (Asia/Bangkok)  
**Kết quả cao nhất đã xác nhận:** 10 phòng đồng thời × 10 participant/phòng = 100 participant, chạy ổn định 60 giây.

## Kết luận

Máy hoàn thành cả hai mốc 5 và 10 phòng. Ở mốc 10, cả 100 client đều kết nối, publish audio/video và nhận track của 9 participant còn lại; không ghi nhận client rớt trong 60 giây đo.

Mốc 10 đã gần giới hạn thực tế của máy trong cấu hình benchmark này: CPU toàn máy đạt 94.33%, RAM khả dụng thấp nhất 584.6 MiB và swap 4 GiB được dùng hết. Mốc 5 có nhiều khoảng trống hơn. Vì chưa thử trên 10 phòng nên 10 là mức cao nhất đã kiểm chứng, không phải giới hạn tuyệt đối.

## Máy và phần mềm

| Thành phần | Cấu hình |
|---|---|
| Máy | Lenovo IdeaPad 5 Pro 14IAP7, mã DMI 82SH |
| CPU | Intel Core i7-1260P, 12 lõi / 16 luồng |
| RAM | 16 GB; Linux nhận 15.34 GiB |
| Swap | 4 GiB |
| Hệ điều hành | Ubuntu 24.04.5 LTS, kernel 7.0.0-43-generic |
| LiveKit | livekit/livekit-server, phiên bản 1.13.11, dev mode, host networking |
| LiveKit CLI | 2.19.4 |
| Ứng dụng Meet | Next.js dev server và HTTPS/WSS proxy vẫn chạy trong lúc đo |

## Cách tạo tải

Mỗi participant là một tiến trình LiveKit CLI tham gia phòng riêng. Mỗi participant:

- Publish một video demo có simulcast và một luồng audio Opus 48 kHz, âm hình sin tổng hợp 32 kbps.
- Bật auto-subscribe để nhận audio và video của 9 participant còn lại, tương đương 18 track từ xa.
- Được xác nhận qua log kết nối, log publish hai loại track và log subscribe.

Mỗi mốc được chạy riêng, tăng client khoảng 2 lần/giây, chờ các track đăng ký rồi đo 60 giây. CPU/RAM được lấy mẫu xấp xỉ mỗi 2 giây. CPU của container LiveKit lấy từ Docker stats; CPU toàn máy bao gồm cả server lẫn các tiến trình giả lập chạy trên chính máy này.

## Kết quả

| Phòng | Participant | Kết quả track | CPU toàn máy đỉnh / TB | CPU LiveKit đỉnh | RAM máy dùng đỉnh / khả dụng thấp nhất | Swap dùng đỉnh | RAM container LiveKit đỉnh |
|---:|---:|---|---:|---:|---:|---:|---:|
| 5 | 50 | Tất cả publish AV và nhận đủ track; ổn định 60 giây | 73.74% / 66.51% | 346.53% một lõi; tương đương 21.66% tổng 16 luồng | 12.26 GiB / 3.08 GiB | 2.61 GiB | 797 MiB |
| 10 | 100 | Tất cả publish AV và nhận đủ track; ổn định 60 giây | 94.33% / 90.66% | 499.34% một lõi; tương đương 31.21% tổng 16 luồng | 14.77 GiB / 584.6 MiB | 4.00 GiB (đầy) | 1.57 GiB |

CPU LiveKit có thể vượt 100% vì Docker biểu diễn mức dùng theo một lõi. Mức 499.34% nghĩa là server dùng xấp xỉ 5 lõi tại đỉnh; phần CPU toàn máy còn lại chủ yếu do các client giả lập.

## Diễn giải

- **5 phòng:** tải cao nhưng còn khoảng 3.08 GiB RAM khả dụng; đây là mốc có dư địa tốt hơn trong bài đo này.
- **10 phòng:** máy vẫn giữ đủ 100 participant và track trong 60 giây, nhưng CPU gần bão hòa và toàn bộ swap đã được dùng. Có thể dùng mốc này làm stress test ngắn; không nên xem đây là mức tải liên tục đã được xác nhận.
- Sau khi các client giả lập dừng, giao diện Meet vẫn trả HTTP 200, LiveKit container vẫn chạy và RAM khả dụng của máy hồi lên khoảng 7.2 GiB. Swap vẫn còn khoảng 3.9 GiB được dùng.

## Giới hạn của phép đo

Load generator chạy cùng máy với LiveKit nên CPU và RAM toàn máy bao gồm cả các tiến trình giả lập. Client kết nối trực tiếp qua loopback tới LiveKit; bài đo này không đo thông lượng Wi-Fi, router/AP, trình duyệt điện thoại, xử lý camera thật hay khử ồn giọng nói. Video và audio là nguồn tổng hợp.

Mỗi mốc chỉ được giữ ổn định 60 giây; chưa có bài soak test dài hoặc kiểm tra trên hơn 10 phòng. Cấu hình LiveKit đang ở dev mode và bật debug logging, nên số liệu này mô tả môi trường test hiện tại, không phải cam kết tải production.

## Tài liệu

- [LiveKit CLI: Rooms and participants](https://docs.livekit.io/reference/developer-tools/livekit-cli/rooms/)
- [LiveKit CLI: Load testing](https://docs.livekit.io/reference/developer-tools/livekit-cli/perf/)
- [LiveKit self-hosted benchmarking](https://docs.livekit.io/transport/self-hosting/benchmark/)
