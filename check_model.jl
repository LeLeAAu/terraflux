using SpeedyWeather
using Dates

function check_state(sim)
    fields = sim.variables.grid

    println("\n--- KIỂM TRA TRẠNG THÁI ---")

    for name in (:temperature, :u, :v, :humidity)
        values = Array(get_step(getproperty(fields, name)))

        # Dừng và báo lỗi nếu xuất hiện NaN hoặc vô cực
        @assert all(isfinite, values) "$name chứa NaN hoặc vô cực"

        lo, hi = extrema(values)
        println("$name: min = $lo | max = $hi")
    end

    temperature = Array(get_step(fields.temperature))
    @assert minimum(temperature) > 0 "Nhiệt độ không hợp lệ: ≤ 0 K"

    println("Đạt kiểm tra giá trị hữu hạn và nhiệt độ > 0 K.")
    return nothing
end

# Kiểm tra kết quả 10 ngày vừa chạy
check_state(simulation)

# Giữ bản sao để đối chiếu sau khi chạy tiếp
temperature_before = copy(
    Array(get_step(simulation.variables.grid.temperature))
)

println("\nĐang chạy tiếp 20 ngày...")

# Không ghi thêm đầu ra trong lần kiểm tra này
elapsed = @elapsed run!(
    simulation;
    period = Day(20),
    output = false,
)

check_state(simulation)

temperature_after = Array(
    get_step(simulation.variables.grid.temperature)
)

max_change = maximum(abs.(temperature_after .- temperature_before))

println("\nThời gian chạy thêm: ", round(elapsed; digits=2), " giây")
println("Thay đổi nhiệt độ lớn nhất: ", max_change, " K")