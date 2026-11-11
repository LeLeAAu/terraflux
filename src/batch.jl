module TerraFluxBatch
using TOML, Dates
include("process_control.jl")
using .TerraFluxProcessControl
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
        println(io, "  - Backend:       $(hasproperty(c, :backend) ? c.backend : "cpu")")
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
        open(logfile) do io
            seekend(io);start=max(0,position(io)-65536);seek(io,start)
            start>0 && readline(io) # Discard the first potentially partial UTF-8 line.
            lines=filter(!isempty,strip.(readlines(io)))
            join(last(lines,min(max_lines,length(lines))),"\n")
        end
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
                    for line in Iterators.reverse(lines)
                        m=match(r"^(\d{1,3})%\s*,\s*ETA:\s*([^,]+)",line)
                        if m!==nothing && 0<=parse(Int,m.captures[1])<=100
                            return "$(m.captures[1])%, ETA: $(strip(m.captures[2]))"
                        end
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
            if attempt==4
                process_exited(job.process) || rethrow()
                break # Recover a dead worker's error from its log even if status is corrupt/missing.
            end
            sleep(0.01)
        end
    end
    if status === nothing
        status = Dict{String,Any}("state" => "starting")
    end

    state=get(status,"state","")
    if process_exited(job.process) && !(state in ("error","stopped")) && (state!="complete" || !success(job.process))
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
    if get(status, "state", "") == "running" && !haskey(status,"percent")
        prog = read_worker_progress(joinpath(job.directory, "output"))
        if !isempty(prog)
            status["progress"] = prog
        end
    end

    status
end

function stop_batch!(job)
    if process_running(job.process)
        # A validated worker may need a moment to exit after writing "complete".
        # Closing the form then must not turn its finished output into a cancelled run.
        terminal=try
            get(batch_status(job),"state","") in ("complete","error")
        catch
            false # Broken metadata must never prevent cancellation of a live process.
        end
        if terminal
            timedwait(()->process_exited(job.process),2;pollint=0.02)==:ok && return
        end
        stop_process!(job.process)
        latest=try;TOML.parsefile(joinpath(job.directory,"status.toml"));catch;Dict();end
        get(latest,"state","")=="error" && return
        get(latest,"state","")=="complete" && success(job.process) && return
        logfile = joinpath(job.directory, "worker.log")
        try
            open(logfile, "a") do io
                println(io, "\n[$(Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"))] [INFO] Tiến trình đã bị dừng bởi người dùng.")
                flush(io)
            end
        catch
        end
        try
            open(joinpath(job.directory,"status.toml"),"w") do io
                TOML.print(io,Dict("state"=>"stopped","error"=>"Đã dừng; đầu ra chưa hoàn tất không được công bố."))
            end
        catch
            # The process is stopped even if its directory was moved/deleted.
        end
    end
end

end
