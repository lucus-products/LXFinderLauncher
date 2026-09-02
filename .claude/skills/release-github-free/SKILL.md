---
name: release-github-free
description: 按标准化流程以 GitHub Free 免费分发方式发布 LXFinderLauncher 新版本（改版本号 → 构建打包 → 发布 GitHub Release → 更新 Gist 更新源 → 推送代码）。适用于「发新版本」「发版」「发布 vX.Y.Z」「更新一版」等请求。
---

# 发布 LXFinderLauncher 新版本（GitHub Free 免费分发）

> 目标：一次走通发版全流程，**不遗漏任何步骤**。按 1→8 顺序执行，**每步完成并验证后再进入下一步**，不得跳步。

## 0. 关键事实（只读参考，勿擅自改动）

| 项 | 值 |
|---|---|
| Xcode 工程 | `LXFinderLauncher.xcodeproj`，版本号在 `project.pbxproj` 的 `MARKETING_VERSION`（**Debug + Release 两处**） |
| 打包脚本 | `./scripts/distribute-free.sh` → 产物 `dist-free/LXFinderLauncher.{app,zip,dmg}` |
| 更新源 Gist | `lucus-linx/b7a192370a3b6ff689faa3a0c3325a8c`，文件名 `LXFinderLauncher-update-info.json` |
| App 内 feedURL | `LXFinderLauncher/UpdateChecker.swift` → 指向上述 Gist（一般无需改） |
| GitHub 仓库 | `lucus-products/LXFinderLauncher`（免费分发，未签名） |

## 1. 确定版本号

- 按语义选择：主版本（破坏性/大改）→ 次版本（新功能）→ patch（修复）。例：修复 `1.1.0 → 1.1.1`。
- 版本号必须是 `X.Y.Z`，且**不得与已发布 tag 重复**（`gh release list` 核对）。
- 确认三处将一致：`MARKETING_VERSION` / GitHub tag `vX.Y.Z` / Gist `version`（Gist 里**不带 v**）。

## 2. 更新工程版本号与文档

1. `project.pbxproj`：`MARKETING_VERSION` 改为 `X.Y.Z`（**两处**，Debug + Release，用 replace_all）。
2. `README.md`：
   - 变更历史**顶部**新增 `### VX.Y.Z · 说明` 条目（最新在上）；
   - 顶部下载入口 `（v旧版）` → `（vX.Y.Z）`。
3. `docs/update.json.example`：`"version"` → `"X.Y.Z"`。

## 3. 构建打包

```bash
./scripts/distribute-free.sh
```

**必须验证产物**（缺一不可）：
- `plutil -extract CFBundleShortVersionString raw dist-free/LXFinderLauncher.app/Contents/Info.plist` == `X.Y.Z`；
- `unzip -p dist-free/LXFinderLauncher.zip "LXFinderLauncher.app/Contents/MacOS/LXFinderLauncher" | strings | grep "gist.githubusercontent.com/lucus-linx"` 含正确 Gist ID（说明更新检查仍指向真实源）；
- zip 内**无** `LXFinderLauncher.debug.dylib`（Release 单二进制）。

## 4. 发布 GitHub Release

```bash
gh release create vX.Y.Z dist-free/LXFinderLauncher.zip \
  --repo lucus-products/LXFinderLauncher \
  --title "LXFinderLauncher vX.Y.Z" \
  --notes "本次更新说明"
```

- 附件文件名**必须保持 `LXFinderLauncher.zip` 不变**（latest 固定链接按文件名匹配，改名则 404）。
- 验证：`gh release view vX.Y.Z --repo lucus-products/LXFinderLauncher` 输出含 `asset: LXFinderLauncher.zip`。

## 5. 更新 Gist 更新源（version）

用 API 更新（**勿用 `gh gist edit`**，那会改文件名）：

```bash
gh api gists/b7a192370a3b6ff689faa3a0c3325a8c -X PATCH \
  -F 'files[LXFinderLauncher-update-info.json][content]={"version":"X.Y.Z","downloadURL":"https://github.com/lucus-products/LXFinderLauncher/releases/latest/download/LXFinderLauncher.zip"}'
```

- 验证：`gh api gists/b7a192370a3b6ff689faa3a0c3325a8c --jq '.files["LXFinderLauncher-update-info.json"].content | fromjson | .version'` == `X.Y.Z`。
- `downloadURL` **不要改**（latest 固定链接，永远指向最新版同名 zip）。

## 6. 提交推送代码

```bash
git add -A && git commit -m "build: 发布 vX.Y.Z ..." && git push
```

- 国内访问 GitHub 偶发超时：push 失败**重试最多 3 次**（`git push` 或 `git push origin main`）。
- 确认 `git status` 干净、`git status -sb` 显示 `## main...origin/main`（无 ahead/behind）。

## 7. 最终自检（发版后）

- [ ] `gh api repos/lucus-products/LXFinderLauncher/releases/latest --jq '.tag_name'` == `vX.Y.Z`
- [ ] `gh release list --repo lucus-products/LXFinderLauncher` 最新一条是 vX.Y.Z
- [ ] Gist `version` == `X.Y.Z`（步骤 5 已验证）
- [ ] 下载链接可用：`curl -sIL -o /dev/null -w "%{http_code}" "https://github.com/lucus-products/LXFinderLauncher/releases/latest/download/LXFinderLauncher.zip"` == `200`（偶发超时则重试，200 才算过）

## 8. 收尾提醒

- 若本次是**修复后发布**：提醒用户同版本号重发时，已装用户收不到更新提示（`isNewer` 版本相等）；要触发升级必须升 patch 版本。
- 若需要**重建 Gist**：`gh gist create` 的 `--filename` 参数**无效**，Gist 文件名取**本地文件名**——必须先用本地名为目标文件名的文件上传。

## 常见坑（发布前逐条排查）

1. **版本号三处不一致**：工程 / tag / Gist 必须同一版本，缺一即 App 检查更新失效或提示错误。
2. **zip 被改名**：上传时确保叫 `LXFinderLauncher.zip`，否则 latest 下载 404。
3. **feedURL 404**：Gist 文件名必须与 feedURL 中 `/raw/<文件名>` 完全一致；文件名用项目前缀（`LXFinderLauncher-update-info.json`）避免多项目 Gist 重名。
4. **push 网络失败**：国内访问 GitHub 偶发超时，重试即可，不是代码问题。
5. **误传 Debug 产物**：Debug 构建含 `debug.dylib` 薄壳，只发 Release 单二进制。
