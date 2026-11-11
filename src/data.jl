module TerraFluxData
using SpeedyWeather: NCDataset, NCDatasets
using Dates
export WeatherData, load_weather, frame, color_limits, nearest_cell, sample_value,
       FIELDS, field_label, field_unit, layer_label, append_weather, load_live_chunk, load_live_history, finite_extrema, is_surface_field, field_context

const FIELDS = [:temp, :wind, :u, :v, :humid, :mslp, :rh, :sst, :lst]
const LABELS = Dict(:temp => "Nhiệt độ không khí (theo tầng)", :sst => "Nhiệt độ mặt biển (SST)", :lst => "Nhiệt độ mặt đất (lớp trên cùng)", :wind => "Tốc độ gió", :u => "Gió Đông–Tây (u)",
    :v => "Gió Bắc–Nam (v)", :humid => "Độ ẩm riêng", :mslp => "Áp suất quy mực biển", :rh=>"Độ ẩm tương đối")
const UNITS = Dict(:sst => "°C", :lst => "°C", :temp => "°C", :wind => "m/s", :u => "m/s", :v => "m/s", :humid => "g/kg", :mslp => "hPa", :rh=>"%")
field_label(field) = LABELS[field]
field_unit(field) = UNITS[field]
is_surface_field(f) = f in (:mslp, :pres, :sst, :lst)
function field_context(d,f,k)
    f==:sst && return "Mặt biển · Không phụ thuộc tầng khí quyển"
    f==:lst && return "Lớp đất trên cùng · Không phụ thuộc tầng khí quyển"
    f==:mslp && return "Quy về mực biển · Không phụ thuộc tầng chọn"
    layer_label(d,k)
end

struct WeatherData
    path::String
    lon::Vector{Float64}
    lat::Vector{Float64}
    layers::Vector{Float64}
    times::Vector{DateTime}
    fields::Dict{Symbol, Array{Float32}}
end

