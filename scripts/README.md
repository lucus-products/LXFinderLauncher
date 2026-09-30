# scripts/

构建、打包、发布用的脚本。四个脚本各管一件事，**没有互相调用**，按需单独跑。

## 该用哪个

```
改完代码
  │
  ├─ 只想自己跑一下看看          → ./scripts/build.sh
  ├─ 免费分发给别人（不签名）     → ./scripts/distribute-free.sh
  └─ 正式对外发布（签名 + 公证）  → ./scripts/release.sh
```

`make-blank-templates.sh` 不在这条线上——它只在**空白 Office 模板本身**需要改时才跑。

| 脚本 | 干什么 | 要 Apple 开发者账号 | 产物目录 |
|---|---|---|---|
| `build.sh` | 构建 App | 不需要 | `dist-build/` |
| `distribute-free.sh` | 构建 + 打包 zip / dmg | 不需要（$0） | `dist-free/` |
| `release.sh` | 构建 + 签名校验 + 公证 + 装订 + 打 DMG | **需要**（$99/年） | `dist-release/` |
| `make-blank-templates.sh` | 重新生成空白 Office 模板 | 不需要 | `LXFinderLauncher/Templates/` |

三个产物目录都在 `.gitignore` 里，不进版本库。

---

## build.sh —— 日常构建

```bash
./scripts/build.sh            # Debug，默认
./scripts/build.sh Release    # Release
```

- 用 `-derivedDataPath` 把产物固定到工程根目录的 `dist-build/`，而不是 Xcode 默认那个 `~/Library/Developer/Xcode/DerivedData/<一堆随机字符>/` 深路径。
- 产物：`dist-build/Build/Products/<Debug|Release>/LXFinderLauncher.app`
- 参数只接受 `Debug` / `Release`，拼错直接报错退出，不浪费一次全量构建。

跑起来：

```bash
open dist-build/Build/Products/Debug/LXFinderLauncher.app
```

> 注意：Debug 产物（Xcode 26 起）代码打进 `LXFinderLauncher.debug.dylib`，主二进制只是薄壳，**只适合本机调试**。

---

## distribute-free.sh —— 免费分发（路径 A，$0）

```bash
./scripts/distribute-free.sh          # Release，默认
./scripts/distribute-free.sh Debug    # 仅本机自测，会警告
```

产物（`dist-free/`）：

| 文件 | 用途 |
|---|---|
| `LXFinderLauncher.app` | 原始 App |
| `LXFinderLauncher.zip` | 通用压缩包，推荐发给别人（`ditto` 打包，保留符号链接与权限） |
| `LXFinderLauncher.dmg` | 拖拽安装的磁盘映像（`hdiutil`，只读压缩 UDZO） |

**默认 Release 的原因**：Debug 产物含 `debug.dylib`，发到别人机器上不稳定；Release 会合并成单一二进制。

**签名校验闸门（发版前必过）**：脚本在打包前会跑 `codesign --verify --deep --strict`，校验不过直接中止，不产出任何产物。

为什么必须有这一步：App 靠「自动化」授权读 Finder 当前目录，而 **TCC 的授权记录是按代码签名要求匹配的**。签名一旦校验不过（最常见是证书被吊销），TCC 就匹配不上任何记录——用户每次点开终端 / 编辑器 / 创建文件都会重新弹授权框，系统设置里的开关也永远不生效。而 Xcode 自动签名在换证时会吊销旧证书，**吊销后本机构建照常成功、不报任何错**，只有校验签名才看得出来。v1.1.7 就是这么发出去的。

报 `CSSMERR_TP_CERT_REVOKED` 时：Xcode → Settings → Accounts → Manage Certificates，删掉吊销/过期的 Apple Development 证书，重新签一张，再跑脚本。脚本每次也会打印实际使用的证书名，方便肉眼核对。

**分发限制**：没有 Developer ID 签名，别人首次运行会被 Gatekeeper 拦截。对方需要：

- 右键 App → **打开**（多一次确认），或
- 终端执行 `xattr -dr com.apple.quarantine '/path/to/LXFinderLauncher.app'`

适合自己用、给信任的人、学习分享。

