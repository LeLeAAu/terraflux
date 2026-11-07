# Dữ liệu kịch bản Storm Tracker

`demo_storms.toml` là dữ liệu **khai báo thủ công để thử giao diện**. Không phải
kết quả nhận diện từ SpeedyWeather, quan trắc hay dự báo. Bản này chỉ nhận provenance
`illustrative_scenario`; nguồn nhập ngoài cần adapter riêng. Nguồn ứng viên mô hình hiện được tạo trực tiếp
từ NetCDF bởi `src/detection.jl`, không nhập giả qua kịch bản TOML này.

```toml
[scenario]
title = "Tên kịch bản"
provenance = "illustrative_scenario"
wind_average_minutes = 1
wind_height_m = 10
basin = "wpac" # wpac/atlantic/epac/cpac/other/unspecified

[[systems]]
id = "DEMO-EXAMPLE"
name = "Tên minh họa"
local_name = "Tên phụ tùy chọn"
[[systems.samples]]
time = "2000-01-01T00:00:00"
lon = 140.0
lat = 12.0
wind_knots = 20.0
kind = "disturbance"
# pressure_hpa = 1005.0  # Tùy chọn; không có thì hiển thị thiếu dữ liệu.
[[systems.samples]]
time = "2000-01-02T00:00:00"
lon = 138.0
lat = 13.0
wind_knots = 15.0
kind = "remnant"
active = false
```

- Mỗi ID không rỗng, duy nhất, có ít nhất hai mốc tăng nghiêm ngặt. Sau mốc
  `active = false` không được tái dùng ID. Các mốc không ghi `active` mặc định true.
- Kinh độ −180…180°, vĩ độ −90…90°, gió cực đại duy trì 1 phút ở 10 m, đơn vị knot không âm, áp suất hPa dương nếu có.
  Mọi số phải hữu hạn. `time` cùng hệ thời gian DateTime của mô hình, không tự đổi
  múi giờ hoặc dịch năm cho khớp tệp đang mở.
- `kind`: `low`, `disturbance`, `tropical`, `subtropical`, `extratropical`,
  `posttropical`, `remnant`. Loại là cấu trúc được khai báo, không suy ra chỉ từ gió.
  Đối với `tropical`, cấp được suy ra từ gió duy trì 1 phút/10 m theo các ngưỡng
  knot 34/64/83/96/113/137. Các loại khác giữ ý nghĩa trạng thái đã khai báo.
  `remnant` phải có gió <34 knot; `subtropical` không tự thành typhoon khi gió >=64.
- `basin` ở `[scenario]` áp dụng mặc định cho các hệ thống; từng `[[systems]]`
  có thể ghi đè. Không khai báo thì là `unspecified`. Ở `wpac` dùng TY >=64 kt,
  STY >=130 kt và ghi rõ Category là **tương đương SSHWS**. Ở `atlantic`, `epac`,
  `cpac` dùng Hurricane/Major hurricane. Menu vùng/camera không đổi phân loại.
  `basin` hiện cố định cho cả track; chưa tự đổi khi track đi qua ranh giới lưu vực.
  Toàn bộ định nghĩa và nguồn: [`STORM_CLASSIFICATION_US.txt`](../STORM_CLASSIFICATION_US.txt).
- Trước mốc đầu/sau mốc cuối hoặc ở mốc inactive không có biểu tượng hoạt động.
  Khi nội suy, vị trí đi qua đường kinh độ ngắn nhất, gió/áp suất nội suy tuyến
  tính nếu cả hai đầu đều có giá trị và cùng `kind`; khác `kind` giữ gió/áp suất
  mốc trước đến mốc chuyển tiếp. Loại hệ thống giữ tới mốc chuyển tiếp.
- Không thêm số impacts, ACE hay ENSO vào schema như thể chúng được tính từ gió;
  các chỉ số này cần nguồn và quy tắc riêng.

Có thể sửa kịch bản để thử, nhưng luôn giữ nhãn nguồn. Dữ liệu này không thay đổi
phương trình, trạng thái, cấu hình hoặc kết quả mô phỏng khí quyển.


Mỗi sample có thể thêm `radius_km = 750.0` (0 < R ≤ 5000 km) cho **phạm vi
minh họa được khai báo**. Thiếu thì giữ thiếu. Nội suy R chỉ khi hai đầu cùng
loại và đều có R; chuyển loại giữ R mốc trước. Không dùng max gió để tự điền R.
Bộ DEMO hiện không khai báo bán kính. Lớp phủ ghi MINH HỌA khi dùng nguồn này.
