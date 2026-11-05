# Deepwork

A macOS menu bar app that, during the hours you choose, blocks apps and sites (in Dia). Each can use an allow list (only listed items get through) or a block list (only listed items are blocked).

- Website: https://frinfo702.github.io/deepwork/ (served from `docs/`)
- Download: [Releases](https://github.com/frinfo702/deepwork/releases/latest)

## Build

```sh
./build.sh                 # builds build/Deepwork.app and build/Deepwork.zip (universal)
VERSION=0.3.0 ./build.sh   # override the version (default: latest git tag)
```

## App icon

The icon is a 3D scene in Blender (`scripts/icon/scene.py`, also saved as `scripts/icon/deepwork.blend`).
It renders three layers (cloud, sun, glow) into `Resources/Deepwork.icon`, an Icon Composer document
whose background gradient (light and dark) lives in `icon.json`.

```sh
scripts/icon/build.sh            # compile Deepwork.icon -> Resources/Assets.car, Resources/Deepwork.icns, docs/icon.png
scripts/icon/build.sh --render   # re-render the layers in Blender first
```

Needs Xcode 26+ and Blender. The outputs are committed, so `./build.sh` and CI need neither.

Self-test:

```sh
swiftc -Onone -parse-as-library -swift-version 5 Sources/*.swift -o /tmp/dw && /tmp/dw --selftest
```

## Release

Push a tag. `.github/workflows/release.yml` runs the self-test, builds the universal app with that version and publishes the GitHub Release:

```sh
git tag v0.4.0 && git push origin v0.4.0
```

Installed copies pick it up through the in-app updater (`Sources/Updater.swift`), which polls `releases/latest`.

The website's download button points to `releases/latest/download/Deepwork.zip`, so keep that file name.

Background artwork on the website: Dreamblur by [@uihssn](https://x.com/uihssn).
