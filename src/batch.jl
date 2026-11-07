module TerraFluxBatch
using TOML, Dates
include("experiment_config.jl")
using .TerraFluxExperimentConfig
export BatchJob,start_batch,batch_status,stop_batch!

struct BatchJob
    directory::String
    process::Base.Process
end

function start_batch(c;root=joinpath(@__DIR__,"..","sessions","generated"))
    c=experiment_config(;c...)
    mkpath(root)
    directory=mktempdir(abspath(root);prefix="batch_",cleanup=false)
    write_config(joinpath(directory,"config.toml"),c)
    write(joinpath(directory,"status.toml"),"state = \"starting\"\n")
    project=abspath(joinpath(@__DIR__,".."))
    worker=joinpath(@__DIR__,"batch_worker.jl")
    command=`$(Base.julia_cmd()) --startup-file=no --threads=$(c.threads) --project=$project $worker $directory`
    logfile=joinpath(directory,"worker.log")
    open(logfile,"w") do io
        println(io, "="^70)
        println(io, "TERRAFLUX BATCH SIMULATION LOG")
        println(io, "Khởi động:       $(Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"))")
        println(io, "Thư mục phiên:   $directory")
        println(io, "Julia runtime:   $(Base.julia_cmd()) (v$VERSION)")
        println(io, "Cấu hình mô phỏng:")
        println(io, "  - Thời lượng:    $(c.days) ngày")
        println(io, "  - Độ phân giải:  T$(c.truncation)")
        println(io, "  - Số tầng sigma: $(c.layers)")
        println(io, "  - Chu kỳ ghi:    $(c.output_hours) giờ")
        println(io, "  - Luồng CPU:     $(c.threads)")
        println(io, "  - Seed:          $(c.seed)")
        println(io, "Lệnh gọi:        $command")
        println(io, "="^70)
        flush(io)
    end
    process=open(logfile,"a") do io
        run(pipeline(addenv(Cmd(command;dir=project),"OPENBLAS_NUM_THREADS"=>"1"),stdout=io,stderr=io);wait=false)
    end
    BatchJob(directory,process)
end

function read_recent_log_tail(logfile; max_lines=8)
    isfile(logfile) || return ""
    try
        lines = filter(!isempty, strip.(readlines(logfile)))
        isempty(lines) && return ""
        return join(last(lines, min(max_lines, length(lines))), "\n")
    catch
        return ""
    end
end

function read_worker_progress(output_dir)
    isdir(output_dir) || return ""
    try
        for entry in readdir(output_dir; join=true)
            if isdir(entry)
                prog_file = joinpath(entry, "progress.txt")
                if isfile(prog_file)
                    lines = filter(!isempty, strip.(readlines(prog_file)))
                    if !isempty(lines)
                        last_line = lines[end]
                        # Ví dụ: "  35%, ETA: 0:12:04, ,   Inf millenia/day"
                        # Rút gọn để hiển thị đẹp
                        m = match(r"(\d+%\s*,\s*ETA:[^,]+)", last_line)
                        return m !== nothing ? strip(m.captures[1]) : last_line
                    end
                end
            end
        end
    catch
    end
    return ""
end

function batch_status(job)
    status=nothing
    # Replacing the worker's status file can briefly remove it on Windows.
    for attempt in 1:4
        try
            status=TOML.parsefile(joinpath(job.directory,"status.toml"))
            break
        catch
            attempt==4 && rethrow()
            sleep(0.01)
        end
    end
    if status === nothing
        status = Dict{String,Any}("state" => "starting")
    end

    if process_exited(job.process) && !(get(status, "state", "") in ("complete", "error", "stopped"))
        exitcode = job.process.exitcode
        tail_log = read_recent_log_tail(joinpath(job.directory, "worker.log"))
        err_msg = "Tiến trình kết thúc ngoài dự kiến (exit code: $exitcode)."
        if !isempty(tail_log)
            err_msg *= "\nChi tiết nhật ký gần nhất:\n" * tail_log
        else
            err_msg *= " (worker.log không có thêm thông tin)."
        end
        status = Dict{String,Any}("state" => "error", "error" => err_msg, "exitcode" => exitcode)
    end

    # Nếu đang chạy, bổ sung thông tin tiến trình thực tế từ progress.txt
    if get(status, "state", "") == "running"
        prog = read_worker_progress(joinpath(job.directory, "output"))
        if !isempty(prog)
            status["progress"] = prog
        end
    end

    status
end

function stop_batch!(job)
    if process_running(job.process)
        kill(job.process)
        wait(job.process)
        logfile = joinpath(job.directory, "worker.log")
        try
            open(logfile, "a") do io
                println(io, "\n[$(Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"))] [INFO] Tiến trình đã bị dừng bởi người dùng.")
                flush(io)
            end
        catch
        end
        open(joinpath(job.directory,"status.toml"),"w") do io
            TOML.print(io,Dict("state"=>"stopped","error"=>"Đã dừng; đầu ra chưa hoàn tất không được công bố."))
        end
    end
end

end
