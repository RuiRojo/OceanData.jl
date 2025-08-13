using OceanData
using Documenter

DocMeta.setdocmeta!(OceanData, :DocTestSetup, :(using OceanData); recursive=true)

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
    pages=[
        "Home" => "index.md",
    ],
)
