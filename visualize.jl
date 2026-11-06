using SpeedyWeather
using GLMakie

GLMakie.activate!()

# Lấy nhiệt độ tại tầng khí quyển thấp nhất
temperature_K = get_step(
    simulation.variables.grid.temperature
)[:, end]

# Đổi Kelvin sang độ C
temperature_C = temperature_K .- 273.15f0

# Vẽ bản đồ theo kinh độ và vĩ độ
fig = heatmap(
    temperature_C;
    title = "TerraFlux — Lowest atmospheric layer",
    colormap = :thermal,
)

display(fig)

image_path = joinpath(@__DIR__, "temperature_day10.png")
save(image_path, fig)

println("Đã lưu bản đồ: ", image_path)