# Tùy biến biểu tượng và animation bão

**Chỗ chỉnh chính: `assets/storm_tracker/style.toml`.** Sửa file rồi đóng/mở lại
TerraFlux. Không cần sửa dữ liệu kịch bản, mô hình khí quyển hay mã giao diện.

## Dùng ảnh PNG riêng

Đặt ảnh PNG trong suốt vào thư mục này, ví dụ `my_storm.png`, rồi sửa mục đã có:

```toml
[sprites.default]
file = "my_storm.png"
frames = 1
fps = 8.0
rotate = true
```

`default` áp dụng cho các cấp không có ảnh riêng. `rotate = true` xoay toàn bộ ảnh
bằng tốc độ cấu hình bên dưới, theo dấu bán cầu. `false` giữ nguyên hướng ảnh.

Dùng ảnh có sẵn biểu tượng/chữ/số ở giữa thì để `show_symbol_on_sprite = false`.
Muốn ứng dụng vẫn vẽ ký hiệu phân loại lên trên ảnh thì đặt giá trị đó thành true.
Nhãn ID/tên và thẻ thông tin luôn lấy từ dữ liệu kịch bản, không lấy từ ảnh.

## Dùng animation nhiều khung

Xuất một **dải PNG nằm ngang**, các khung bằng nhau, từ trái sang phải. Nên dùng
khung vuông với nền trong suốt để dễ căn chỉnh. Ví dụ 8 khung, mỗi khung 128×128:
ảnh tổng có kích thước **1024×128**.

```toml
[sprites.default]
file = "storm_strip.png"
frames = 8
fps = 10.0
rotate = false
```

Ảnh chạy vòng lặp theo thời gian thực. Nếu animation trong ảnh đã xoay rồi,
`rotate = false` tránh xoay thêm cả dải. Chiều chuyển động bên trong khung ảnh do
chính ảnh quyết định; `rotate` chỉ điều khiển phép xoay toàn bộ ảnh. GIF, video
và dải nhiều hàng chưa được hỗ trợ trực tiếp.

Tốc độ cập nhật giao diện ở `[animation].refresh_fps` (mặc định 30; tối đa 60).
FPS của sprite chọn khung theo thời gian; nếu đặt cao hơn tần suất cập nhật hoặc
khả năng máy thì một số khung sẽ bị bỏ qua. Phát lại dữ liệu vẫn là 2 khung/giây,
và việc đổi animation không làm thời gian mô phỏng chạy nhanh/chậm hơn.

## Ảnh riêng cho từng cấp

Có thể thêm các mục override sau, trong khi mục default vẫn là ảnh dùng chung
hoặc để `file = ""` cho hình dự phòng:

```toml
[sprites.C3]
file = "category3_strip.png"
frames = 8
fps = 12.0
rotate = false

[sprites.S]
file = "tropical_storm.png"
frames = 1
fps = 8.0
rotate = true
```

Các key hỗ trợ: `L`, `D`, `SD`, `S`, `SS`, `EX`, `RL` (ký hiệu ×), `C1`…`C5`
và `LOW`, `POST`, `UNKNOWN`, `MODEL_LOW` (L?), `MODEL_WARM` (W), `MODEL_COLD` (C).
Ba nhóm `MODEL_*` dùng ảnh riêng
nếu khai báo, nếu không dùng hình dự phòng; không mượn default của bão nhiệt đới.
Hình dự phòng của mô hình là chấm tròn nhỏ W/C/L?, không xoay; các nhóm kịch bản
vẫn có cánh xoáy. Kích thước chấm mô hình bằng 0.4×`size`, đang chọn bằng
0.6×`selected_size`. Có thể dùng ảnh/strip riêng cho từng `MODEL_*` để thay hình.
Ảnh nên dùng màu/ký hiệu nhất quán với chú giải phân loại. `file` rỗng nghĩa là
bỏ cấu hình ảnh đó; nếu không có ảnh riêng và default cũng rỗng, dùng hình vẽ dự
phòng. Tệp không tồn tại, số khung không chia hết chiều rộng hoặc cấu hình sai
sẽ báo lỗi cụ thể khi mở app.

## Chỉnh hình vẽ dự phòng và hiệu ứng

```toml
[appearance]
size = 58.0                 # Kích thước icon thông thường, pixel
selected_size = 70.0        # Icon đang chọn
glow_opacity = 0.16         # 0 để bỏ quầng sáng
glow_scale = 1.12
show_symbol_on_sprite = false

[procedural]
arms = 3
inner_radius = 0.24
twist = 1.6

[animation]
spin_radians_per_second = 0.32
refresh_fps = 30.0
```

Tùy chọn **Giảm hiệu ứng / ngừng xoay** trên giao diện dừng phép xoay và giữ khung
PNG đầu tiên. Kích thước icon và tốc độ animation là thông số hình ảnh, không phải
bán kính bão hay tốc độ gió thực.

Muốn viết kiểu vẽ hoàn toàn mới bằng Julia: xem **`src/storm_icons.jl`**:

- `procedural_marker(style)`: đường bao biểu tượng chuẩn hóa khoảng −0.5…0.5.
- `icon_frame(sprite, seconds)`: chọn khung hình.
- `icon_rotation(style, latitude, seconds)`: góc xoay.

`src/tracker.jl` chỉ nối các hàm này với vị trí/phân loại và phần còn lại của UI.
Không cần thay đổi phương trình, trạng thái hay đồng hồ của SpeedyWeather.


## Kích thước theo vùng xoáy

`[appearance].scale_with_vortex = true` nhân cỡ icon theo căn bậc hai của
`radius_km / extent_reference_km` (mặc định 750 km), giới hạn 0.6–1.8 lần.
Đặt false để giữ cỡ cố định. Model giữ hệ số nhỏ hơn và không mượn sprite bão
nhiệt đới. Bán kính thiếu giữ cỡ gốc; pixel icon không phải phạm vi km chính xác.
Phương pháp đo và vòng phạm vi ở [MAP_OVERLAYS.md](../../docs/MAP_OVERLAYS.md).
