using OceanData
using Documenter

DocMeta.setdocmeta!(OceanData, :DocTestSetup, :(using OceanData); recursive=true)

if get(ENV, "CI", "false") != "true"
    doctest(OceanData)
else
    @info "Skipping doctests in CI environment"
end


makedocs(;
    modules=[OceanData],
    authors="Rui Rojo <rui.rojo@gmail.com> and contributors",
    repo="https://gitlab.com/das-ara/priv/julia/OceanData.jl/blob/{commit}{path}#{line}",
    sitename="OceanData.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://das-ara/priv/julia.gitlab.io/OceanData.jl",
        assets=String[],
    ),
    doctest = false,
    checkdocs = :none,
    pages=[
        "Home" => "index.md",
    ],
)
