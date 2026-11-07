using GLMakie,Test,Dates
include(joinpath(@__DIR__,"..","src","viewer.jl"))
using .TerraFluxViewer
using .TerraFluxViewer.TerraFluxData
using .TerraFluxViewer.TerraFluxDetection
using .TerraFluxViewer.TerraFluxStorms
path=joinpath(@__DIR__,"..","run_0001","output.nc")
data=load_weather(path)
original=deepcopy(data.fields)
viewer=build_viewer(data)
screen=display(viewer.fig)
function wait_model()
    result=timedwait(120;pollint=0.05) do
        viewer.tracker.poll_model!()
        viewer.tracker.catalog[] isa ModelStormSet
    end
    result==:ok || error("Model analysis failed or timed out: $(viewer.tracker.card[])")
    viewer.tracker.catalog[]
end
try
    @testset "Model-backed Storm Tracker with real NetCDF" begin
        tracker=viewer.tracker
        viewer.viewmenu.i_selected[]=3
        # Open the new source dropdown through the real input route.
        box=tracker.source_menu.layoutobservables.computedbbox[]
        events(viewer.fig).mouseposition[]=Tuple(box.origin .+ box.widths ./ 2)
        events(viewer.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(viewer.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test tracker.source_menu.is_open[]
        @test !viewer.fieldmenu.is_open[]
        tracker.source_menu.is_open[]=false
        tracker.source_menu.i_selected[]=2
        detected=wait_model()
        @test detected.provenance=="model_detection"
        @test occursin("Không gán cấp bão",tracker.title[])
        @test all(!h.member[] for (id,h) in tracker.handles if startswith(id,"DEMO"))
        @test tracker.systemmenu.selection[] === nothing # frame zero has no candidates
        @test !isempty(detected.systems)
        @test all(s.samples[1].time>data.times[1] for s in detected.systems)
        set_close_to!(viewer.slider,2)
        id=tracker.systemmenu.selection[]
        @test startswith(id,"MODEL-")
        metric=detected.metrics[(id,data.times[2])]
        @test tracker.handles[id].symbol[]=="L?"
        @test collect(keys(tracker.handles[id].paths))==[:MODEL_LOW]
        @test occursin("Không phải gió 10 m",tracker.card[])
        @test !occursin("kịch bản minh họa",tracker.card[])
        sample=storm_state(only(filter(s->s.id==id,detected.systems)),data.times[2])
        @test sample.pressure_hpa==data.fields[:mslp][metric.i,metric.j,2]
        @test tracker.handles[id].position[]==[Point2f(sample.lon,sample.lat)]
        @test length(tracker.systemmenu.options[])==count(s->s.samples[1].time<=data.times[2],detected.systems)
        set_close_to!(viewer.slider,3)
        @test tracker.systemmenu.selection[]==id
        set_close_to!(viewer.slider,2)
        tracker.physical.clicks[]+=1
        @test viewer.viewmenu.selection[]==:map
        @test viewer.time[]==2
        @test viewer.selected[]==(metric.i,metric.j)
        viewer.viewmenu.i_selected[]=3
        @test tracker.source_menu.selection[]==:model
        tracker.globe.clicks[]+=1
        @test viewer.viewmenu.selection[]==:globe
        @test viewer.time[]==2
        viewer.viewmenu.i_selected[]=3
        tracker.source_menu.i_selected[]=1
        @test tracker.catalog[].provenance=="illustrative_scenario"
        @test all(!h.member[] for (id,h) in tracker.handles if startswith(id,"MODEL"))
        @test all(startswith(option[2],"DEMO") for option in tracker.systemmenu.options[])
        tracker.source_menu.i_selected[]=2
        wait_model()
        set_close_to!(viewer.slider,13)
        active_ids=[s.id for s in detected.systems if storm_state(s,data.times[13])!==nothing]
        @test !isempty(active_ids)
        tracker.systemmenu.i_selected[]=findfirst(option->option[2]==first(active_ids),tracker.systemmenu.options[])
        selected=tracker.systemmenu.selection[]
        set_close_to!(viewer.slider,41)
        @test length(tracker.systemmenu.options[])==length(detected.systems)
        @test count(h->h.visible[],values(tracker.handles))==detected.reports[end].kept
        set_close_to!(viewer.slider,13)
        @test all(!tracker.handles[s.id].member[] for s in detected.systems if s.samples[1].time>data.times[13])
        tracker.systemmenu.i_selected[]=findfirst(option->option[2]==selected,tracker.systemmenu.options[])
        if !isempty(ARGS); save(abspath(first(ARGS)),viewer.fig); end
        # Changing the viewed data must invalidate cached detections, including empty results.
        fields=deepcopy(data.fields); fields[:mslp].=1010f0
        flat=WeatherData("flat-pressure",data.lon,data.lat,data.layers,data.times,fields)
        viewer.replace_data!(flat)
        empty=wait_model()
        @test isempty(empty.systems)
        @test tracker.systemmenu.selection[]===nothing
        @test all(!h.visible[] && !h.member[] for h in values(tracker.handles))
        @test occursin("Không có ứng viên",tracker.card[])
        @test all(isequal(data.fields[f],original[f]) for f in keys(original))
    end
    println("DETECTION_VIEWER_PASSED")
finally
    close(screen)
end
