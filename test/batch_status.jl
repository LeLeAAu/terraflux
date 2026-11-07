using Test,TOML
include(joinpath(@__DIR__,"..","src","batch.jl"))
include(joinpath(@__DIR__,"..","src","local_open.jl"))
using .TerraFluxBatch,.TerraFluxLocalOpen

@testset "Progress file fallback ignores headers, partial records and final footer" begin
    mktempdir() do root
        p=joinpath(root,"run_0001","progress.txt");mkpath(dirname(p))
        write(p,"Starting SpeedyWeather\nTime: 60 days\n")
        @test TerraFluxBatch.read_worker_progress(root)==""
        write(p," 25%, ETA: 0:12:04, extra\n 50%, ETA:")
        @test TerraFluxBatch.read_worker_progress(root)=="25%, ETA: 0:12:04"
        write(p," 75%, ETA: 0:00:30, extra\n\nIntegration done in empty period.\n")
        @test TerraFluxBatch.read_worker_progress(root)=="75%, ETA: 0:00:30"
        write(p,"101%, ETA: impossible\n")
        @test TerraFluxBatch.read_worker_progress(root)==""
        write(p,repeat("old line\n",100000)*"lỗi cuối cùng\nstack frame\n")
        @test TerraFluxBatch.read_recent_log_tail(p;max_lines=2)=="lỗi cuối cùng\nstack frame"
    end
end

function exited_job(root,state;code=0,corrupt=false)
    directory=mktempdir(root)
    write(joinpath(directory,"worker.log"),"ROOT FAILURE: test marker\n")
    open(joinpath(directory,"status.toml"),"w") do io
        corrupt ? write(io,"bad[[") : TOML.print(io,Dict("state"=>state))
    end
    process=run(ignorestatus(`$(Base.julia_cmd()) --startup-file=no -e $("exit($code)")`))
    BatchJob(directory,process)
end
@testset "Dead workers expose exit status and log even without a valid status file" begin
    mktempdir() do root
        for (state,code,corrupt) in (("running",7,false),("complete",17,false),("starting",23,true))
            j=exited_job(root,state;code,corrupt)
            status=batch_status(j)
            @test status["state"]=="error" && status["exitcode"]==code
            @test occursin("ROOT FAILURE",status["error"])
        end
        @test batch_status(exited_job(root,"complete"))["state"]=="complete"
        # The worker has certified output but has not quite exited yet.
        dir=mktempdir(root)
        write(joinpath(dir,"status.toml"),"state = \"complete\"\n")
        process=run(`$(Base.julia_cmd()) --startup-file=no -e 'sleep(0.2)'`;wait=false)
        j=BatchJob(dir,process)
        try
            stop_batch!(j)
            @test success(process) && batch_status(j)["state"]=="complete"
        finally
            process_running(process) && (kill(process);wait(process))
        end
        dir=mktempdir(root)
        write(joinpath(dir,"status.toml"),"bad[[")
        process=run(`$(Base.julia_cmd()) --startup-file=no -e 'sleep(15)'`;wait=false)
        j=BatchJob(dir,process)
        try
            stop_batch!(j)
            @test !process_running(process) && batch_status(j)["state"]=="stopped"
        finally
            process_running(process) && (kill(process);wait(process))
        end
    end
end

@testset "Log paths remain literal arguments on each platform" begin
    mktempdir(;prefix="TerraFlux paths ") do root
        file=joinpath(root,"100% & simulation.log");write(file,"log")
        @test local_open_command(file;platform=:windows).exec==["notepad.exe",file]
        @test local_open_command(root;platform=:windows).exec==["explorer.exe",root]
        @test local_open_command(file;platform=:macos).exec==["open",file]
        @test local_open_command(file;platform=:linux).exec==["xdg-open",file]
        @test_throws Exception local_open_command(joinpath(root,"missing"))
    end
end

@testset "Unix launcher captures dependency/startup errors before any GUI exists" begin
    if !Sys.iswindows()
        mktempdir(;prefix="TerraFlux startup ") do root
            script=joinpath(root,"create_simulation.sh")
            cp(joinpath(@__DIR__,"..","create_simulation.sh"),script)
            bin=joinpath(root,"bin");mkpath(bin)
            fake=joinpath(bin,"julia")
            write(fake,"#!/bin/sh\necho SETUP_STDOUT\necho IMPORT_FAILED >&2\nexit 17\n");chmod(fake,0o755)
            cmd=addenv(`bash $script`,"PATH"=>bin*":"*ENV["PATH"])
            process=run(pipeline(ignorestatus(cmd),stdout=devnull,stderr=devnull))
            @test process.exitcode==17
            log=read(joinpath(root,"simulation_setup.log"),String)
            @test occursin("SETUP_STDOUT",log) && occursin("IMPORT_FAILED",log)
        end
    end
end
