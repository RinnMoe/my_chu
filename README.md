<div align="center">

<img src="logo.png" alt="Logo" width="100" style="clip-path: path('M 50.00 0.00 58.12 0.07 62.87 0.29 66.82 0.64 70.31 1.14 73.46 1.79 76.36 2.57 79.03 3.50 81.50 4.57 83.79 5.79 85.91 7.15 87.88 8.66 89.69 10.31 91.34 12.12 92.85 14.09 94.21 16.21 95.43 18.50 96.50 20.97 97.43 23.64 98.21 26.54 98.86 29.69 99.36 33.18 99.71 37.13 99.93 41.88 100.00 50.00 99.93 58.12 99.71 62.87 99.36 66.82 98.86 70.31 98.21 73.46 97.43 76.36 96.50 79.03 95.43 81.50 94.21 83.79 92.85 85.91 91.34 87.88 89.69 89.69 87.88 91.34 85.91 92.85 83.79 94.21 81.50 95.43 79.03 96.50 76.36 97.43 73.46 98.21 70.31 98.86 66.82 99.36 62.87 99.71 58.12 99.93 50.00 100.00 41.88 99.93 37.13 99.71 33.18 99.36 29.69 98.86 26.54 98.21 23.64 97.43 20.97 96.50 18.50 95.43 16.21 94.21 14.09 92.85 12.12 91.34 10.31 89.69 8.66 87.88 7.15 85.91 5.79 83.79 4.57 81.50 3.50 79.03 2.57 76.36 1.79 73.46 1.14 70.31 0.64 66.82 0.29 62.87 0.07 58.12 0.00 50.00 0.07 41.88 0.29 37.13 0.64 33.18 1.14 29.69 1.79 26.54 2.57 23.64 3.50 20.97 4.57 18.50 5.79 16.21 7.15 14.09 8.66 12.12 10.31 10.31 12.12 8.66 14.09 7.15 16.21 5.79 18.50 4.57 20.97 3.50 23.64 2.57 26.54 1.79 29.69 1.14 33.18 0.64 37.13 0.29 41.88 0.07 Z');">

<h1 align="center">MyCHU</h1>
<p align="center">
  <a href="https://github.com/RinnMoe/my_chu/releases/latest"><img src="https://img.shields.io/github/v/release/RinnMoe/my_chu?logo=github&label=GitHub&style=for-the-badge" alt="GitHub latest release"></a>
</p>
</div>
MyCHU 是为长安大学学生开发的第三方校园助手，聚合数十项校内学习生活服务。

## 主要功能

- 学习与教务：空教室查询、课堂直录播、图书馆服务、第二课堂、畅课课件下载、频道资料站、考试安排、成绩、全校排课查询、评教系统、体育系统等。
- 校园生活：我在长大、校历、通勤车、学信网、校园网自助服务、通知公告、淘宝取件码、云达人等。
- 校园地图：支持通过教室编码及校内地点搜索、解析，部分教学楼支持查看平面图。HarmonyOS 暂不支持此功能。

## 本地构建

本地 Android Debug 构建需要 Flutter、Android SDK，以及两个用途不同的 Mapbox token：

- `MAPBOX_DOWNLOADS_TOKEN`：仅供 Gradle 下载 Mapbox SDK，需使用带 `Downloads:Read` 权限的 Secret Token。只放在本机环境或密钥管理器中，不要提交到仓库。
- `MAPBOX_PUBLIC_ACCESS_TOKEN`：运行地图所需的 Public Token（`pk.*`）。它会编译进应用，属于客户端可见值；源码仓库不提供默认 token。

在 PowerShell 中设置好这两个变量后运行：

```powershell
$env:MAPBOX_DOWNLOADS_TOKEN = '<your Mapbox Downloads:Read Secret Token>'
$env:MAPBOX_PUBLIC_ACCESS_TOKEN = '<your Mapbox public pk.* token>'
flutter pub get --enforce-lockfile
flutter build apk --debug --no-pub "--dart-define=MAPBOX_PUBLIC_ACCESS_TOKEN=$env:MAPBOX_PUBLIC_ACCESS_TOKEN"
```

在 iOS 等支持校园地图的平台本地构建时，也要把相同的 `MAPBOX_PUBLIC_ACCESS_TOKEN` 通过 `--dart-define` 传入 Flutter；HarmonyOS 当前不支持校园地图。

发布 GitHub Release（包括 Pre-release）会自动构建并上传正式签名 APK。可先用 Pre-release 验收，确认后取消 Pre-release 标记升格为正式版，期间保留的是同一 APK。若需重建已有版本，在 Actions 的 `Android Release APK` 中运行 workflow 并输入已发布的 tag；它会覆盖该 Release 中固定命名的 APK 附件。工作流从 `android-release` Environment Secrets 读取签名材料和 `MAPBOX_DOWNLOADS_TOKEN`，并从该 Environment 的 Actions variable 读取 `MAPBOX_PUBLIC_ACCESS_TOKEN`。

## 开发文档

[更新日志](CHANGELOG.md)

本地构建说明见上方“本地构建”。

## 鸣谢

本项目开发中受到了 [HFUT-Schedule](https://github.com/Chiu-xaH/HFUT-Schedule)、[DanXi](https://github.com/DanXi-Dev/DanXi) 等项目的灵感启发，在此向他们表示感谢。

## 开源协议

本项目使用 Mozilla Public License 2.0
