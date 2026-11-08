module TerraFluxComparison
using TOML,Dates
using ..TerraFluxLive
using ..TerraFluxLive.TerraFluxSavedSessions
using ..TerraFluxLive.TerraFluxThermalPatch
using ..TerraFluxLive.TerraFluxVortexProfiles
using ..TerraFluxData
export ComparisonJob,start_comparison,comparison_status,stop_comparison!,load_comparison,
    comparison_values,comparison_path,comparison_manifest

struct ComparisonJob
    directory::String
    process::Base.Process
end
comparison_path(path)=isdir(path) ? joinpath(abspath(path),"comparison.toml") : abspath(path)
function local_payload(root,name)
    name isa String && !isempty(name) && !occursin('\\',name) && !isabspath(name) &&
        all(s->!isempty(s) && !(s in (".","..")) && !occursin(':',s),split(name,'/')) || error("Đường dẫn trong kết quả A/B không hợp lệ.")
    payload_path(root,name)
end
function comparison_manifest(path)
    file=comparison_path(path)
    isfile(file) || error("Không tìm thấy comparison.toml: $file")
    m=nothing
    for attempt in 1:4
        try
            m=TOML.parsefile(file);break
        catch
            attempt==4 && rethrow()
            sleep(0.01)
        end
    end
    get(m,"format","")=="terraflux.comparison" && get(m,"format_version",0)==1 || error("Định dạng kết quả A/B không hỗ trợ.")
    get(m,"intervention","thermal") in ("thermal","vortex") || error("Loại tác động trong kết quả A/B không hỗ trợ.")
    m["steps"] isa Integer && 1<=m["steps"]<=40 || error("Giới hạn A/B không hợp lệ.")
    DateTime(m["fork_time"])
    for side in ("a","b")
        entries=m["outputs_"*side]
        length(entries)<=m["steps"] || error("Quá nhiều đầu ra A/B.")
        names=[e["path"] for e in entries]
        length(unique(names))==length(names) || error("Đầu ra A/B bị lặp.")
        for name in names
            local_payload(dirname(file),name)
            endswith(name,".nc") || error("Đầu ra A/B không phải NetCDF.")
        end
    end
    m["state"]=="complete" && !(length(m["outputs_a"])==length(m["outputs_b"])==m["steps"]) && error("Kết quả A/B chưa đủ mốc để hoàn tất.")
    m
end
function start_comparison(path;patch=nothing,treatment=true,intervention="thermal",steps=4,root=joinpath(@__DIR__,"..","sessions","comparisons"))
    steps isa Integer && !(steps isa Bool) && 1<=steps<=40 || error("Chọn 1–40 bước, mỗi bước 6 giờ.")
    treatment isa Bool || error("Lựa chọn can thiệp không hợp lệ.")
    source=saved_manifest_path(path);meta=saved_manifest(source;verify=false)
    !meta["pending_edit"] || error("Bản lưu còn tác động chờ mốc mới. Tính thêm +6 giờ rồi lưu để có mốc đối chứng rõ ràng.")
    meta["completed"]+steps<=meta["config"]["max_chunks"] || error("Số bước vượt thời lượng còn lại của bản lưu.")
    intervention in ("thermal","vortex") || error("Loại tác động A/B không hỗ trợ.")
    spec=treatment ? (intervention=="thermal" ? thermal_spec(;patch...) : vortex_spec(;patch...)) : nothing
    spec===nothing || intervention=="vortex" || spec.layer<=meta["config"]["layers"] || error("Tầng can thiệp không có trong bản lưu.")
    mkpath(root);directory=mktempdir(abspath(root);prefix="ab_",cleanup=false)
    # Hashing/copying long histories belongs in the worker, keeping the form responsive.
    config=Dict{String,Any}("format"=>"terraflux.comparison","format_version"=>1,
        "steps"=>steps,"treatment"=>treatment,"intervention"=>intervention,"fork_time"=>meta["model_time"],
        "truncation"=>meta["config"]["truncation"],"layers"=>meta["config"]["layers"],
        "source_manifest"=>source,"state_sha256"=>only(e["sha256"] for e in meta["payloads"] if e["path"]=="state.jld2"),
        "julia_version"=>string(VERSION),"speedyweather_version"=>speedy_version(),
        "created_utc"=>string(now(UTC)),"state"=>"starting","phase"=>"loading",
        "error"=>"","outputs_a"=>Any[],"outputs_b"=>Any[],"archive_a"=>"","archive_b"=>"")
    spec===nothing || (config["patch"]=Dict(string(k)=>v for (k,v) in pairs(spec)))
    atomic_toml(joinpath(directory,"comparison.toml"),config)
    project=abspath(joinpath(@__DIR__,".."))
    cmd=`$(Base.julia_cmd()) --startup-file=no --threads=2 --project=$project $(joinpath(@__DIR__,"comparison_worker.jl")) $directory`
    process=open(joinpath(directory,"worker.log"),"w") do io
        run(pipeline(addenv(Cmd(cmd;dir=directory),"OPENBLAS_NUM_THREADS"=>"1"),stdout=io,stderr=io);wait=false)
    end
    ComparisonJob(directory,process)
