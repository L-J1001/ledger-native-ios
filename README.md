# 记账本 · 原生 iPhone 版

这是独立于安卓 WebView 壳的原生 SwiftUI 工程。它不复制 `apk/` 的壳，也不修改现有桌面账本、PWA 或 `E:\记账本\data`。

## 已实现

- 原生 SwiftUI 界面，4 个主 Tab：首页、明细、统计、设置
- 本地优先：无网也能记，数据落在本机 Application Support
- 登录现有云端账号后双向同步：`/v1/login`、`/v1/books`、`/v1/push`、`/v1/pull`
- 金额按“分”存储，和桌面 `records.amount` 完全一致；同时发送 `amount` 元字段，兼容现有 PWA
- 记录编辑、删除、按日期分组、搜索、支出/收入筛选
- 原生金额键盘、分类 Chips、保存并继续、触觉反馈
- 月度收支、分类占比、最近 7 天趋势
- CSV 导出（分享到文件/微信/邮件）
- Token 存 Keychain，不写进普通 JSON

## 构建说明

当前本机是 Windows，没有 Xcode，不能在本机编译出 IPA。已提供 GitHub Actions 的 macOS 构建链：

1. 新建一个 GitHub 仓库（建议 Private，只自己用）。
2. 把本目录 `ios-native` 的内容作为仓库根目录推送。
3. 打开 Actions → `Build iOS unsigned IPA` → Run workflow。
4. 构建完成后下载 artifact `LedgerNative-unsigned-ipa`，里面是 `LedgerNative-unsigned.ipa`。
5. 在 Windows 用 Sideloadly（或 AltStore）用免费 Apple ID 签名安装。
6. iPhone 设置 → 隐私与安全性 → 开发者模式，打开并重启；首次运行还要在“VPN 与设备管理”里信任你的开发者证书。

如果构建时报签名错误，确认 workflow 里的 `CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO`、`CODE_SIGN_IDENTITY=""` 三行都在；这个工程本身不依赖开发者证书，签名是在 Sideloadly 那一步做的。

## 签名限制（必须知道）

- 免费 Apple ID 的签名 **7 天有效**。到期 App 会打不开，需要重新用 Sideloadly 签名覆盖安装。
- 覆盖安装时不要先卸载，本机数据会保留；卸载会清掉本机数据。
- 想要真正长期免续签，只能走 99 美元/年的 Apple Developer Program，或继续用现有 PWA。
- 这个 IPA 是 **unsigned**，不能直接双击安装；必须经过签名。

## 云端账号

登录时使用现有记账本账号（手机 PWA 同一个账号）。登录成功后会自动拉取该账号的账本和记录；手机上新记的会进入 outbox，联网后自动推送。

默认服务地址：

`https://ledger-sync-9eb2fc.pages.dev`

登录响应会返回真实 endpoint，客户端会以服务端返回的地址为准。

## 不做的事

- 不读取或写入 `E:\记账本\data` 的真实账目
- 不修改桌面端、维护工具、PWA
- 不把密码写进本地文件；密码只在登录请求中使用，Token 存 Keychain
- 不做多用户注册、邀请码、管理后台；这是单人自用客户端
