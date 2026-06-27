# Windows桌面软件自更新方案复用指南

## 1. 方案定位

这套方案适用于：

- Flutter Windows 桌面软件
- 也适用于其他 Windows 原生桌面程序，只要安装器可静默安装
- 希望实现“客户端自动检查更新 -> 自动下载 -> 退出当前程序 -> 启动独立更新器 -> 静默安装 -> 自动重启新版本 -> 回写成功/失败结果”的完整闭环

这套方案在当前项目里的实际落地目标是：

- 默认支持“完整安装包更新”
- 可选支持“补丁安装包更新”
- 当前线上推荐策略是“优先只发完整安装包”，避免用户跨多个版本跳更时出现功能异常

当前项目中的实现入口主要分为五层：

1. 客户端更新状态与安装执行
2. 独立更新器窗口
3. 安装包构建脚本
4. 发布脚本
5. 更新后端服务

## 2. 当前方案真实支持范围

### 2.1 已经可稳定使用

- `installer.exe` 完整安装包更新
- `patch-installer.exe` 补丁安装包更新

### 2.2 代码里保留但当前不作为主链路

- `delta.zip + update-plan.json` 文件级增量包

注意：

- 当前服务端 `check` 接口最终返回给客户端的 `packageKind` 实际是 `installer`
- 当前客户端安装执行链路实际是“下载 `.exe` 安装器并运行它”
- 所以如果你要复用这套方法，建议先按“完整安装包更新”复用
- 如果后面确实需要再节省流量，再打开“补丁安装包”分支

## 3. 整体架构

```text
应用主程序
  -> 启动时读取版本、检查待安装任务、自动检查更新
  -> 下载 installer.exe / patch-installer.exe
  -> 把下载任务写入 data/.system_update/pending_update.json
  -> 复制一份当前程序到 staging，作为独立更新器运行

独立更新器
  -> 等主程序退出
  -> 静默启动 Inno Setup 安装器
  -> 安装器写 result 文件
  -> 安装器拉起 PowerShell helper
  -> helper 启动新版本 exe
  -> 新版本启动后写 ack 确认文件
  -> 独立更新器读取 ack，判定更新成功或失败

更新后端
  -> 存储 full.zip / manifest.json / installer.exe / patch-installer.exe
  -> 对外提供 health / history / check / publish / delete
  -> 根据客户端版本决定返回 full installer 还是 patch installer

发布工具链
  -> build windows
  -> build_update_bundle.ps1
  -> build_installer.ps1
  -> build_patch_installer.ps1（可选）
  -> publish_update_release.ps1
```

## 4. 关键目录与文件

### 4.1 客户端

- `pond5_clip_manager/lib/main.dart`
- `pond5_clip_manager/lib/app.dart`
- `pond5_clip_manager/lib/core/constants.dart`
- `pond5_clip_manager/lib/core/app_paths.dart`
- `pond5_clip_manager/lib/models/app_update_info.dart`
- `pond5_clip_manager/lib/models/app_update_state.dart`
- `pond5_clip_manager/lib/models/app_update_result.dart`
- `pond5_clip_manager/lib/services/app_version_service.dart`
- `pond5_clip_manager/lib/services/app_update_service.dart`
- `pond5_clip_manager/lib/providers/app_update_provider.dart`
- `pond5_clip_manager/lib/widgets/app_update_gate.dart`
- `pond5_clip_manager/lib/pages/app_updater_page.dart`

### 4.2 打包与发布

- `tools/build_update_bundle.ps1`
- `tools/build_installer.ps1`
- `tools/build_patch_installer.ps1`
- `tools/publish_update_release.ps1`
- `tools/installer/Pond5ClipManager.iss`

### 4.3 后端

- `tools/pond5_lunch_update_backend/app/main.py`
- `tools/pond5_lunch_update_backend/app/service.py`
- `tools/pond5_lunch_update_backend/app/config.py`
- `tools/pond5_lunch_update_backend/tests/test_service.py`
- `tools/pond5_lunch_update_backend/README.md`

