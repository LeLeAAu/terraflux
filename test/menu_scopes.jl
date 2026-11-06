# Regression for a real pointer click opening an invisible overlapping menu.
using GLMakie, Test
include(joinpath(@__DIR__,"..","src","ui_scope.jl"))
using .TerraFluxUIScope
fig=Figure(size=(600,400))
physical=Menu(fig[1,1],options=["Nhiệt độ","Gió","Áp suất"],width=280)
tracker=Menu(fig[1,1],options=["DEMO-01","DEMO-02"],width=280)
scope_widget_inputs!([physical,tracker])
physical.blockscene.visible[]=false
screen=display(fig)
function click_menu(menu)
    area=menu.layoutobservables.computedbbox[]
    events(fig).mouseposition[]=Tuple(area.origin .+ area.widths ./ 2)
    events(fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
    events(fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
end
try
    @testset "Only the visible menu receives pointer/text input" begin
        input_events=(events(fig).mouseposition,events(fig).mousebutton,events(fig).scroll,
            events(fig).keyboardbutton,events(fig).unicode_input)
        listener_counts=map(e -> length(Makie.Observables.listeners(e)),input_events)
        for _ in 1:4
            click_menu(tracker)
            @test tracker.is_open[]
            @test !physical.is_open[]
            @test physical.selection[] == "Nhiệt độ"
            physical.blockscene.visible[]=true
            tracker.blockscene.visible[]=false
            @test !tracker.is_open[]
            click_menu(physical)
            @test physical.is_open[]
            @test !tracker.is_open[]
            @test tracker.selection[] == "DEMO-01"
            physical.blockscene.visible[]=false
            tracker.blockscene.visible[]=true
            @test !physical.is_open[]
        end
        @test map(e -> length(Makie.Observables.listeners(e)),input_events) == listener_counts
        click_menu(tracker)
        events(fig).unicode_input[]='2'
        # Menu search filters entries; Enter only closes this Makie menu.
        popup=only(filter(s -> s.visible[] && all(>(0),s.viewport[].widths),tracker.blockscene.children))
        area=popup.viewport[]
        events(fig).mouseposition[]=Tuple(area.origin .+ area.widths ./ 2)
        events(fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test physical.selection[] == "Nhiệt độ"
        @test tracker.selection[] == "DEMO-02"
        @test !physical.is_open[]
        if !isempty(ARGS)
            click_menu(tracker)
            save(abspath(first(ARGS)),fig)
        end
    end
finally
    close(screen)
end
