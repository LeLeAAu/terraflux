using Test
include(joinpath(@__DIR__,"..","simulation_setup.jl"))
struct ClosedTestScreen
    closed::Base.RefValue{Bool}
end
Base.isopen(::ClosedTestScreen)=false
Base.close(s::ClosedTestScreen)=(s.closed[]=true)
@testset "Startup logging uses the inherited stream and preserves errors" begin
    io=IOBuffer();closed=Ref(false)
    build=()->(;fig=nothing,job=Ref{Nothing}(nothing))
    launch_setup(;build,display_window=_->ClosedTestScreen(closed),log_io=io)
    @test closed[]
    @test occursin("Khởi chạy simulation_setup",String(take!(io)))
    original=ErrorException("GUI_STARTUP_SENTINEL")
    broken=IOBuffer();close(broken)
    for output in (io,broken)
        caught=try
            launch_setup(;build=()->throw(original),log_io=output)
            nothing
        catch err
            err
        end
        @test caught===original
    end
    text=String(take!(io))
    @test occursin("LỖI KHỞI ĐỘNG GUI",text) && occursin("GUI_STARTUP_SENTINEL",text)
    closed[]=false
    launch_setup(;build,display_window=_->ClosedTestScreen(closed),log_io=broken)
    @test closed[] # An unwritable log is not a fatal GUI initialization error.
end

@testset "Launcher-owned log receives the original startup error" begin
    mktempdir(;prefix="TerraFlux log sharing ") do dir
        project=abspath(joinpath(@__DIR__,".."))
        cp(joinpath(project,"simulation_setup.jl"),joinpath(dir,"simulation_setup.jl"))
        mkpath(joinpath(dir,"src"))
        for name in ("batch.jl","experiment_config.jl","local_open.jl")
            cp(joinpath(project,"src",name),joinpath(dir,"src",name))
        end
        child=joinpath(dir,"probe.jl")
        write(child,"""
        include(joinpath(@__DIR__,"simulation_setup.jl"))
        try
            launch_setup(;build=()->error("GUI_STARTUP_SENTINEL"))
            exit(0)
        catch err
            exit(sprint(showerror,err)=="GUI_STARTUP_SENTINEL" ? 23 : 24)
        end
        """)
        logfile=joinpath(dir,"simulation_setup.log")
        command=`$(Base.julia_cmd()) --startup-file=no --project=$project $child`
        process=if Sys.iswindows()
            # Use cmd's real redirection/share mode, reproducing the reported lock.
            batch=joinpath(dir,"probe.bat")
            line="\"$(first(Base.julia_cmd().exec))\" --startup-file=no --project=\"$project\" \"$child\" >> \"$logfile\" 2>&1"
            write(batch,"@echo off\r\n"*line*"\r\nexit /b %ERRORLEVEL%\r\n")
            run(ignorestatus(`cmd /c $batch`))
        else
            open(logfile,"a") do io
                run(pipeline(ignorestatus(command),stdout=io,stderr=io))
            end
        end
        @test process.exitcode==23
        text=read(logfile,String)
        @test occursin("GUI_STARTUP_SENTINEL",text) && occursin("LỖI KHỞI ĐỘNG GUI",text)
        @test !occursin("Permission denied",text)
    end
end
