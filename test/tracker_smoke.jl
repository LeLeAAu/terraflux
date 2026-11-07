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
        # Reproduce the user's overlapping dropdowns with real pointer clicks.
        function click_menu(menu)
            area=menu.layoutobservables.computedbbox[]
            events(viewer.fig).mouseposition[]=Tuple(area.origin .+ area.widths ./ 2)
            events(viewer.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
            events(viewer.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        end
        for menu in (tracker.systemmenu,tracker.unitmenu,tracker.region)
            click_menu(menu)
            @test menu.is_open[]
            @test !viewer.fieldmenu.is_open[]
            @test !viewer.layermenu.is_open[]
            menu.is_open[]=false
        end
        click_menu(tracker.systemmenu)
        viewer.viewmenu.i_selected[]=1
        @test !tracker.systemmenu.is_open[]
        click_menu(viewer.fieldmenu)
        @test viewer.fieldmenu.is_open[]
        @test !tracker.systemmenu.is_open[]
        viewer.viewmenu.i_selected[]=3
        @test !viewer.fieldmenu.is_open[]
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
        @test occursin("Typhoon · TY",tracker.card[])
        @test occursin("Tương đương SSHWS Cấp 3",tracker.card[])
        @test tracker.handles["DEMO-02"].symbol[] == "SS"
        @test tracker.handles["DEMO-01"].position[] == [Point2f(130,16)]
        @test viewer.mapvalues[][1:end-1,:] == frame(data,:temp,8,13)
        tracker.unitmenu.i_selected[]=4
        @test occursin("mph",tracker.card[])
        @test occursin("115.1",tracker.card[])
        tracker.animate!(0.7)
        @test tracker.handles["DEMO-01"].rotation[] ≈ 0.224f0
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
        tracker.systemmenu.i_selected[]=1
        original_classification=tracker.card[]
        tracker.region.i_selected[]=2
        @test tracker.ax.limits[][1] == (-180,180)
        @test tracker.card[]==original_classification # camera does not change source basin
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
        # Use declared scenario winds to exercise STY separately from C5 in the UI.
        samples=tracker.scenario.systems[1].samples
        original_sample=samples[4]
        try
            for (wind,glyph) in ((130,"4"),(137,"5"))
                a=original_sample
                samples[4]=StormSample(a.time,a.lon,a.lat,wind,a.pressure_hpa,a.kind,a.active)
                notify(tracker.clock)
                @test tracker.handles["DEMO-01"].symbol[]==glyph
                @test occursin("Super typhoon · STY",tracker.card[])
                @test occursin("Tương đương SSHWS Cấp "*glyph,tracker.card[])
            end
        finally
            samples[4]=original_sample
            notify(tracker.clock)
        end
        if !isempty(ARGS)
            click_menu(tracker.systemmenu)
            save(abspath(first(ARGS)),viewer.fig)
        end
    end
    println("TRACKER_SMOKE_PASSED")
finally
    close(screen)
end