## 5. 客户端完整执行链路

## 5.1 程序启动

程序启动入口在 [main.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/main.dart:10)。

启动顺序是：

1. `AppPaths.ensureDirectories()` 先确保本地数据目录和更新目录都存在
2. `AppVersionService` 读取当前版本号
3. `AppUpdateService.confirmStartupIfNeeded()` 判断这次启动是不是“更新完成后的首次启动”
4. 如果命令行带了 `--run-update-session=...`，说明当前进程不是主程序，而是“独立更新器窗口”
5. 否则正常启动主应用，并由 `AppUpdateGate` 挂到整个主界面外层

## 5.2 常驻更新入口

[app.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/app.dart:36) 把 `AppUpdateGate` 包在 `AppShell` 外层，这样整个软件生命周期都能监听更新状态。

`AppUpdateGate` 的职责：

- 首次启动时触发 `appUpdateProvider.initialize()`
- 监听“发现已下载更新包”并弹出安装对话框
- 监听“上次更新结果”并弹出成功/失败提示
- 在右下角显示下载/安装进度卡片

对应实现见 [app_update_gate.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/widgets/app_update_gate.dart:11)。

## 5.3 状态机

客户端更新状态定义在 [app_update_state.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/models/app_update_state.dart:4)：

- `idle`
- `checking`
- `downloading`
- `downloaded`
- `launchingUpdater`
- `waitingAppExit`
- `installing`
- `waitingRestart`
- `succeeded`
- `failed`

更新步骤定义在同文件：

- `checking`
- `downloading`
- `preparing`
- `closingCurrentApp`
- `installing`
- `startingNewVersion`
- `completed`

这部分很适合直接复用到其他软件，因为它已经把“用户看到的状态”和“内部真实步骤”拆开了。

## 5.4 自动检查与下载

状态流转主要在 [app_update_provider.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/providers/app_update_provider.dart:12)。

初始化时会做四件事：

1. 读取当前版本号
2. 读取上次更新结果
3. 尝试恢复待安装更新任务
4. 如果开启了自动检查，则向服务端发起更新检查

更新检查调用的是 [app_update_service.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/services/app_update_service.dart:385)：

- 请求地址：
  - `GET /api/pond5-update/v1/check/windows/x86_64/{currentVersion}`
- 返回 `204`：
  - 当前已是最新版本
- 返回 `200`：
  - 解析为 `AppUpdateInfo`

## 5.5 更新描述模型

服务端返回结果被解析为 [app_update_info.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/models/app_update_info.dart:52)：

- `currentVersion`
- `targetVersion`
- `strategy`
- `notes`
- `packageUrl`
- `packageSha256`
- `packageSize`
- `mandatory`
- `pubDate`
- `oldestSupportedVersion`
- `restartExecutable`
- `packageKind`
- `installerMode`

这里最关键的是：

- `packageKind = installer`
- `installerMode = full | patch`

其他软件复用时，建议沿用这两个字段，不要只用一个 `strategy` 硬凑，否则后续补丁安装包和完整安装包会不好区分。

## 5.6 下载与校验

下载逻辑在 [app_update_service.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/services/app_update_service.dart:413)。

实现要点：

1. 按 `packageUrl` 下载更新包
2. 下载过程中实时汇报进度
3. 计算实际 `sha256`
4. 与服务端返回的 `packageSha256` 比较
5. 如果校验失败，立即删除下载文件并报错
6. 如果成功，写入待更新任务 `PendingAppUpdateJob`

这是非常重要的一步，其他软件复用时不要省略哈希校验。

## 5.7 待更新任务持久化

待更新任务模型在 [app_update_service.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/services/app_update_service.dart:59) 的 `PendingAppUpdateJob`。

持久化文件：

- `data/.system_update/pending_update.json`

任务里会保存：

