using OceanData
using Documenter

DocMeta.setdocmeta!(OceanData, :DocTestSetup, :(using OceanData); recursive=true)

makedocs(;
    modules=[OceanData],
    authors="Rui Rojo <rui.rojo@gmail.com> and contributors",
    repo="https://github.com/RuiRojo/OceanData.jl/blob/{commit}{path}#{line}",
    sitename="OceanData.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://ruirojo.github.io/OceanData.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)
