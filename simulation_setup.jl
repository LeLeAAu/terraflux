using Pkg
"--setup" in ARGS && Pkg.instantiate()
using GLMakie,TOML,Printf,Dates
include("src/batch.jl")
using .TerraFluxBatch,.TerraFluxBatch.TerraFluxExperimentConfig
include("src/local_open.jl")
using .TerraFluxLocalOpen

function build_simulation_setup(;root=joinpath(@__DIR__,"sessions","generated"),open_path=open_local_path)
    set_theme!(theme_dark();fontsize=15,textcolor="#e8eef5")
    fig=Figure(size=(850,730),backgroundcolor="#101722")
    Label(fig[1,1:2],"TERRAFLUX / TẠO MÔ PHỎNG",fontsize=25,color="#66ded0",font=:bold)
    Label(fig[2,1:2],"Chọn thời lượng và độ phân giải vật lý. Phép tính chạy CPU trong tiến trình riêng.",fontsize=13)
    Label(fig[3,1],"Số ngày (1–365)",halign=:left)
    days=Textbox(fig[3,2],stored_string="60",reset_on_defocus=false,width=360)
    Label(fig[4,1],"Độ phân giải ngang",halign=:left)
    resolution=Menu(fig[4,2],options=[("T21 · thử nhanh",21),("T32 · nhẹ",32),("T63 · cân bằng",63),("T85 · chi tiết hơn",85)],default=2,width=360)
    Label(fig[5,1],"Số tầng khí quyển",halign=:left)
    levels=Menu(fig[5,2],options=[("$n tầng",n) for n in (8,16,24,32)],default=1,width=360)
    Label(fig[6,1],"Ghi một khung mỗi",halign=:left)
    interval=Menu(fig[6,2],options=[("$n giờ",n) for n in (1,3,6,12,24)],default=3,width=360)
    Label(fig[7,1],"Luồng CPU",halign=:left)
    threads=Menu(fig[7,2],options=[("$n luồng",n) for n in (1,2,4,8)],default=2,width=360)
    Label(fig[8,1],"Seed",halign=:left)
    seed=Textbox(fig[8,2],stored_string="20261107",reset_on_defocus=false,width=360)
    Label(fig[9,1],"Thư mục lưu",halign=:left)
    destination=Textbox(fig[9,2],stored_string=abspath(root),reset_on_defocus=false,width=360)
    estimate=Observable("")
    Label(fig[10,1:2],estimate,fontsize=13,color="#a6b7c8",tellwidth=false)
    buttons=GridLayout(fig[11,1:2])
    runbutton=Button(buttons[1,1],label="Tạo và chạy",buttoncolor="#213044",labelcolor="#e8eef5")
    stop=Button(buttons[1,2],label="Dừng",buttoncolor="#213044",labelcolor="#e8eef5")
    openlog=Button(buttons[1,3],label="Mở nhật ký",buttoncolor="#213044",labelcolor="#e8eef5")
    openresult=Button(buttons[1,4],label="Mở kết quả",buttoncolor="#213044",labelcolor="#e8eef5")
    status=Observable("Sẵn sàng. Mỗi lần tạo dùng thư mục mới, có cấu hình và nhật ký.")
    Label(fig[12,1:2],status,fontsize=13,tellwidth=false,justification=:left,word_wrap=true)
    job=Ref{Union{Nothing,BatchJob}}(nothing)
    function config()
        experiment_config(days=parse(Int,days.displayed_string[]),truncation=resolution.selection[],layers=levels.selection[],
            output_hours=interval.selection[],threads=threads.selection[],seed=parse(Int,seed.displayed_string[]))
    end
    function update_estimate!()
        try
            c=config();e=estimate_experiment(c)
            estimate[]=@sprintf("%d khung · tệp ~%.0f MiB · RAM dữ liệu ~%.0f MiB (+ RAM ứng dụng)\nTăng T/số tầng làm tăng phép tính; chu kỳ ghi chỉ đổi lượng đầu ra.\nGPU dựng hình qua OpenGL; tính mô hình hiện dùng CPU.",e.frames,e.disk_mib,e.viewer_ram_mib)
        catch err
            estimate[]="Kiểm tra số ngày/seed: "*first(sprint(showerror,err),120)
        end
    end
    for value in (days.displayed_string,seed.displayed_string,resolution.selection,levels.selection,interval.selection,threads.selection)
        on(_->update_estimate!(),value)
    end
    on(runbutton.clicks) do _
        try
            job[]!==nothing && process_running(job[].process) && error("Phiên đang chạy; hãy dừng hoặc chờ hoàn tất.")
            job[]=start_batch(config();root=destination.displayed_string[])
            status[]="Đang khởi tạo/biên dịch…\n$(job[].directory)"
        catch err
            status[]=first(sprint(showerror,err),240)
        end
    end
    on(stop.clicks) do _
        try
            job[]===nothing || stop_batch!(job[])
        catch err
            status[]="Không thể dừng phiên: "*first(sprint(showerror,err),220)
        end
    end
    on(openlog.clicks) do _
        try
            target = nothing
            if job[] !== nothing
                logf = joinpath(job[].directory, "worker.log")
                target = isfile(logf) ? logf : job[].directory
            else
                setuplog = joinpath(@__DIR__, "simulation_setup.log")
                target = isfile(setuplog) ? setuplog : @__DIR__
            end
            open_path(target)
        catch err
            status[]="Không thể mở nhật ký: "*sprint(showerror,err)
        end
    end
    function poll!()
        job[]===nothing && return
        s=batch_status(job[])
        state=s["state"]
        if state == "complete"
            status[] = "Đã hoàn tất và kiểm chứng. Bấm Mở kết quả.\n$(s["output_path"])"
        elseif state == "stopped"
            status[] = get(s, "error", "Đã dừng bởi người dùng.")
        elseif state == "error"
            err_text = get(s, "error", "Tiến trình gặp lỗi.")
            status[] = "LỖI: $(first(err_text,280))\n(Bấm 'Mở nhật ký' để kiểm tra chi tiết)"
        else
            phase=get(s,"phase","")
            if phase=="loading"
                status[]="Đang nạp thư viện / biên dịch Julia…\nNhật ký: $(job[].directory)"
            elseif phase=="initializing"
                status[]="Đang khởi tạo mô hình…\nNhật ký: $(job[].directory)"
            elseif phase=="validating"
                status[]="Tích phân $(get(s,"percent",0))% · Đang kiểm chứng đầu ra.\nChưa công bố kết quả. Nhật ký: $(job[].directory)"
            elseif phase=="integrating"
                eta=get(s,"eta_seconds",-1)
                timing=eta<0 ? "ETA chưa xác định" : "ETA ước tính ~$(ceil(Int,eta/60)) phút"
                status[]=@sprintf("Tích phân %d%% · %.1f / %.1f giờ mô hình · %s\nNhật ký: %s",s["percent"],s["hours_done"],s["hours_total"],timing,job[].directory)
            elseif !isempty(get(s,"progress",""))
                prog=s["progress"]
                status[] = "Đang tính [$prog]\nNhật ký: $(job[].directory)"
            else
                status[] = "Đang tính / lần đầu có thể mất vài phút để biên dịch.\nNhật ký: $(job[].directory)"
            end
        end
        s
    end
    on(openresult.clicks) do _
        try
            job[]===nothing && error("Chưa có phiên.")
            s=batch_status(job[])
            s["state"]=="complete" || error("Kết quả chưa hoàn tất/kiểm chứng.")
            project=abspath(@__DIR__)
            command=`$(Base.julia_cmd()) --threads=2 --project=$project $(joinpath(project,"viewer.jl")) $(s["output_path"])`
            run(command;wait=false)
        catch err
            status[]=first(sprint(showerror,err),220)
        end
    end
    update_estimate!()
    (;fig,days,resolution,levels,interval,threads,seed,destination,estimate,runbutton,stop,openlog,openresult,status,job,poll!,config)
end

function launch_setup()
    setuplog = joinpath(@__DIR__, "simulation_setup.log")
    try
        open(setuplog, "a") do io
            println(io, "[$(Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"))] Khởi chạy simulation_setup GUI...")
            flush(io)
        end
        setup=build_simulation_setup();screen=display(setup.fig)
        try
            while isopen(screen)
                sleep(0.25)
                try
                    setup.poll!()
                catch err
                    setup.status[]=first(sprint(showerror,err),220)
                end
            end
        finally
            setup.job[]===nothing || stop_batch!(setup.job[])
            close(screen)
        end
    catch err
        bt = catch_backtrace()
        open(setuplog, "a") do io
            println(io, "\n[$(Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"))] [LỖI KHỞI ĐỘNG GUI]")
            showerror(io, err, bt)
            println(io, "\n" * "="^70)
            flush(io)
        end
        rethrow()
    end
end

if abspath(PROGRAM_FILE)==@__FILE__
    launch_setup()
end
