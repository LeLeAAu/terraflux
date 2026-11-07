# julia --threads=2 --project=. generate_long_run.jl [days=60] [output directory]
using SpeedyWeather, Dates, Random, TOML
using SpeedyWeather: NCDataset, SurfacePressureOutput

function generate_long_run(days=60,directory=joinpath(@__DIR__,"datasets","earth_$(days)d"))
    10<=days<=365 || error("Chọn thời lượng 10–365 ngày.")
    isdir(directory) && !isempty(readdir(directory)) && error("Thư mục đầu ra đã có dữ liệu: $directory")
    mkpath(directory)
    Random.seed!(20261107)
    grid=SpectralGrid(truncation=32,nlayers=8)
    output=NetCDFOutput(grid,PrimitiveWet;path=abspath(directory),interval=Hour(6))
    add!(output,SurfacePressureOutput())
    model=PrimitiveWetModel(grid;output)
    simulation=initialize!(model)
    started=simulation.variables.prognostic.clock.time
    println("Running $days days: T32 / 8 sigma levels / output every 6 hours")
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
        DateTime.(ds["time"][:])==collect(started:Hour(6):finish) || error("Thiếu mốc đầu ra.")
        for key in ("temp","u","v","humid","mslp","pres")
            variable=ds[key]
            a=variable[ntuple(_->Colon(),ndims(variable))...]
            checked=key in ("mslp","pres") ? ds[key][:,:,2:end] : a
            all(x->!ismissing(x) && isfinite(x),checked) || error("Đầu ra $key không hữu hạn.")
        end
        ds.attrib["terraflux_initial_surface_diagnostics"]="unavailable"
        ds.attrib["terraflux_experiment"]="Idealized free-running T32 moist atmosphere; not observed weather or a forecast"
    end
    manifest=Dict("model"=>"PrimitiveWetModel","truncation"=>32,"layers"=>8,
        "days"=>days,"output_hours"=>6,"frames"=>4days+1,"start"=>string(started),
        "finish"=>string(finish),"rng_seed"=>20261107,"julia_version"=>string(VERSION),
        "elapsed_seconds"=>elapsed,"bytes"=>filesize(path),"netcdf"=>relpath(path,directory),
        "validation"=>"All saved temp/u/v/humid finite; MSLP and surface pressure finite after initialization; final state finite and T>0 K",
        "purpose"=>"Idealized model experiment, not a weather forecast")
    open(joinpath(directory,"experiment.toml"),"w") do io;TOML.print(io,manifest);end
    println("VALIDATED: $path | $(4days+1) frames | $(round(filesize(path)/2.0^20;digits=1)) MiB | $(round(elapsed;digits=1)) seconds")
    path
end
if abspath(PROGRAM_FILE)==@__FILE__
    days=isempty(ARGS) ? 60 : parse(Int,ARGS[1])
    directory=length(ARGS)>=2 ? abspath(ARGS[2]) : joinpath(@__DIR__,"datasets","earth_$(days)d")
    generate_long_run(days,directory)
end
