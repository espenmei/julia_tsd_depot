using Pkg

# Tving Julia til å bruke offline_depot-mappen for nedlastingene.
# JULIA_DEPOT_PATH kan settes utenfra (f.eks. i CI på Linux); ellers
# faller vi tilbake på en relativ mappe ved siden av dette scriptet,
# slik at oppsettet fungerer likt på Windows og Linux.
if !haskey(ENV, "JULIA_DEPOT_PATH") || isempty(ENV["JULIA_DEPOT_PATH"])
    ENV["JULIA_DEPOT_PATH"] = joinpath(@__DIR__, "offline_depot")
end

println("Definerer depot-sti: ", ENV["JULIA_DEPOT_PATH"])

Pkg.activate(".")

pakkebunt = [
    "CSV",
    "CodecZlib",
    "DataFrames",
    "Distributions",
    "GLM",
    "HDF5",
    "IterativeSolvers",
    "JLD",
    "JLD2",
    "LazyArtifacts",
    "LoopVectorization",
    "MixedModels",
    "Plots",
    "SnpArrays",
    "Statistics",
    "StatsBase",
    "StatsModels"
]

println("Legger til hovedpakker: ", pakkebunt)
Pkg.add(pakkebunt)

Pkg.add(url="https://github.com/espenmei/GREMLModels.jl")

# 4. Last ned alle sekundære avhengigheter basert på listen over
println("Henter absolutt alle sekundære dependencies...")
Pkg.instantiate()

# 5. Tving frem nedlasting av ALLE "Lazy Artifacts" (binærfiler) som finnes i pakkene
println("Tvinger nedlasting av alle binærfiler (artifacts)...")
using LazyArtifacts
# Dette skanner igjennom alt du har lagt til og henter binærfilene med en gang

# 5. Tving full kompilering av alt på nett-maskinen
# Dette bygger pakkene ferdig og lagrer de kompilerte filene i depotet ditt!
#println("Kompilerer pakker og sjekker etter skjulte avhengigheter...")
#Pkg.precompile()