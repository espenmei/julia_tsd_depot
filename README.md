# Julia offline depot for Colossus / TSD

Workflow for building a Linux-native Julia package depot on GitHub Actions
and transferring it to an offline HPC cluster (e.g. Colossus/TSD).

## Why this is needed

Colossus has no internet access, so `Pkg.instantiate()` can't download
packages/artifacts there directly. Building the depot on **Windows**
does **not** work: package artifacts (binary libraries) and the
precompile cache are OS/architecture-specific. A Windows-built depot
copied to Linux causes mass "failed to precompile" errors. The depot
must be built on a matching Linux x86_64 environment, which is what the
GitHub Actions workflow in this repo does.

Repo: https://github.com/espenmei/julia_tsd_depot

## 1. Update package list (if needed)

Edit `updepot.jl` (package list) and/or `Project.toml` in this folder.
Commit and push to `main`:

```powershell
git add Project.toml Manifest.toml updepot.jl greml_gpu prefetch_cuda_artifacts.jl .github/workflows/build-depot.yml
git commit -m "Update package list"
git push
```

Pushing changes to `Project.toml`, `Manifest.toml`, `updepot.jl`,
`greml_gpu/`, `prefetch_cuda_artifacts.jl`, or the workflow file
automatically triggers the build. You can also trigger it
manually from the GitHub Actions tab ("Run workflow" button) without
changing anything.

## 2. Build the depot on GitHub Actions

- Go to https://github.com/espenmei/julia_tsd_depot/actions
- Wait for the "Build offline Julia depot (Linux)" run to finish
  (~10–15 minutes — it installs and precompiles all packages on an
  Ubuntu runner with Julia 1.12.2, matching the Colossus module version).
- Open the completed run, scroll to **Artifacts**, and download
  `offline_depot_linux` (a zip, valid for 14 days after the run).

> If you update the Julia version used on Colossus, update the
> `version:` field in `.github/workflows/build-depot.yml` to match.

## 3. Transfer the zip to Colossus

Use `scp`/`sftp` or the TSD file import mechanism to copy the
downloaded zip onto Colossus. The depot includes large CUDA artifacts;
allow time and storage for the transfer and extraction.

**Important**: GitHub always wraps a downloaded Actions artifact in an
extra outer zip, even though the file inside already has the same
name. So `offline_depot_linux.zip` as downloaded from the browser/API
contains a single file, itself named `offline_depot_linux.zip` — the
real depot archive. You must unzip twice.

## 4. Unzip on Colossus

```bash
# 1st unzip: unwraps GitHub's outer artifact zip
unzip offline_depot_linux.zip

# 2nd unzip: extracts the actual depot contents (can take several
# minutes — Julia depots contain huge numbers of small files, which is
# slow especially on networked HPC filesystems)
unzip offline_depot_linux.zip -d offline_depot

# optional cleanup: remove the leftover zip copied into offline_depot
rm -f offline_depot/offline_depot_linux.zip
```

If `unzip` isn't available, use Python instead:

```bash
python3 -c "import zipfile; zipfile.ZipFile('offline_depot_linux.zip').extractall('offline_depot')"
```

### Sanity check after extraction

```bash
du -sh offline_depot
ls offline_depot
# expect: artifacts  clones  compiled  logs  packages  registries  scratchspaces
```

If `offline_depot` looks tiny or is missing `packages`/`artifacts`, you
likely only did the first unzip — repeat step 4.

### Find the extracted depot directory

The path to use is the `offline_depot` directory created by the second
unzip, not necessarily one of the default paths printed by Julia. From the
TSD shell, find it with:

```bash
find "$HOME" -maxdepth 5 -type d -name offline_depot -print
```

Use the full path printed by this command as `JULIA_DEPOT_PATH`. For example,
if the result is `/cluster/home/username/TSD/offline_depot`:

```bash
export JULIA_DEPOT_PATH=/cluster/home/username/TSD/offline_depot
```

## 5. Use the depot offline

```bash
export JULIA_DEPOT_PATH=/path/to/offline_depot
export JULIA_PKG_OFFLINE=true   # forces Pkg to never touch the network

julia --project=/path/to/your/project -e 'using Pkg; Pkg.instantiate()'
```

`JULIA_PKG_OFFLINE=true` makes Pkg fail fast with a clear error if
anything is missing from the depot, instead of silently trying (and
timing out) on network access.

Do **not** run `Pkg.update()` offline — it always needs network access
to refresh the registry. Only `instantiate()`/`precompile()` are
needed, and everything required should already be present in the
depot.

## GREML GPU test

The workflow also instantiates the separate locked `greml_gpu` environment,
whose dependency versions and tree hashes match the GREML GPU test bundle.
This keeps the existing depot project separate. `SnpArrays` in this depot
environment is the registered 0.3.23 release: the GPU test bundle supplies
its own patched SnpArrays source and must be transferred separately.

The workflow explicitly downloads the Linux x86_64 CUDA **12.8** runtime and
compiler artifacts. Building without a GPU does not test the actual driver,
GPU compilation, or all possible lazy artifacts. A compatible NVIDIA driver
and working GPU node are still required.

After extracting both the depot and the GPU test bundle, load the intended
Julia module and set `JULIA_DEPOT_PATH` and `JULIA_PKG_OFFLINE` as above.
From the extracted GPU test directory, configure that project to select the
same CUDA artifacts, then instantiate:

```bash
julia --startup-file=no --project=gpu -e 'using CUDA; CUDA.set_runtime_version!(v"12.8"; local_toolkit=false)'
julia --startup-file=no --project=gpu -e 'using Pkg; Pkg.instantiate()'
sbatch tsd/run_gpu.sbatch
```

The first command writes CUDA preferences into the **test project**; restart
Julia before using them, as shown above. Do not copy the depot's GPU manifest
over the test manifest: the latter points at the patched local SnpArrays.
The test manifest was resolved with Julia 1.12.5; offline instantiation and
the CPU product tests have also been checked on Linux with Julia 1.12.2.
This did not test a GPU or the TSD system. Verify the target Julia version and
offline instantiation before submitting, and check both Slurm output files if
the GPU test fails.
