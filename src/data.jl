module TerraFluxData
using SpeedyWeather: NCDataset, NCDatasets
using Dates
export WeatherData, load_weather, frame, color_limits, nearest_cell, sample_value,
       FIELDS, field_label, field_unit, layer_label

const FIELDS = [:temp, :wind, :u, :v, :humid, :mslp]
const LABELS = Dict(:temp => "Nhiệt độ", :wind => "Tốc độ gió", :u => "Gió Đông–Tây (u)",
    :v => "Gió Bắc–Nam (v)", :humid => "Độ ẩm riêng", :mslp => "Áp suất quy mực biển")
const UNITS = Dict(:temp => "°C", :wind => "m/s", :u => "m/s", :v => "m/s", :humid => "g/kg", :mslp => "hPa")
field_label(field) = LABELS[field]
field_unit(field) = UNITS[field]

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
        issorted(times) || error("Thời gian không theo thứ tự.")
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
        WeatherData(abspath(path), lon, lat, layers, times, fields)
    end
end

function frame(d::WeatherData, field::Symbol, layer::Int, time::Int)
    checkbounds(d.layers, layer)
    checkbounds(d.times, time)
    field == :wind && return hypot.(frame(d, :u, layer, time), frame(d, :v, layer, time))
    a = d.fields[field]
    field == :mslp ? a[:, :, time] : a[:, :, layer, time]
end

function color_limits(d, field, layer, time; locked=true)
    # Fixed across recorded times for the current field and layer.
    values = if !locked
        frame(d, field, layer, time)
    elseif field == :wind
        hypot.(d.fields[:u][:, :, layer, :], d.fields[:v][:, :, layer, :])
    elseif field == :mslp
        d.fields[field]
    else
        d.fields[field][:, :, layer, :]
    end
    valid = filter(isfinite, vec(values))
    isempty(valid) && return (0f0, 1f0)
    lo, hi = extrema(valid)
    if field in (:u, :v)
        bound = max(abs(lo), abs(hi), 1f-3)
        return (-bound, bound)
    end
    lo == hi ? (lo - 0.5f0, hi + 0.5f0) : (lo, hi)
end

function nearest_cell(d, lon, lat)
    x = mod(lon + 180, 360) - 180
    dx = abs.(d.lon .- x)
    (argmin(min.(dx, 360 .- dx)), argmin(abs.(d.lat .- clamp(lat, -90, 90))))
end
sample_value(d, field, layer, time, lon, lat) = frame(d, field, layer, time)[nearest_cell(d, lon, lat)...]
layer_label(d, k) = "Tầng $k / $(length(d.layers)) · σ = $(round(d.layers[k]; digits=4))"
end
