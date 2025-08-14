using OceanData
using Documenter

DocMeta.setdocmeta!(OceanData, :DocTestSetup, :(using OceanData); recursive=true)


makedocs(;
    modules=[OceanData],
    authors="Rui Rojo <rui.rojo@gmail.com> and contributors",
    repo="https://github.com/RuiRojo/OceanData.jl/blob/{commit}{path}#{line}",
    sitename="OceanData.jl",
    format=Documenter.HTML(),
    doctest = false,
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(
    repo = "github.com/RuiRojo/OceanData.jl.git",
    devbranch = "main",
   )
