# CI and production releases

This document describes how automated builds and GitHub Releases work, what the hosted runners assume, and how to ship a version without surprises.

## Workflows

| Workflow | File | When it runs | What it does |
|----------|------|----------------|---------------|
| **CI** | `.github/workflows/ci.yml` | Pull requests and pushes to `main` / `master` (path-filtered), plus **Run workflow** manually | Builds Android APK, iOS unsigned IPA, and Windows zip. Uploads artifacts to the workflow run (14-day retention). **Does not** create a GitHub Release. |
| **Release** | `.github/workflows/release.yml` | Push of a tag matching `v*` | Same three builds via shared composite actions, then creates a **GitHub Release** with attached binaries. |

Shared build logic lives in **composite actions** under `.github/actions/` so CI and Release stay in sync:

- `android-build` — JDK 17, Gradle `assembleRelease`, versioned APK artifact  
- `ios-build` — Homebrew XcodeGen, unsigned archive + IPA  
- `windows-build` — `run-vcpkg`, Softcam libraries + installer (no test projects), VCamdroid, `package.bat`, zip  

### Why three jobs instead of one sequential job?

The three platforms run **in parallel** on different runners (Ubuntu, macOS, Windows). That **cuts wall-clock time** (slow Windows + vcpkg does not block Android/iOS) and gives **clear logs per platform** when something fails. It does not change correctness; a single job would be simpler to read but slower and harder to retry one OS.

## Shipping a new version (maintainers)

From the **repository root** (not `ios/VCamdroidiOS`):

```bash
# One command: bump semver, commit, tag, push (triggers Release workflow)
make ship-patch    # or ship-minor / ship-major

# Equivalent two-step
make release-patch && make push
```

Requirements:

1. **`gh` CLI** and `gh auth login`, then `gh auth setup-git` so `git push` over HTTPS works (or use SSH remotes).  
2. **`VERSION`** at repo root is the source of truth; `scripts/bump-version.sh` updates Android, iOS plist, and `windows/vcpkg.json` together.  
3. Push must include the **new tag** (`make push` runs `git push origin HEAD --tags`).

After push, open **Actions → Release** and confirm all three jobs succeeded before announcing the release.

## Hosted runner assumptions (especially Windows)

CI matches **GitHub-hosted** images, not necessarily a bleeding-edge dev box.

| Topic | Expectation |
|-------|----------------|
| **Visual Studio** | `windows-latest` is **VS 2022** with MSVC **v143**. `VCamdroid.vcxproj` uses **PlatformToolset v143**. Do not retarget to preview toolsets (e.g. v145) unless you also change CI (e.g. self-hosted runner with that VS). |
| **vcpkg + MSBuild manifest** | `run-vcpkg` installs from `windows/vcpkg.json` into **`windows/vcpkg_installed/<triplet>/`**. MSBuild must use **manifest mode** (`VcpkgEnableManifest=true`) and **`VcpkgManifestRoot`** pointing at `windows/`; otherwise the compiler only sees classic **`$(VCPKG_ROOT)/installed/`**, which does not contain those packages — symptoms: missing `wx/wx.h`, `asio.hpp`, `libavformat/avformat.h`, `usbmuxd.h`. See `windows/VCamdroid.vcxproj` when `VCPKG_ROOT` is set. |
| **Softcam** | Build only **`BaseClasses;softcamcore;softcam`** from `softcam.sln`, then **`softcam_installer.sln`**. The full solution builds **GoogleTest** NuGet projects that are not restored on CI. |
| **Timeouts** | Windows job allows **120 minutes** for first-time vcpkg compiles. |

## iOS IPA (Signulous / sideload)

The Release and CI workflows produce an **unsigned** IPA suitable for re-signing (e.g. Signulous). Local rebuild: `ios/VCamdroidiOS/build_ipa.sh`.

## Android signing

Release builds use the Gradle **release** configuration as defined in `android/app/build.gradle.kts` (currently debug signing for release — adjust for Play Store if needed).

## Troubleshooting

- **Release workflow does not start** — Ensure the push included the tag (`git push origin --tags`). Only tags matching `v*` trigger Release.  
- **Windows: missing wx / ffmpeg / asio / usbmux headers** — Almost always **manifest vs classic vcpkg paths**: `VcpkgEnableManifest` must be `true` when using `vcpkg.json` so includes come from `windows/vcpkg_installed/...`, not empty `vcpkg/installed/...`. Also confirm the job sets **`VCPKG_ROOT`** to the same path as `run-vcpkg`’s `vcpkgDirectory`.  
- **Release shows all three jobs red** — Jobs are independent; open each log. If only Windows failed, Android/iOS may have been cancelled or also failed for unrelated reasons (check the first error in each).
- **Windows: `ffmpeg does not have required feature avutil`** — The vcpkg **ffmpeg** port no longer exposes an `avutil` feature; libavutil is pulled in with **avcodec** / **avformat**. Remove `avutil` from `windows/vcpkg.json` feature lists (keep `avcodec`, `avformat`, `swscale` as needed).  
- **CI skipped on a PR** — Check path filters in `ci.yml`; only changes under listed paths run CI. Use **Actions → CI → Run workflow** to force a build.

## Optional hardening

- Add **branch protection** requiring the **CI** workflow to pass before merge.  
- For **stricter reproducibility**, bump `builtin-baseline` in `windows/vcpkg.json` only when intentionally updating ports.  
- Use **self-hosted Windows** runners if you must match a non–VS-2022 toolchain.
