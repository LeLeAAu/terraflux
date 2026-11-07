using Test,Dates,TOML
include(joinpath(@__DIR__,"..","simulation_setup.jl"))
root=mktempdir(;prefix="terraflux setup test ")
opened=String[]
s=build_simulation_setup(;root,open_path=p->push!(opened,p));screen=display(s.fig)
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
        s.openlog.clicks[]+=1
        @test last(opened)==joinpath(s.job[].directory,"worker.log")
        c=TOML.parsefile(joinpath(s.job[].directory,"config.toml"))
        @test c["days"]==1 && c["truncation"]==21 && c["threads"]==1 && c["seed"]==123
        phases=Set{String}();fractions=Int[]
        result=timedwait(600;pollint=0.1) do
            status=s.poll!()
            if status!==nothing
                push!(phases,get(status,"phase",""))
                haskey(status,"percent") && push!(fractions,status["percent"])
            end
            status!==nothing && status["state"] in ("error","complete")
        end
        @test result==:ok
        status=batch_status(s.job[])
        status["state"]=="complete" || error("Worker did not complete: $(get(status,"error_detail",get(status,"error","unknown")))\n"*read(joinpath(s.job[].directory,"worker.log"),String))
        @test status["state"]=="complete"
        @test isfile(status["output_path"])
        @test "integrating" in phases
        @test !isempty(fractions) && issorted(fractions) && last(fractions)==100
        log=read(joinpath(s.job[].directory,"worker.log"),String)
        @test !occursin("world prior",log) && !occursin("too new",log)
        @test occursin("Tiến độ tích phân: 0%",log) && occursin("Tiến độ tích phân: 100%",log)
        @test occursin("[4/4]",log) && occursin("VALIDATED HOÀN TẤT",log)
        @test TOML.parsefile(joinpath(dirname(dirname(status["output_path"])),"experiment.toml"))["frames"]==2
        if !isempty(ARGS);save(first(ARGS),s.fig);end
        s.stop.clicks[]+=1
        @test batch_status(s.job[])["state"]=="complete"
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
