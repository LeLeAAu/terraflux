using Pkg
"--setup" in ARGS && Pkg.instantiate()
try
    include(joinpath(@__DIR__,"src","comparison_viewer.jl"))
    args=filter(!=("--setup"),ARGS)
    source=isempty(args) ? "" : Base.invokelatest(TerraFluxComparisonViewer.input_path,first(args))
    Base.invokelatest(TerraFluxComparisonViewer.launch_comparison;path=isempty(source) ? "" : abspath(source))
catch err
    showerror(stderr,err,catch_backtrace());println(stderr)
    rethrow()
end
