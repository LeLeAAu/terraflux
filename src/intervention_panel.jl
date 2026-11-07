module TerraFluxInterventionPanel
using GLMakie,Printf
using ..TerraFluxData, ..TerraFluxMapMath, ..TerraFluxGlobe
using ..TerraFluxLive.TerraFluxThermalPatch
export build_intervention_panel
function build_intervention_panel(cell,ax,globe,mode,opened,selected,layer;get_data,on_apply,on_undo,on_layer)
    layout=GridLayout(cell,width=285,tellheight=false);widgets=Any[]
    add(w)=(push!(widgets,w);w)
    add(Label(layout[1,1],"CAN THIỆP NHIỆT",fontsize=22,color="#66ded0",font=:bold))
    add(Label(layout[2,1],"Một lần · phiên live đã tạm dừng\nBấm bản đồ / địa cầu để chọn tâm.",fontsize=13,halign=:left))
    center=Observable("")
    add(Label(layout[3,1],center,fontsize=13,halign=:left))
    d=get_data()
    menu=add(Menu(layout[4,1],options=[(layer_label(d,k),k) for k in eachindex(d.layers)],default=layer[],width=280))
    add(Label(layout[5,1],"Bán kính (1000–5000 km)",fontsize=13,halign=:left))
    radius=add(Textbox(layout[6,1],stored_string="2500",reset_on_defocus=false,width=280))
    add(Label(layout[7,1],"ΔT tại tâm (−5…+5 K, khác 0)",fontsize=13,halign=:left))
    delta=add(Textbox(layout[8,1],stored_string="2",reset_on_defocus=false,width=280))
    row=GridLayout(layout[9,1]);preview=add(Checkbox(row[1,1],checked=true))
    add(Label(row[1,2],"Xem trước phạm vi",fontsize=13))
    apply=add(Button(layout[10,1],label="Áp dụng một lần",buttoncolor="#213044",labelcolor=:white))
    undo=add(Button(layout[11,1],label="Hoàn tác trước bước mới",buttoncolor="#213044",labelcolor=:white))
    message=Observable("Tạo phiên mới, tính +6 giờ, rồi tạm dừng.\nMở nguồn Phiên mô phỏng và xem mốc cuối.")
    add(Label(layout[12,1],message,fontsize=12,tellwidth=false,word_wrap=true,halign=:left,color="#a6b7c8"))
    ring=Observable(Point2f[]);sphere_ring=Observable(Point3f[])
    visible2=lift((o,m,p)->o && m==:map && p,opened,mode,preview.checked)
    visible3=lift((o,m,p)->o && m==:globe && p,opened,mode,preview.checked)
    linesegments!(ax,ring;color="#ffbd68",linewidth=2,linestyle=:dash,visible=visible2,depth_shift=-0.04f0)
    lines!(globe,sphere_ring;color="#ffbd68",linewidth=2,linestyle=:dash,visible=visible3)
    function spec()
        selected[]===nothing && error("Bấm bản đồ hoặc địa cầu để chọn tâm trước.")
        d=get_data();i,j=selected[]
        thermal_spec(lon=d.lon[i],lat=d.lat[j],radius_km=parse(Float64,radius.displayed_string[]),
            layer=layer[],delta_k=parse(Float64,delta.displayed_string[]))
    end
    function refresh!()
        if selected[]===nothing
            center[]="Chưa chọn tâm."
            ring[]=Point2f[];sphere_ring[]=Point3f[]
            return
        end
        d=get_data();i,j=selected[]
        center[]=@sprintf("Tâm %.2f° / %.2f° · tầng %d",d.lon[i],d.lat[j],layer[])
        try
            s=spec();boundary=radius_outline(s.lon,s.lat,s.radius_km)
            pairs=Point2f[]
            for k in 1:length(boundary)-1
                abs(boundary[k+1][1]-boundary[k][1])<=180 && append!(pairs,[Point2f(boundary[k]),Point2f(boundary[k+1])])
            end
            ring[]=pairs;sphere_ring[]=[Point3f(sphere_point(p...;radius=1.02)) for p in boundary]
        catch
            ring[]=Point2f[];sphere_ring[]=Point3f[]
        end
    end
    on(menu.selection) do k;on_layer(k);end
    on(layer) do k;menu.i_selected[]==k || (menu.i_selected[]=k);refresh!();end
    for obs in (selected,radius.displayed_string,delta.displayed_string)
        on(_->refresh!(),obs)
    end
    on(apply.clicks) do _
        try;on_apply(spec());catch err;message[]=first(sprint(showerror,err),220);end
    end
    on(undo.clicks) do _
        try;on_undo();catch err;message[]=first(sprint(showerror,err),220);end
    end
    refresh!()
    (;widgets,menu,radius,delta,preview,apply,undo,message,ring,spec,refresh!)
end
end
