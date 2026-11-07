# julia --threads=2 --project=. generate_long_run.jl [days=60] [output directory]
using SpeedyWeather, Dates, Random, TOML
using SpeedyWeather: NCDataset, SurfacePressureOutput
include("src/experiment_config.jl")
using .TerraFluxExperimentConfig
include("src/model_progress.jl")
using .TerraFluxModelProgress

function glog(msg)
    ts = Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS")
    println("[$ts] $msg")
    flush(stdout)
end

function generate_long_run(days=60,directory=joinpath(@__DIR__,"datasets","earth_$(days)d");truncation=32,layers=8,output_hours=6,seed=20261107,on_progress=_->nothing)
    cfg=experiment_config(;days,truncation,layers,output_hours,seed)
    on_progress((phase="initializing",percent=0))
    glog("Khởi tạo cấu hình: $days ngày | T$(cfg.truncation) | $(cfg.layers) tầng sigma | ghi mỗi $(cfg.output_hours)h | seed=$(cfg.seed)")
    isdir(directory) && !isempty(readdir(directory)) && error("Thư mục đầu ra đã có dữ liệu: $directory")
    mkpath(directory)
    Random.seed!(cfg.seed)
    
    glog("Thiết lập SpectralGrid (T$(cfg.truncation), $(cfg.layers) tầng sigma)...")
    grid=SpectralGrid(truncation=cfg.truncation,nlayers=cfg.layers)
    
    glog("Thiết lập NetCDFOutput tại: $(abspath(directory))...")
    output=NetCDFOutput(grid,PrimitiveWet;path=abspath(directory),interval=Hour(cfg.output_hours))
    add!(output,SurfacePressureOutput())
    
    glog("Khởi tạo PrimitiveWetModel và trạng thái ban đầu...")
    model=PrimitiveWetModel(grid;output)
    simulation=initialize!(model)
    started=simulation.variables.prognostic.clock.time
    
    glog("Bắt đầu chạy mô phỏng vật lý trong $days ngày (bước ghi $(cfg.output_hours)h)...")
    
    progress=ModelProgress(started,started+Day(days),event->begin
        glog("$(event.phase == "validating" ? "Kiểm chứng đầu ra" : "Tiến độ tích phân"): $(event.percent)% · $(round(event.hours_done;digits=2))/$(event.hours_total) giờ mô hình")
        on_progress(event)
    end)
    add!(model.callbacks,:terraflux_progress=>progress)
    elapsed=@elapsed run!(simulation;period=Day(days),output=true)
    
    finish=simulation.variables.prognostic.clock.time
    report_progress!(progress,finish;phase="validating",force=true)
    glog("Tích phân mô hình hoàn tất sau $(round(elapsed; digits=1)) giây. Bắt đầu kiểm chứng dữ liệu...")
    
    # 1. Kiểm tra đồng hồ
    if finish-started != Day(days)
        glog("[LỖI] Đồng hồ mô hình không khớp thời lượng: bắt đầu $started, kết thúc $finish (chênh lệch: $(finish-started), mong đợi: $(Day(days)))")
        error("Đồng hồ mô hình không khớp thời lượng.")
    end
    glog("[1/4] Đồng hồ mô hình chính xác: $started -> $finish ($days ngày) ... ĐẠT")
    
    # 2. Kiểm tra tính ổn định NaNs
    if model.feedback.nans_detected
        glog("[LỖI] SpeedyWeather phát hiện giá trị NaN trong quá trình tích phân (mất ổn định số học).")
        error("Mô hình báo mất ổn định.")
    end
    glog("[2/4] Kiểm tra tính ổn định số học (không phát hiện NaN) ... ĐẠT")
    
    # 3. Kiểm tra trạng thái lưới
    for name in (:temperature,:u,:v,:humidity)
        values=Array(get_step(getproperty(simulation.variables.grid,name)))
        if !all(isfinite,values)
            nan_count = count(!isfinite, values)
            glog("[LỖI] Trạng thái biến '$name' chứa $nan_count giá trị không hữu hạn.")
            error("Trạng thái $name không hữu hạn.")
        end
        if name==:temperature && minimum(values)<=0
            glog("[LỖI] Nhiệt độ có giá trị <= 0 K (tối thiểu: $(minimum(values)) K).")
            error("Nhiệt độ <=0 K.")
        end
    end
    glog("[3/4] Trạng thái các biến lưới (T, u, v, q hữu hạn và T > 0 K) ... ĐẠT")
    
    # 4. Kiểm tra NetCDF đầu ra
    path=joinpath(output.run_path,output.filename)
    parameters=joinpath(output.run_path,"parameters.txt")
    text=join(rstrip.(split(read(parameters,String),'\n')),"\n")
    write(parameters,rstrip(text)*"\n")
    
    expected_times = collect(started:Hour(cfg.output_hours):finish)
    NCDataset(path,"a") do ds
        actual_times = DateTime.(ds["time"][:])
        if actual_times != expected_times
            glog("[LỖI] Mốc thời gian NetCDF không khớp (thực tế: $(length(actual_times)), mong đợi: $(length(expected_times))).")
            error("Thiếu mốc đầu ra.")
        end
        for key in ("temp","u","v","humid","mslp","pres")
            variable=ds[key]
            first_time=key in ("mslp","pres") ? 2 : 1
            for t in first_time:length(ds["time"])
                slice=ndims(variable)==3 ? variable[:,:,t] : variable[:,:,:,t]
                if !all(x->!ismissing(x) && isfinite(x),slice)
                    bad_count = count(x->ismissing(x) || !isfinite(x), slice)
                    glog("[LỖI] Biến '$key' có $bad_count giá trị không hợp lệ tại khung t=$t ($(actual_times[t])).")
                    error("Đầu ra $key không hữu hạn ở mốc $t.")
                end
            end
        end
        ds.attrib["terraflux_initial_surface_diagnostics"]="unavailable"
        ds.attrib["terraflux_experiment"]="Idealized free-running moist atmosphere; not observed weather or a forecast"
        ds.attrib["terraflux_truncation"]=cfg.truncation
    end
    glog("[4/4] Các biến tệp NetCDF ($path) đã được xác thực hợp lệ ... ĐẠT")
    
    frames=24days÷cfg.output_hours+1
    manifest=Dict("model"=>"PrimitiveWetModel","truncation"=>cfg.truncation,"layers"=>cfg.layers,
        "days"=>days,"output_hours"=>cfg.output_hours,"frames"=>frames,"start"=>string(started),
        "finish"=>string(finish),"rng_seed"=>cfg.seed,"julia_version"=>string(VERSION),"backend"=>"CPU","cpu_threads"=>Threads.nthreads(),
        "elapsed_seconds"=>elapsed,"bytes"=>filesize(path),"netcdf"=>relpath(path,directory),
        "validation"=>"All saved temp/u/v/humid finite; MSLP and surface pressure finite after initialization; final state finite and T>0 K",
        "purpose"=>"Idealized model experiment, not a weather forecast")
    open(joinpath(directory,"experiment.toml"),"w") do io;TOML.print(io,manifest);end
    
    glog("Đã tạo manifest tại: $(joinpath(directory,"experiment.toml"))")
    glog("VALIDATED HOÀN TẤT: $path | $frames khung | $(round(filesize(path)/2.0^20;digits=1)) MiB | $(round(elapsed;digits=1)) giây")
    path
end

if abspath(PROGRAM_FILE)==@__FILE__
    days=isempty(ARGS) ? 60 : parse(Int,ARGS[1])
    directory=length(ARGS)>=2 ? abspath(ARGS[2]) : joinpath(@__DIR__,"datasets","earth_$(days)d")
    generate_long_run(days,directory)
end
