using GLMakie,Test,Dates,Printf
include(joinpath(@__DIR__,"..","src","viewer.jl"))
using .TerraFluxViewer
using .TerraFluxViewer.TerraFluxData
using .TerraFluxViewer.TerraFluxDetection
using .TerraFluxViewer.TerraFluxStormIcons
d=load_weather(joinpath(@__DIR__,"..","run_0001","output.nc"))
original=deepcopy(d.fields)
v=build_viewer(d);screen=display(v.fig)
function hover_at(lon,lat)
    pixel=Makie.project(v.ax.scene,Point3f(lon,lat,0))
    events(v.fig).mouseposition[]=Tuple(pixel[1:2].+v.ax.scene.viewport[].origin)
    v.hover.update!()
end
try
    @testset "Independent map overlays, extent and field-aware hover" begin
        v.regionmenu.i_selected[]=1
        set_close_to!(v.slider,41)
        @test !v.overlay_open[] && !v.systemstoggle.blockscene.visible[]
        box=v.overlaybutton.layoutobservables.computedbbox[]
        events(v.fig).mouseposition[]=Tuple(box.origin.+box.widths./2)
        events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test v.overlay_open[] && v.systemstoggle.blockscene.visible[]
        @test !v.fieldmenu.blockscene.visible[]
        box=v.overlaysource.layoutobservables.computedbbox[]
        events(v.fig).mouseposition[]=Tuple(box.origin.+box.widths./2)
        events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test v.overlaysource.is_open[] && !v.fieldmenu.is_open[]
        v.overlaysource.is_open[]=false
        v.systemstoggle.checked[]=true
        result=timedwait(180;pollint=0.05) do
            v.poll_layers!();v.layers.catalog[] isa ModelStormSet
        end
        @test result==:ok
        @test length(v.layers.active[])==v.layers.catalog[].reports[end].kept
        resolved=filter(e->e.state.radius_km!==nothing,v.layers.active[])
        @test !isempty(resolved)
        entry=first(resolved)
        selected=v.selected[];clock=v.time[]
        hover_at(entry.state.lon,entry.state.lat)
        @test v.hover.visible[]
        @test occursin(entry.system.id,v.hover.text[])
        @test occursin("Nhiệt độ",v.hover.text[]) && occursin("°C",v.hover.text[])
        @test occursin("Vùng xoáy R",v.hover.text[])
        @test !isempty(v.layers.ring[])
        @test v.selected[]==selected && v.time[]==clock
        for i in 1:2:length(v.layers.ring[])-1
            @test abs(v.layers.ring[][i+1][1]-v.layers.ring[][i][1])<=180
        end
        small=extent_icon_size(v.tracker.style,500.;model=true)
        large=extent_icon_size(v.tracker.style,1500.;model=true)
        @test large>small
        v.valuestoggle.checked[]=true
        @test any(s->occursin("°C",s),v.layers.city_text[])
        v.labelstoggle.checked[]=false
        @test all(s->!occursin("Tokyo",s),v.layers.city_text[])
        v.fieldmenu.i_selected[]=2
        hover_at(entry.state.lon,entry.state.lat)
        @test occursin("km/h",v.hover.text[])
        @test any(s->occursin("km/h",s),v.layers.city_text[])
        v.nighttoggle.checked[]=true
        night=copy(v.layers.night_image[])
        @test any(c->c.alpha>0.2,night) && any(c->c.alpha==0,night)
        set_close_to!(v.slider,39)
        @test night!=v.layers.night_image[]
        v.gridtoggle.checked[]=false
        @test !v.ax.xgridvisible[] && !v.ax.ygridvisible[]
        v.viewmenu.i_selected[]=2
        @test !v.overlay_open[]
        @test length(v.smoothcolors[])>length(v.vertexcolors[])
        viewport=v.globe.scene.viewport[]
        events(v.fig).mouseposition[]=Tuple(viewport.origin.+viewport.widths./2)
        v.hover.update!()
        @test v.hover.visible[] && occursin("km/h",v.hover.text[])
        events(v.fig).mouseposition[]=Tuple(viewport.origin.+(2,2))
        v.hover.update!()
        @test !v.hover.visible[]
        v.viewmenu.i_selected[]=1
        v.fieldmenu.i_selected[]=1
        set_close_to!(v.slider,13)
        v.overlaysource.i_selected[]=2
        @test v.layers.catalog[].provenance=="illustrative_scenario"
        @test occursin("KỊCH BẢN MINH HỌA",v.helpcaption[])
        hover_at(130.,16.)
        @test occursin("DEMO-01",v.hover.text[]) && occursin("MINH HỌA",v.hover.text[])
        @test occursin("Bán kính xoáy chưa xác định",v.hover.text[])
        v.systemstoggle.checked[]=false
        hover_at(130.,16.)
        @test !occursin("DEMO",v.hover.text[])
        @test all(isequal(d.fields[k],original[k]) for k in keys(original))
        # Save actual model overlay + hover with a resolvable radius.
        v.overlaysource.i_selected[]=1;v.systemstoggle.checked[]=true
        set_close_to!(v.slider,41);v.poll_layers!()
        target=first(filter(e->e.state.radius_km!==nothing,v.layers.active[]))
        v.fieldmenu.i_selected[]=1;v.labelstoggle.checked[]=true
        v.nighttoggle.checked[]=false;v.gridtoggle.checked[]=true
        hover_at(target.state.lon,target.state.lat)
        if !isempty(ARGS);save(first(ARGS),v.fig);end
        v.overlaybutton.clicks[]+=1
        if !isempty(ARGS);save(replace(first(ARGS),".png"=>"-menu.png"),v.fig);end
        v.viewmenu.i_selected[]=2
        if !isempty(ARGS);save(replace(first(ARGS),".png"=>"-globe.png"),v.fig);end
    end
    println("OVERLAYS_VIEWER_PASSED")
finally
    close(screen)
end
