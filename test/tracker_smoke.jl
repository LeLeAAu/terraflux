using GLMakie, Test, Dates
include(joinpath(@__DIR__,"..","src","viewer.jl"))
using .TerraFluxViewer
using .TerraFluxViewer.TerraFluxData
using .TerraFluxViewer.TerraFluxStorms
path=joinpath(@__DIR__,"..","run_0001","output.nc")
data=load_weather(path)
original=copy(data.fields[:temp])
viewer=build_viewer(data)
screen=display(viewer.fig)
try
    @testset "Storm Tracker scenario UI and shared clock" begin
        tracker=viewer.tracker
        viewer.viewmenu.i_selected[]=3
        @test tracker.active[]
        @test tracker.ax.scene.visible[]
        @test !viewer.ax.scene.visible[]
        @test !viewer.globe.scene.visible[]
        @test tracker.clock[] == data.times[1]
        @test tracker.handles["DEMO-01"].visible[]
        @test !tracker.handles["DEMO-02"].visible[]
        @test occursin("chưa có dữ liệu",tracker.card[])
        set_close_to!(viewer.slider,13) # Jan 4, both declared systems are active.
        @test tracker.clock[] == DateTime(2000,1,4)
        @test tracker.handles["DEMO-01"].symbol[] == "3"
        @test tracker.handles["DEMO-02"].symbol[] == "SS"
        @test tracker.handles["DEMO-01"].position[] == [Point2f(130,16)]
        @test viewer.mapvalues[][1:end-1,:] == frame(data,:temp,8,13)
        tracker.unitmenu.i_selected[]=4
        @test occursin("mph",tracker.card[])
        @test occursin("115.1",tracker.card[])
        tracker.animate!(0.7)
        @test tracker.handles["DEMO-01"].rotation[] ≈ 0.7f0
        @test viewer.time[] == 13
        tracker.reduced.checked[]=true
        tracker.animate!(1.2)
        @test tracker.handles["DEMO-01"].rotation[] == 0
        tracker.reduced.checked[]=false
        tracker.animate!(0.5)
        # Send actual mouse events to the second icon, using its projected position.
        position=Makie.project(tracker.ax.scene,Point3f(150,21,0))
        pixel=Tuple(position[1:2] .+ tracker.ax.scene.viewport[].origin)
        events(viewer.fig).mouseposition[]=pixel
        events(viewer.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(viewer.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test tracker.systemmenu.selection[] == "DEMO-02"
        @test occursin("MINH HỌA B",tracker.card[])
        tracker.physical.clicks[]+=1
        @test viewer.viewmenu.selection[] == :map
        @test viewer.time[] == 13
        @test viewer.selected[] == nearest_cell(data,150,21)
        @test !tracker.active[]
        viewer.viewmenu.i_selected[]=3
        @test tracker.systemmenu.selection[] == "DEMO-02"
        tracker.globe.clicks[]+=1
        @test viewer.viewmenu.selection[] == :globe
        @test viewer.time[] == 13
        @test viewer.selected[] == nearest_cell(data,150,21)
        viewer.viewmenu.i_selected[]=3
        tracker.trails.checked[]=false
        @test !tracker.trails.checked[]
        tracker.trails.checked[]=true
        tracker.region.i_selected[]=2
        @test tracker.ax.limits[][1] == (-180,180)
        tracker.region.i_selected[]=1
        set_close_to!(viewer.slider,41)
        @test !any(h.visible[] for h in values(tracker.handles))
        @test !isempty(tracker.handles["DEMO-01"].ending[])
        @test !isempty(tracker.handles["DEMO-01"].paths[:C3][])
        tracker.start.clicks[]+=1
        @test viewer.time[] == 1
        @test tracker.handles["DEMO-01"].visible[]
        @test !tracker.handles["DEMO-02"].visible[]
        @test data.fields[:temp] == original
        set_close_to!(viewer.slider,13)
        tracker.systemmenu.i_selected[]=1
        if !isempty(ARGS); save(abspath(first(ARGS)),viewer.fig); end
    end
    println("TRACKER_SMOKE_PASSED")
finally
    close(screen)
end
