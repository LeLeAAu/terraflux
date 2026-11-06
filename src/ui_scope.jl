module TerraFluxUIScope
using GLMakie
export scope_widget_inputs!

"""
Gate a widget's native input subscriptions on its blockscene visibility.
Makie 0.24 menus hit-test their button geometry without checking visibility;
merely hiding the scene leaves invisible menus able to steal clicks/open lists.

Install once after constructing each mode-specific widget. Read Makie's owned
subscription list, then use Observables.off/on to retain callback priorities and
scene/plot cleanup. Do not gate layout/window events or change widget selections.
"""
function scope_widget_inputs!(widgets)
    seen = Base.IdSet{Any}()
    function guard!(owner, visible, inputs)
        owner in seen && return
        push!(seen,owner)
        for subscription in copy(owner.deregister_callbacks)
            source = subscription.observable
            any(input -> input === source,inputs) || continue
            registered = Makie.Observables.listeners(source)
            index = findfirst(pair -> last(pair) === subscription.f,registered)
            index === nothing && continue
            priority = first(registered[index])
            callback = subscription.f
            Makie.Observables.off(subscription)
            on(owner,source;priority) do value
                visible[] ? callback(value) : Consume(false)
            end
        end
        for plot in owner.plots; guard!(plot,visible,inputs); end
        if owner isa Scene
            for child in owner.children; guard!(child,visible,inputs); end
        end
    end
    for widget in widgets
        scene = widget.blockscene
        e = events(scene)
        inputs = (e.mouseposition,e.mousebutton,e.scroll,e.keyboardbutton,e.unicode_input)
        guard!(scene,scene.visible,inputs)
        if widget isa Menu
            on(scene,scene.visible) do visible
                !visible && (widget.is_open[] = false)
            end
        end
    end
    nothing
end
end
