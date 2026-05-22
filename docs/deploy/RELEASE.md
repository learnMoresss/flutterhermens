# 发布 Android APK（GitHub Releases）

APK **不入 Git 仓库**（见根目录 `.gitignore` 中的 `app/build/`），通过 **GitHub Releases** 向用户分发。

仓库：[learnMoresss/flutterhermens](https://github.com/learnMoresss/flutterhermens)

---

## 用户如何安装

1. 打开 [Releases / Latest](https://github.com/learnMoresss/flutterhermens/releases/latest)
2. 下载 Assets 中的 **`app-release.apk`**
3. 安装后在 App 内配置 Gateway 地址并登录

---

## 维护者：打包容器

版本号与 [`app/pubspec.yaml`](../../app/pubspec.yaml) 中 `version:` 保持一致（当前示例 `1.0.0+1` → 标签建议 `v1.0.0`）。

```bash
cd app
flutter pub get
flutter build apk --release
```

产物路径：

```text
app/build/app/outputs/flutter-apk/app-release.apk
```

可选：按 ABI 分包减小体积（Release 页可上传多个 apk）：

```bash
flutter build apk --release --split-per-abi
# 产物: app-arm64-v8a-release.apk 等
```

---

## 维护者：上传到 GitHub Release

### 方式 A：`gh` CLI（推荐）

```bash
# 在仓库根目录，已安装 gh 并 gh auth login
VERSION=v1.0.0
cd app && flutter build apk --release && cd ..

gh release create "$VERSION" \
  --repo learnMoresss/flutterhermens \
  --title "Hermes Mobile $VERSION" \
  --notes "Android Release APK。安装后请在 App 内配置 Gateway 地址。" \
  app/build/app/outputs/flutter-apk/app-release.apk#app-release.apk
```

若 Release 已存在，只追加/替换 APK：

```bash
gh release upload "$VERSION" \
  --repo learnMoresss/flutterhermens \
  --clobber \
  app/build/app/outputs/flutter-apk/app-release.apk
```

### 方式 B：GitHub 网页

1. 仓库 → **Releases** → **Draft a new release**
2. Tag：`v1.0.0`（与 `pubspec` 版本对应）
3. 上传 `app-release.apk` 到 Assets
4. 发布

---

## 命名建议

| 文件名 | 说明 |
|--------|------|
| `app-release.apk` | 通用名，README 默认链接 |
| `HermesMobile-v1.0.0.apk` | 带版本，便于多版本并存 |

---

## 说明

- Gateway 仍须单独部署（Docker / 服务器），Release **仅包含 Flutter 客户端**。
- 更新 App 后用户可覆盖安装：`adb install -r app-release.apk` 或重新下载最新 Release。
