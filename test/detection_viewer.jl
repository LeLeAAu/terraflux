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
        state=storm_state(only(filter(s->s.id==id,detected.systems)),data.times[2])
        @test tracker.handles[id].symbol[]==CATEGORY_STYLES[storm_class(state.kind,state.wind_knots)][1]
        @test Set(keys(tracker.handles[id].paths))==Set((:MODEL_LOW,:MODEL_WARM,:MODEL_COLD))
        @test occursin("Không phải gió 10 m",tracker.card[])
        @test !occursin("kịch bản minh họa",tracker.card[])
        sample=storm_state(only(filter(s->s.id==id,detected.systems)),data.times[2])
        @test sample.pressure_hpa==data.fields[:mslp][metric.i,metric.j,2]
        @test tracker.handles[id].position[]==[Point2f(sample.lon,sample.lat)]
        @test length(tracker.systemmenu.options[])==detected.reports[2].kept
        set_close_to!(viewer.slider,3)
        previous=only(filter(s->s.id==id,detected.systems))
        @test storm_state(previous,data.times[3])===nothing || tracker.systemmenu.selection[]==id
        set_close_to!(viewer.slider,2)
        tracker.systemmenu.i_selected[]=findfirst(option->option[2]==id,tracker.systemmenu.options[])
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
        @test !tracker.filter_menu.blockscene.visible[]
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
        @test tracker.filter_menu.selection[]==:active
        @test length(tracker.systemmenu.options[])==detected.reports[end].kept
        @test count(h->h.visible[],values(tracker.handles))==detected.reports[end].kept
        @test count(h->h.label_visible[],values(tracker.handles))==1
        @test count(h->h.trail_visible[],values(tracker.handles))==1
        @test !tracker.handles["MODEL-0001"].visible[] # ended early; no stale selection
        @test tracker.systemmenu.selection[]!="MODEL-0001"
        for system in detected.systems
            state=storm_state(system,tracker.clock[])
            state===nothing && continue
            h=tracker.handles[system.id]
            h.visible[] || continue
            @test h.size[]==TerraFluxViewer.TerraFluxStormIcons.extent_icon_size(tracker.style,state.radius_km;
                selected=system.id==tracker.systemmenu.selection[],model=true)
        end
        tracker.animate!(2.)
        @test all(!h.visible[] || h.rotation[]==0 for h in values(tracker.handles))
        # Small unlabelled model markers remain selectable through real pointer input.
        target=last(tracker.listed_systems())
        state=storm_state(target,tracker.clock[])
        position=Makie.project(tracker.ax.scene,Point3f(state.lon,state.lat,0))
        events(viewer.fig).mouseposition[]=Tuple(position[1:2] .+ tracker.ax.scene.viewport[].origin)
        events(viewer.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(viewer.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test tracker.systemmenu.selection[]==target.id
        @test tracker.handles[target.id].label_visible[] && tracker.handles[target.id].trail_visible[]
        tracker.filter_menu.i_selected[]=5
        @test length(tracker.systemmenu.options[])==length(detected.systems)
        @test count(h->h.label_visible[],values(tracker.handles))<=1
        set_close_to!(viewer.slider,13)
        @test all(!tracker.handles[s.id].member[] for s in detected.systems if s.samples[1].time>data.times[13])
        tracker.systemmenu.i_selected[]=findfirst(option->option[2]==selected,tracker.systemmenu.options[])
        # Reproduce the user's last frame, then isolate its warm/cold/other groups.
        set_close_to!(viewer.slider,41)
        for (index,group) in ((2,:warm),(3,:cold),(4,:other))
            tracker.filter_menu.i_selected[]=index
            expected=[s for s in detected.systems if begin
                st=storm_state(s,data.times[end])
                st!==nothing && (group==:other ? detected.metrics[(s.id,data.times[end])].thermal_core in (:mixed,:unknown) :
                    detected.metrics[(s.id,data.times[end])].thermal_core==group)
            end]
            @test count(h->h.visible[],values(tracker.handles))==length(expected)
            @test Set(s.id for s in tracker.listed_systems())==Set(s.id for s in expected)
            @test count(h->h.label_visible[],values(tracker.handles))<=1
        end
        tracker.filter_menu.i_selected[]=1
        warm_ids=[s.id for s in tracker.listed_systems() if detected.metrics[(s.id,data.times[end])].thermal_core==:warm]
        @test !isempty(warm_ids) # measured for this checked-in NetCDF fixture, not required of arbitrary files
        tracker.systemmenu.i_selected[]=findfirst(option->option[2]==first(warm_ids),tracker.systemmenu.options[])
        if !isempty(ARGS)
            save(abspath(first(ARGS)),viewer.fig)
            tracker.filter_menu.i_selected[]=2
            save(replace(abspath(first(ARGS)),".png"=>"-warm.png"),viewer.fig)
        end
        tracker.start.clicks[]+=1
        @test any(storm_state(s,tracker.clock[])!==nothing for s in tracker.listed_systems())
        # The filter menu is model-only: actual pointer input must stay scoped.
        box=tracker.filter_menu.layoutobservables.computedbbox[]
        events(viewer.fig).mouseposition[]=Tuple(box.origin .+ box.widths ./ 2)
        events(viewer.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(viewer.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test tracker.filter_menu.is_open[]
        tracker.source_menu.i_selected[]=1
        @test !tracker.filter_menu.is_open[] && !tracker.filter_menu.blockscene.visible[]
        tracker.source_menu.i_selected[]=2
        tracker.filter_menu.i_selected[]=1
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
