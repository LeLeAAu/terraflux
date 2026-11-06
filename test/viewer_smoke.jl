# Requires a display/OpenGL. Exercises controls and renders an actual frame.
include(joinpath(@__DIR__, "..", "src", "viewer.jl"))
path = joinpath(@__DIR__, "..", "run_0001", "output.nc")
screenshot = isempty(ARGS) ? nothing : abspath(first(ARGS))
TerraFluxViewer.launch(path; smoke=true, screenshot)
