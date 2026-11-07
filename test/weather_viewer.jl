using GLMakie,Test,Dates
include(joinpath(@__DIR__,"..","src","viewer.jl"))
using .TerraFluxViewer
using .TerraFluxViewer.TerraFluxData
using .TerraFluxViewer.TerraFluxWeatherStyle
path=joinpath(@__DIR__,"..","datasets","earth_60d","run_0001","output.nc")
data=load_weather(path)
original=deepcopy(data.fields)
viewer=build_viewer(data)
screen=display(viewer.fig)
try
    @testset "Weather colors, wind animation and 60-day data" begin
        @test length(data.times)==241 && data.times[end]-data.times[1]==Day(60)
        @test haskey(data.fields,:pres)
        @test all(isnan,frame(data,:rh,8,1))
        @test all(isnan,frame(data,:mslp,8,1))
        set_close_to!(viewer.slider,121)
        @test viewer.regionmenu.selection[]==:asia
        @test viewer.limits[]==(-30f0,50f0)
        @test viewer.heat.interpolate[]
        @test viewer.durationmenu.selection[]==60
        @test viewer.mapvalues[][1:end-1,:]==frame(data,:temp,8,121)
        before=copy(GLMakie.colorbuffer(screen))
        for _ in 1:24;viewer.animate_wind!(1/30);end
        after=copy(GLMakie.colorbuffer(screen))
        @test before!=after
        @test count(p->all(isfinite,p),viewer.wind2d[])>100
        @test viewer.time[]==121 && !viewer.playing[]
        previous=copy(viewer.particles.lon)
        viewer.windtoggle.checked[]=false
        viewer.animate_wind!(0.1)
        @test viewer.particles.lon==previous
        if !isempty(ARGS);save(joinpath(first(ARGS),"weather_temperature.png"),viewer.fig);end
        viewer.windtoggle.checked[]=true
        viewer.fieldmenu.i_selected[]=2
        @test viewer.limits[]==(0f0,120f0)
        @test viewer.mapvalues[][1:end-1,:]≈3.6f0.*frame(data,:wind,8,121)
        viewer.selected[]=nearest_cell(data,132,20)
        @test occursin("km/h",viewer.pointtext[])
        for _ in 1:12;viewer.animate_wind!(1/30);end
        if !isempty(ARGS);save(joinpath(first(ARGS),"weather_wind.png"),viewer.fig);end
        viewer.windtoggle.checked[]=false
        viewer.fieldmenu.i_selected[]=7
        @test viewer.limits[]==(0f0,100f0)
        @test isequal(viewer.mapvalues[][1:end-1,:],frame(data,:rh,8,121))
        @test count(isfinite,viewer.mapvalues[])>4000
        if !isempty(ARGS);save(joinpath(first(ARGS),"weather_humidity.png"),viewer.fig);end
        viewer.fieldmenu.i_selected[]=6
        @test viewer.limits[]==(970f0,1045f0)
        @test viewer.contour_visible[]
        @test viewer.mapvalues[][1:end-1,:]==frame(data,:mslp,8,121)
        if !isempty(ARGS);save(joinpath(first(ARGS),"weather_pressure.png"),viewer.fig);end
        viewer.isobartoggle.checked[]=false
        @test !viewer.contour_visible[]
        viewer.isobartoggle.checked[]=true
        @test viewer.contour_visible[]
        viewer.scalemenu.i_selected[]=2
        @test viewer.limits[]==color_limits(data,:mslp,8,121)
        viewer.smooth.checked[]=false
        @test !viewer.heat.interpolate[]
        viewer.viewmenu.i_selected[]=2
        @test !viewer.contour_visible[] && !viewer.regionmenu.blockscene.visible[]
        viewer.windtoggle.checked[]=true
        for _ in 1:5;viewer.animate_wind!(1/30);end
        valid=filter(p->all(isfinite,p),viewer.wind3d[])
        @test !isempty(valid)
        @test all(p->isapprox(sqrt(sum(abs2,p)),1.008;atol=1e-5),valid)
        viewer.viewmenu.i_selected[]=1
        box=viewer.scalemenu.layoutobservables.computedbbox[]
        events(viewer.fig).mouseposition[]=Tuple(box.origin .+ box.widths ./ 2)
        events(viewer.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(viewer.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test viewer.scalemenu.is_open[]
        viewer.viewmenu.i_selected[]=3
        @test !viewer.scalemenu.is_open[] && !viewer.windtoggle.blockscene.visible[]
        clock=viewer.time[]
        positions=copy(viewer.particles.lon)
        viewer.animate_wind!(0.1)
        @test viewer.particles.lon==positions && viewer.time[]==clock
        @test all(isequal(data.fields[k],original[k]) for k in keys(original))
        # Optional short video demonstrates actual moving streaks on the same frozen frame.
        if length(ARGS)>=2
            viewer.viewmenu.i_selected[]=1
            viewer.fieldmenu.i_selected[]=2
            viewer.scalemenu.i_selected[]=1
            viewer.smooth.checked[]=true
            record(viewer.fig,ARGS[2],1:60;framerate=30) do _
                viewer.animate_wind!(1/30)
            end
        end
    end
    println("WEATHER_VIEWER_PASSED")
finally
    close(screen)
end
