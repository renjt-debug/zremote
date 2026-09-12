# ZRemote 安全审查与修复记录

日期：2026-09-12。基线提交：`22726647ef7b2e558d5b48795391b078d5a8d42e`，审查与修复对象为当前工作区（包括已有的未提交更改）。

## 结论与范围

在项目自有 Dart、Kotlin、Swift 代码和构建/发布脚本中，未发现明确的恶意后门、隐藏系统命令执行、额外凭据回传地址或下载执行载荷。发现的认证失败放行、网页信任边界及依赖桥接问题属于真实安全缺陷；没有证据据此认定作者恶意。

已检查启动与生命周期、设备链接和安全存储、WebView/JavaScript 数据流、通知和保活服务、Android 合并清单、iOS 原生入口、依赖锁及 GitHub Actions。进一步读取了本地 WebView 插件关键原生实现，并检查了现有本地 APK 的签名。审查没有连接用户的远程设备，也没有读取或上传真实控制链接。

这不是对所有第三方源码、线上网页、远程中继/桌面端或公开下载 APK/IPA 的完整审计，不能将“未发现后门”理解为对整个运行环境的保证。

## 已确认问题与修复

| 优先级 | 问题及触发条件 | 修复 |
| --- | --- | --- |
| 高 | Android WebView 插件 1.1.3 的 `JavaScriptBridgeInterface._callHandler` 将网页可控回调 ID 直接拼接到主页面 JavaScript。接口可由子框架调用，成功和错误返回路径均有问题；恶意表达式有机会在主页面上下文执行，危及其控制链接与会话。 | 保留稳定版必要源码及 Apache 2.0 许可证，在 `third_party/flutter_inappwebview_android` 应用本地补丁，并通过依赖覆盖固定使用。原生入队前只接受 1–20 位 ASCII 数字 ID、非空参数引用及最多 8 MiB UTF-8 参数。详细变更见同目录 `PATCHES.md`。iOS 对该字段转换为 `Int64`，未发现同一字符串插值问题。 |
| 高（此前已修）/中（本次补齐） | 启动门禁原先在认证不可用时直接解锁；设置页关闭安全锁时仍在同类异常下直接保存关闭。设置页路径需要已经能访问设置，不能等同于冷启动绕过。 | 两条路径均要求认证成功，异常或取消不再关闭安全开关；设置页处理可用性检查异常及验证期间页面退出的情况。 |
| 中 | 仅在内容上方覆盖锁屏，底层已聚焦的控件仍可接收硬件键盘输入；退后台时未立即遮挡，可能暴露任务切换快照。 | 锁定/后台时增加 `ExcludeFocus`、`IgnorePointer` 与立即遮挡。Android 开启应用锁时设置 `FLAG_SECURE`；iOS 加原生后台遮挡并等待 Flutter 安全前台帧后移除。保留原 10 秒重认证宽限和后台会话保活。 |
| 中 | 任意 HTTP(S) 域名只要带 `sid`/`hash` 即可导入，WebView 无应用层导航来源限制，桥接处理器不鉴别调用来源。 | 按用户选择，仅允许精确的 `https://zcode.z.ai`、443 端口且无 userinfo 的地址。拒绝重复/畸形/过长参数，重新验证旧存储链接；非法链接不创建 WebView。限制主页面导航、禁用子框架加载、文件与明文混合访问；观察脚本仅在官方主框架执行，桥接要求每个会话独立的随机令牌。 |
| 中 | 消息大小部分依赖远端 `messageBytes`；字符串消息、分片累计内存和 fetch 克隆响应读取缺少完整界限。 | 按实际 UTF-8/解码字节校验，限制分片数量、编号、累计内存和过期时间；防重复分片/原型键问题。限制消息队列和并发读取，流式读取使用固定大小缓冲、限制块数，超限取消观察器的读取，不保留无限分块数组/Promise 链。 |
| 发布加固 | 缺少正式密钥会回退 debug 签名；CI SDK 与当前锁文件不一致，第三方 Actions 使用可移动标签，旧 Gradle wrapper 不支持分发包 SHA256 校验。 | 缺少有效签名配置时拒绝 release 任务，CI 明确要求密钥；统一 Flutter 3.47.4、强制锁文件、固定 Actions 提交。升级为官方 Gradle 8.14 wrapper 并核对 JAR 校验值、配置发行包校验值。debug 构建保持可用。 |

其他修复：更新设备拖拽 API 以通过当前 SDK 静态检查，保持原索引语义；更新中英文拒绝链接提示与构建文档。

## 后门排查证据

