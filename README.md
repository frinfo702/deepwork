# Deepwork

A macOS menu bar app that, during the hours you choose, only lets the apps and sites (in Dia) you allow through.

- Website: https://frinfo702.github.io/deepwork/ (served from `docs/`)
- Download: [Releases](https://github.com/frinfo702/deepwork/releases/latest)

## Build

```sh
./build.sh                 # builds build/Deepwork.app and build/Deepwork.zip (universal)
VERSION=0.3.0 ./build.sh   # override the version (default: latest git tag)
```

Regenerate the icon:

```sh
swiftc -parse-as-library scripts/icon.swift -o /tmp/icon && /tmp/icon
```

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
