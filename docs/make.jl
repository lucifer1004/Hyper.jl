using Hyper
using Documenter

DocMeta.setdocmeta!(Hyper, :DocTestSetup, :(using Hyper); recursive=true)

makedocs(;
    modules=[Hyper],
    authors="Gabriel Wu <wuzihua@pku.edu.cn> and contributors",
    repo="https://github.com/lucifer1004/Hyper.jl/blob/{commit}{path}#{line}",
    sitename="Hyper.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://lucifer1004.github.io/Hyper.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/lucifer1004/Hyper.jl",
    devbranch="main",
)
