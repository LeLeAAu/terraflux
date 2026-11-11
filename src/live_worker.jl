# Separate Julia process: compute never blocks the GLMakie event loop.
using SpeedyWeather, Dates, TOML, CUDA
using SpeedyWeather: SurfacePressureOutput
include("live.jl")
using .TerraFluxLive: atomic_toml
include("data.jl")
using .TerraFluxData
using .TerraFluxLive.TerraFluxThermalPatch
include("thermal_model.jl")
using .TerraFluxThermalModel
using .TerraFluxLive.TerraFluxVortexProfiles
include("vortex_model.jl")
using .TerraFluxVortexModel
include("session_snapshot.jl")
using .TerraFluxSessionSnapshot
include("model_chunk.jl")
using .TerraFluxModelChunk
using Printf

function worker(directory)
    config = TOML.parsefile(joinpath(directory,"config.toml"))
    files = String[]
    completed, sequence = 0, 0
    clock_time="";pending_edit=false;undo_file="";undo_previous_pending=false
    edit_summary="";command_error="";last_saved=""
    publish(state; error="") = atomic_toml(joinpath(directory,"status.toml"),Dict(
        "state"=>state,"completed"=>completed,"max_chunks"=>config["max_chunks"],"files"=>files,"sequence"=>sequence,"error"=>error,
        "model_time"=>clock_time,"pending_edit"=>pending_edit,"undo_available"=>!isempty(undo_file),
        "edit_summary"=>edit_summary,"command_error"=>command_error,"last_saved"=>last_saved))
    try
        cd(directory)
        publish("starting")
        haskey(config,"resume_from") && TerraFluxLive.TerraFluxSavedSessions.saved_manifest(config["resume_from"])
        backend = get(config, "backend", "cpu")
        arch = if backend == "cuda"
            CUDA.functional() || error("CUDA không khả dụng hoặc driver NVIDIA chưa tương thích.")
            SpeedyWeather.GPU()
        else
            SpeedyWeather.CPU()
        end
        grid = SpectralGrid(truncation=config["truncation"],nlayers=config["layers"],architecture=arch)
        model = PrimitiveWetModel(grid)
        add!(model,SurfacePressureOutput())
        add!(model, SpeedyWeather.SeaSurfaceTemperatureOutput(), SpeedyWeather.SoilTemperatureOutput(), SpeedyWeather.LandSeaMaskOutput())
        simulation = initialize!(model)
        if haskey(config,"resume_from")
            restored=restore_session_bundle!(simulation,config["resume_from"],directory)
            files=restored.files;completed=restored.meta["completed"]
            pending_edit=restored.meta["pending_edit"];undo_file=restored.undo
            undo_previous_pending=restored.meta["undo_previous_pending"]
            edit_summary=restored.meta["edit_summary"]
        end
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
                    if action=="save"
                        try
                            mode=="pause" || error("Tạm dừng mô hình trước khi lưu phiên.")
                            publish("saving")
                            last_saved=save_session_bundle(simulation,directory,config,files;
                                pending_edit,undo_file,undo_previous_pending,edit_summary,sequence)
                        catch err
                            command_error=sprint(showerror,err)
                        end
                        publish(mode=="pause" ? "paused" : "running")
                    elseif action in ("thermal","vortex","undo_thermal","undo_edit")
                        rollback=""
                        dir=joinpath(directory,"edits",lpad(string(sequence),6,'0'))
                        try
                            mode=="pause" || error("Phải tạm dừng mô hình trước khi can thiệp.")
                            mkpath(dir)
                            if action in ("thermal","vortex")
                                parser=action=="thermal" ? thermal_spec : vortex_spec
                                spec=parser(;(Symbol(k)=>v for (k,v) in command["patch"])...)
                                rollback=joinpath(dir,"before.jld2")
                                save_checkpoint(simulation,rollback)
                                report=action=="thermal" ? apply_thermal!(simulation,spec) : apply_vortex!(simulation,spec)
                                save_checkpoint(simulation,joinpath(dir,"after.jld2"))
                                record=Dict{String,Any}("action"=>action,"model_time"=>clock_time,
                                    "status"=>"applied",
                                    "sequence"=>sequence,"checkpoint"=>rollback,"patch"=>command["patch"],
                                    "effect"=>Dict(string(k)=>v for (k,v) in pairs(report)),"application"=>action=="thermal" ? "instantaneous, one sigma layer" : "instantaneous idealized vortex, full atmospheric column")
                                atomic_toml(joinpath(dir,"event.toml"),record)
                                undo_file=rollback;undo_previous_pending=pending_edit;pending_edit=true
                                edit_summary=action=="thermal" ? @sprintf("ΔT chiếu: %+.3f…%+.3f K · Q khô ≈ %.3e J",report.projected_min_k,report.projected_max_k,report.heat_dry_approx_j) :
                                    @sprintf("Xoáy · lúc chèn: Δps %.2f…%.2f hPa · ΔT %.2f…%.2f K",report.projected_pressure_min_hpa,report.projected_pressure_max_hpa,report.projected_delta_t_min_k,report.projected_delta_t_max_k)
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
            elseif completed >= config["max_chunks"] && !get(config,"keep_open_at_limit",false)
                publish("complete")
                break
            elseif mode in ("run","step")
                if completed>=config["max_chunks"]
                    mode="pause";publish("paused");continue
                end
                undo_file=""
                publish(mode == "run" ? "running" : "stepping")
                path=run_chunk!(simulation,config["truncation"])
                finish=simulation.variables.prognostic.clock.time
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
