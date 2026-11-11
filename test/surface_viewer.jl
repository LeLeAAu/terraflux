# Known synthetic surface fields exercise UI routing, independent of model physics.
using GLMakie, Test
include(joinpath(@__DIR__,"..","src","viewer.jl"))
using .TerraFluxViewer
using .TerraFluxViewer.TerraFluxData
base=load_weather(joinpath(@__DIR__,"..","run_0001","output.nc"))
fields=copy(base.fields)
shape=(length(base.lon),length(base.lat),length(base.times))
fields[:sst]=fill(26f0,shape);fields[:lst]=fill(35f0,shape)
fields[:sst][1:48,:,:].=NaN32;fields[:lst][49:end,:,:].=NaN32
v=build_viewer(WeatherData(base.path,base.lon,base.lat,base.layers,base.times,fields))
screen=display(v.fig)
try
    @testset "Surface fields in 2D and globe" begin
        for (f,value) in ((:sst,26f0),(:lst,35f0))
            v.fieldmenu.i_selected[]=findfirst(==(f),FIELDS)
            @test v.field[]==f
            before=copy(v.mapvalues[])
            @test any(==(value),before) && any(isnan,before)
            v.layermenu.i_selected[]=1
            @test isequal(v.mapvalues[],before)
            v.layermenu.i_selected[]=8
            @test isequal(v.mapvalues[],before)
            v.viewmenu.i_selected[]=2
            @test !isempty(GLMakie.colorbuffer(screen))
            v.viewmenu.i_selected[]=1
            @test !isempty(GLMakie.colorbuffer(screen))
        end
    end
finally
    close(screen)
end