---

## release.sh —— 正式发布（路径 B，$99/年）

```bash
APPLE_ID=you@example.com \
TEAM_ID=ABCDE12345 \
APP_PASSWORD=xxxx-xxxx-xxxx-xxxx \
./scripts/release.sh
```

**前置条件（一次性）**

1. 注册 Apple Developer Program（$99/年）；
2. Xcode → Settings → Accounts 登录付费账号，并生成「Developer ID Application」证书；
3. 工程 Signing & Capabilities 里把 Team 切为付费账号。

**`APP_PASSWORD` 不是 Apple ID 的登录密码**，是 App 专用密码：appleid.apple.com → 登录与安全 → App 专用密码。

**流程**（任一步失败即中止）

1. 构建 Release；
2. `codesign -dv` 校验签名**确实是** Developer ID Application —— 防止误用免费账号的 Apple Development 签名，那样公证必然失败；
3. `xcrun notarytool submit --wait` 提交苹果公证；
4. `xcrun stapler staple` 把凭证装订回 App —— 装订后离线运行也能过 Gatekeeper，不必每次联网验证；
5. `hdiutil` 打 DMG。

产物：`dist-release/LXFinderLauncher.dmg`，任何人下载双击即可运行。

> GitHub 免费分发（打 tag + Release + 更新 Gist 更新源）还有一层自动化流程，见 `.claude/skills/release-github-free/`。

---

## make-blank-templates.sh —— 重新生成空白 Office 模板

```bash
./scripts/make-blank-templates.sh
```

改写 `LXFinderLauncher/Templates/blank.docx`、`blank.xlsx`、`blank.pptx`，**幂等**，任何时候重跑都得到内容一致的产物。

**为什么需要它**：这几种格式是 OOXML（一堆 XML 部件打成的 zip），「创建文件」功能要生成能直接双击打开的文档，写 0 字节空文件会被 Office 判为「文件已损坏」。脚本手工拼出最小可用的合法文档。把生成过程留在仓库里，是为了避免 `Templates/` 下躺着三个来源不明的二进制文件。

**什么时候要跑**：只有想改模板内容（比如换主题色、加默认字体）时才跑。跑完记得重新构建，确认新版本进了 App 的 `Contents/Resources/`：

```bash
./scripts/make-blank-templates.sh && ./scripts/build.sh
ls -l dist-build/Build/Products/Debug/LXFinderLauncher.app/Contents/Resources/
```

> `Templates/` 下的文件**不要手工编辑**——它们是 zip 包，改了就成损坏文件；下次跑脚本也会被覆盖。

---

## 发版前必看：版本号在哪里改

**唯一的版本号来源是 `LXFinderLauncher.xcodeproj/project.pbxproj` 里的 `MARKETING_VERSION`，共 6 处**（app / Tests / UITests 三个 target 各 Debug + Release 两种配置），当前值 `1.1.6`。

```bash
# 一次改掉全部 6 处
sed -i '' 's/MARKETING_VERSION = 1.1.6;/MARKETING_VERSION = 1.1.7;/g' \
    LXFinderLauncher.xcodeproj/project.pbxproj
grep -o "MARKETING_VERSION = [0-9.]*" LXFinderLauncher.xcodeproj/project.pbxproj | sort -u
```

`LXFinderLauncher/Info.plist` **不含**版本号——它靠 `GENERATE_INFOPLIST_FILE = YES` 在构建时把 `MARKETING_VERSION` 合并进去。运行时代码读的也是合并后的 `Bundle.main`，所以**不需要**改 `UpdateChecker.swift`。

改完版本号之后，还需要同步：

- `README.md` 顶部的下载入口版本号与「变更历史」章节（新条目加在最上面）
- `docs/update.json.example` 里的 `version`
- Gist 上的更新源 JSON（`UpdateChecker.feedURL` 指向的那个文件，含 `version` 与 `notes`）

> ⚠️ `docs/RELEASE.md:143` 目前写的是「改 `LXFinderLauncher/Info.plist` 的 `CFBundleShortVersionString`」——**这条已经过时了**，`Info.plist` 里根本没有这个键（构建时生成）。以本节为准。
