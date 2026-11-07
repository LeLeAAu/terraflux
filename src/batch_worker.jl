using Dates, TOML

directory = isempty(ARGS) ? pwd() : abspath(ARGS[1])
statusfile = joinpath(directory, "status.toml")

function wlog(msg)
    ts = Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS")
    println("[$ts] $msg")
    flush(stdout)
end

function werr(err, bt=catch_backtrace())
    ts = Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS")
    err_full = sprint(showerror, err, bt)
    println(stderr, "\n[$ts] [LỖI WORKER XẢY RA]")
    println(stderr, err_full)
    println(stderr, "="^70)
    flush(stderr)
    return err_full
end

wlog("Bắt đầu tiến trình worker (PID: $(getpid()), Luồng CPU: $(Threads.nthreads()), Julia: v$VERSION).")

function worker_main()
    config_path = joinpath(directory, "config.toml")
    isfile(config_path) || error("Không tìm thấy tệp cấu hình: $config_path")
    c = TOML.parsefile(config_path)
    wlog("Đã đọc cấu hình: $(c["days"]) ngày | T$(c["truncation"]) | $(c["layers"]) tầng sigma | chu kỳ $(c["output_hours"])h | seed=$(c["seed"])")

    TerraFluxLive.atomic_toml(statusfile, Dict("state" => "running","phase"=>"initializing"))
    wlog("Trạng thái phiên chuyển sang 'running'. Bắt đầu chạy generate_long_run...")

    report=event->begin
        status=Dict{String,Any}("state"=>"running")
        for (key,value) in pairs(event);status[string(key)]=value;end
        TerraFluxLive.atomic_toml(statusfile,status)
    end
    path = generate_long_run(c["days"], joinpath(directory, "output");
        truncation=c["truncation"], layers=c["layers"], output_hours=c["output_hours"], seed=c["seed"],on_progress=report)

    wlog("Mô phỏng và kiểm chứng hoàn tất thành công tại: $path")
    TerraFluxLive.atomic_toml(statusfile, Dict("state" => "complete", "phase"=>"complete","percent"=>100,"output_path" => path))
end

function record_worker_error(err,bt)
    err_full = werr(err, bt)
    short_err = sprint(showerror, err)
    try
        status_dict = Dict("state" => "error", "error" => short_err, "error_detail" => err_full)
        if isdefined(@__MODULE__, :TerraFluxLive) && isdefined(TerraFluxLive, :atomic_toml)
            TerraFluxLive.atomic_toml(statusfile, status_dict)
        else
            open(statusfile, "w") do io
                TOML.print(io, status_dict)
            end
        end
    catch e_toml
        println(stderr, "Không thể ghi status.toml: ", sprint(showerror, e_toml))
        flush(stderr)
    end
end

try
    wlog("Đang nạp các thư viện mô phỏng (TOML, live, generate_long_run, SpeedyWeather)...")
    include("live.jl")
    TerraFluxLive.atomic_toml(statusfile, Dict("state"=>"starting","phase"=>"loading"))
    include(joinpath(@__DIR__, "..", "generate_long_run.jl"))
    wlog("Đã nạp xong tất cả thư viện thành công.")

    # Includes add methods/bindings. Enter their latest world before executing
    # callbacks or saving an exception raised while loading libraries (Julia 1.13).
    Base.invokelatest(worker_main)
catch err
    Base.invokelatest(record_worker_error,err,catch_backtrace())
    rethrow()
end