- `jobId`
- `targetVersion`
- `packagePath`
- `packageSha256`
- `startupConfirmToken`
- `resultFilePath`
- `status`
- `attemptCount`
- `lastFailureReason`
- 是否下次启动安装 / 是否下次启动提醒

这样即使主程序重启，也能恢复“这个更新包已经下载好了，还没安装”的状态。

## 5.8 启动独立更新器

一旦用户点击“立即更新”，主程序不会直接在当前进程里安装，而是：

1. 把当前程序运行目录复制到 `staging`
2. 复制 `data` 目录
3. 写入一个 `runtime_config.json`
4. 用复制出来的 exe 以独立模式再次启动

对应实现：

- 任务准备：[app_update_service.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/services/app_update_service.dart:581)
- 复制运行时：[app_update_service.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/services/app_update_service.dart:816)
- 启动独立更新器：[app_update_service.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/services/app_update_service.dart:623)

这么做的目的很明确：

- 避免“正在运行的 exe 无法被覆盖”
- 主程序可以安全退出
- 更新逻辑不会依赖主窗口是否还活着

这也是整套方案里最值得复用的设计之一。

## 5.9 独立更新器窗口

当程序通过 `--run-update-session=` 启动时，会进入 [AppUpdaterPage](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/pages/app_updater_page.dart:9)。

这个窗口只做一件事：

- 执行真正的安装流程，并把进度明确展示给用户

优点：

- 用户能知道现在处于“准备安装 / 关闭旧版本 / 安装新版本 / 启动新版本”的哪个阶段
- 即便主程序已退出，也还有单独的 UI 承接整个更新过程

## 5.10 静默安装

独立更新器的核心安装逻辑在 [app_update_service.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/services/app_update_service.dart:652)。

它会直接运行下载好的安装器，并传入这些关键参数：

- `/VERYSILENT`
- `/SUPPRESSMSGBOXES`
- `/NOCANCEL`
- `/CLOSEAPPLICATIONS`
- `/FORCECLOSEAPPLICATIONS`
- `/DIR=...`
- `/LOG=...`
- `/UPDATEJOBID=...`
- `/TARGETVERSION=...`
- `/RESULTFILE=...`
- `/EXPECTEDINSTALLDIR=...`
- `/RESTARTEXECUTABLE=...`
- `/STARTUPCONFIRMTOKEN=...`
- `/UPDATEHELPER=1`
- `/HELPERLOGPATH=...`

这一步说明：

- 安装器不是单纯“安装文件”
- 它还承担了向更新器回写结果、触发 helper 重启新版本的责任

## 5.11 安装器结果回写

安装器脚本是 [Pond5ClipManager.iss](G:/data/app/pond5_clip_manager/tools/installer/Pond5ClipManager.iss:64)。

它会把安装结果写入 `RESULTFILE` 指向的结果文件，内容大致包括：

- `status`
- `targetVersion`
- `installedExePath`
- `message`
- `logFilePath`
- `helperLogPath`
- `timestamp`

客户端再通过 [app_update_service.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/services/app_update_service.dart:966) 读取这个结果文件，判断安装是否成功。

## 5.12 安装完成后自动拉起新版本

安装器自身不会直接信任“安装成功就一定能启动成功”，而是额外拉起一个 PowerShell helper。

这个 helper 的作用：

1. 等待 `RESULTFILE` 出现
2. 读取 `installedExePath`
3. 二次确认新 exe 已存在
4. 使用 `--confirm-update-startup=` 和 `--confirm-update-target-version=` 启动新版本

对应逻辑见 [Pond5ClipManager.iss](G:/data/app/pond5_clip_manager/tools/installer/Pond5ClipManager.iss:199)。

## 5.13 新版本启动确认

新版本启动后，主程序第一时间执行 [confirmStartupIfNeeded](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/services/app_update_service.dart:310)。

它会：

