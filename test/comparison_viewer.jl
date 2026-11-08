using Test,GLMakie,Dates
include(joinpath(@__DIR__,"..","src","comparison_viewer.jl"))
using .TerraFluxComparisonViewer
using .TerraFluxComparisonViewer.TerraFluxComparison
using .TerraFluxComparisonViewer.TerraFluxData
using .TerraFluxComparisonViewer.TerraFluxLive.TerraFluxSavedSessions
isempty(ARGS) && error("Provide a T21/8 saved session with no pending edits and a remaining 6h interval.")
root=length(ARGS)>2 ? abspath(ARGS[3]) : mktempdir(;prefix="TerraFlux AB UI ",cleanup=false)
mkpath(root)
println("A/B UI validation: $root");flush(stdout)
source=joinpath(root,"baseline source");cp(dirname(abspath(ARGS[1])),source)
v=build_comparison_viewer(;root)
screen=display(v.fig)
function click(widget)
    sleep(0.3)
    b=widget.layoutobservables.computedbbox[]
    events(v.fig).mouseposition[]=Tuple(b.origin.+b.widths./2)
    events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
    events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
end
try
    @testset "Native A/B form, real heating and linked comparison maps" begin
        v.steps.displayed_string[]="0";click(v.create)
        @test v.job[]===nothing && occursin("1–40",v.status[])
        v.source.displayed_string[]="\"$(joinpath(source,"session.toml"))\""
        v.steps.displayed_string[]="1"
        v.inputs[:radius_km].displayed_string[]="3000"
        click(v.create)
        @test v.job[]!==nothing && v.result[]===nothing
        @test timedwait(900;pollint=0.1) do
            m=v.poll!()
            m["state"]=="error" && error(m["error"]*"\n"*read(joinpath(v.job[].directory,"worker.log"),String))
            m["state"]=="complete"
        end == :ok
        wait(v.job[].process);@test v.job[].process.exitcode==0
        r=v.result[]
        @test length(r.times)==1 && r.meta["treatment"]
        @test r.meta["effect"]["heat_dry_approx_j"]>0
        @test r.times[1]==DateTime(r.meta["fork_time"])+Hour(6)
        @test maximum(abs,v.displayed[].delta)>0.01
        @test v.displayed[].delta≈v.displayed[].b.-v.displayed[].a
        @test v.deltalimits[][1]==-v.deltalimits[][2]
        # Same heatmap scales for A/B; a distinct symmetric scale for B-A.
        @test v.sharedlimits[]==(-30f0,50f0)
        v.fieldmenu.i_selected[]=findfirst(==(:wind),FIELDS)
        expected=comparison_values(r,:wind,8,1)
        @test v.displayed[].a≈3.6f0.*expected.a
        @test v.displayed[].delta≈3.6f0.*expected.delta
        v.fieldmenu.i_selected[]=findfirst(==(:rh),FIELDS)
        @test occursin("Độ ẩm tương đối",v.clock[])
        v.fieldmenu.i_selected[]=1
        # A click on any map samples the corresponding original cell in all three.
        vp=v.axes[2].scene.viewport[]
        events(v.fig).mouseposition[]=Tuple(vp.origin.+vp.widths./2)
        events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test occursin("· A",v.pointtext[]) && occursin("· Δ",v.pointtext[])
        limits!(v.axes[1],60,180,-5,55)
        @test v.axes[1].targetlimits[]==v.axes[2].targetlimits[]==v.axes[3].targetlimits[]
        for side in ("a","b")
            file=joinpath(v.job[].directory,r.meta["archive_"*side])
            @test saved_manifest(file)["model_time"]==string(r.times[end])
        end
        # Opening a result must not start another physics process.
        previous=v.job[]
        v.source.displayed_string[]=joinpath(previous.directory,"comparison.toml")
        click(v.openresult)
        @test v.job[]===nothing && occursin("Đã mở kết quả",v.status[])
        stop_comparison!(previous)
        @test comparison_status(previous)["state"]=="complete"
        length(ARGS)>1 && save(ARGS[2],v.fig)
        println("A/B heated result: $(joinpath(previous.directory,"comparison.toml"))");flush(stdout)
    end
    println("COMPARISON_VIEWER_PASSED")
finally
    v.job[]===nothing || stop_comparison!(v.job[])
    close(screen)
end
