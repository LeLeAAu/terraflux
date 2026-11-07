# julia --threads=2 --project=. generate_long_run.jl [days=60] [output directory]
using SpeedyWeather, Dates, Random, TOML
using SpeedyWeather: NCDataset, SurfacePressureOutput
include("src/experiment_config.jl")
using .TerraFluxExperimentConfig

function generate_long_run(days=60,directory=joinpath(@__DIR__,"datasets","earth_$(days)d");truncation=32,layers=8,output_hours=6,seed=20261107)
    cfg=experiment_config(;days,truncation,layers,output_hours,seed)
    isdir(directory) && !isempty(readdir(directory)) && error("Thư mục đầu ra đã có dữ liệu: $directory")
    mkpath(directory)
    Random.seed!(cfg.seed)
    grid=SpectralGrid(truncation=cfg.truncation,nlayers=cfg.layers)
    output=NetCDFOutput(grid,PrimitiveWet;path=abspath(directory),interval=Hour(cfg.output_hours))
    add!(output,SurfacePressureOutput())
    model=PrimitiveWetModel(grid;output)
    simulation=initialize!(model)
    started=simulation.variables.prognostic.clock.time
    println("Running $days days: T$(cfg.truncation) / $(cfg.layers) sigma levels / output every $(cfg.output_hours) hours")
    flush(stdout)
    elapsed=@elapsed run!(simulation;period=Day(days),output=true)
    finish=simulation.variables.prognostic.clock.time
    finish-started==Day(days) || error("Đồng hồ mô hình không khớp thời lượng.")
    !model.feedback.nans_detected || error("Mô hình báo mất ổn định.")
    for name in (:temperature,:u,:v,:humidity)
        values=Array(get_step(getproperty(simulation.variables.grid,name)))
        all(isfinite,values) || error("Trạng thái $name không hữu hạn.")
        name==:temperature && minimum(values)<=0 && error("Nhiệt độ <=0 K.")
    end
    path=joinpath(output.run_path,output.filename)
    parameters=joinpath(output.run_path,"parameters.txt")
    text=join(rstrip.(split(read(parameters,String),'\n')),"\n")
    write(parameters,rstrip(text)*"\n")
    NCDataset(path,"a") do ds
        DateTime.(ds["time"][:])==collect(started:Hour(cfg.output_hours):finish) || error("Thiếu mốc đầu ra.")
        for key in ("temp","u","v","humid","mslp","pres")
            variable=ds[key]
            first_time=key in ("mslp","pres") ? 2 : 1
            for t in first_time:length(ds["time"])
                slice=ndims(variable)==3 ? variable[:,:,t] : variable[:,:,:,t]
                all(x->!ismissing(x) && isfinite(x),slice) || error("Đầu ra $key không hữu hạn ở mốc $t.")
            end
        end
        ds.attrib["terraflux_initial_surface_diagnostics"]="unavailable"
        ds.attrib["terraflux_experiment"]="Idealized free-running moist atmosphere; not observed weather or a forecast"
        ds.attrib["terraflux_truncation"]=cfg.truncation
    end
    frames=24days÷cfg.output_hours+1
    manifest=Dict("model"=>"PrimitiveWetModel","truncation"=>cfg.truncation,"layers"=>cfg.layers,
        "days"=>days,"output_hours"=>cfg.output_hours,"frames"=>frames,"start"=>string(started),
        "finish"=>string(finish),"rng_seed"=>cfg.seed,"julia_version"=>string(VERSION),"backend"=>"CPU","cpu_threads"=>Threads.nthreads(),
        "elapsed_seconds"=>elapsed,"bytes"=>filesize(path),"netcdf"=>relpath(path,directory),
        "validation"=>"All saved temp/u/v/humid finite; MSLP and surface pressure finite after initialization; final state finite and T>0 K",
        "purpose"=>"Idealized model experiment, not a weather forecast")
    open(joinpath(directory,"experiment.toml"),"w") do io;TOML.print(io,manifest);end
    println("VALIDATED: $path | $frames frames | $(round(filesize(path)/2.0^20;digits=1)) MiB | $(round(elapsed;digits=1)) seconds")
    path
end
if abspath(PROGRAM_FILE)==@__FILE__
    days=isempty(ARGS) ? 60 : parse(Int,ARGS[1])
    directory=length(ARGS)>=2 ? abspath(ARGS[2]) : joinpath(@__DIR__,"datasets","earth_$(days)d")
    generate_long_run(days,directory)
end
