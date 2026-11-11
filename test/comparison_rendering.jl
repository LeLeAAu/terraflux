using Test,GLMakie,TOML
include(joinpath(@__DIR__,"..","src","comparison_viewer.jl"))
using .TerraFluxComparisonViewer,.TerraFluxComparisonViewer.TerraFluxComparison
using .TerraFluxComparisonViewer.TerraFluxData
length(ARGS)>=2 || error("Provide a two-frame A/B result and another result on a different grid.")
root=mktempdir(;prefix="TerraFlux cached results ")
cp(dirname(comparison_path(ARGS[1])),joinpath(root,"result"))
path=joinpath(root,"result","comparison.toml");full=comparison_manifest(path)
@assert length(full["outputs_b"])>=2
stage=deepcopy(full);stage["state"]="running";stage["outputs_b"]=stage["outputs_b"][1:1]
put(m)=open(io->TOML.print(io,m),path,"w")
put(stage);first=load_comparison(path)
put(full);next=load_comparison(path;previous=first);expected=load_comparison(path)
@testset "Incremental A/B data keeps history and verifies cached files" begin
    @test next.times==expected.times
    @test all(isequal(next.a.fields[f],expected.a.fields[f]) && isequal(next.b.fields[f],expected.b.fields[f]) for f in keys(expected.a.fields))
    same=load_comparison(path;previous=next)
    @test same.a===next.a && same.b===next.b
    target=joinpath(dirname(path),full["outputs_a"][1]["path"])
    original=Ref{UInt8}()
    try
        open(target,"r+") do io;original[]=read(io,UInt8);seekstart(io);write(io,original[]⊻0x01);end
        @test_throws ErrorException load_comparison(path;previous=same)
    finally
        open(target,"r+") do io;write(io,original[]);end
    end
end
v=build_comparison_viewer(;path);screen=display(v.fig)
try
    @testset "Map resources persist and point reads do not redraw them" begin
        v.inputs[:lat].displayed_string[]="22";v.inputs[:radius_km].displayed_string[]="1700"
        v.kind.i_selected[]=2;v.kind.i_selected[]=1;v.kind.i_selected[]=2
        @test v.inputs[:lat].displayed_string[]=="22" && v.inputs[:radius_km].displayed_string[]=="1700"
        plots=[copy(ax.scene.plots) for ax in v.axes]
        for f in (2,3,1),t in (1,2)
            v.fieldmenu.i_selected[]=f;set_close_to!(v.slider,t)
            @test all(length(ax.scene.plots)==length(p) && all(x===y for (x,y) in zip(ax.scene.plots,p)) for (ax,p) in zip(v.axes,plots))
        end
        set_close_to!(v.slider,1)
        before=v.displayed[];cache_count=length(v.delta_cache)
        notifications=Ref(0);on(_->(notifications[]+=1),v.mapdata[1])
        vp=v.axes[2].scene.viewport[]
        events(v.fig).mouseposition[]=Tuple(vp.origin.+vp.widths./2)
        events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test occursin("· A",v.pointtext[])
        @test v.displayed[]===before && notifications[]==0 && length(v.delta_cache)==cache_count
        v.import_result!(path)
        @test v.time[]==1 && notifications[]==0 && v.displayed[]===before
        v.import_result!(ARGS[2])
        @test occursin("Bấm một bản đồ",v.pointtext[])
        @test size(v.mapdata[1][])==(length(v.result[].a.lon)+1,length(v.result[].a.lat))
    end
    println("COMPARISON_RENDERING_PASSED")
finally
    close(screen)
end
