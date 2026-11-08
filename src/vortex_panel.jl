module TerraFluxVortexPanel
using GLMakie,Printf
using ..TerraFluxData,..TerraFluxMapMath,..TerraFluxGlobe
using ..TerraFluxLive.TerraFluxVortexProfiles
export build_vortex_panel
function build_vortex_panel(cell,ax,globe,mode,opened,selected;get_data,on_apply,on_undo)
    layout=GridLayout(cell;width=285,tellheight=false);rowgap!(layout,6);widgets=Any[]
    add(w)=(push!(widgets,w);w)
    add(Label(layout[1,1],"XOÁY LÝ TƯỞNG",fontsize=22,font=:bold,color="#66ded0"))
    add(Label(layout[2,1],"Áp thấp + gió xoáy + lõi ấm\nMột lần · chưa xác nhận bão nhiệt đới",fontsize=12,halign=:left))
    center=Observable("Chưa chọn tâm.")
    add(Label(layout[3,1],center,fontsize=12,halign=:left))
    suggested=add(Button(layout[4,1],label="Đặt tâm / R gợi ý theo lưới",buttoncolor="#213044",labelcolor=:white))
    function input(row,label,value)
        g=GridLayout(layout[row,1]);add(Label(g[1,1],label,fontsize=12,halign=:left))
        add(Textbox(g[1,2],stored_string=value,reset_on_defocus=false,width=100))
    end
    radius=input(5,"R ngoài (800–3000 km)","3000")
    pressure=input(6,"Trũng áp ref (5–25 hPa)","15")
    g=GridLayout(layout[7,1]);add(Label(g[1,1],"Giảm theo cao k",fontsize=12))
    depth=add(Menu(g[1,2],options=[("Sâu · 0.5",0.5),("Vừa · 0.75",0.75),("Nông · 1.5",1.5)],default=2,width=135))
    g2=GridLayout(layout[8,1]);preview=add(Checkbox(g2[1,1],checked=true));add(Label(g2[1,2],"Xem trước phạm vi",fontsize=12))
    summary=Observable("");add(Label(layout[9,1],summary,fontsize=11,tellwidth=false,word_wrap=true,halign=:left,color="#a6b7c8"))
    apply=add(Button(layout[10,1],label="Chèn xoáy một lần",buttoncolor="#213044",labelcolor=:white))
    undo=add(Button(layout[11,1],label="Hoàn tác tác động gần nhất",buttoncolor="#213044",labelcolor=:white))
    message=Observable("Chỉ dùng ở mốc cuối của phiên live đã tạm dừng.\nLưới thô có thể từ chối R quá nhỏ.")
    add(Label(layout[12,1],message,fontsize=12,tellwidth=false,word_wrap=true,halign=:left,color="#a6b7c8"))
    ring=Observable(Point2f[]);sphere_ring=Observable(Point3f[])
    visible2=lift((o,m,p)->o && m==:map && p,opened,mode,preview.checked)
    visible3=lift((o,m,p)->o && m==:globe && p,opened,mode,preview.checked)
    linesegments!(ax,ring;color="#ffbd68",linewidth=2,linestyle=:dash,visible=visible2,depth_shift=-0.04f0)
    lines!(globe,sphere_ring;color="#ffbd68",linewidth=2,linestyle=:dash,visible=visible3)
    function spec()
        selected[]===nothing && error("Bấm bản đồ/địa cầu hoặc chọn tâm gợi ý trước.")
        d=get_data();i,j=selected[]
        vortex_spec(lon=d.lon[i],lat=d.lat[j],radius_km=parse(Float64,radius.displayed_string[]),
            pressure_drop_hpa=parse(Float64,pressure.displayed_string[]),depth=depth.selection[])
    end
    function refresh!()
        if selected[]===nothing
            center[]="Chưa chọn tâm.";summary[]="Chọn tâm rồi xem cấu trúc tham chiếu.";ring[]=Point2f[];sphere_ring[]=Point3f[];return
        end
        d=get_data();i,j=selected[];center[]=@sprintf("Tâm %.2f° / %.2f° · toàn cột khí quyển",d.lon[i],d.lat[j])
        try
            s=spec();r=reference_profile(s)
            summary[]=@sprintf("Tham chiếu: gió tối đa %.1f m/s\nΔTv tại đáy %.2f K · ps ref 1000 hPa\nVòng: R ngoài, không phải bán kính gió bão.",r.max_wind_mps,r.max_delta_tv)
            outline=radius_outline(s.lon,s.lat,s.radius_km);points=Point2f[]
            for n in 1:length(outline)-1
                abs(outline[n+1][1]-outline[n][1])<=180 && append!(points,[Point2f(outline[n]),Point2f(outline[n+1])])
            end
            ring[]=points;sphere_ring[]=[Point3f(sphere_point(p...;radius=1.02)) for p in outline]
        catch err
            summary[]=first(sprint(showerror,err),180);ring[]=Point2f[];sphere_ring[]=Point3f[]
        end
    end
    on(suggested.clicks) do _
        fine=length(get_data().lon)>=160
        Makie.set!(radius,fine ? "1700" : "3000")
        selected[]=nearest_cell(get_data(),130,fine ? 20 : 35)
    end
    for obs in (selected,radius.displayed_string,pressure.displayed_string,depth.selection);on(_->refresh!(),obs);end
    on(apply.clicks) do _;try;on_apply(spec());catch err;message[]=first(sprint(showerror,err),240);end;end
    on(undo.clicks) do _;try;on_undo();catch err;message[]=first(sprint(showerror,err),240);end;end
    refresh!()
    (;widgets,radius,pressure,depth,preview,suggested,apply,undo,ring,summary,message,spec,refresh!)
end
end
