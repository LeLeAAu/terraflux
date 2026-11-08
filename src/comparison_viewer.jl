module TerraFluxComparisonViewer
include("data.jl");using .TerraFluxData
include("live.jl");using .TerraFluxLive
include("comparison.jl");using .TerraFluxComparison
include("weather_style.jl");using .TerraFluxWeatherStyle
using GLMakie,GeoMakie,Dates,Printf,TOML
export build_comparison_viewer,launch_comparison
const BG="#101722";const INK="#e8eef5";const MUTED="#a6b7c8";const PANEL="#213044"
function input_path(path)
    s=strip(path)
    length(s)>=2 && startswith(s,'"') && endswith(s,'"') ? s[nextind(s,firstindex(s)):prevind(s,lastindex(s))] : s
end
function build_comparison_viewer(;path="",root=joinpath(@__DIR__,"..","sessions","comparisons"))
    set_theme!(theme_dark();fontsize=14,backgroundcolor=BG,textcolor=INK)
    fig=Figure(size=(1560,1000),figure_padding=22)
    header=GridLayout(fig[1,1:3])
    Label(header[1,1],"TERRAFLUX · THÍ NGHIỆM A/B",fontsize=26,font=:bold,color="#66ded0",halign=:left,tellwidth=false)
    Label(header[2,1],"Cùng trạng thái xuất phát · A đối chứng · B có/không tác động mới · Δ = B − A",halign=:left,fontsize=13)
    form=GridLayout(fig[2,1:3])
    Label(form[1,1],"Bản lưu / kết quả",halign=:left)
    source=Textbox(form[1,2:7],stored_string=path,placeholder="Đường dẫn session.toml hoặc comparison.toml",reset_on_defocus=false,tellwidth=false)
    openresult=Button(form[1,8],label="Mở kết quả A/B",buttoncolor=PANEL,labelcolor=INK)
    Label(form[2,1],"Số bước × 6 giờ",halign=:left)
    steps=Textbox(form[2,2],stored_string="4",width=80,reset_on_defocus=false)
    treatment=Checkbox(form[2,3],checked=true)
    kind=Menu(form[2,4],options=[("B: nhiệt một tầng","thermal"),("B: xoáy lý tưởng","vortex")],default=1,width=210)
    create=Button(form[2,5:7],label="Tạo và chạy A/B",buttoncolor=PANEL,labelcolor=INK)
    stop=Button(form[2,8],label="Dừng",buttoncolor=PANEL,labelcolor=INK)
    controls=GridLayout(form[3,1:8])
    inputs=Dict{Symbol,Any}()
    for (i,(key,label,value)) in enumerate(((:lon,"Kinh độ","130"),(:lat,"Vĩ độ","20"),
            (:radius_km,"R ngoài (km)","2500"),(:layer,"Tầng tác động","8"),(:delta_k,"ΔT (−5…+5 K)","2")))
        Label(controls[1,2i-1],label,fontsize=12)
        inputs[key]=Textbox(controls[1,2i],stored_string=value,width=85,reset_on_defocus=false)
    end
    extra=GridLayout(form[4,1:8])
    Label(extra[1,1],"Xoáy: trũng áp ref (hPa)",fontsize=12)
    inputs[:pressure_drop_hpa]=Textbox(extra[1,2],stored_string="15",width=80,reset_on_defocus=false)
    Label(extra[1,3],"Giảm theo cao k",fontsize=12)
    inputs[:depth]=Textbox(extra[1,4],stored_string="0.75",width=80,reset_on_defocus=false)
    Label(extra[1,5],"Nhiệt: R 1000–5000, tầng, ΔT · Xoáy: R 800–3000, trũng áp, k.",fontsize=11)
    on(kind.selection) do choice
        if choice=="vortex"
            Makie.set!(inputs[:lat],"35");Makie.set!(inputs[:radius_km],"3000")
        end
    end
    status=Observable("Lưu phiên live đã tạm dừng sau ít nhất +6 giờ, rồi dán đường dẫn ở trên. Chọn 1–40 bước; physics dùng CPU.")
    Label(fig[3,1:3],status,halign=:left,fontsize=12,tellwidth=false,word_wrap=true,color=MUTED)
    toolbar=GridLayout(fig[4,1:3])
    fieldmenu=Menu(toolbar[1,1],options=[(field_label(f),f) for f in FIELDS],width=220)
    layermenu=Menu(toolbar[1,2],options=[("Tầng 1",1)],width=240)
    standard=Checkbox(toolbar[1,3],checked=true)
    Label(toolbar[1,4],"Thang khí tượng chung A/B",fontsize=12)
    reset=Button(toolbar[1,5],label="Đặt lại vùng xem",buttoncolor=PANEL,labelcolor=INK)
    axes=[Axis(fig[5,i],title=t,xlabel="Kinh độ",ylabel=i==1 ? "Vĩ độ" : "",aspect=DataAspect())
        for (i,t) in enumerate(("A · đối chứng","B · nhánh thí nghiệm","Δ = B − A"))]
    linkaxes!(axes...)
    for ax in axes;limits!(ax,-180,180,-90,90);end
    unit=Observable("°C");deltaunit=Observable("Δ · °C")
    sharedlimits=Observable((-30f0,50f0));deltalimits=Observable((-1f0,1f0))
    style=load_weather_style();cmap=Observable(weather_palette(style,:temp))
    Colorbar(fig[6,1:2];limits=sharedlimits,colormap=cmap,label=unit,vertical=false,tellheight=true,height=16)
    Colorbar(fig[6,3];limits=deltalimits,colormap=:balance,label=deltaunit,vertical=false,tellheight=true,height=16)
    clock=Observable("Chưa có mốc mới chung.")
    Label(fig[7,1:3],clock,halign=:left,font=:bold)
    slider=Slider(fig[8,1:3],range=1:1,startvalue=1)
    pointtext=Observable("Bấm một bản đồ để đọc cùng một ô trên A, B và Δ. Các khung xuất phát trước tác động không được dùng làm kết quả sau tác động.")
    Label(fig[9,1:3],pointtext,halign=:left,tellwidth=false,word_wrap=true,fontsize=12)
    destination=Observable("")
    Label(fig[10,1:3],destination,halign=:left,tellwidth=false,word_wrap=true,fontsize=11,color=MUTED)
    job=Ref{Union{Nothing,ComparisonJob}}(nothing);result=Ref{Any}(nothing)
    resultpath=Ref("");imported=Ref(0);time=Observable(1);selected=Ref{Any}(nothing)
    displayed=Ref{Any}(nothing);importing=Ref(false)
    function refresh!()
        (result[]===nothing || importing[] || layermenu.selection[]===nothing) && return
        r=result[];f=fieldmenu.selection[];k=layermenu.selection[];t=clamp(time[],1,length(r.times))
        values=comparison_values(r,f,k,t)
        factor=f==:wind ? 3.6f0 : 1f0
        a,b,delta=(values.a.*factor,values.b.*factor,values.delta.*factor)
        displayed[]=(;a,b,delta)
        cmap[]=weather_palette(style,f);unit[]=display_unit(f)
        deltaunit[]=f==:rh ? "Δ · điểm phần trăm" : "Δ · "*unit[]
        key=get(Dict(:temp=>"temperature",:wind=>"wind",:rh=>"humidity",:mslp=>"pressure"),f,nothing)
        vals=filter(isfinite,vcat(vec(a),vec(b)))
        if standard.checked[] && key!==nothing
            sharedlimits[]=Tuple(Float32.(style[key]["range"]))
        else
            lo,hi=isempty(vals) ? (-1f0,1f0) : extrema(vals)
            f in (:u,:v) && ((lo,hi)=(-max(abs(lo),abs(hi)),max(abs(lo),abs(hi))))
            sharedlimits[]=lo==hi ? (lo-1f0,hi+1f0) : (lo,hi)
        end
        bound=0f0
        for i in eachindex(r.times)
            differences=comparison_values(r,f,k,i).delta
            for x in differences;isfinite(x) && (bound=max(bound,abs(x)*factor));end
        end
        bound=bound>0 ? bound : 1f0;deltalimits[]=(-bound,bound)
        for (i,(ax,matrix)) in enumerate(zip(axes,(a,b,delta)))
            empty!(ax)
            heatmap!(ax,vcat(r.a.lon,r.a.lon[1]+360),r.a.lat,vcat(matrix,matrix[1:1,:]);
                colorrange=i==3 ? deltalimits : sharedlimits,colormap=i==3 ? :balance : cmap,
                nan_color=:transparent,interpolate=true)
            lines!(ax,GeoMakie.coastlines();color=(:black,0.8),linewidth=0.6,xautolimits=false,yautolimits=false)
        end
        axes[2].title[]=!r.meta["treatment"] ? "B · không tác động mới" : get(r.meta,"intervention","thermal")=="vortex" ? "B · xoáy lý tưởng" : "B · can thiệp nhiệt"
        clock[]="$(r.times[t]) · Mốc chung $t / $(length(r.times)) · $(layer_label(r.a,k)) · $(field_label(f))"
        if selected[]!==nothing
            i,j=selected[]
            value(x)=isfinite(x) ? @sprintf("%.4g",x) : "thiếu"
            pointtext[]=@sprintf("Ô %.2f° / %.2f° · A %s %s · B %s %s · Δ %s %s",r.a.lon[i],r.a.lat[j],
                value(a[i,j]),unit[],value(b[i,j]),unit[],value(delta[i,j]),f==:rh ? "điểm %" : unit[])
        end
    end
    function import_result!(path;verify=true)
        r=load_comparison(path;verify)
        old=result[]
        (old===nothing || old.a.lon!=r.a.lon || old.a.lat!=r.a.lat) && (selected[]=nothing)
        importing[]=true
        try
            result[]=r;resultpath[]=r.path;imported[]=length(r.times)
            if old===nothing || old.a.layers!=r.a.layers
                layermenu.options[]=[(layer_label(r.a,k),k) for k in eachindex(r.a.layers)]
                layermenu.i_selected[]=length(r.a.layers)
            end
            slider.range[]=1:length(r.times);set_close_to!(slider,length(r.times))
            time[]=length(r.times)
        finally
            importing[]=false
        end
        refresh!()
        archive(side)=isempty(r.meta["archive_"*side]) ? "chưa lưu" : joinpath(dirname(r.path),split(r.meta["archive_"*side],'/')...)
        destination[]="Kết quả: $(r.path)\nBản lưu cuối A: $(archive("a"))\nBản lưu cuối B: $(archive("b"))"
        r
    end
    function show_config!(r)
        Makie.set!(steps,string(r.meta["steps"]))
        treatment.checked[]=r.meta["treatment"]
        kind.i_selected[]=get(r.meta,"intervention","thermal")=="vortex" ? 2 : 1
        for (key,w) in inputs
            spec=get(r.meta,"patch",Dict())
            haskey(spec,string(key)) && Makie.set!(w,string(spec[string(key)]))
        end
    end
    for obs in (fieldmenu.selection,layermenu.selection,standard.checked);on(_->refresh!(),obs);end
    on(slider.value) do t;time[]=round(Int,t);refresh!();end
    on(reset.clicks) do _;for ax in axes;limits!(ax,-180,180,-90,90);end;end
    for ax in axes
        on(events(ax.scene).mousebutton;priority=2) do event
            if result[]!==nothing && event.button==Mouse.left && event.action==Mouse.press && Makie.is_mouseinside(ax.scene)
                p=mouseposition(ax);selected[]=nearest_cell(result[].a,p...);refresh!()
            end
            Consume(false)
        end
    end
    on(create.clicks) do _
        try
            job[]!==nothing && process_running(job[].process) && error("Đợi hoặc dừng thí nghiệm đang chạy trước.")
            keys=kind.selection[]=="vortex" ? (:lon,:lat,:radius_km,:pressure_drop_hpa,:depth) : (:lon,:lat,:radius_km,:layer,:delta_k)
            patch=treatment.checked[] ? (;(key=>parse(key==:layer ? Int : Float64,inputs[key].displayed_string[]) for key in keys)...) : nothing
            job[]=start_comparison(input_path(source.displayed_string[]);patch,treatment=treatment.checked[],intervention=kind.selection[],steps=parse(Int,steps.displayed_string[]),root)
            result[]=nothing;resultpath[]="";imported[]=0;selected[]=nothing;displayed[]=nothing
            for ax in axes;empty!(ax);end
            clock[]="Chờ mốc mới chung sau khi A và B tính xong."
            destination[]="Kết quả và nhật ký: $(job[].directory)"
            status[]="Đang nạp/biên dịch. A tính trước, sau đó B; cửa sổ vẫn phản hồi."
        catch err
            status[]=first(sprint(showerror,err),280)
        end
    end
    on(stop.clicks) do _
        try
            job[]===nothing || stop_comparison!(job[])
        catch err
            status[]=first(sprint(showerror,err),260)
        end
    end
    on(openresult.clicks) do _
        try
            job[]!==nothing && process_running(job[].process) && error("Dừng hoặc chờ thí nghiệm hiện tại hoàn tất trước khi mở kết quả khác.")
            r=import_result!(input_path(source.displayed_string[]));show_config!(r)
            job[]=nothing # Stop polling the prior completed job when viewing another result.
            status[]="Đã mở kết quả A/B; thanh thời gian chỉ phát lại các mốc chung."
        catch err
            status[]=first(sprint(showerror,err),280)
        end
    end
    function poll!()
        job[]===nothing && return
        m=comparison_status(job[]);na=length(m["outputs_a"]);nb=length(m["outputs_b"])
        phase=get(Dict("loading"=>"Nạp thư viện/biên dịch","copying_baseline"=>"Kiểm tra và sao chép bản lưu","initializing_a"=>"Khởi tạo A","initializing_b"=>"Khởi tạo B",
            "applying_b"=>"Chèn tác động lên B","integrating_a"=>"Tính A","integrating_b"=>"Tính B",
            "saving_a"=>"Lưu trạng thái A","saving_b"=>"Lưu trạng thái B","complete"=>"Hoàn tất","stopped"=>"Đã dừng","error"=>"Lỗi"),m["phase"],m["phase"])
        message="$phase · A $na / $(m["steps"]) · B $nb / $(m["steps"]) bước × 6 giờ · Xuất phát $(m["fork_time"])"*
            (m["state"]=="error" ? " · "*first(m["error"],240) : "")
        status[]==message || (status[]=message)
        count=min(na,nb)
        if count>imported[] || (m["state"]=="complete" && result[]!==nothing && result[].meta["state"]!="complete")
            import_result!(job[].directory;verify=m["state"]=="complete")
        end
        m
    end
    if !isempty(path)
        file=comparison_path(input_path(path))
        if isfile(file) && get(TOML.parsefile(file),"format","")=="terraflux.comparison"
            r=import_result!(file);show_config!(r);status[]="Đã mở kết quả A/B."
        end
    end
    (;fig,source,steps,treatment,kind,inputs,create,stop,openresult,fieldmenu,layermenu,standard,
        reset,axes,status,clock,slider,pointtext,destination,job,result,time,displayed,sharedlimits,deltalimits,poll!,import_result!)
end
function launch_comparison(;path="")
    ui=build_comparison_viewer(;path)
    screen=display(ui.fig)
    try
        while isopen(screen)
            sleep(0.3)
            try;ui.poll!();catch err;ui.status[]=first(sprint(showerror,err),280);end
        end
    finally
        ui.job[]===nothing || stop_comparison!(ui.job[])
        close(screen)
    end
end
end
