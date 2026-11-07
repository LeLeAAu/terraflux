using TOML
include("live.jl")
include(joinpath(@__DIR__,"..","generate_long_run.jl"))
directory=abspath(only(ARGS))
statusfile=joinpath(directory,"status.toml")
try
    c=TOML.parsefile(joinpath(directory,"config.toml"))
    TerraFluxLive.atomic_toml(statusfile,Dict("state"=>"running"))
    path=generate_long_run(c["days"],joinpath(directory,"output");truncation=c["truncation"],
        layers=c["layers"],output_hours=c["output_hours"],seed=c["seed"])
    TerraFluxLive.atomic_toml(statusfile,Dict("state"=>"complete","output_path"=>path))
catch err
    TerraFluxLive.atomic_toml(statusfile,Dict("state"=>"error","error"=>sprint(showerror,err)))
    rethrow()
end
