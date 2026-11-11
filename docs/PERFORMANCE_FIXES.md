# Sửa lỗi và giảm cấp phát khi xem dữ liệu

Bản rà soát ngày 11/11/2026 tập trung vào viewer, nạp kết quả A/B và vòng đời
worker. Không đổi phương trình mô hình, tiêu chí nhận diện hay dữ liệu mẫu.

## Thay đổi

- Đọc giá trị tại một điểm bằng ô lưới gốc; không tạo cả bản đồ gió/RH cho
  một lần đọc. Các phép tính RH và quy tắc thiếu dữ liệu được giữ nguyên.
- Tính min/max hữu hạn theo từng mặt phẳng, tránh sao chép nhiều tháng dữ liệu
  và tạo mảng lọc. Viewer nhớ thang màu khóa theo trường/tầng; thay dữ liệu live
  sẽ xóa bộ nhớ đệm. Palette được tái sử dụng.
- A/B giữ lại heatmap và đường bờ khi tua/đổi trường. Bấm đọc điểm không dựng
  lại bản đồ hoặc quét lịch sử Δ. Biên màu Δ được nhớ theo trường/tầng và xóa
  khi có dữ liệu mới. Đổi lưới vẫn dựng lại các plot cần thiết.
- Cập nhật A/B chỉ đọc các đoạn NetCDF mới, vẫn kiểm tra kích thước/checksum
  các đoạn cũ khi bật xác minh. Đang xem mốc trước thì cập nhật trạng thái không
  kéo thanh thời gian về cuối. Đổi loại can thiệp giữ tọa độ/bán kính đã nhập.
- Ghi lệnh live thất bại không làm tăng số thứ tự lệnh, tránh kẹt lưu/can thiệp
  vì chờ một lệnh chưa từng được ghi.
- Dừng live/batch có bước kết thúc cưỡng bức nếu SIGTERM bị kẹt. Không ghi được
  tệp lệnh hoặc mất thư mục cũng không được bỏ qua việc dừng tiến trình.
  Batch giữ lỗi gốc và trạng thái hoàn tất hợp lệ.
- Điều phối A/B có thêm pipe nhận STOP/EOF, không chỉ dựa vào tệp STOP.
  Coordinator được dành ít nhất 6 giây để dừng và thu hồi worker con trước
  khi áp dụng bước kết thúc cưỡng bức cho chính coordinator.
- Từ chối thời gian NetCDF lặp/đảo thứ tự và các đoạn live đổi tập trường.

## Đo và kiểm chứng

Trên Linux, Julia 1.13.3, bộ mẫu T32/8 tầng/60 ngày, sau khi biên dịch nóng,
`@allocated color_limits(data, field, 8, 1)` với thang khóa:

| Trường | Trước | Sau |
| --- | ---: | ---: |
| u | 8.88 MB | 160 byte |
| Tốc độ gió | 17.77 MB | 80 byte |
| RH | 14.10 MB | 96 byte |

Đây là cấp phát tạm của phép quét thang màu, không phải RAM toàn ứng dụng hay
FPS. Lượt quét đầu vẫn duyệt toàn bộ thời gian; trên phép đo này u/gió chậm hơn
bản cũ vài mili giây, RH tương đương. Lợi ích khi tương tác đến từ bỏ các lượt
quét lặp, tránh dựng lại plot và giảm cấp phát. Viewer vẫn giữ dữ liệu trong RAM.

Các kiểm tra có thể chạy lại từ thư mục repo:

```sh
julia --project=. test/runtests.jl
julia --project=. test/data_scans.jl
julia --project=. test/weather_data.jl
julia --project=. test/live_history.jl
julia --project=. test/process_shutdown.jl
julia --project=. test/batch_status.jl
# Cần OpenGL/màn hình:
julia --threads=2 --project=. test/viewer_smoke.jl
julia --threads=2 --project=. test/comparison_reopen.jl /path/to/comparison.toml
julia --threads=2 --project=. test/comparison_rendering.jl /path/to/two-frame/comparison.toml /path/to/different-grid/comparison.toml
# Cần bản lưu sạch còn ít nhất hai đoạn 6 giờ:
julia --threads=2 --project=. test/comparison_model.jl /path/to/session.toml /path/to/new-validation-dir
julia --threads=2 --project=. test/comparison_cancel.jl /path/to/session.toml
```

A/B thật T21/8 đã qua 38 kiểm tra: cặp không can thiệp giống nhau, mốc cuối,
bản lưu hai nhánh, chuyển thư mục và phát hiện checksum sai. Kiểm tra hủy dùng
worker thật, gồm metadata hỏng, không ghi được STOP và đóng pipe phía UI.
Giao diện được kiểm tra trên OpenGL phần mềm Linux; chưa chạy trực tiếp Windows.
