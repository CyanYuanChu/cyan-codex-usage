# Cyan Codex Usage

Codex 额度与本机用量。可独立运行，无需安装 Cyan Grove；也可由 [Cyan Grove](https://github.com/CyanYuanChu/cyangrove) 安装和控制。

## 下载

从 [Releases](https://github.com/CyanYuanChu/cyan-codex-usage/releases) 下载 `Cyan-Codex-Usage-macOS-arm64.zip`，解压并放入应用程序目录。最低 macOS 14.0，当前预览包仅支持 Apple Silicon。

当前版本是 **开发预览版**：安装包使用 ad hoc 签名，未做 Developer ID 公证，macOS 可能阻止首次打开。不要关闭系统安全保护；需要常规免拦截安装的用户请等待正式签名版。

## 独立使用

打开 App 后使用自己的窗口和菜单栏。关闭窗口保留后台运行；菜单中的退出才结束本模块。登录启动在 App 的设置中配置。

## 接入 Grove

通过用户私有目录中的 Unix socket 接受协议 v1 的状态、打开窗口、刷新和退出请求；不会要求 Grove 常驻，也不会监听 TCP 网络端口。Grove 退出不会结束本模块。

## 从源码构建

需要 Xcode（含 Command Line Tools）、Python 3。运行 `./scripts/build.sh`，产物在 `build/Cyan Codex Usage.app`；运行 `./scripts/check.sh` 做模块自检与签名检查。构建脚本无需其他本地仓库。`CODE_SIGN_IDENTITY` 可指定你自己的签名身份。

## 数据

配置和数据由模块自身保存。检测到旧 Cyan Grove 安装时，只迁移本模块的已知配置；卸载 App 默认保留数据。所有运行时数据、配对密钥和本地会话均不进入仓库或安装包。

## 进程验收

`python3 scripts/test-runtime.py` 验证真实进程的单实例、socket 权限、未知动作拒绝、菜单栏模式切换与干净退出。测试跳过快捷键监听及语音桥自动启动，不会发起语音任务。

## 运行前提

需要本机已登录的 Codex CLI 或包含 CLI 的桌面 App。只读额度和本机会话用量，不发起模型推理。API 等价价格为带日期的离线估算。
