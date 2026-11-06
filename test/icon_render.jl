# A real PNG sprite rendered through the tracker, not only a frame-index unit test.
using GLMakie, Test, TOML, Dates
module TrackerFixture
include(joinpath(@__DIR__,"..","src","storms.jl"))
include(joinpath(@__DIR__,"..","src","ui_scope.jl"))
include(joinpath(@__DIR__,"..","src","storm_icons.jl"))
include(joinpath(@__DIR__,"..","src","tracker.jl"))
end
using .TrackerFixture.TerraFluxTracker
mktempdir(;prefix="icon render ") do dir
    image=fill(RGBAf(1,0,0,0.8),16,32)
    image[:,17:32] .= RGBAf(0,0,1,1)
    Makie.FileIO.save(joinpath(dir,"sprite.png"),image)
    config=Dict("sprites"=>Dict("C3"=>Dict("file"=>"sprite.png","frames"=>2,"fps"=>8.,"rotate"=>false)))
    stylepath=joinpath(dir,"style.toml")
    open(stylepath,"w") do io; TOML.print(io,config); end
    fig=Figure(size=(1200,850))
    tracker=build_tracker(fig[1,1],fig[1,2],DateTime(2000,1,4);
        on_physical=(p,g)->nothing,on_start=t->nothing,icon_style_path=stylepath)
    tracker.set_active!(true)
    screen=display(fig)
    try
        @testset "PNG sprite animation through Storm Tracker" begin
            h=tracker.handles["DEMO-01"]
            @test h.has_sprite[]
            @test !tracker.handles["DEMO-02"].has_sprite[]
            tracker.animate!(0.)
            before=copy(GLMakie.colorbuffer(screen))
            tracker.animate!(0.125)
            after=copy(GLMakie.colorbuffer(screen))
            redpixels(buffer)=count(c -> c.r > 0.4 && c.g < 0.2 && c.b < 0.2,buffer)
            @test redpixels(before) > 100
            @test redpixels(after) < redpixels(before)/2
            @test tracker.clock[] == DateTime(2000,1,4)
            @test h.rotation[] == 0
            tracker.reduced.checked[]=true
            tracker.animate!(0.125)
            @test h.sprite_image[][1,1].r > 0.9
            tracker.clock[]=DateTime(2000,1,3)
            @test !h.has_sprite[]
            tracker.clock[]=DateTime(2000,1,4)
            @test h.has_sprite[]
        end
    finally
        close(screen)
    end
end
