# Run with: julia --project=. viewer.jl [path/to/output.nc]
using Pkg
if "--setup" in ARGS
    Pkg.instantiate()
end
include(joinpath(@__DIR__, "src", "viewer.jl"))
args = filter(x -> x != "--setup", ARGS)
path = isempty(args) ? joinpath(@__DIR__, "run_0001", "output.nc") : abspath(first(args))
try
    TerraFluxViewer.launch(path)
catch err
    println(stderr, "\nKhông mở được TerraFlux: ", sprint(showerror, err))
    println(stderr, "Hãy kiểm tra đường dẫn NetCDF và trình điều khiển đồ họa hỗ trợ OpenGL 3.3.")
    rethrow()
end