1. 解析命令行里的确认 token 和目标版本
2. 把实际启动版本写入 `acks/{token}.ack`
3. 同时把“最近一次更新结果”写入 `last_update_result.json`

独立更新器再等待这个 ack 文件：

- 收到且版本一致：
  - 更新成功
- 超时未收到：
  - 更新失败
- 收到了但版本不一致：
  - 更新失败

这套“安装成功 != 更新成功，必须以新版本实际启动为准”的设计非常关键，建议在其他软件里保留。

## 6. 本地更新目录结构

更新相关目录定义在 [app_paths.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/core/app_paths.dart:77)。

根目录：

- `data/.system_update/`

子目录：

- `downloads/`
  - 下载好的安装包
- `jobs/`
  - 预留任务目录
- `staging/`
  - 临时复制出的独立更新器运行时
- `backups/`
  - 预留备份目录
- `acks/`
  - 新版本启动确认文件
- `logs/`
  - 安装日志和 helper 日志
- `results/`
  - 安装器结果文件

关键文件：

- `pending_update.json`
- `last_update_result.json`

建议其他软件也沿用这种目录分层，不要把更新缓存散落到多个位置。

## 7. 更新服务端接口契约

服务端入口在 [main.py](G:/data/app/pond5_clip_manager/tools/pond5_lunch_update_backend/app/main.py:37)。

核心接口：

- `GET /api/pond5-update/v1/health`
- `GET /api/pond5-update/v1/check/{target}/{arch}/{current_version}`
- `GET /api/pond5-update/v1/history`
- `POST /api/pond5-update/v1/releases/publish`
- `DELETE /api/pond5-update/v1/releases/{version}`
- `GET /pond5-updates/releases/{version}/full.zip`
- `GET /pond5-updates/releases/{version}/manifest.json`
- `GET /pond5-updates/releases/{version}/installer.exe`
- `GET /pond5-updates/releases/{version}/patch-installer.exe`

### 7.1 check 接口返回字段

由 [build_check_payload](G:/data/app/pond5_clip_manager/tools/pond5_lunch_update_backend/app/service.py:449) 生成。

主要字段：

- `currentVersion`
- `targetVersion`
- `strategy`
- `notes`
- `pubDate`
- `packageUrl`
- `packageSha256`
- `packageSize`
- `packageKind`
- `installerMode`
- `mandatory`
- `oldestSupportedVersion`
- `restartExecutable`

### 7.2 publish 接口上传字段

由 [main.py](G:/data/app/pond5_clip_manager/tools/pond5_lunch_update_backend/app/main.py:81) 接收。

必填：

- `version`
- `notes`
- `fullBundleZip`
- `manifestJson`
- `installerExe`

可选：

- `patchInstallerExe`

## 8. 服务端更新包选择逻辑

核心逻辑在 [service.py](G:/data/app/pond5_clip_manager/tools/pond5_lunch_update_backend/app/service.py:449) 和 [service.py](G:/data/app/pond5_clip_manager/tools/pond5_lunch_update_backend/app/service.py:489)。

返回策略如下：

1. 先找到 latest 版本
2. 默认返回 `installer.exe`
3. 如果 latest 同时带有 `patch-installer.exe`
4. 且 `patch-installer.json.baseVersion == currentVersion`
5. 就改为返回 `patch-installer.exe`
6. 否则继续返回完整安装包

这意味着：

- patch 安装包只能覆盖它的“基线版本”
- 旧版本跨级更新时，会自动回退到完整安装包

## 9. 打包产物设计

## 9.1 full bundle

[build_update_bundle.ps1](G:/data/app/pond5_clip_manager/tools/build_update_bundle.ps1:1) 会生成：

- `manifest.json`
- `package/update-plan.json`
- `package/update-plan.txt`
- `full.zip`

其中 `manifest.json` 描述所有需要发布的文件：

- 相对路径
- sha256
- size

`full.zip` 内则包含：

- `update-plan.json`
- `files/...`

