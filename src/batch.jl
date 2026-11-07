module TerraFluxBatch
using TOML
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
    process=open(joinpath(directory,"worker.log"),"w") do io
        run(pipeline(addenv(Cmd(command;dir=project),"OPENBLAS_NUM_THREADS"=>"1"),stdout=io,stderr=io);wait=false)
    end
    BatchJob(directory,process)
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
    if process_exited(job.process) && !(status["state"] in ("complete","error","stopped"))
        status=Dict("state"=>"error","error"=>"Tiến trình kết thúc ngoài dự kiến. Xem worker.log.")
    end
    status
end
function stop_batch!(job)
    if process_running(job.process)
        kill(job.process)
        wait(job.process)
        open(joinpath(job.directory,"status.toml"),"w") do io
            TOML.print(io,Dict("state"=>"stopped","error"=>"Đã dừng; đầu ra chưa hoàn tất không được công bố."))
        end
    end
end
end
