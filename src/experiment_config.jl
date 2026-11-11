module TerraFluxExperimentConfig
using TOML
export experiment_config, estimate_experiment, write_config
function experiment_config(;days=60,truncation=32,layers=8,output_hours=6,threads=2,seed=20261107,backend="cpu")
    days isa Integer && 1<=days<=365 || error("Số ngày phải là số nguyên 1–365.")
    truncation in (21,32,63,85) || error("Độ phân giải hỗ trợ: T21/T32/T63/T85.")
    layers in (8,16,24,32) || error("Số tầng hỗ trợ: 8/16/24/32.")
    output_hours in (1,3,6,12,24) || error("Chu kỳ ghi hỗ trợ: 1/3/6/12/24 giờ.")
    threads in (1,2,4,8) || error("Số luồng hỗ trợ: 1/2/4/8.")
    seed isa Integer && 0<=seed<=typemax(Int32) || error("Seed phải là số nguyên 0…2147483647.")
    backend in ("cpu","cuda") || error("Backend hỗ trợ: cpu hoặc cuda.")
    (;days=Int(days),truncation=Int(truncation),layers=Int(layers),output_hours=Int(output_hours),threads=Int(threads),seed=Int(seed),backend=String(backend))
end
function estimate_experiment(c)
    frames=24c.days÷c.output_hours+1
    ratio=((c.truncation+1)/33)^2*(c.layers/8)*(frames/241)
    (;frames,disk_mib=52.4ratio,viewer_ram_mib=160ratio,approximate=true)
end
function write_config(path,c)
    open(path,"w") do io;TOML.print(io,Dict(string(k)=>v for (k,v) in pairs(c)));end
end
end
