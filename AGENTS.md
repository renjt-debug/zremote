# Agent 交接说明

本文件适用于整个仓库。以下是 **2026-09-12** 的工作交接，后续操作前请核对当前文件和 `git status`，不要把历史验证结果当作当前代码的保证。工作区已有多项未提交的安全修复，勿重置或覆盖。

## 先了解这些背景

用户已要求完成项目安全/后门审查、修复确认的问题，并构建 release APK。审查结论是：在已检查的项目代码中未发现明确恶意后门，但确实发现并修复了安全缺陷；没有对整个运行环境作“绝对安全”的保证。

详细证据、修复范围及验证限制见 [安全审查记录](docs/SECURITY_REVIEW.zh-CN.md)。Android WebView 的本地补丁见 [PATCHES.md](third_party/flutter_inappwebview_android/PATCHES.md)。

## 发布签名：必须保留已有身份

**已经生成并使用过专用发布密钥。后续构建应复用，不要因为找不到文件、访问被拒绝或构建失败就重新生成密钥。**

- 本机私钥：`android/app/zremote-release.jks`。
- 本机签名配置：`android/key.properties`，包含密码；`keyAlias` 为 `zremote`，`storeFile` 相对于 `android/app`。
- 两个文件均被 Git 忽略，并已收紧 Windows 文件访问权限。因此，新 checkout 不会自动带上它们；缺失时应使用用户保存的原密钥备份。
- 不要输出、提交、上传私钥或密码，不要把密码写入 Markdown、日志或命令行参数。需要调用 keytool 时可通过进程环境变量传密码，并在使用后清除。
- 证书名称：`CN=ZRemote Local Release`，RSA 3072 位。这是本地发布身份，**不是原作者的签名**。
- 证书 SHA256：`8b3abba69db58b8b87da9842ec1ae437cb239b7e8b10660fb94b37589959ac83`。
- 不同签名的 APK 不能直接覆盖安装；不要自动卸载用户现有应用，以免丢失数据。只有用户明确要求更换签名身份时才考虑新密钥。
- release 构建在缺少有效签名配置时必须失败。不要恢复 debug 签名回退，也不要为了构建成功绕过签名检查。

## 已生成的 APK

这是历史产物记录；重新构建后应重新校验，不要沿用旧哈希。

- 路径：`build/app/outputs/flutter-apk/app-release.apk`。
- 校验文件：同目录 `app-release.apk.sha256`。
- 版本：`1.4.0`，versionCode `7`，包名 `com.pjpv.zremote`。
- 大小：71,724,546 字节；架构：`arm64-v8a`、`armeabi-v7a`、`x86_64`。
- APK SHA256：`95f6db5a7b2b8053635c7d6208fca8e56307571a946e9278c9755d1677ef59a7`。
- `apksigner verify --verbose --print-certs` 已通过；APK v2 签名，未启用 `debuggable` 或 `testOnly`。
- 已完成本地构建，未安装到手机、未上传或公开发布，未构建 iOS 安装包。

## 不要撤销的安全约束

1. **用户明确选择只允许官方域名**：控制链接仅接受 `https://zcode.z.ai`、443 端口且无 userinfo。旧存储链接也要检查；不要重新开放任意域名或 HTTP。
2. 启动解锁及关闭安全开关都必须认证成功；认证取消、不可用或异常时保持安全状态，不可自动关闭锁。保持锁定时的焦点/输入隔离与后台隐私遮挡。
3. `pubspec.yaml` 的 `flutter_inappwebview_android` 本地 `dependency_overrides` 是有意的安全补丁。上游 1.1.3 原生桥曾将网页可控回调 ID 拼入主页面 JavaScript；升级或移除覆盖前必须确认等效修复，并保留原生回归测试。不要仅为消除 override 提示而删掉它。
4. 保持 WebView 来源/导航限制、仅主框架观察脚本、每会话随机桥接令牌及消息/分片/流式读取边界。`sid`、`hash` 和完整控制链接应按凭据对待，勿记录到日志或文档。
5. 保持正式签名要求、依赖锁校验、Actions 提交固定及 Gradle wrapper 校验。不要为消除弃用警告直接进行未经验证的构建工具主版本升级。

应用锁仍是交互门禁；后台会话按产品设计继续工作。Android 锁开启时使用 `FLAG_SECURE`；iOS 是后台快照遮挡，不声称可禁止前台系统截图。

## 本机工具与构建

已确认本机安装了 Flutter 和 Dart。`Get-Command` 无结果只能说明当前 PATH 未找到，不能据此断言没有安装；应继续检查 `android/local.properties` 和 SDK 路径。

- 已验证 SDK：Flutter 3.47.4 / Dart 3.13.3，与 CI 一致。
- 本机 Flutter：`D:\software\AndroidDevelop\flutter\bin\flutter.bat`。
- 本机 JDK：`D:\software\AndroidDevelop\jdk-17`。
- 本机 Android SDK：`D:\software\AndroidDevelop\Android\Sdk`；构建工具 36.0.0 可用。
- JavaScript 安全测试需要 Node.js；CI 配置 Node.js 22。

常用命令（在仓库根目录）：

```text
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub
```

缓存完整时可给 `pub get` 加 `--offline`。Android 桥接补丁测试在 `android` 目录执行：

```text
gradlew.bat :flutter_inappwebview_android:testDebugUnitTest
```

首次 checkout 应先通过 Flutter 构建初始化 Android 本地配置，再直接执行 Gradle。没有发布密钥时可以使用 `flutter build apk --debug --no-pub` 做开发验证。

Flutter 启动器需要写入 SDK 缓存；受限执行环境曾因缓存锁访问受限而静默等待。遇到这种情况应检查日志和权限，使用环境提供的授权执行机制，不要反复启动进程或擅自删除其他进程的锁。签名文件访问被拒绝时同样先核对权限，不要替换密钥。

重新生成 release APK 后，至少验证签名、证书指纹、版本/包名、调试标记和文件 SHA256；更新产物记录，明确区分本地构建与实际发布。

## 已完成验证与剩余范围

- 安全修复后：289 项 Flutter 测试通过，`flutter analyze` 无问题。
- Android 桥接补丁：6 项 Java 单元测试通过；Android 原生编译、后续 release APK 构建均成功。
- 修复时的无密钥 release 拒绝测试通过；**这是添加发布密钥之前的测试，现在本机已有密钥**。
- OSV 查询当时锁定的 108 个公开 Pub 包版本，未返回已登记漏洞；不等于所有依赖和未知漏洞均被排除。
- Windows 上尚未完成 Xcode 编译、iOS 真机、真实 WebView/硬件键盘与线上控制流程验收，也没有进行服务器审计或运行流量抓包。
- 审查日志位于 `build/security-audit-*`，发布构建日志为 `build/release-build.log`；这些生成文件可能被清理，长期结论以审查记录为准。

后续修改运行逻辑时执行相应回归；纯文档改动不需要重跑全部构建。涉及新的源码或构建变化时，不要把以上历史通过结果当作新改动已通过验证。
