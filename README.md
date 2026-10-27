# Fresh yt-dlp for Nix

Run a recently published [yt-dlp](https://github.com/yt-dlp/yt-dlp) without adding it to your NixOS or Home Manager configuration, rebuilding your system, or waiting for your pinned Nixpkgs revision to catch up.

This flake provides a small Nix-built **launcher**, not a Nix-built copy of yt-dlp itself. The launcher uses [uv](https://docs.astral.sh/uv/) to resolve and run yt-dlp from Python package indexes **when you invoke it**. It works with `nix shell`, `nix run`, and runtime scripts in other flakes.

> **Intended use:** interactive shells and programs run on a normal machine with network access. **Do not use this launcher in sandboxed Nix builds.**

## Quick start

From this repository remotely:

```sh
nix shell github:primaemateriae/yt-dlp-fresh#yt-dlp
yt-dlp --version
```

From this repository locally:

```sh
nix shell .#yt-dlp
yt-dlp --version
yt-dlp 'https://example.com/video'
exit
```

For a single command, without entering a shell:

```sh
nix run .#yt-dlp -- --version
# or
nix shell .#yt-dlp -c yt-dlp --version
```

Replace the example URL with an actual video URL. The flake currently supports `x86_64-linux` and `aarch64-linux`.

Leaving `nix shell` restores your previous shell environment; yt-dlp is **not installed into your NixOS system configuration or user profile**. Nix store paths and application caches can remain on disk, as described below.

## What the flake provides

| Output | Purpose |
| --- | --- |
| `packages.<system>.yt-dlp` | Launcher that resolves and executes yt-dlp on demand |
| `packages.<system>.default` | Alias for the same launcher |
| `overlays.default` | Adds `pkgs.yt-dlp-fresh` to a consumer's Nixpkgs package set |

The launcher itself is built with `writeShellApplication`. Its Nix-managed runtime inputs are:

- **uv:** resolves and runs the Python package;
- **Python:** a known Nix-supplied interpreter, rather than a Python downloaded by uv;
- **FFmpeg:** media merging, conversion, and post-processing;
- **Deno:** JavaScript runtime for yt-dlp's supported challenge-solving functionality.

The underlying invocation is equivalent to:

```sh
uvx \
  --isolated \
  --refresh \
  --no-config \
  --no-managed-python \
  --python /nix/store/...-python3-.../bin/python3 \
  --prerelease allow \
  --from 'yt-dlp[default]' \
  yt-dlp "$@"
```

The actual Python path is inserted by Nix. `yt-dlp[default]` requests yt-dlp's recommended Python extras, including the companion JavaScript challenge-solver package where applicable.

## Freshness: how it works

**yt-dlp is selected at execution time, not at flake evaluation or build time.**

- `--refresh` asks uv to refresh its cached package information, so a newly published compatible yt-dlp release can be selected on the next invocation.
- `--isolated` prevents an existing `uv tool install` installation from taking precedence over the tool run.
- `--prerelease allow` includes prereleases in resolution. This can pick up releases newer than the stable release, including nightly-style prereleases.
- `--no-managed-python` and `--python ...` use the Python interpreter supplied by the flake's Nixpkgs input.
- `--no-config` prevents uv from reading discovered `uv.toml` or `pyproject.toml` configuration files. Relevant environment variables and network/index settings can still affect behavior.

**“Fresh” does not mean “guaranteed nightly” or “guaranteed newest under all circumstances.”** uv chooses a compatible version according to the package index and normal version ordering. A stable release may be selected over older prereleases. Python compatibility, unavailable or withdrawn distributions, network errors, and index configuration can also affect which version is usable.

The resulting yt-dlp version **can change between runs**, even if neither this repository nor the consuming flake changes. This is deliberate, but it makes execution non-reproducible.

## What `flake.lock` does—and does not—pin

**Keep and commit `flake.lock`. You do not need to update it to receive newer yt-dlp releases from PyPI.**

| Component | Version controlled by |
| --- | --- |
| Python, uv, FFmpeg, Deno | The pinned Nixpkgs input in `flake.lock` |
| The launcher implementation | This flake's source revision (or the consumer's pinned input) |
| yt-dlp and its Python dependencies | uv's runtime resolution against the configured package index |

For example, a `flake.lock` created in October can still run a newer compatible yt-dlp published in November: the launcher consults the index at execution time via `--refresh`.

Update the lock file when you **want newer Nix-provided tools or compatibility fixes**, not merely to update yt-dlp:

```sh
nix flake update
```

A downstream flake can pin **this flake** in its own `flake.lock` and still obtain newer yt-dlp releases at runtime. That downstream lock pins the wrapper code and Nix inputs, not the package fetched by uv.

## Caching and disk usage

Caches are intentionally **enabled**. They improve repeat-run performance without placing a permanent yt-dlp executable in your profile or system PATH.

| Cache / storage | What it contains | Typical location |
| --- | --- | --- |
| uv | Downloaded Python package artifacts, metadata, and cached tool environments | `$XDG_CACHE_HOME/uv` or `~/.cache/uv` |
| yt-dlp | Reusable information such as client IDs and signatures | `$XDG_CACHE_HOME/yt-dlp` or `~/.cache/yt-dlp` |
| Deno | Runtime caches (location depends on Deno configuration) | `DENO_DIR`, or an XDG/platform-specific cache location |
| Nix store | The launcher and Nix-managed runtime tools | `/nix/store` |

`--refresh` **does not disable uv's cache**. It revalidates package data so future runs can discover newer versions, while uv can still retain downloaded artifacts. This is different from `--no-cache`, which uses a temporary uv cache for that invocation and typically increases download/setup work.

Similarly, the wrapper does **not** pass yt-dlp's `--no-cache-dir` or disable Deno's cache. Those caches do not decide which yt-dlp version uv selects, and disabling them can make repeated downloads or challenge solving slower.

Leaving `nix shell` removes the temporary **PATH modification**, not these caches or Nix store paths. Nix store paths persist until eligible for garbage collection; downloaded videos, output files, cookies, and other files deliberately written by yt-dlp remain wherever you requested them.

If you prefer a stricter no-persistent-uv-cache policy, replace `--refresh` with `--no-cache` in the launcher. That is a performance/freshness trade-off, not a requirement for keeping yt-dlp out of your system configuration.

## Using it from another flake

The primary interface is the package output. Replace `YOURNAME/yt-dlp-fresh` with this repository's actual flake URL.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ytDlpFresh.url = "github:YOURNAME/yt-dlp-fresh";
  };

  outputs = { nixpkgs, ytDlpFresh, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system}.default = pkgs.writeShellApplication {
        name = "download-video";
        runtimeInputs = [ ytDlpFresh.packages.${system}.yt-dlp ];
        text = ''
          exec yt-dlp --no-playlist "$@"
        '';
      };
    };
}
```

Then run the consumer's script:

```sh
nix run . -- 'https://example.com/video'
```

For a project that prefers overlays, add this flake's overlay to its Nixpkgs import:

```nix
pkgs = import nixpkgs {
  inherit system;
  overlays = [ ytDlpFresh.overlays.default ];
};
```

Then use `pkgs.yt-dlp-fresh` in `runtimeInputs`. The overlay creates the launcher using the **consumer's Nixpkgs package set**; the direct package output uses the Nixpkgs input pinned by this flake. The overlay does not replace the ordinary `pkgs.yt-dlp` package.

**Important:** this reusable package is a *runtime executable*. Making it a Nix dependency does not make the dynamically downloaded Python package part of the immutable Nix store output.

## Why not use it inside sandboxed Nix builds?

**Do not call this launcher from a derivation's build script** (for example, inside `runCommand`, `stdenv.mkDerivation` build phases, or a build-time data-fetching step).

The launcher accesses a Python package index **when it runs**. Normal sandboxed Nix builds have restricted network access and generally cannot fetch yt-dlp from PyPI at build time. Even if you deliberately allow network access, the dynamically chosen package version is not pinned in the derivation's inputs: the same Nix build definition could execute different yt-dlp code on different days. That defeats Nix's reproducibility guarantees.

Use this flake for **interactive commands, runtime scripts, and programs started after the Nix build has completed**. If a build actually needs yt-dlp, use a pinned, Nix-built yt-dlp package (or another properly fixed, content-addressed input) instead.

## Trade-offs and limitations

- **Network access:** checking for newer versions normally requires reaching a Python package index; first-time execution also needs the required distributions. Offline behavior is not guaranteed.
- **Startup latency:** refresh checks add some network work, though cached artifacts reduce repeated downloads.
- **Not fully reproducible:** the Python application and dependency versions can change without changing `flake.lock`.
- **Python compatibility:** the newest release may require a newer Python than the Nixpkgs revision supplies. Occasionally updating `flake.lock` may be necessary for compatibility.
- **Trust:** running a fresh package from PyPI means trusting newly published upstream code and the configured package index, rather than reviewing and pinning every executable version.
- **No system profile installation, not zero disk writes:** cache entries and `/nix/store` paths are expected, and yt-dlp can write requested output files.

## References

- [uv: Running tools and tool-version selection](https://docs.astral.sh/uv/concepts/tools/)
- [uv: Cache behavior and `--refresh`](https://docs.astral.sh/uv/concepts/cache/)
- [uv: CLI option reference](https://docs.astral.sh/uv/reference/cli/)
- [Nix: Flake lock files](https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake)
- [yt-dlp: Installation](https://github.com/yt-dlp/yt-dlp/wiki/Installation)
- [yt-dlp: External JavaScript scripts](https://github.com/yt-dlp/yt-dlp/wiki/EJS)
