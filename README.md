# Deepwork

決めた時間だけ、許可したアプリとサイト（Dia）しか使えないようにする macOS のメニューバーアプリです。

- サイト: `docs/`（GitHub Pages: Settings › Pages › Branch `main` / folder `/docs`）
- ダウンロード: [Releases](https://github.com/frinfo702/deepwork/releases/latest)

## ビルド

```sh
./build.sh                 # build/Deepwork.app と build/Deepwork.zip を作る
VERSION=0.3.0 ./build.sh   # バージョンを指定する
```

アイコンを作り直すとき:

```sh
swiftc -parse-as-library scripts/icon.swift -o /tmp/icon && /tmp/icon
```

自己テスト:

```sh
swiftc -Onone -parse-as-library -swift-version 5 Sources/*.swift -o /tmp/dw && /tmp/dw --selftest
```

## リリース

```sh
./build.sh && gh release create v0.2.0 build/Deepwork.zip
```

サイトのダウンロードボタンは `releases/latest/download/Deepwork.zip` を指しているので、zip のファイル名は変えないでください。
