# flutter_logs

本项目基于 [flutter_logs](https://pub.dev/packages/flutter_logs) 开发。

## 简介

`flutter_logs` 是一个面向 Flutter 应用的文件日志框架，支持日志分级、日志文件管理、日志导出，以及与 ELK 元信息和 MQTT 上报场景结合使用。<br/>

## 下载安装

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

```yaml
dependencies:
  flutter_logs:
    git:
      url: https://gitcode.com/OpenHarmony-Flutter/fluttertpc_flutter_logs
      ref: 2.2.1-ohos-1.0.0
```

执行命令

```bash
flutter pub get
```

> TAG 命名规则：`原库版本-ohos-版本号-betax`，不同 TAG 之间的变更详见 OHOSCHANGELOG.md。

| Flutter 框架版本 | TAG 名称 | 备注 |
| ---------------- | ----------------------- | ---- |
| 3.22.1-ohos-1.1.0 | 2.2.1-ohos-1.0.0 | |
| 3.27.5-ohos-1.0.4 | 2.2.1-ohos-1.0.0 | |
| 3.35.8-ohos-0.0.2 | 2.2.1-ohos-1.0.0 | |

## 约束与限制

### 兼容性

在以下版本中已测试通过

1. Flutter: 3.22.1-ohos-1.1.0; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.0.830; ROM: 6.0.0.130 SP25;
2. Flutter: 3.27.5-ohos-1.0.4; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.0.830; ROM: 6.0.0.130 SP25;
3. Flutter: 3.35.8-ohos-0.0.2; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.0.830; ROM: 6.0.0.130 SP25;

### 权限要求

本库不需要额外申请权限。

## 使用示例

以下示例演示日志初始化、写入与导出流程：<br/>

```dart
import 'package:flutter_logs/flutter_logs.dart';

Future<void> setupAndWriteLogs() async {
  // 1) 初始化日志系统
  await FlutterLogs.initLogs(
    logLevelsEnabled: [LogLevel.INFO, LogLevel.ERROR],
    timeStampFormat: TimeStampFormat.TIME_FORMAT_READABLE,
    directoryStructure: DirectoryStructure.FOR_DATE,
    logTypesEnabled: <String>['app_log'],
    logFileExtension: LogFileExtension.LOG,
    logsWriteDirectoryName: 'MyLogs',
    logsExportDirectoryName: 'MyLogs/Exported',
    enabled: true,
  );

  // 2) 写入日志
  await FlutterLogs.logThis(
    tag: 'Demo',
    subTag: 'setup',
    logMessage: 'flutter_logs initialized',
    level: LogLevel.INFO,
  );

  // 3) 导出日志
  await FlutterLogs.exportLogs(exportType: ExportType.ALL);
}
```

## 接口说明

### API

> [!TIP] "ohos Support"列为 yes 表示 ohos 平台支持该属性，no 则表示不支持。使用方法跨平台一致，效果对标 IOS 或 Android 的效果。

#### FlutterLogs

| 名称 | 类型 | 参数类型 | 返回值 | OHOS 平台支持 | 描述 |
| --- | --- | --- | --- | --- | --- |
| setDebugLevel() | 方法 | int value | void | yes | 设置调试输出等级（0/1/2） |
| initLogs() | 方法 | `List<LogLevel> logLevelsEnabled, TimeStampFormat timeStampFormat, DirectoryStructure directoryStructure, List<String> logTypesEnabled, LogFileExtension logFileExtension, String logsWriteDirectoryName, bool debugFileOperations, bool isDebuggable, bool enabled` | `Future<String>` | yes | 初始化日志系统 |
| initMQTT() | 方法 | `String topic, String brokerUrl, String certificate, String port, bool writeLogsToLocalStorage, bool debug` | `Future<String?>` | yes | 初始化 MQTT 上报配置 |
| setMetaInfo() | 方法 | `String appId, String appName, String appVersion, String deviceId, String environmentId, String userId` | `Future<String>` | yes | 设置 ELK 元信息 |
| logThis() | 方法 | `String tag, String subTag, String logMessage, LogLevel level, Exception exception, Error error` | `Future<void>` | yes | 写入通用日志 |
| logInfo() | 方法 | `String tag, String subTag, String logMessage` | `Future<void>` | yes | 写入 INFO 级别日志 |
| logWarn() | 方法 | `String tag, String subTag, String logMessage` | `Future<void>` | yes | 写入 WARNING 级别日志 |
| logError() | 方法 | `String tag, String subTag, String logMessage` | `Future<void>` | yes | 写入 ERROR 级别日志 |
| logErrorTrace() | 方法 | `String tag, String subTag, String logMessage, Error e` | `Future<void>` | yes | 写入错误堆栈日志 |
| logToFile() | 方法 | `String logFileName, bool overwrite, String logMessage, bool appendTimeStamp` | `Future<void>` | yes | 写入指定文件 |
| printLogs() | 方法 | `ExportType exportType, bool decryptBeforeExporting` | `Future<void>` | yes | 打印日志 |
| exportLogs() | 方法 | `ExportType exportType, bool decryptBeforeExporting` | `Future<void>` | yes | 导出日志压缩包 |
| printFileLogForName() | 方法 | `String logFileName, bool decryptBeforeExporting` | `Future<void>` | yes | 打印指定文件日志 |
| exportFileLogForName() | 方法 | `String logFileName, bool decryptBeforeExporting` | `Future<void>` | yes | 导出指定文件日志 |
| exportAllFileLogs() | 方法 | `bool decryptBeforeExporting` | `Future<void>` | yes | 导出全部文件日志 |
| clearLogs() | 方法 | `/` | `Future<void>` | yes | 清空日志 |

## 遗留问题

无

## 其他

无

## 目录结构

```text
|---- flutter_logs
|     |---- android                 # Android 平台实现
|     |---- example                 # 示例工程
|     |     |---- lib               # 示例 Dart 代码
|     |     |---- ohos              # 示例 OpenHarmony 工程
|     |---- ios                     # iOS 平台实现
|     |---- lib                     # Dart API 入口与定义
|     |     |---- flutter_logs.dart # 核心 API
|     |---- ohos                    # OpenHarmony 平台实现
|     |---- test                    # 测试代码
|     |---- LICENSE                 # 开源协议
|     |---- pubspec.yaml            # 包配置
|     |---- README.OpenHarmony_CN.md
|     |---- README.OpenHarmony.md
```

## 贡献代码

使用过程中发现任何问题都可以提 [Issue](https://gitcode.com/OpenHarmony-Flutter/fluttertpc_flutter_logs/issues) ，当然，也非常欢迎发 [PR](https://gitcode.com/OpenHarmony-Flutter/fluttertpc_flutter_logs/pulls) 共建。

## 开源协议

本项目基于 [Apache-2.0](https://gitcode.com/OpenHarmony-Flutter/fluttertpc_flutter_logs/blob/master/LICENSE) ，请自由地享受和参与开源。
