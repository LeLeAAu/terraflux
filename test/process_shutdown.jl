using Test,TOML
include(joinpath(@__DIR__,"..","src","live.jl"));using .TerraFluxLive
include(joinpath(@__DIR__,"..","src","batch.jl"));using .TerraFluxBatch
function stubborn_process(directory)
    ready=joinpath(directory,"ready")
    ignore_term=Sys.iswindows() ? "" : "ccall(:signal,Ptr{Cvoid},(Cint,Ptr{Cvoid}),15,Ptr{Cvoid}(1));"
    code=ignore_term*"write(ARGS[1],\"ready\");sleep(60)"
    p=run(pipeline(`$(Base.julia_cmd()) --startup-file=no -e $code $ready`,stdout=devnull,stderr=devnull);wait=false)
    timedwait(()->isfile(ready),30.;pollint=0.05)==:ok || error("Test child did not start")
    p
end
function cleanup(p)
    process_running(p) && kill(p,Base.SIGKILL)
    wait(p)
end
@testset "Cancellation survives missing folders and ignored termination" begin
    mktempdir() do root
        d=mktempdir(root);p=stubborn_process(d)
        try
            session=LiveSession(d,p,0) # No commands directory: cooperative stop cannot be written.
            elapsed=@elapsed stop_session!(session;timeout=0.1)
            @test process_exited(p) && elapsed<8
        finally;cleanup(p);end
        d=mktempdir(root);p=stubborn_process(d)
        try
            write(joinpath(d,"status.toml"),"state = \"error\"\nerror = \"ROOT FAILURE\"\n")
            elapsed=@elapsed stop_batch!(BatchJob(d,p))
            @test process_exited(p) && elapsed<8
            @test TOML.parsefile(joinpath(d,"status.toml"))["error"]=="ROOT FAILURE"
        finally;cleanup(p);end
        d=mktempdir(root);p=stubborn_process(d)
        try
            rm(d;recursive=true)
            stop_batch!(BatchJob(d,p))
            @test process_exited(p)
        finally;cleanup(p);end
    end
end

@testset "Failed command writes do not create an unacknowledgeable request" begin
    mktempdir() do d
        p=stubborn_process(d);session=LiveSession(d,p,0)
        write(joinpath(d,"status.toml"),"state = \"paused\"\nsequence = 0\n")
        try
            @test_throws Exception send_command!(session,"save")
            @test session.sequence==0
            mkpath(joinpath(d,"commands"))
            send_command!(session,"save")
            @test session.sequence==1
            @test TOML.parsefile(joinpath(d,"commands","000001.toml"))["action"]=="save"
        finally
            stop_session!(session;timeout=0.1)
        end
    end
end
