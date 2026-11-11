# Trạng thái hỗ trợ GPU trong TerraFlux

## 1. Dựng hình giao diện (GLMakie)
- **Công nghệ:** GLMakie sử dụng OpenGL 3.3.
- **Phần cứng xác nhận:** NVIDIA GeForce RTX 3050 Ti Laptop GPU (hoặc GPU tích hợp tùy cấu hình Windows).
- **Thiết lập:** Để đảm bảo cửa sổ 3D Globe và hệ thống hạt gió đạt 60 FPS, người dùng có thể gán `julia.exe` chạy ở chế độ **High Performance** trong Windows Settings > Display > Graphics.

---

## 2. Tính toán mô phỏng vật lý khí quyển (SpeedyWeather + CUDA)
- **Thư viện tích hợp:** `CUDA.jl` (v6.4.2), `KernelAbstractions.jl`, `SpeedyWeatherInternalsCUDAExt`, `SpeedyTransformsCUDAExt`.
- **Thiết bị kiểm chứng thực tế:** NVIDIA GeForce RTX 3050 Ti Laptop GPU (Compute Capability 8.6, 4096 MiB VRAM, Driver 610.62, CUDA Toolkit 13.3).
- **Kiến trúc mô hình:** Sử dụng `architecture = SpeedyWeather.GPU()`. Các mảng trạng thái (nhiệt độ, gió u/v, độ ẩm, xoáy, phân kỳ) được cấp phát trực tiếp trên VRAM dưới dạng `CuArray`.
- **Hiệu năng đo đạc thực tế:**
  - Chu kỳ khởi động / JIT kernel đầu tiên: ~85s.
  - Sau JIT compile: **~0.37 giây cho mỗi bước tích phân 6 giờ mô hình** (T32, 8 tầng sigma).
  - Mức chiếm dụng VRAM: ~115–350 MiB (rất an toàn so với trần 4 GB của RTX 3050 Ti).
  - Độ ổn định số học: Không phát hiện NaN (`nans_detected == false`), toàn bộ các biến $T, u, v, q$ và NetCDF xuất xưởng đều đạt chuẩn hữu hạn.

---

## 3. Cách cấu hình và sử dụng

### Khởi tạo qua giao diện (`Create_Simulation.bat` / `simulation_setup.jl`)
1. Mở `Create_Simulation.bat`.
2. Tại mục **Bộ tính toán mô hình**, hệ thống tự động nhận diện phần cứng và cung cấp 2 tùy chọn:
   - `NVIDIA CUDA (NVIDIA GeForce RTX 3050 Ti Laptop GPU)` (mặc định nếu có GPU).
   - `CPU đa luồng`.
3. Nhấn **Tạo và chạy**.

### Chạy qua dòng lệnh (`generate_long_run.jl`)
```powershell
julia --threads=2 --project=. generate_long_run.jl [số_ngày] [thư_mục_lưu] cuda
```
Ví dụ:
```powershell
julia --threads=2 --project=. generate_long_run.jl 30 datasets/earth_30d_gpu cuda
```

### Xuất xứ dữ liệu (Provenance)
Tệp `experiment.toml` lưu cùng dữ liệu NetCDF ghi nhận rõ ràng:
- `backend`: `"CUDA"` hoặc `"CPU"`.
- `gpu_device`: `"NVIDIA GeForce RTX 3050 Ti Laptop GPU"`.
- `validation`: `"All saved temp/u/v/humid finite..."`.
