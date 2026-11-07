module TerraFluxHover
using GLMakie,Printf
using ..TerraFluxData, ..TerraFluxGlobe, ..TerraFluxDetection, ..TerraFluxWeatherStyle
export build_hover
function build_hover(fig,ax,globe,tracker,mode,menus,layers,systems;get_data,get_field,get_layer,get_time,get_values)
    text=Observable("");visible=Observable(false);position=Observable(Point2f(0,0))
    tip=tooltip!(fig.scene,position;text,visible,space=:pixel,fontsize=13,textcolor=:white,
        backgroundcolor="#1a2634",outline_color="#66ded0",textpadding=(10,10,7,7))
    # Axis plots occupy child scenes; place the popup above their depth range.
    translate!(tip,0,0,1000)
    function update!()
        if any(m->m.is_open[],menus) || ispressed(fig,Mouse.left) || ispressed(fig,Mouse.right)
            visible[]=false;return
        end
        location=nothing
        if mode[]==:map && is_mouseinside(ax.scene)
            location=Tuple(Float64.(mouseposition(ax)))
        elseif mode[]==:globe && is_mouseinside(globe.scene)
            ray=Makie.ray_at_cursor(globe.scene);location=sphere_hit(ray.origin,ray.direction)
        elseif mode[]==:tracker && is_mouseinside(tracker.ax.scene)
            location=Tuple(Float64.(mouseposition(tracker.ax)))
        end
        if location===nothing || !( -180<=location[1]<=180 && -90<=location[2]<=90)
            visible[]=false
            layers.highlight[]===nothing || layers.highlight!(nothing,get_time())
            return
        end
        d=get_data();f=get_field();k=get_layer();now=get_time()
        i,j=nearest_cell(d,location...);value=get_values()[i,j]
        reading=isfinite(value) ? @sprintf("%.2f %s",value,display_unit(f)) : "Thiếu dữ liệu"
        message="$(field_label(f)): $reading\n"*@sprintf("Ô gần nhất %.2f° / %.2f°",d.lon[i],d.lat[j])
        f!=:mslp && (message*="\nσ = $(round(d.layers[k];digits=4))")
        item=systems[] && mode[]!=:tracker ? layers.system_at(location...) : nothing
        id=item===nothing ? nothing : item.system.id
        if item!==nothing
            st=item.state
            source=layers.catalog[] isa ModelStormSet ? "ứng viên mô hình" : "MINH HỌA"
            message="$(item.system.id) · $source\n"*message
            if st.radius_km!==nothing
                censored=layers.catalog[] isa ModelStormSet && layers.catalog[].metrics[(id,now)].radius_censored
                message*="\nVùng xoáy R $(censored ? "≥" : "≈") $(round(Int,st.radius_km)) km"
            else
                message*="\nBán kính xoáy chưa xác định"
            end
        end
        layers.highlight[]==id || layers.highlight!(id,now)
        text[]=message;position[]=Point2f(events(fig).mouseposition[]);visible[]=true
        tip.placement[]=position[][2]>fig.scene.viewport[].widths[2]-170 ? :below : :above
        tip.align[]=position[][1]>fig.scene.viewport[].widths[1]-220 ? 1f0 : position[][1]<220 ? 0f0 : 0.5f0
    end
    on(events(fig).mouseposition,priority=10) do _;update!();Consume(false);end
    on(events(fig).mousebutton,priority=-1) do _;update!();Consume(false);end
    for menu in menus;on(menu.is_open) do open;open && (visible[]=false);end;end
    (;text,visible,position,update!)
end
end
