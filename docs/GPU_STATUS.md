# GPU hiện tại

**Dựng hình:** GLMakie dùng OpenGL 3.3; driver trên máy người dùng có thể dùng
GPU để vẽ bản đồ/địa cầu. Nếu máy có cả GPU tích hợp và NVIDIA, có thể đặt
`julia.exe` dùng GPU hiệu năng cao trong Graphics settings của Windows.
Điều này không chuyển phép tính khí quyển sang GPU. Kiểm thử cloud dùng
Mesa software rendering/Xvfb, không phải benchmark GPU.

**Tính mô hình:** launcher, live worker và bộ tạo phiên hiện dùng **CPU**;
manifest ghi backend rõ. Project chưa thêm CUDA.jl hoặc nút chọn CUDA.

SpeedyWeather phiên bản khóa trong Manifest có kiến trúc `GPU()` và kiểm tra
CUDA cho PrimitiveWetModel (`test/GPU/primitive_wet.jl`,
`test/GPU/CUDA/architecture.jl` trong mã thư viện). Vì vậy có nền tảng để tích
hợp, nhưng không thể chỉ bật một cờ và khẳng định toàn pipeline đã hoạt động.
Cần môi trường NVIDIA/CUDA phù hợp, đưa mảng lên thiết bị, kiểm tra mọi thành
phần vật lý/đầu ra, đồng bộ/chuyển dữ liệu khi ghi NetCDF và so sánh CPU/GPU.

Cloud hiện không có thiết bị NVIDIA/`nvidia-smi` để kiểm chứng CUDA. Chưa có
kết quả đo tăng tốc hay VRAM cho cấu hình máy người dùng; chưa thể bảo đảm một
cấu hình T/tầng sẽ vừa GPU. Ở lưới nhỏ, chi phí chuyển dữ liệu/khởi tạo có thể
lớn hơn lợi ích tính GPU. Khi tích hợp cần benchmark cùng cấu hình và ghi
backend/thiết bị vào manifest, thay vì dùng khả năng dựng hình làm bằng chứng.