虽然当前客户端主链路不直接解这个 zip，但它仍然很重要，因为：

- 服务端会校验 bundle 结构
- 以后如果要恢复文件级增量，这份 manifest 仍能直接复用

## 9.2 完整安装包

[build_installer.ps1](G:/data/app/pond5_clip_manager/tools/build_installer.ps1:1) 会：

1. 把 Release 目录复制到 `installer-staging`
2. 调用 `iscc.exe`
3. 生成 `pond5_clip_manager-V{version}-setup.exe`

Inno Setup 脚本使用的是 [Pond5ClipManager.iss](G:/data/app/pond5_clip_manager/tools/installer/Pond5ClipManager.iss:1)。

## 9.3 补丁安装包

[build_patch_installer.ps1](G:/data/app/pond5_clip_manager/tools/build_patch_installer.ps1:1) 会：

1. 对比 `FromManifest` 和 `ToManifest`
2. 只把变更文件复制进 patch staging
3. 用同一个 Inno Setup 脚本，但传 `InstallerMode=patch`

所以 patch 安装包本质上也是一个 `.exe` 安装器，只是里面带的文件更少。

## 10. 发布流程

发布脚本是 [publish_update_release.ps1](G:/data/app/pond5_clip_manager/tools/publish_update_release.ps1:1)。

标准发布顺序：

1. `flutter build windows --release`
2. 生成 `full.zip + manifest.json`
3. 生成完整安装包
4. 如有需要，再生成 patch 安装包
5. 调用发布脚本上传
6. 回读 `health / history / check`

### 10.1 仅发布完整安装包

这是当前推荐方式。

命令特征：

- 不传 `-PatchInstallerPath`

效果：

- 服务端只存 `installer.exe`
- 客户端统一拿完整安装包

### 10.2 同时发布 patch 安装包

命令特征：

- 额外传 `-PatchInstallerPath`

效果：

- 服务端保存 `patch-installer.exe`
- 并写入 `patch-installer.json.baseVersion`
- 只有 baseVersion 命中的客户端才会拿到 patch

## 11. 后端存储设计

服务端每个版本一个目录，典型结构如下：

```text
storage/
  releases/
    4.81.16/
      full.zip
      manifest.json
      installer.exe
      patch-installer.exe            # 可选
      patch-installer.json           # 可选
      bundle/
        update-plan.json
        files/...
```

数据库里记录：

- `version`
- `major/minor/patch`
- `notes`
- `target`
- `arch`
- `published_at`
- `full_bundle_sha256`
- `full_bundle_size`
- `manifest_sha256`
- `manifest_size`

当前配置默认只保留 `1` 个 latest 版本，因此更偏向“正式服单版本覆盖式更新”。

## 12. 迁移到其他软件时必须替换的内容

如果你要把这套方案复用到别的软件，至少要替换下面这些标识。

### 12.1 客户端常量

在 [constants.dart](G:/data/app/pond5_clip_manager/pond5_clip_manager/lib/core/constants.dart:44)：

- `defaultUpdateServerBaseUrl`
- `installConfigFile`
- 更新命令行参数前缀

### 12.2 可执行文件名

所有出现 `pond5_clip_manager.exe` 的地方都要改成你的软件 exe 名：

- `build_update_bundle.ps1`
- `Pond5ClipManager.iss`
- `app_update_info.dart`
- `app_update_service.dart`
- 服务端 manifest 默认值

### 12.3 Inno Setup 安装器标识

在 [Pond5ClipManager.iss](G:/data/app/pond5_clip_manager/tools/installer/Pond5ClipManager.iss:1)：

- `MyAppName`
- `AppId`
- 默认安装目录
- 默认开始菜单名称
- 图标路径

`AppId` 一定要换成新的 GUID，不能和原软件共用。

### 12.4 服务端路径与接口前缀

在后端配置里要改：

