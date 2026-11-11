module TerraFluxModelChunk
using SpeedyWeather,Dates
using ..TerraFluxData
export run_chunk!

"Integrate one closed, validated 6h interval shared by live and A/B workers."
function run_chunk!(simulation,truncation)
    model=simulation.model
    start=simulation.variables.prognostic.clock.time
    run!(simulation;period=Hour(6),output=true)
    finish=simulation.variables.prognostic.clock.time
    finish-start==Hour(6) || error("Đồng hồ mô hình không tiến đúng 6 giờ.")
    for name in (:temperature,:u,:v,:humidity)
        values=Array(get_step(getproperty(simulation.variables.grid,name)))
        all(isfinite,values) || error("Trạng thái $name không hữu hạn; mô phỏng đã dừng.")
        name==:temperature && minimum(values)<=0 && error("Nhiệt độ không hợp lệ.")
    end
    !model.feedback.nans_detected || error("Mô hình phát hiện phép tính mất ổn định.")
    path=joinpath(model.output.run_path,model.output.filename)
    SpeedyWeather.NCDataset(path,"a") do ds
        ds.attrib["terraflux_truncation"]=truncation
        for name in ("sst","st")
            haskey(ds,name) || continue
            all(x->!ismissing(x) && isfinite(x),ds[name][ntuple(_->Colon(),ndims(ds[name]))...]) || error("Đầu ra $name không hữu hạn.")
        end
    end
    chunk=load_weather(path)
    length(chunk.times)==2 && chunk.times[1]==start && chunk.times[end]==finish || error("Thời gian đầu ra không khớp mô hình.")
    for (field,data) in chunk.fields
        # Surface diagnostics at the very first initialization are unavailable.
        checked=field in (:mslp,:pres) ? data[:,:,end:end] : data
        # Surface values were validated above before applying the land/ocean mask.
        field in (:sst,:lst) && continue
        all(isfinite,checked) || error("Đầu ra $field không hữu hạn.")
    end
    abspath(path)
end
end
