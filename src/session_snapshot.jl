module TerraFluxSessionSnapshot
using SpeedyWeather,Dates,Random,TOML
using ..TerraFluxLive.TerraFluxSavedSessions
using ..TerraFluxThermalModel
using ..TerraFluxData
export save_session_bundle, restore_session_bundle!

function save_session_bundle(sim,directory,config,files;pending_edit,undo_file,undo_previous_pending,edit_summary,sequence)
    !isempty(files) || error("Tính ít nhất +6 giờ trước khi lưu phiên.")
    rng=copy(Random.default_rng());staging=""
    try
        root=joinpath(dirname(directory),"saved_sessions");mkpath(root)
        staging=mktempdir(root;prefix=".saving_",cleanup=false)
        mkpath(joinpath(staging,"history"))
        history=String[]
        for (i,file) in enumerate(files)
            name="history/chunk_$(lpad(string(i),6,'0')).nc"
            cp(file,payload_path(staging,name));push!(history,name)
        end
        has_undo=!isempty(undo_file)
        has_undo && cp(undo_file,joinpath(staging,"undo.jld2"))
        journal=String[]
        function archive_record(source,name)
            target=payload_path(staging,name);mkpath(dirname(target));cp(source,target)
            push!(journal,name)
        end
        provenance=joinpath(directory,"provenance")
        if isdir(provenance)
            for (folder,_,names) in walkdir(provenance),name in names
                endswith(name,".toml") || continue
                source=joinpath(folder,name)
                archive_record(source,"journal/"*replace(relpath(source,provenance),'\\'=>'/'))
            end
        end
        for name in readdir(joinpath(directory,"commands"))
            n=endswith(name,".toml") ? tryparse(Int,splitext(name)[1]) : nothing
            n!==nothing && n<=sequence || continue
            archive_record(joinpath(directory,"commands",name),"journal/$(basename(directory))/commands/$name")
            event=joinpath(directory,"edits",lpad(string(n),6,'0'),"event.toml")
            isfile(event) && archive_record(event,"journal/$(basename(directory))/events/$name")
        end
        # Filesystem helpers must not shift the model's random stream.
        copy!(Random.default_rng(),rng)
        save_checkpoint(sim,joinpath(staging,"state.jld2"))
        names=vcat(["state.jld2"],history,has_undo ? ["undo.jld2"] : String[],journal)
        meta=Dict("format"=>"terraflux.saved-session","format_version"=>1,
            "model"=>"PrimitiveWetModel","backend"=>"CPU","julia_version"=>string(VERSION),
            "speedyweather_version"=>string(pkgversion(SpeedyWeather)),
            "created_utc"=>string(Dates.now(Dates.UTC)),"source_session"=>basename(directory),
            "config"=>Dict(k=>config[k] for k in ("truncation","layers","chunk_hours","max_chunks")),
            "completed"=>length(files),"model_time"=>string(sim.variables.prognostic.clock.time),
            "pending_edit"=>pending_edit,"undo_available"=>has_undo,
            "undo_previous_pending"=>undo_previous_pending,"edit_summary"=>edit_summary,
            "history"=>history,"journal"=>journal,"payloads"=>[payload_entry(staging,n) for n in names])
        open(joinpath(staging,"session.toml"),"w") do io;TOML.print(io,meta);end
        saved_manifest(joinpath(staging,"session.toml"))
        destination=joinpath(root,replace(basename(staging),".saving_"=>"saved_"))
        mv(staging,destination)
        joinpath(destination,"session.toml")
    catch
        !isempty(staging) && isdir(staging) && rm(staging;recursive=true)
        rethrow()
    finally
        copy!(Random.default_rng(),rng)
    end
end

function restore_session_bundle!(sim,path,directory)
    meta=saved_manifest(path)
    root=dirname(saved_manifest_path(path));history_dir=joinpath(directory,"history");mkpath(history_dir)
    files=String[]
    previous=nothing
    for name in meta["history"]
        target=joinpath(history_dir,basename(name))
        cp(payload_path(root,name),target);push!(files,target)
        data=load_weather(target)
        length(data.times)==2 && data.times[end]-data.times[1]==Hour(6) || error("Đoạn lịch sử không đủ hai mốc 6 giờ.")
        previous===nothing || previous==data.times[1] || error("Lịch sử bản lưu không liên tục.")
        output_grid=sim.model.output.field2D.grid
        length(data.layers)==sim.model.geometry.nlayers && length(data.lon)==SpeedyWeather.RingGrids.get_nlon_max(output_grid) && length(data.lat)==SpeedyWeather.RingGrids.get_nlat(output_grid) || error("Lưới/tầng đầu ra không khớp bản lưu.")
        previous=data.times[end]
    end
    string(previous)==meta["model_time"] || error("Mốc cuối lịch sử không khớp checkpoint.")
    undo=get(meta,"undo_available",false) ? joinpath(directory,"restored_undo.jld2") : ""
    isempty(undo) || cp(joinpath(root,"undo.jld2"),undo)
    for name in get(meta,"journal",String[])
        target=joinpath(directory,"provenance",split(name,'/')[2:end]...)
        mkpath(dirname(target));cp(payload_path(root,name),target)
    end
    restore_checkpoint!(sim,joinpath(root,"state.jld2"))
    string(sim.variables.prognostic.clock.time)==meta["model_time"] || error("Đồng hồ checkpoint không khớp bản lưu.")
    sim.variables.prognostic.scale[]==1 || error("Checkpoint không ở trạng thái giữa các đoạn tính.")
    for name in (:temperature,:humidity,:vorticity,:divergence,:pressure)
        all(isfinite,getproperty(sim.variables.prognostic,name)) || error("Checkpoint chứa trường không hữu hạn: $name")
    end
    (;meta,files,undo)
end
end
