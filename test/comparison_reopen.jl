using Test,GLMakie
include(joinpath(@__DIR__,"..","src","comparison_viewer.jl"))
using .TerraFluxComparisonViewer,.TerraFluxComparisonViewer.TerraFluxData
v=build_comparison_viewer(;path=abspath(ARGS[1]))
screen=display(v.fig)
try
    @testset "Read-only A/B reopening and field/time controls" begin
        @test v.job[]===nothing && length(v.result[].times)>0
        @test v.treatment.checked[]==v.result[].meta["treatment"]
        @test v.displayed[]!==nothing && v.layermenu.selection[]==8
        for f in FIELDS
            v.fieldmenu.i_selected[]=findfirst(==(f),FIELDS)
            @test isequal(v.displayed[].delta,v.displayed[].b.-v.displayed[].a) || f==:wind
        end
        v.fieldmenu.i_selected[]=1;v.layermenu.i_selected[]=1
        set_close_to!(v.slider,1)
        @test v.time[]==1 && occursin(string(v.result[].times[1]),v.clock[])
        original=v.result[]
        v.source.displayed_string[]="missing-comparison.toml";v.openresult.clicks[]+=1
        @test v.result[]===original && occursin("Không tìm thấy",v.status[])
        v.source.displayed_string[]="\"$(ARGS[1])\"";v.openresult.clicks[]+=1
        @test v.job[]===nothing && occursin("Đã mở kết quả",v.status[])
        v.layermenu.i_selected[]=8
        limits!(v.axes[1],60,180,-5,55)
        @test v.axes[1].targetlimits[]==v.axes[2].targetlimits[]==v.axes[3].targetlimits[]
        length(ARGS)>1 && save(ARGS[2],v.fig)
    end
    println("COMPARISON_REOPEN_PASSED")
finally
    close(screen)
end
