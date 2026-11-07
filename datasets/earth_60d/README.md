# Thí nghiệm khí quyển 60 ngày

Đã tính sẵn bằng `generate_long_run.jl`. App mặc định mở `run_0001/output.nc`;
bạn không cần chạy lại để xem. T32 / 8 tầng sigma, ghi mỗi 6 giờ, **241 mốc** từ
2000-01-01 tới 2000-03-01; NetCDF khoảng 52.4 MiB.

Đây là PrimitiveWetModel từ điều kiện mặc định SpeedyWeather, không phải dữ liệu
quan trắc hoặc dự báo. Biến `pres` bổ sung áp suất bề mặt cho RH; `mslp` là áp
suất quy mực biển, không thể thay thế `pres`. Mốc khởi tạo chưa có chẩn đoán áp
suất; thuộc tính NetCDF yêu cầu viewer hiển thị thiếu tại mốc đó.

- `experiment.toml`: ngày, seed, Julia, thời gian chạy, dung lượng, kiểm chứng.
- `run_0001/parameters.txt`: cấu hình mô hình.
- `run_0001/restart.jld2`: trạng thái cuối; chưa có nút khôi phục trong UI.
- `run_0001/progress.txt`: tiến trình ghi bởi SpeedyWeather.

Các biến dùng nén/keepbits mặc định của thư viện; không thêm chi tiết ảnh để giả
độ phân giải cao hơn. Hướng dẫn lớp hiển thị/công thức và tái tạo ở
[`docs/WEATHER_MAPS.md`](../../docs/WEATHER_MAPS.md).
