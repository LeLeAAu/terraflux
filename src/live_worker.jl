# Separate Julia process: compute never blocks the GLMakie event loop.
using SpeedyWeather, Dates, TOML
include("live.jl")
using .TerraFluxLive: atomic_toml
include("data.jl")
using .TerraFluxData

function worker(directory)
    config = TOML.parsefile(joinpath(directory,"config.toml"))
    files = String[]
    completed, sequence = 0, 0
    publish(state; error="") = atomic_toml(joinpath(directory,"status.toml"),Dict(
        "state"=>state,"completed"=>completed,"files"=>files,"sequence"=>sequence,"error"=>error))
    try
        cd(directory)
        publish("starting")
        grid = SpectralGrid(truncation=config["truncation"],nlayers=config["layers"])
        model = PrimitiveWetModel(grid)
        simulation = initialize!(model)
        # Runs are a new experiment, independent of the file currently being viewed.
        mode = "pause"
        publish("paused")
        while true
            # Immutable command records avoid replacement races on Windows.
            commands = filter(name -> endswith(name,".toml"),readdir(joinpath(directory,"commands")))
            if !isempty(commands)
                command = TOML.parsefile(joinpath(directory,"commands",last(commands)))
                if command["sequence"] > sequence
                    sequence = command["sequence"]
                    mode = command["action"]
                    mode == "pause" && publish("paused")
                end
            end
            if mode == "stop"
                publish("stopped")
                break
            elseif completed >= config["max_chunks"]
                publish("complete")
                break
            elseif mode in ("run","step")
                publish(mode == "run" ? "running" : "stepping")
                start = simulation.variables.prognostic.clock.time
                run!(simulation;period=Hour(config["chunk_hours"]),output=true)
                finish = simulation.variables.prognostic.clock.time
                finish-start == Hour(config["chunk_hours"]) || error("Đồng hồ mô hình không tiến đúng 6 giờ.")
                for name in (:temperature,:u,:v,:humidity)
                    values = Array(get_step(getproperty(simulation.variables.grid,name)))
                    all(isfinite,values) || error("Trạng thái $name không hữu hạn; mô phỏng đã dừng.")
                    name == :temperature && minimum(values) <= 0 && error("Nhiệt độ không hợp lệ.")
                end
                !model.feedback.nans_detected || error("Mô hình phát hiện phép tính mất ổn định.")
                path = joinpath(model.output.run_path,model.output.filename)
                chunk = load_weather(path)  # NetCDF has been finalized and closed by run!.
                chunk.times[1] == start && chunk.times[end] == finish || error("Thời gian đầu ra không khớp mô hình.")
                for (field,data) in chunk.fields
                    # Initial MSLP uses surface diagnostics that do not exist until physics runs.
                    # Every completed endpoint must be valid; never mask a later model failure.
                    checked = field == :mslp ? data[:,:,end:end] : data
                    all(isfinite,checked) || error("Đầu ra $field không hữu hạn.")
                end
                push!(files,abspath(path))
                completed += 1
                mode == "step" && (mode = "pause")
                publish(mode == "pause" ? "paused" : "running")
            else
                sleep(0.05)
            end
        end
    catch err
        publish("error";error=sprint(showerror,err))
        rethrow()
    end
end
worker(abspath(only(ARGS)))
