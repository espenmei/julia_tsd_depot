using Pkg
using Pkg.Artifacts
using Base.BinaryPlatforms

check_only = ARGS == ["--check"]
isempty(ARGS) || check_only || error("Usage: julia --project=greml_gpu prefetch_cuda_artifacts.jl [--check]")

platform = Platform("x86_64", "linux"; libc="glibc", cuda="12.8")
dependencies = Pkg.dependencies()
for (package, artifact) in (("CUDA_Runtime_jll", "CUDA_Runtime"),
                            ("CUDA_Compiler_jll", "CUDA_Compiler"))
    matches = [info for info in values(dependencies) if info.name == package]
    length(matches) == 1 || error("Expected one $package dependency, found $(length(matches))")
    source = only(matches).source
    isnothing(source) && error("Package source not available for $package")
    artifacts_file = joinpath(source, "Artifacts.toml")
    metadata = artifact_meta(artifact, artifacts_file; platform)
    isnothing(metadata) && error("No Linux x86_64 CUDA 12.8 artifact for $package")
    println("$artifact: ", metadata["git-tree-sha1"])
    if !check_only
        ensure_artifact_installed(artifact, metadata, artifacts_file; platform)
        artifact_exists(Base.SHA1(metadata["git-tree-sha1"])) ||
            error("Artifact installation failed for $artifact")
    end
end
println(check_only ? "CUDA artifact metadata checked; no downloads performed." :
                     "CUDA 12.8 runtime and compiler artifacts installed.")