"Read and close NetCDF; normalize longitude and latitude ordering together with the data."
function load_weather(path::AbstractString)
    isfile(path) || error("Không tìm thấy dữ liệu: $path")
    NCDataset(path, "r") do ds
        required = ("lon", "lat", "layer", "time", "temp", "u", "v", "humid", "mslp")
        all(n -> haskey(ds, n), required) || error("Tệp thiếu tọa độ hoặc trường khí tượng cần thiết.")
        lon = mod.(Float64.(ds["lon"][:]) .+ 180, 360) .- 180
        lat = Float64.(ds["lat"][:])
        ix, iy = sortperm(lon), sortperm(lat)
        lon, lat = lon[ix], lat[iy]
        layers = Float64.(ds["layer"][:])
        times = DateTime.(ds["time"][:])
        length(lon) >= 2 && length(lat) >= 2 && !isempty(layers) && !isempty(times) || error("Lưới dữ liệu rỗng hoặc quá nhỏ.")
        all(isfinite, lon) && all(isfinite, lat) && all(isfinite, layers) || error("Tọa độ không hữu hạn.")
        all(diff(lon) .> 0) && all(diff(lat) .> 0) || error("Tọa độ lưới phải khác nhau.")
        all(i->times[i]>times[i-1],2:length(times)) || error("Thời gian phải tăng và không được lặp.")
        fields = Dict{Symbol, Array{Float32}}()
        expected_units = Dict(:temp => ("degC", "K", "°C"), :u => ("m/s",), :v => ("m/s",),
            :humid => ("kg/kg", "g/kg"), :mslp => ("hPa", "Pa"))
        for name in (:temp, :u, :v, :humid, :mslp)
            v = ds[string(name)]
            units = get(v.attrib, "units", "")
            units in expected_units[name] || error("Đơn vị không hỗ trợ cho $name: $units")
            dims = name == :mslp ? ("lon", "lat", "time") : ("lon", "lat", "layer", "time")
            NCDatasets.dimnames(v) == dims || error("Thứ tự chiều không hỗ trợ cho $name")
            values = Float32.(coalesce.(v[ntuple(_ -> Colon(), ndims(v))...], NaN32))
            shape = name == :mslp ? (length(lon), length(lat), length(times)) :
                (length(lon), length(lat), length(layers), length(times))
            size(values) == shape || error("Kích thước trường $name không khớp tọa độ: $(size(values))")
            values = name == :mslp ? values[ix, iy, :] : values[ix, iy, :, :]
            name == :temp && units == "K" && (values .-= 273.15f0)
            name == :humid && units == "kg/kg" && (values .*= 1000f0)
            name == :mslp && units == "Pa" && (values ./= 100f0)
            fields[name] = values
        end
        if haskey(ds,"pres")
            variable=ds["pres"]
            unit=get(variable.attrib,"units","")
            unit in ("Pa","hPa") || error("Đơn vị áp suất bề mặt không hỗ trợ: $unit")
            NCDatasets.dimnames(variable)==("lon","lat","time") || error("Chiều áp suất bề mặt không hợp lệ.")
            values=Float32.(coalesce.(variable[:,:,:],NaN32))[ix,iy,:]
            size(values)==size(fields[:mslp]) || error("Áp suất bề mặt không khớp lưới.")
            unit=="Pa" && (values./=100f0)
            fields[:pres]=values
        end
        # Surface temperatures are prognostic fields, separate from atmospheric temp.
        # Keep coastal land/ocean components wherever their area fraction is nonzero.
        if haskey(ds,"lsm")
            maskvar=ds["lsm"]
            NCDatasets.dimnames(maskvar)==("lon","lat") || error("Chiều mặt nạ đất/biển không hợp lệ.")
            mask=Float32.(coalesce.(maskvar[:,:],NaN32))[ix,iy]
            size(mask)==(length(lon),length(lat)) || error("Lưới mặt nạ đất/biển không khớp.")
            all(x->isfinite(x) && 0<=x<=1,mask) || error("Tỷ lệ đất phải trong [0,1].")
            for (field,name) in ((:sst,"sst"),(:lst,"st"))
                haskey(ds,name) || continue
                v=ds[name];unit=get(v.attrib,"units","")
                unit in ("K","degC","°C") || error("Đơn vị nhiệt độ bề mặt không hỗ trợ: $unit")
                dims=field==:sst ? ("lon","lat","time") : ("lon","lat","soil_layer","time")
                NCDatasets.dimnames(v)==dims || error("Chiều nhiệt độ bề mặt không hợp lệ: $name")
                field==:lst && size(v,3)<1 && error("Không có lớp đất trên cùng.")
                raw=field==:sst ? v[:,:,:] : v[:,:,1,:]
                values=Float32.(coalesce.(raw,NaN32))[ix,iy,:]
                size(values)==size(fields[:mslp]) || error("Lưới nhiệt độ bề mặt không khớp.")
                unit=="K" && (values .-= 273.15f0)
                for t in axes(values,3), j in axes(values,2), i in axes(values,1)
                    active=field==:sst ? mask[i,j]<1 : mask[i,j]>0
                    active || (values[i,j,t]=NaN32)
                end
                fields[field]=values
            end
        end
        if get(ds.attrib,"terraflux_initial_surface_diagnostics","")=="unavailable"
            fields[:mslp][:,:,1].=NaN32
            haskey(fields,:pres) && (fields[:pres][:,:,1].=NaN32)
        end
        WeatherData(abspath(path), lon, lat, layers, times, fields)
    end
end

# RH with respect to liquid water, using Bolton (1980) saturation vapour pressure.
@inline function relative_humidity(T,q,p,sigma)
    isfinite(T) && isfinite(q) && isfinite(p) && T> -100 && T<100 && q>=0 && q<1000 && p>0 || return NaN32
    specific=Float64(q)/1000
    vapor=specific*(sigma*p)/(0.622+0.378specific)
    saturation=6.112exp(17.67T/(T+243.5))
    Float32(100vapor/saturation)
end
function frame(d::WeatherData, field::Symbol, layer::Int, time::Int)
    checkbounds(d.layers,layer);checkbounds(d.times,time)
    field==:wind && return hypot.(@view(d.fields[:u][:,:,layer,time]),@view(d.fields[:v][:,:,layer,time]))
    if field==:rh
        haskey(d.fields,:pres) && 0<d.layers[layer]<=1 || return fill(NaN32,length(d.lon),length(d.lat))
        # Actual sigma pressure, never MSLP. The scalar and full-frame paths share arithmetic.
        return relative_humidity.(@view(d.fields[:temp][:,:,layer,time]),
            @view(d.fields[:humid][:,:,layer,time]),@view(d.fields[:pres][:,:,time]),d.layers[layer])
    end
    field in (:sst,:lst) && !haskey(d.fields,field) && return fill(NaN32,length(d.lon),length(d.lat))
    a=d.fields[field]
    is_surface_field(field) ? a[:,:,time] : a[:,:,layer,time]
