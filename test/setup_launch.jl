using Test
include(joinpath(@__DIR__,"..","simulation_setup.jl"))
@testset "Actual GUI startup with a caller-owned log stream" begin
    mktempdir(;prefix="TerraFlux startup GUI ") do root
        setup=Ref{Any}(nothing);screen=Ref{Any}(nothing)
        logfile=joinpath(root,"simulation_setup.log")
        try
            open(logfile,"a") do io
                build=()->(setup[]=build_simulation_setup(;root))
                display_window=fig->begin
                    s=display(fig);screen[]=s
                    @test all(>(0),size(GLMakie.colorbuffer(s)))
                    close(s)
                    s
                end
                launch_setup(;build,display_window,log_io=io)
                @test isopen(io) # The GUI must not close or replace the launcher's handle.
            end
            @test setup[]!==nothing && setup[].job[]===nothing
            @test occursin("Khởi chạy simulation_setup",read(logfile,String))
        finally
            screen[]===nothing || close(screen[])
        end
    end
end
