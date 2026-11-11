module TerraFluxLive
using TOML
include("process_control.jl")
using .TerraFluxProcessControl
include("thermal_patch.jl")
using .TerraFluxThermalPatch
include("vortex_profiles.jl")
using .TerraFluxVortexProfiles
include("saved_sessions.jl")
using .TerraFluxSavedSessions
export LiveSession, start_session, resume_session, send_command!, read_status, stop_session!, atomic_toml

mutable struct LiveSession
    directory::String
    process::Base.Process
    sequence::Int
end

function atomic_toml(path, data)
    temporary = path * ".tmp"
    open(temporary,"w") do io
        TOML.print(io,data)
    end
    mv(temporary,path;force=true)
end

function start_session(; root=joinpath(@__DIR__,"..","sessions"), max_chunks=40,truncation=32,layers=8)
    max_chunks isa Integer && 1<=max_chunks<=1460 || throw(ArgumentError("Số bước phải là số nguyên 1–1460."))
    truncation in (21,32,63,85) && layers in (8,16,24,32) || throw(ArgumentError("Cấu hình lưới/tầng không hỗ trợ."))
    config=Dict("truncation"=>truncation,"layers"=>layers,"chunk_hours"=>6,"max_chunks"=>max_chunks,
        "model"=>"PrimitiveWetModel","initial_mslp"=>"unavailable_before_surface_diagnostics",
        "julia_version"=>string(VERSION),"created_at"=>string(time()))
    spawn_session(config,root)
end
function resume_session(path;root=joinpath(@__DIR__,"..","sessions"),keep_open_at_limit=false)
    meta=saved_manifest(path;verify=false) # Worker verifies all hashes before deserializing state.
    config=Dict{String,Any}(meta["config"])
    config["resume_from"]=saved_manifest_path(path)
    config["model"]="PrimitiveWetModel"
    config["julia_version"]=string(VERSION)
    keep_open_at_limit && (config["keep_open_at_limit"]=true)
    spawn_session(config,root)
end
function spawn_session(config,root)
    mkpath(root)
    directory = mktempdir(abspath(root);prefix="session_",cleanup=false)
    mkpath(joinpath(directory,"commands"))
    atomic_toml(joinpath(directory,"config.toml"),config)
    atomic_toml(joinpath(directory,"status.toml"),Dict("state"=>"starting","completed"=>0,"files"=>String[]))
    project = abspath(joinpath(@__DIR__,".."))
    worker = joinpath(@__DIR__,"live_worker.jl")
    cmd = `$(Base.julia_cmd()) --startup-file=no --threads=2 --project=$project $worker $directory`
    process = open(joinpath(directory,"worker.log"),"w") do io
        run(pipeline(addenv(Cmd(cmd;dir=directory),"OPENBLAS_NUM_THREADS"=>"1"),stdin=devnull,stdout=io,stderr=io);wait=false)
    end
    LiveSession(directory,process,0)
end

function send_command!(session::LiveSession, action::String;patch=nothing)
    action in ("run","pause","step","stop","thermal","vortex","undo_thermal","undo_edit","save") || throw(ArgumentError("Lệnh không hỗ trợ: $action"))
    process_running(session.process) || error("Tiến trình mô phỏng đã kết thúc. Xem $(joinpath(session.directory,"worker.log"))")
    if action in ("thermal","vortex","undo_thermal","undo_edit","save")
        status=read_status(session)
        status["state"]=="paused" && get(status,"sequence",0)==session.sequence || error("Lưu/can thiệp chỉ dùng khi đã tạm dừng và xử lý xong lệnh trước.")
    end
    spec=action=="thermal" ? thermal_spec(;patch...) : action=="vortex" ? vortex_spec(;patch...) : nothing
    sequence=session.sequence+1
    command = Dict{String,Any}("sequence"=>sequence,"action"=>action)
    spec===nothing || (command["patch"]=Dict(string(k)=>v for (k,v) in pairs(spec)))
    atomic_toml(joinpath(session.directory,"commands",lpad(string(sequence),6,'0')*".toml"),command)
    session.sequence=sequence
end

"Apply queued edits in order; an explicit stop cancels work not yet started."
function next_command(directory,sequence)
    folder=joinpath(directory,"commands")
    names=filter(readdir(folder)) do name
        n=endswith(name,".toml") ? tryparse(Int,splitext(name)[1]) : nothing
        n!==nothing && n>sequence
    end
    isempty(names) && return nothing
    sort!(names;by=n->parse(Int,splitext(n)[1]))
    latest=TOML.parsefile(joinpath(folder,last(names)))
    latest["action"]=="stop" ? latest : TOML.parsefile(joinpath(folder,first(names)))
end

function read_status(session::LiveSession)
    # Windows may briefly remove the old destination during replacement.
    status = nothing
    for attempt in 1:4
        try
            status = TOML.parsefile(joinpath(session.directory,"status.toml"))
            break
        catch
            attempt == 4 && rethrow()
            sleep(0.01)
        end
    end
    if process_exited(session.process) && !(status["state"] in ("complete","stopped","error"))
        status["state"] = "error"
        status["error"] = "Tiến trình kết thúc ngoài dự kiến (exit $(session.process.exitcode)). Xem worker.log trong thư mục phiên."
    end
    status
end

function stop_session!(session::LiveSession; timeout=3.0)
    if process_running(session.process)
        sent=try
            send_command!(session,"stop");true
        catch
            false # Missing/unwritable command folders must not leave a model running.
        end
        stop_process!(session.process;grace=sent ? timeout : 0.)
    end
    nothing
end
end