end

"Finite extrema without allocating a filtered array; nothing means all values are missing."
function finite_extrema(values)
    lo=Inf32;hi=-Inf32
    for x in values
        if isfinite(x);lo=min(lo,x);hi=max(hi,x);end
    end
    lo==Inf32 ? nothing : (lo,hi)
end
function finite_extrema(values::AbstractArray)
    lo=Inf32;hi=-Inf32
    @inbounds @simd for i in eachindex(values)
        x=values[i]
        lo=min(lo,ifelse(isfinite(x),x,Inf32))
        hi=max(hi,ifelse(isfinite(x),x,-Inf32))
    end
    lo==Inf32 ? nothing : (lo,hi)
end
# Function barriers retain concrete array ranks outside WeatherData's heterogeneous
# dictionary, so spatial-plane scans use contiguous indexing without boxing views.
function frame_extrema(values_at,times)
    lo=Inf32;hi=-Inf32
    for time in times
        bounds=finite_extrema(values_at(time))
        bounds===nothing && continue
        lo=min(lo,bounds[1]);hi=max(hi,bounds[2])
    end
    lo==Inf32 ? nothing : (lo,hi)
end
function raw_extrema(a,layer,times)
    frame_extrema(times) do t
        ndims(a)==3 ? @view(a[:,:,t]) : @view(a[:,:,layer,t])
    end
end
function wind_extrema(u,v,layer,times)
    frame_extrema(times) do t
        (hypot(a,b) for (a,b) in zip(@view(u[:,:,layer,t]),@view(v[:,:,layer,t])))
    end
end
function humidity_extrema(temp,q,p,sigma,layer,times)
    frame_extrema(times) do t
        (relative_humidity(a,b,c,sigma) for (a,b,c) in zip(@view(temp[:,:,layer,t]),@view(q[:,:,layer,t]),@view(p[:,:,t])))
    end
end
function color_limits(d,field,layer,time;locked=true)
    checkbounds(d.layers,layer);checkbounds(d.times,time)
    field in (:sst,:lst) && !haskey(d.fields,field) && return (0f0,1f0)
    times=locked ? eachindex(d.times) : (time:time)
    bounds=if field==:wind
        wind_extrema(d.fields[:u],d.fields[:v],layer,times)
    elseif field==:rh
        haskey(d.fields,:pres) && 0<d.layers[layer]<=1 || return (0f0,1f0)
        humidity_extrema(d.fields[:temp],d.fields[:humid],d.fields[:pres],d.layers[layer],layer,times)
    else
        raw_extrema(d.fields[field],layer,times)
    end
    bounds===nothing && return (0f0,1f0)
    lo,hi=bounds
    if field in (:u,:v)
        bound=max(abs(lo),abs(hi),1f-3)
        return (-bound,bound)
    end
    lo==hi ? (lo-0.5f0,hi+0.5f0) : (lo,hi)
end

function nearest_cell(d,lon,lat)
    x=mod(lon+180,360)-180;y=clamp(lat,-90,90)
    ix=iy=1;dx=dy=Inf
    for i in eachindex(d.lon)
        delta=abs(d.lon[i]-x);distance=min(delta,360-delta)
        if distance<dx;ix=i;dx=distance;end
    end
    for j in eachindex(d.lat)
        distance=abs(d.lat[j]-y)
        if distance<dy;iy=j;dy=distance;end
    end
    (ix,iy)
end
function sample_value(d,field,layer,time,lon,lat)
    checkbounds(d.layers,layer);checkbounds(d.times,time)
    field in (:sst,:lst) && !haskey(d.fields,field) && return NaN32
    i,j=nearest_cell(d,lon,lat)
    field==:wind && return hypot(d.fields[:u][i,j,layer,time],d.fields[:v][i,j,layer,time])
    if field==:rh
        haskey(d.fields,:pres) && 0<d.layers[layer]<=1 || return NaN32
        return relative_humidity(d.fields[:temp][i,j,layer,time],d.fields[:humid][i,j,layer,time],d.fields[:pres][i,j,time],d.layers[layer])
    end
    is_surface_field(field) ? d.fields[field][i,j,time] : d.fields[field][i,j,layer,time]