- 静态资源路径
- 存储目录
- 服务名
- 接口前缀
- Basic Auth 账号密码

### 12.5 发布脚本默认文件名

在 [publish_update_release.ps1](G:/data/app/pond5_clip_manager/tools/publish_update_release.ps1:35)：

- 默认 bundle 目录名
- 默认安装包文件名

### 12.6 用户数据目录

如果新软件的数据目录结构和当前项目不同：

- `AppPaths` 要重新适配
- 安装器写入的 `runtime_config.json` 也要同步调整

## 13. 推荐复用策略

如果是新软件第一次接入自更新，建议分三阶段。

### 阶段一：先只做完整安装包更新

原因：

- 最稳
- 逻辑最简单
- 不依赖 patch 基线
- 用户跨版本升级最不容易出错

### 阶段二：补上独立更新器和启动确认

原因：

- 单纯“下载后让用户自己安装”不算完整闭环
- 只有加入独立更新器、结果文件和 ack 机制，才能真正做到自动更新

### 阶段三：最后再考虑 patch 安装包

原因：

- patch 只适合连续版本
- 多人协作、多分支发布、跳版本升级时更容易出现基线问题

## 14. 已知注意事项

### 14.1 patch 安装包不适合随意跨版本

如果发布顺序错了，或者 latest 基线不是你预期的上一版，就会导致 patch 命不中。

### 14.2 “安装成功”不等于“更新成功”

必须保留 ack 机制，以“新版本真的启动了”作为最终成功判定。

### 14.3 更新器一定要脱离主程序运行

否则你会遇到：

- exe 被占用
- dll 被锁定
- 安装器无法覆盖

### 14.4 发布后一定要回读 check 接口

至少验证：

- `health.latestVersion`
- `history[0].version`
- `check(old_version)`
- `check(latest_version)`

### 14.5 默认全量安装包更适合生产稳定性

尤其是用户可能跳过多个版本时，完整安装包更稳。

## 15. 最小可复用清单

如果你要最快把它挪到另一个软件，最少要带走这些内容：

1. `AppUpdateService`
2. `AppUpdateProvider`
3. `AppUpdateGate`
4. `AppUpdaterPage`
5. `AppUpdateInfo / State / Result`
6. `AppPaths` 更新目录定义
7. `build_update_bundle.ps1`
8. `build_installer.ps1`
9. `publish_update_release.ps1`
10. `Pond5ClipManager.iss`
11. `pond5_lunch_update_backend`

如果只复制其中一半，通常会缺：

- 更新任务恢复
- 安装结果回写
- 新版本启动确认
- 线上发布链路

## 16. 推荐验收清单

迁移到其他软件后，至少做下面这些测试。

### 16.1 客户端侧

- 当前已是最新版时返回 `204`
- 发现新版本时能正常弹更新对话框
- 下载完成后能保留任务，重启后仍可继续安装
- 点击“立即更新”后能拉起独立更新器

### 16.2 安装器侧

- 静默安装能覆盖原目录
- `RESULTFILE` 能正确写出
- helper 能自动拉起新版本

### 16.3 启动确认侧

- 新版本首次启动后能写 ack
- 独立更新器能正确判定 success
- 故意让新版本不启动时，能正确判定 failure

### 16.4 服务端侧

- 发布完整安装包成功
- `check(old_version)` 返回完整安装包
- patch 发布时，仅 baseVersion 命中的版本返回 patch

## 17. 当前项目的复用结论

对于其他软件，当前最推荐直接复制的方案是：

- 保留这套“独立更新器 + Inno Setup 安装器 + helper 自动重启 + ack 启动确认 + FastAPI 发布后端”
- 发布策略先只用“完整安装包”
- 等新软件跑稳定以后，再决定是否启用 `patch-installer.exe`

一句话总结：

这套方案的核心不是“下载更新包”，而是“把更新过程从主程序里剥离出来，并且用安装结果文件和启动确认文件把整个过程闭环起来”。
