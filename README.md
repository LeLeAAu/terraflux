# TerraFlux

Trình quan sát khí quyển từ dữ liệu mô phỏng SpeedyWeather. Bản V1 hiện tại mở dữ liệu NetCDF đã ghi, không chạy lại mô phỏng khi kéo thời gian.

![Giao diện TerraFlux](docs/viewer.png)

## Mở trên Windows

1. Cài **Julia 1.13.3**, bảo đảm lệnh `julia --version` chạy được trong Terminal. Có thể cài qua [Juliaup](https://julialang.org/downloads/).
2. Tải/clone toàn bộ repo về máy, giải nén nếu dùng ZIP.
3. Bấm đúp **`Open_TerraFlux.bat`**.

Lần đầu cần Internet để Julia cài thư viện và biên dịch; cửa sổ dòng lệnh sẽ hiện tiến trình. Những lần sau dùng lại bộ nhớ đệm. Giao diện cần driver đồ họa hỗ trợ **OpenGL 3.3**. Nếu mở lỗi, cửa sổ dòng lệnh sẽ giữ lại thông báo để kiểm tra.

Mặc định mở `run_0001/output.nc` đi kèm repo. Có thể kéo thả một tệp `output.nc` khác lên `Open_TerraFlux.bat` để mở tệp đó. Đường dẫn chứa dấu cách được hỗ trợ. Tệp cần theo cấu trúc SpeedyWeather của dự án: `lon`, `lat`, `layer`, `time`, `temp`, `u`, `v`, `humid`, `mslp`.

Linux/macOS, với Julia trong PATH:

```sh
./open_terraflux.sh
# Hoặc chọn dữ liệu khác:
./open_terraflux.sh /path/to/output.nc
```

Từ Terminal, trên mọi hệ điều hành:

```sh
julia --project=. viewer.jl --setup
julia --project=. viewer.jl /path/to/output.nc
```

## Sử dụng

- **Trường quan sát:** nhiệt độ (°C), tốc độ gió hoặc từng thành phần gió (m/s), độ ẩm riêng (g/kg), áp suất quy về mực biển (hPa).
- **Tầng:** chọn một trong 8 tầng của dữ liệu mẫu. Sigma gần 1 là gần bề mặt, gần 0 là tầng cao. Đây không phải độ cao cố định. Áp suất quy mực biển là trường 2D, không thay đổi khi chọn tầng.
- **Thời gian:** kéo thanh hoặc bấm nút tiến/lùi. Nút Phát/Dừng phát lại 2 khung/giây, dừng ở khung cuối. Dữ liệu mẫu có 41 khung cách nhau 6 giờ trong 10 ngày. Thời gian là thời gian vật lý của mô hình.
- **Đọc tại điểm:** bấm trái vào bản đồ. Dấu chấm và bảng bên trái chỉ tọa độ/giá trị tại ô lưới gần nhất; điểm được giữ khi đổi tầng, trường và thời gian. Không nội suy giá trị tại vị trí chuột.
- **Thang màu:** mặc định giữ cùng thang cho toàn bộ thời gian của trường và tầng đang chọn. Bỏ chọn để tự co giãn theo từng khung. Gió u/v dùng thang đối xứng quanh 0.
- **Bản đồ:** cuộn để thu/phóng, giữ chuột phải để di chuyển; Ctrl + bấm trái để đặt lại. Phóng to không tăng độ phân giải vật lý.

Phần bản đồ dùng kinh độ −180…180°, vĩ độ −90…90°, đường bờ Natural Earth được đóng gói cùng GeoMakie. Nhiệt độ trong NetCDF mẫu đã là °C, không trừ Kelvin thêm lần nữa. Độ ẩm kg/kg được đổi sang g/kg. Dữ liệu thiếu được bỏ qua khi tính thang màu/thống kê, hiện trong bảng điểm dưới dạng “Thiếu dữ liệu”.

## Cấu trúc

- `src/data.jl`: đọc/kiểm tra NetCDF, chuẩn hóa tọa độ và đơn vị, chọn trường/tầng/thời gian.
- `src/viewer.jl`: giao diện GLMakie, các điều khiển và phát lại.
- `viewer.jl`: điểm khởi chạy, nhận đường dẫn dữ liệu.
- `main.jl`, `check_model.jl`: mô phỏng và kiểm tra trạng thái hiện có.
- `note1.txt`: mục tiêu và lộ trình phát triển.

Địa cầu 3D, chạy mô phỏng trực tiếp, chỉnh trạng thái và so sánh A/B là các mốc tiếp theo; chưa có trong bản này.

## Kiểm tra

Kiểm thử tọa độ, chuyển đổi đơn vị, chọn điểm, thang màu và đối chiếu trực tiếp dữ liệu mẫu:

```sh
julia --project=. test/runtests.jl
```

Kiểm thử giao diện (cần màn hình và OpenGL; trên Linux có thể dùng Xvfb):

```sh
julia --project=. test/viewer_smoke.jl
```