- 项目自有运行时代码没有额外的硬编码上报服务器。原有 fetch、WebSocket、EventSource 包装将网页事件送入本地状态/通知，未发现额外网络发送分支。这不等于第三方 SDK 或动态网页不会联网。
- Android 的保活服务非导出、不可绑定，仅处理固定保活通知、唤醒锁和屏幕事件；原生 MethodChannel 处理固定的保活、电池与应用设置操作。没有任意命令或任意文件读取接口。
- 设备凭据通过 `flutter_secure_storage` 保存，Android 应用禁用备份。应用锁是交互门禁，启用后仍保留后台会话；不声称每次读取密钥都受生物识别硬件约束。
- 未发现应用主动忽略 TLS 证书错误的代码。
- 原先本地 `build/app/outputs/flutter-apk/app-release.apk` 签名验证有效，但证书为 `CN=Android Debug`，证书 SHA256 为 `c510a0534a2da9385c967d69f43ace29628e4048fecb8778b4c78990503a4f0d`。这只描述该现有本地产物，不证明公开下载包使用同一签名，也不表示修改后的源码已进入旧包。

## 验证

- 修复前基线：278 项 Flutter 测试通过。
- 修复后：289 项 Flutter 测试通过，包含真实 Node.js 引擎执行的观察器脚本测试、门禁异常、锁定后硬件键盘焦点、后台遮挡、设置持久化以及旧非法链接不创建 WebView 的测试。
- `flutter analyze --no-pub`：无问题。
- `flutter pub get --offline --enforce-lockfile`：通过。
- `:flutter_inappwebview_android:testDebugUnitTest`：6 项 Java 测试通过；`:app:compileDebugKotlin`：构建成功，覆盖 Android 原生及依赖编译。
- `:app:assembleRelease --dry-run`：在缺少正式签名密钥的当前环境中，按预期在执行构建前拒绝。
- Gradle 8.14 wrapper JAR SHA256：`7d3a4ac4de1c32b59bc6a4eb8ecb8e612ccd0cf1ae1e99f66902da64df296172`，与 [Gradle 官方校验值](https://services.gradle.org/distributions/gradle-8.14-wrapper.jar.sha256) 一致。
- [OSV API](https://api.osv.dev/v1/querybatch) 对当前锁文件的 108 个公开 Pub 包版本查询（2026-09-12）：未返回已登记漏洞。包括原生桥接问题在内的未登记漏洞不会因此被排除；未将此结果扩大为 Maven/系统 WebView 漏洞扫描结论。
- `git diff --check`：通过。执行日志保存在本地 `build/security-audit-*`，未提交生成物。

## 实际使用和剩余验证范围

- 已保存的非官方链接会被拒绝，需使用官方二维码替换。子框架和跨域主页面跳转受限，需在真实手机上验收当前线上控制页面的业务兼容性。
- Android 应用锁开启后，截图/录屏会受到系统限制。iOS 改动用于后台快照遮挡，不宣称可禁止前台系统截图；本机为 Windows，未完成 Xcode 编译或 iOS 真机验收。
- Flutter 测试验证了焦点策略，不能替代手机系统 WebView、硬件键盘、系统认证与任务快照时序的设备测试。
- 未做运行流量抓包、服务器端认证/令牌撤销测试、公开下载包与源码的可复现构建比对；不能证明现有安装包已经包含这些修复。
- 安全审查结束时尚未配置正式签名密钥，未生成或发布新的正式 APK/IPA；之后用户要求构建 APK，结果记录在下方。原来的 debug 签名包应视为开发产物。
- 构建仍有上游 Gradle/Kotlin 兼容性弃用警告，但本轮验证成功；没有为消除警告进行未经必要验证的主版本升级。

## 维护约束

本地 WebView 补丁是审查后的源码依赖，不是修改全局 Pub 缓存。升级时必须复核原生桥接输入校验的等效修复，保留回归测试；不要直接删除 `dependency_overrides`。CI 已配置 Node.js 测试运行时及 Android 补丁单元测试，并固定 Actions 提交和 Flutter SDK。

## 后续 release APK 构建（2026-09-12）

按用户要求生成了本地专用发布密钥，并执行 `flutter build apk --release --no-pub`，构建成功。

- 产物：`build/app/outputs/flutter-apk/app-release.apk`，71,724,546 字节；版本 `1.4.0`，versionCode `7`，包名 `com.pjpv.zremote`。
- 包含 `arm64-v8a`、`armeabi-v7a`、`x86_64`；未启用 `debuggable` 或 `testOnly`。
- `apksigner verify --verbose --print-certs` 通过（APK v2 签名）。证书为 `CN=ZRemote Local Release`，RSA 3072 位，属于本次新生成的本地发布身份，并非原作者的签名。
- APK SHA256：`95f6db5a7b2b8053635c7d6208fca8e56307571a946e9278c9755d1677ef59a7`，同目录提供 `.sha256` 文件。
- 签名证书 SHA256：`8b3abba69db58b8b87da9842ec1ae437cb239b7e8b10660fb94b37589959ac83`。
- 私钥保存在 `android/app/zremote-release.jks`，密码配置保存在 `android/key.properties`，均已被 Git 忽略并收紧 Windows 文件访问权限；密码没有写入构建日志或审查记录。必须安全备份这两份文件，后续更新继续使用同一密钥。
- 新签名不能直接覆盖不同签名的已安装版本。本次没有安装到手机、上传或公开发布，也没有构建 iOS 安装包。
