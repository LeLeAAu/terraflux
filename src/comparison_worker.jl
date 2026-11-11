using TOML,Dates
include("live.jl");using .TerraFluxLive
using .TerraFluxLive.TerraFluxSavedSessions

function worker(directory)
    file=joinpath(directory,"comparison.toml");m=TOML.parsefile(file)
    publish()=atomic_toml(file,m)
    stop_requested=Ref(false)
    if get(m,"stop_via_stdin",false)
        @async try
            for line in eachline(stdin)
                line=="STOP" && break
            end
        finally
            # STOP or EOF works even when metadata is no longer writable.
            stop_requested[]=true
        end
    end
    cancelled()=stop_requested[] || isfile(joinpath(directory,"STOP"))
    child=nothing
    function await_child(session,predicate)
        while true
            cancelled() && throw(InterruptException())
            status=read_status(session)
            if status["state"]=="error"
                m["failed_child"]=replace(relpath(session.directory,directory),'\\'=>'/')
                process_exited(session.process) && (m["child_exitcode"]=session.process.exitcode)
                error(status["error"]*" · Nhật ký: $(joinpath(session.directory,"worker.log"))")
            end
            predicate(status) && return status
            process_running(session.process) || error("Nhánh kết thúc trước khi xử lý xong lệnh.")
            sleep(0.05)
        end
    end
    ack(session)=s->s["state"]=="paused" && s["sequence"]==session.sequence
    try
        cd(directory)
        baseline=joinpath(directory,"baseline","session.toml")
        m["phase"]="copying_baseline";publish()
        source=m["source_manifest"];source_meta=saved_manifest(source)
        digest=only(e["sha256"] for e in source_meta["payloads"] if e["path"]=="state.jld2")
        digest==m["state_sha256"] && source_meta["model_time"]==m["fork_time"] &&
            source_meta["config"]["truncation"]==m["truncation"] && source_meta["config"]["layers"]==m["layers"] &&
            source_meta["completed"]+m["steps"]<=source_meta["config"]["max_chunks"] || error("Bản lưu nguồn đã đổi sau khi tạo A/B; hãy chọn lại bản lưu.")
        mkpath(dirname(baseline))
        for e in source_meta["payloads"]
            cancelled() && throw(InterruptException())
            target=payload_path(dirname(baseline),e["path"]);mkpath(dirname(target))
            cp(payload_path(dirname(source),e["path"]),target)
        end
        cp(source,baseline)
        meta=saved_manifest(baseline)
        !meta["pending_edit"] || error("Bản lưu đối chứng còn tác động chưa xuất ra mốc mới.")
        for side in ("a","b")
            cancelled() && throw(InterruptException())
            m["state"]="running";m["phase"]="initializing_"*side;publish()
            # Independent model lifetimes avoid retaining two native model/FFT caches
            # in one process; both children still restore the exact same saved state.
            child=resume_session(baseline;root=directory,keep_open_at_limit=true)
            m["child_pid"]=getpid(child.process);publish()
            await_child(child,s->s["state"]=="paused")
            if side=="b" && m["treatment"]
                m["phase"]="applying_b";publish()
                patch=(;(Symbol(k)=>v for (k,v) in m["patch"])...)
                send_command!(child,get(m,"intervention","thermal");patch)
                status=await_child(child,ack(child))
                isempty(status["command_error"]) || error(status["command_error"])
                event=TOML.parsefile(joinpath(child.directory,"edits",lpad(string(child.sequence),6,'0'),"event.toml"))
                m["effect"]=event["effect"];publish()
            end
            for step in 1:m["steps"]
                cancelled() && throw(InterruptException())
                m["phase"]="integrating_"*side;publish()
                send_command!(child,"step")
                status=await_child(child,ack(child))
                expected=DateTime(m["fork_time"])+Hour(6step)
                status["completed"]==meta["completed"]+step && status["model_time"]==string(expected) || error("Nhánh không tiến đúng mốc chung 6 giờ.")
                path=last(status["files"])
                push!(m["outputs_"*side],payload_entry(directory,replace(relpath(path,directory),'\\'=>'/')))
                publish();println("$side · $step / $(m["steps"]) · $expected");flush(stdout)
            end
            cancelled() && throw(InterruptException())
            m["phase"]="saving_"*side;publish()
            send_command!(child,"save")
            status=await_child(child,ack(child))
            isempty(status["command_error"]) && !isempty(status["last_saved"]) || error("Không lưu được nhánh: "*status["command_error"])
            m["archive_"*side]=replace(relpath(status["last_saved"],directory),'\\'=>'/');publish()
            stop_session!(child;timeout=0.3);child=nothing
        end
        m["state"]="complete";m["phase"]="complete";publish()
    catch err
        if cancelled()
            m["state"]="stopped";m["phase"]="stopped";publish()
        else
            m["state"]="error";m["phase"]="error";m["error"]=sprint(showerror,err);publish()
            rethrow()
        end
    finally
        child===nothing || stop_session!(child;timeout=0.3)
        get(m,"stop_via_stdin",false) && close(stdin)
    end
end
worker(abspath(only(ARGS)))
