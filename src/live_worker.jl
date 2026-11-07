# Separate Julia process: compute never blocks the GLMakie event loop.
using SpeedyWeather, Dates, TOML
using SpeedyWeather: SurfacePressureOutput
include("live.jl")
using .TerraFluxLive: atomic_toml
include("data.jl")
using .TerraFluxData
using .TerraFluxLive.TerraFluxThermalPatch
include("thermal_model.jl")
using .TerraFluxThermalModel
using Printf

function worker(directory)
    config = TOML.parsefile(joinpath(directory,"config.toml"))
    files = String[]
    completed, sequence = 0, 0
    clock_time="";pending_edit=false;undo_file="";undo_previous_pending=false
    edit_summary="";command_error=""
    publish(state; error="") = atomic_toml(joinpath(directory,"status.toml"),Dict(
        "state"=>state,"completed"=>completed,"files"=>files,"sequence"=>sequence,"error"=>error,
        "model_time"=>clock_time,"pending_edit"=>pending_edit,"undo_available"=>!isempty(undo_file),
        "edit_summary"=>edit_summary,"command_error"=>command_error))
    try
        cd(directory)
        publish("starting")
        grid = SpectralGrid(truncation=config["truncation"],nlayers=config["layers"])
        model = PrimitiveWetModel(grid)
        add!(model,SurfacePressureOutput())
        simulation = initialize!(model)
        clock_time=string(simulation.variables.prognostic.clock.time)
        # Runs are a new experiment, independent of the file currently being viewed.
        mode = "pause"
        publish("paused")
        while true
            # Immutable command records avoid replacement races on Windows.
            command=TerraFluxLive.next_command(directory,sequence)
            if command!==nothing
                if command["sequence"] > sequence
                    sequence = command["sequence"]
                    action=command["action"];command_error=""
                    if action in ("thermal","undo_thermal")
                        rollback=""
                        dir=joinpath(directory,"edits",lpad(string(sequence),6,'0'))
                        try
                            mode=="pause" || error("Phải tạm dừng mô hình trước khi can thiệp.")
                            mkpath(dir)
                            if action=="thermal"
                                spec=thermal_spec(;(Symbol(k)=>v for (k,v) in command["patch"])...)
                                rollback=joinpath(dir,"before.jld2")
                                save_checkpoint(simulation,rollback)
                                report=apply_thermal!(simulation,spec)
                                save_checkpoint(simulation,joinpath(dir,"after.jld2"))
                                record=Dict{String,Any}("action"=>action,"model_time"=>clock_time,
                                    "status"=>"applied",
                                    "sequence"=>sequence,"checkpoint"=>rollback,"patch"=>command["patch"],
                                    "effect"=>Dict(string(k)=>v for (k,v) in pairs(report)),"application"=>"instantaneous, one sigma layer")
                                atomic_toml(joinpath(dir,"event.toml"),record)
                                undo_file=rollback;undo_previous_pending=pending_edit;pending_edit=true
                                edit_summary=@sprintf("ΔT chiếu: %+.3f…%+.3f K · Q khô ≈ %.3e J",report.projected_min_k,report.projected_max_k,report.heat_dry_approx_j)
                            else
                                isempty(undo_file) && error("Không có tác động để hoàn tác trước bước tính tiếp theo.")
                                # Keep a rollback for the undo operation itself.
                                rollback=joinpath(dir,"before_undo.jld2")
                                save_checkpoint(simulation,rollback)
                                restored=undo_file
                                restore_checkpoint!(simulation,restored)
                                atomic_toml(joinpath(dir,"event.toml"),Dict("action"=>action,"status"=>"undone","model_time"=>clock_time,"restored_from"=>restored,"sequence"=>sequence))
                                undo_file="";pending_edit=undo_previous_pending
                                edit_summary="Đã hoàn tác tác động gần nhất."
                            end
                        catch err
                            isfile(rollback) && restore_checkpoint!(simulation,rollback)
                            command_error=sprint(showerror,err)
                            mkpath(dir)
                            atomic_toml(joinpath(dir,"event.toml"),Dict("action"=>action,"status"=>"rejected","error"=>command_error,"model_time"=>clock_time,"sequence"=>sequence))
                        end
                        publish(mode=="pause" ? "paused" : "running")
                    else
                        mode = action
                        mode == "pause" && publish("paused")
                    end
                end
            end
            if mode == "stop"
                publish("stopped")
                break
            elseif completed >= config["max_chunks"]
                publish("complete")
                break
            elseif mode in ("run","step")
                undo_file=""
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
                    checked = field in (:mslp,:pres) ? data[:,:,end:end] : data
                    all(isfinite,checked) || error("Đầu ra $field không hữu hạn.")
                end
                push!(files,abspath(path))
                completed += 1
                clock_time=string(finish);pending_edit=false
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
