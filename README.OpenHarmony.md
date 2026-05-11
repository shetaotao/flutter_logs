> Document Template: v0.4.1
# flutter_logs

This project is developed based on [flutter_logs](https://pub.dev/packages/flutter_logs).

## Introduction

`flutter_logs` is a file logging framework for Flutter applications. It supports log levels, log file management, log export, and integration with ELK metadata and MQTT reporting scenarios.<br/>

## Installation

Navigate to the project directory and add the following dependency to `pubspec.yaml`:

```yaml
dependencies:
  flutter_logs:
    git:
      url: https://gitcode.com/OpenHarmony-Flutter/fluttertpc_flutter_logs
      ref: 2.2.1-ohos-1.0.0
```

Run the command

```bash
flutter pub get
```

> TAG naming rule: `upstream-version-ohos-version`.

| Flutter Framework Version | TAG Name |
| ---------------- | ----------------------- |
| 3.22.1-ohos-1.1.0 | 2.2.1-ohos-1.0.0 |
| 3.27.5-ohos-1.0.4 | 2.2.1-ohos-1.0.0 |
| 3.35.8-ohos-0.0.2 | 2.2.1-ohos-1.0.0 |

## Constraints and Limitations

### Compatibility

Tested and passed in the following versions

1. Flutter: 3.22.1-ohos-1.1.0; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.0.830; ROM: 6.1.0.117 SP6;
2. Flutter: 3.27.5-ohos-1.0.4; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.0.830; ROM: 6.1.0.117 SP6;
3. Flutter: 3.35.8-ohos-0.0.2; SDK: 5.0.0(12); IDE: DevEco Studio: 6.1.0.830; ROM: 6.1.0.117 SP6;

### Permission Requirements

This library does not require additional permissions.

## Usage Example

The following example demonstrates log initialization, writing, and export:<br/>

```dart
import 'package:flutter_logs/flutter_logs.dart';

Future<void> setupAndWriteLogs() async {
  // 1) Initialize the logging system
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

  // 2) Write logs
  await FlutterLogs.logThis(
    tag: 'Demo',
    subTag: 'setup',
    logMessage: 'flutter_logs initialized',
    level: LogLevel.INFO,
  );

  // 3) Export logs
  await FlutterLogs.exportLogs(exportType: ExportType.ALL);
}
```

## API Reference

### API

> [!TIP] In the "ohos Support" column, `yes` means the property is supported on OHOS, and `no` means it is not supported. Usage is consistent across platforms, with behavior aligned to iOS or Android.

#### FlutterLogs

| Name | Type | Parameter Type | Return Value | OHOS Platform Support | Description |
| --- | --- | --- | --- | --- | --- |
| setDebugLevel() | Method | int value | void | yes | Sets debug output level (0/1/2) |
| initLogs() | Method | `List<LogLevel> logLevelsEnabled, TimeStampFormat timeStampFormat, DirectoryStructure directoryStructure, List<String> logTypesEnabled, LogFileExtension logFileExtension, String logsWriteDirectoryName, bool debugFileOperations, bool isDebuggable, bool enabled` | `Future<String>` | yes | Initializes logging system |
| initMQTT() | Method | `String topic, String brokerUrl, String certificate, String port, bool writeLogsToLocalStorage, bool debug` | `Future<String?>` | yes | Initializes MQTT reporting configuration |
| setMetaInfo() | Method | `String appId, String appName, String appVersion, String deviceId, String environmentId, String userId` | `Future<String>` | yes | Sets ELK metadata |
| logThis() | Method | `String tag, String subTag, String logMessage, LogLevel level, Exception exception, Error error` | `Future<void>` | yes | Writes general logs |
| logInfo() | Method | `String tag, String subTag, String logMessage` | `Future<void>` | yes | Writes INFO level logs |
| logWarn() | Method | `String tag, String subTag, String logMessage` | `Future<void>` | yes | Writes WARNING level logs |
| logError() | Method | `String tag, String subTag, String logMessage` | `Future<void>` | yes | Writes ERROR level logs |
| logErrorTrace() | Method | `String tag, String subTag, String logMessage, Error e` | `Future<void>` | yes | Writes error stack logs |
| logToFile() | Method | `String logFileName, bool overwrite, String logMessage, bool appendTimeStamp` | `Future<void>` | yes | Writes to a specified file |
| printLogs() | Method | `ExportType exportType, bool decryptBeforeExporting` | `Future<void>` | yes | Prints logs |
| exportLogs() | Method | `ExportType exportType, bool decryptBeforeExporting` | `Future<void>` | yes | Exports logs as a zip package |
| printFileLogForName() | Method | `String logFileName, bool decryptBeforeExporting` | `Future<void>` | yes | Prints logs for a specified file |
| exportFileLogForName() | Method | `String logFileName, bool decryptBeforeExporting` | `Future<void>` | yes | Exports logs for a specified file |
| exportAllFileLogs() | Method | `bool decryptBeforeExporting` | `Future<void>` | yes | Exports all file logs |
| clearLogs() | Method | `/` | `Future<void>` | yes | Clears logs |

## Known Issues

None.

## Others

None.

## Directory Structure

```text
|---- flutter_logs
|     |---- android                 # Android platform implementation
|     |---- example                 # Example project
|     |     |---- lib               # Example Dart source code
|     |     |---- ohos              # Example OpenHarmony project
|     |---- ios                     # iOS platform implementation
|     |---- lib                     # Dart API entry and definitions
|     |     |---- flutter_logs.dart # Core API
|     |---- ohos                    # OpenHarmony platform implementation
|     |---- test                    # Test code
|     |---- LICENSE                 # Open-source license
|     |---- pubspec.yaml            # Package configuration
|     |---- README.OpenHarmony_CN.md
|     |---- README.OpenHarmony.md
```

## Contributing

If you find any issue while using this project, feel free to submit an [Issue](https://gitcode.com/OpenHarmony-Flutter/fluttertpc_flutter_logs/issues). You are also welcome to submit a [PR](https://gitcode.com/OpenHarmony-Flutter/fluttertpc_flutter_logs/pulls).

## License

This project is licensed under [Apache-2.0](https://gitcode.com/OpenHarmony-Flutter/fluttertpc_flutter_logs/blob/master/LICENSE). Feel free to use and contribute.
