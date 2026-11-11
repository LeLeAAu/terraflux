using SpeedyWeather
using Dates

println("Đang tạo lưới khí quyển...")

# Cấu hình ban đầu: T32, 8 tầng khí quyển
grid = SpectralGrid(
    truncation = 32,
    nlayers = 8,
)

# Mô hình khí quyển có hơi nước
model = PrimitiveWetModel(grid)
add!(model, SpeedyWeather.SeaSurfaceTemperatureOutput(),
    SpeedyWeather.SoilTemperatureOutput(), SpeedyWeather.LandSeaMaskOutput())

println("Đang khởi tạo mô phỏng...")
simulation = initialize!(model)

println("Bắt đầu chạy 10 ngày mô phỏng...")
run!(
    simulation,
    period = Day(10),
    output = true,
)

println("Đã chạy xong!")
println("Thư mục làm việc: ", pwd())