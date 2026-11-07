using Test,Dates,TOML
include(joinpath(@__DIR__,"..","simulation_setup.jl"))
root=mktempdir(;prefix="terraflux setup test ")
s=build_simulation_setup(;root);screen=display(s.fig)
try
    @testset "Local simulation form starts a validated independent job" begin
        @test s.config().days==60 && s.config().truncation==32
        # Use edited text without pressing Enter, then click the real button.
        s.days.displayed_string[]="1"
        s.resolution.i_selected[]=1
        s.interval.i_selected[]=5
        s.threads.i_selected[]=1
        s.seed.displayed_string[]="123"
        @test s.days.stored_string[]=="60"
        @test s.config().days==1 && s.config().output_hours==24
        @test occursin("2 khung",s.estimate[])
        Makie.focus!(s.seed)
        box=s.runbutton.layoutobservables.computedbbox[]
        events(s.fig).mouseposition[]=Tuple(box.origin.+box.widths./2)
        events(s.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(s.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test s.job[]!==nothing
        c=TOML.parsefile(joinpath(s.job[].directory,"config.toml"))
        @test c["days"]==1 && c["truncation"]==21 && c["threads"]==1 && c["seed"]==123
        result=timedwait(600;pollint=0.1) do
            status=s.poll!()
            status!==nothing && status["state"] in ("error","complete")
        end
        @test result==:ok
        status=batch_status(s.job[])
        @test status["state"]=="complete"
        @test isfile(status["output_path"])
        @test TOML.parsefile(joinpath(dirname(dirname(status["output_path"])),"experiment.toml"))["frames"]==2
        if !isempty(ARGS);save(first(ARGS),s.fig);end
        # Cancellation never advertises a partial output as complete.
        s.runbutton.clicks[]+=1
        s.stop.clicks[]+=1
        @test !process_running(s.job[].process)
        @test batch_status(s.job[])["state"]=="stopped"
    end
    println("SETUP_VIEWER_PASSED")
finally
    s.job[]===nothing || stop_batch!(s.job[])
    close(screen)
end
