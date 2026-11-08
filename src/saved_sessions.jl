module TerraFluxSavedSessions
using TOML,SHA,Dates
export saved_manifest, saved_manifest_path, payload_path, payload_entry, speedy_version
speedy_version()=TOML.parsefile(joinpath(@__DIR__,"..","Manifest.toml"))["deps"]["SpeedyWeather"][1]["version"]
saved_manifest_path(path)=isdir(path) ? joinpath(abspath(path),"session.toml") : abspath(path)
payload_path(root,name)=joinpath(root,split(name,'/')...)
function payload_entry(root,name)
    path=payload_path(root,name)
    digest=open(path,"r") do io;bytes2hex(sha256(io));end
    Dict("path"=>name,"bytes"=>filesize(path),"sha256"=>digest)
end
function saved_manifest(path;verify=true)
    file=saved_manifest_path(path)
    isfile(file) || error("Không tìm thấy session.toml: $file")
    meta=TOML.parsefile(file)
    get(meta,"format","")=="terraflux.saved-session" && get(meta,"format_version",0)==1 || error("Định dạng phiên đã lưu không hỗ trợ.")
    get(meta,"julia_version","")==string(VERSION) || error("Phiên này cần Julia $(get(meta,"julia_version","?")); hiện tại là $VERSION.")
    get(meta,"speedyweather_version","")==speedy_version() || error("Phiên bản SpeedyWeather của bản lưu không khớp project.")
    get(meta,"model","")=="PrimitiveWetModel" && get(meta,"backend","")=="CPU" || error("Chỉ khôi phục PrimitiveWetModel CPU mặc định.")
    all(k->haskey(meta,k),("config","completed","model_time","history","payloads","pending_edit","undo_available","undo_previous_pending","edit_summary")) || error("Bản lưu thiếu thông tin trạng thái.")
    all(k->meta[k] isa Bool,("pending_edit","undo_available","undo_previous_pending")) && meta["edit_summary"] isa String || error("Thông tin tác động trong bản lưu không hợp lệ.")
    c=meta["config"]
    all(k->haskey(c,k) && c[k] isa Integer && !(c[k] isa Bool),("truncation","layers","chunk_hours","max_chunks")) || error("Cấu hình bản lưu phải chứa T/tầng/bước lưu/giới hạn dạng số nguyên.")
    c["truncation"] in (21,32,63,85) && c["layers"] in (8,16,24,32) && c["chunk_hours"]==6 || error("Cấu hình lưới/tầng/bước lưu không hỗ trợ.")
    n=meta["completed"]
    n isa Integer && !(n isa Bool) && 1<=n<=c["max_chunks"]<=1460 || error("Số bước đã lưu/giới hạn phiên không hợp lệ.")
    DateTime(meta["model_time"])
    expected=["history/chunk_$(lpad(string(i),6,'0')).nc" for i in 1:n]
    meta["history"]==expected || error("Danh sách lịch sử bị thiếu hoặc sai thứ tự.")
    journal=get(meta,"journal",String[])
    all(n->n isa String && occursin(r"^journal/session_[A-Za-z0-9]+/(commands|events)/[0-9]+\.toml$",n),journal) || error("Đường dẫn nhật ký bản lưu không hợp lệ.")
    length(unique(journal))==length(journal) || error("Nhật ký bản lưu bị trùng.")
    allowed=Set(vcat(["state.jld2"],expected,get(meta,"undo_available",false) ? ["undo.jld2"] : String[],journal))
    entries=meta["payloads"]
    names=[e["path"] for e in entries]
    length(unique(names))==length(names) && Set(names)==allowed || error("Danh sách tệp trong bản lưu không khớp.")
    root=dirname(file)
    for e in entries
        target=payload_path(root,e["path"])
        isfile(target) || error("Bản lưu thiếu tệp $(e["path"]).")
        filesize(target)==e["bytes"] || error("Kích thước tệp $(e["path"]) đã thay đổi.")
        verify && payload_entry(root,e["path"])["sha256"]!=e["sha256"] && error("Tệp $(e["path"]) không khớp checksum.")
    end
    meta
end
end