end
function comparison_status(job)
    m=try
        comparison_manifest(job.directory)
    catch err
        return Dict{String,Any}("state"=>"error","phase"=>"error","outputs_a"=>Any[],"outputs_b"=>Any[],
            "steps"=>0,"fork_time"=>"?","error"=>"Không đọc được kết quả A/B: "*sprint(showerror,err))
    end
    if process_exited(job.process) && !(m["state"] in ("complete","error","stopped"))
        m["state"]="error";m["error"]="Worker A/B kết thúc ngoài dự kiến. Xem worker.log."
    end
    m
end
function stop_comparison!(job;timeout=6.)
    if process_running(job.process)
        write(joinpath(job.directory,"STOP"),"stop")
        if timedwait(()->process_exited(job.process),timeout;pollint=0.05)==:timed_out
            kill(job.process)
            # Julia can stall while handling SIGTERM during native compilation.
            if timedwait(()->process_exited(job.process),2.;pollint=0.05)==:timed_out
                kill(job.process,Base.SIGKILL)
            end
        end
        wait(job.process)
    end
    m=try;comparison_manifest(job.directory);catch;return nothing;end
    if !(m["state"] in ("complete","error","stopped"))
        m["state"]="stopped";m["phase"]="stopped"
        atomic_toml(joinpath(job.directory,"comparison.toml"),m)
    end
end
function load_comparison(path;verify=true)
    file=comparison_path(path);root=dirname(file);m=comparison_manifest(file)
    n=min(length(m["outputs_a"]),length(m["outputs_b"]))
    n>0 || error("Chưa có mốc mới chung cho A và B.")
    data=WeatherData[]
    for side in ("a","b")
        paths=String[]
        for e in m["outputs_"*side][1:n]
            target=local_payload(root,e["path"])
            isfile(target) && filesize(target)==e["bytes"] || error("Tệp kết quả A/B thiếu hoặc đã đổi kích thước.")
            verify && payload_entry(root,e["path"])["sha256"]!=e["sha256"] && error("Checksum đầu ra A/B không khớp.")
            push!(paths,target)
        end
        d=load_live_history(paths)
        d.times[1]==DateTime(m["fork_time"]) || error("Mốc xuất phát A/B không khớp.")
        length(d.layers)==m["layers"] || error("Số tầng kết quả A/B không khớp.")
        push!(data,d)
    end
    a,b=data
    a.lon==b.lon && a.lat==b.lat && a.layers==b.layers && a.times==b.times || error("A/B phải cùng lưới, tầng và thời gian; không tự nội suy.")
    (;a,b,times=a.times[2:end],meta=m,path=file)
end
function comparison_values(result,field,layer,time)
    checkbounds(result.times,time)
    a=frame(result.a,field,layer,time+1);b=frame(result.b,field,layer,time+1)
    (;a,b,delta=b.-a)
end
end