end
layer_label(d, k) = "Tầng $k / $(length(d.layers)) · σ = $(round(d.layers[k]; digits=4))"

function append_weather(a::WeatherData, b::WeatherData)
    (a.lon == b.lon && a.lat == b.lat && a.layers == b.layers) || error("Lưới phiên mô phỏng đã thay đổi.")
    setdiff(Set(keys(a.fields)),(:sst,:lst))==setdiff(Set(keys(b.fields)),(:sst,:lst)) || error("Các trường trong đoạn mô phỏng đã thay đổi.")
    b.times[1] == a.times[end] || error("Các đoạn mô phỏng không nối tiếp nhau.")
    length(b.times) > 1 || error("Đoạn mô phỏng không có thời gian mới.")
    fields = Dict{Symbol,Array{Float32}}()
    for f in union(keys(a.fields),keys(b.fields))
        left=get(a.fields,f,nothing)
        right=get(b.fields,f,nothing)
        left===nothing && (left=fill(NaN32,length(a.lon),length(a.lat),length(a.times)))
        right===nothing && (right=fill(NaN32,length(b.lon),length(b.lat),length(b.times)))
        new = is_surface_field(f) ? right[:,:,2:end] : right[:,:,:,2:end]
        fields[f] = cat(left,new;dims=ndims(new))
    end
    WeatherData(b.path,a.lon,a.lat,a.layers,vcat(a.times,b.times[2:end]),fields)
end


"SpeedyWeather has not computed surface-air diagnostics for initial MSLP at t=0."
function load_live_chunk(path; initial=false)
    d = load_weather(path)
    initial && (d.fields[:mslp][:,:,1] .= NaN32)
    initial && haskey(d.fields,:pres) && (d.fields[:pres][:,:,1].=NaN32)
    d
end

"Load archived two-frame chunks with one allocation per field, preserving initial missing data."
function load_live_history(paths)
    isempty(paths) && error("Phiên chưa có lịch sử đầu ra.")
    first=load_live_chunk(paths[1];initial=true)
    length(first.times)==2 && first.times[2]-first.times[1]==Hour(6) || error("Đoạn đầu không có đúng hai mốc 6 giờ.")
    times=Vector{DateTime}(undef,length(paths)+1);times[1:2]=first.times
    fields=Dict{Symbol,Array{Float32}}()
    for (f,a) in first.fields
        dims=Base.setindex(size(a),length(times),ndims(a))
        fields[f]=similar(a,dims)
        selectdim(fields[f],ndims(a),1).=selectdim(a,ndims(a),1)
        selectdim(fields[f],ndims(a),2).=selectdim(a,ndims(a),2)
    end
    for i in 2:length(paths)
        chunk=load_live_chunk(paths[i])
        chunk.lon==first.lon && chunk.lat==first.lat && chunk.layers==first.layers && setdiff(Set(keys(chunk.fields)),(:sst,:lst))==setdiff(Set(keys(fields)),(:sst,:lst)) || error("Lưới/trường trong lịch sử không khớp.")
        length(chunk.times)==2 && chunk.times[1]==times[i] && chunk.times[2]-chunk.times[1]==Hour(6) || error("Lịch sử phiên không liên tục theo bước 6 giờ.")
        times[i+1]=chunk.times[2]
        for f in (:sst,:lst)
            if haskey(chunk.fields,f) && !haskey(fields,f)
                fields[f]=fill(NaN32,length(first.lon),length(first.lat),length(times))
            end
        end
        for (f,a) in fields
            if haskey(chunk.fields,f)
                source=chunk.fields[f]
                selectdim(a,ndims(a),i+1).=selectdim(source,ndims(source),2)
            else
                selectdim(a,ndims(a),i+1).=NaN32
            end
        end
    end
    WeatherData(abspath(last(paths)),first.lon,first.lat,first.layers,times,fields)
end

end
