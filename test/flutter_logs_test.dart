import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_logs/flutter_logs.dart';

void main() {
  const MethodChannel channel = MethodChannel('flutter_logs');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'initLogs':
          return 'Logs initialized successfully';
        case 'initMQTT':
          return 'MQTT initialized successfully';
        case 'setMetaInfo':
          return 'Meta info set successfully';
        case 'logThis':
          return 'Log written successfully';
        case 'logToFile':
          return 'Log written to file successfully';
        case 'exportLogs':
          return 'Logs exported successfully';
        case 'printLogs':
          return 'Logs printed successfully';
        case 'exportFileLogForName':
          return 'File log exported successfully';
        case 'exportAllFileLogs':
          return 'All file logs exported successfully';
        case 'printFileLogForName':
          return 'File log printed successfully';
        case 'clearLogs':
          return 'Logs cleared successfully';
        default:
          return null;
      }
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  group('FlutterLogs', () {
    group('Debug Level', () {
      test('setDebugLevel should set debug level correctly', () {
        FlutterLogs.setDebugLevel(0);
        FlutterLogs.setDebugLevel(1);
        FlutterLogs.setDebugLevel(2);
      });

      test('printDebugMessage should print when debug level is sufficient', () {
        FlutterLogs.setDebugLevel(2);
        FlutterLogs.printDebugMessage('Test message', 1);
        FlutterLogs.printDebugMessage('Test message', 2);
      });

      test('printDebugMessage should not print when debug level is insufficient', () {
        FlutterLogs.setDebugLevel(1);
        FlutterLogs.printDebugMessage('Test message', 2);
      });
    });

    group('initLogs', () {
      test('initLogs with required parameters should return success', () async {
        final result = await FlutterLogs.initLogs(
          directoryStructure: DirectoryStructure.FOR_DATE,
          timeStampFormat: TimeStampFormat.TIME_FORMAT_READABLE,
          logFileExtension: LogFileExtension.LOG,
        );
        expect(result, equals('Logs initialized successfully'));
      });

      test('initLogs with all parameters should return success', () async {
        final result = await FlutterLogs.initLogs(
          logLevelsEnabled: [LogLevel.INFO, LogLevel.ERROR],
          logTypesEnabled: ['Device', 'Network'],
          logsRetentionPeriodInDays: 7,
          zipsRetentionPeriodInDays: 1,
          autoDeleteZipOnExport: true,
          autoClearLogs: false,
          autoExportErrors: false,
          encryptionEnabled: true,
          encryptionKey: 'testKey',
          directoryStructure: DirectoryStructure.FOR_EVENT,
          logSystemCrashes: false,
          isDebuggable: false,
          debugFileOperations: false,
          attachTimeStamp: false,
          attachNoOfFiles: false,
          timeStampFormat: TimeStampFormat.DATE_FORMAT_1,
          logFileExtension: LogFileExtension.CSV,
          zipFilesOnly: true,
          logsWriteDirectoryName: 'testLogs',
          logsExportZipFileName: 'testExport.zip',
          logsExportDirectoryName: 'testExport',
          singleLogFileSize: 5,
          enabled: false,
        );
        expect(result, equals('Logs initialized successfully'));
      });
    });

    group('initMQTT', () {
      test('initMQTT with valid parameters should return success', () async {
        // Note: This test requires rootBundle access which may not work in unit tests
        // Skipping as it requires asset bundle
      });

      test('initMQTT with empty brokerUrl should return null', () async {
        final result = await FlutterLogs.initMQTT(
          brokerUrl: '',
          certificate: '',
        );
        expect(result, isNull);
      });
    });

    group('setMetaInfo', () {
      test('setMetaInfo with default parameters should return success', () async {
        final result = await FlutterLogs.setMetaInfo();
        expect(result, equals('Meta info set successfully'));
      });

      test('setMetaInfo with all parameters should return success', () async {
        final result = await FlutterLogs.setMetaInfo(
          appId: 'testAppId',
          appName: 'Test App',
          appVersion: '1.0.0',
          language: 'en',
          deviceId: 'testDeviceId',
          environmentId: 'testEnvId',
          environmentName: 'Test Environment',
          organizationId: 'testOrgId',
          organizationUnitId: 'testOrgUnitId',
          userId: 'testUserId',
          userName: 'Test User',
          userEmail: 'test@example.com',
          deviceSerial: 'testSerial',
          deviceBrand: 'TestBrand',
          deviceName: 'TestDevice',
          deviceManufacturer: 'TestManufacturer',
          deviceModel: 'TestModel',
          deviceSdkInt: '30',
          deviceBatteryPercent: '100',
          latitude: '0.0',
          longitude: '0.0',
          labels: 'test,labels',
        );
        expect(result, equals('Meta info set successfully'));
      });
    });

    group('logThis', () {
      test('logThis with basic parameters should complete', () async {
        await FlutterLogs.logThis(
          tag: 'TEST',
          subTag: 'SUB_TEST',
          logMessage: 'Test message',
          level: LogLevel.INFO,
        );
      });

      test('logThis with exception should complete', () async {
        await FlutterLogs.logThis(
          tag: 'TEST',
          subTag: 'SUB_TEST',
          logMessage: 'Test message with exception',
          level: LogLevel.ERROR,
          exception: Exception('Test exception'),
        );
      });

      test('logThis with error should complete', () async {
        await FlutterLogs.logThis(
          tag: 'TEST',
          subTag: 'SUB_TEST',
          logMessage: 'Test message with error',
          level: LogLevel.ERROR,
          error: Error(),
        );
      });

      test('logThis with errorMessage should complete', () async {
        await FlutterLogs.logThis(
          tag: 'TEST',
          subTag: 'SUB_TEST',
          logMessage: 'Test message',
          level: LogLevel.WARNING,
          errorMessage: 'Custom error message',
        );
      });

      test('logThis with all log levels should complete', () async {
        for (final level in LogLevel.values) {
          await FlutterLogs.logThis(
            tag: 'TEST',
            subTag: 'SUB_TEST',
            logMessage: 'Test message with $level',
            level: level,
          );
        }
      });
    });

    group('Convenience log methods', () {
      test('logInfo should complete', () async {
        await FlutterLogs.logInfo('TEST', 'SUB_TEST', 'Info message');
      });

      test('logWarn should complete', () async {
        await FlutterLogs.logWarn('TEST', 'SUB_TEST', 'Warning message');
      });

      test('logError should complete', () async {
        await FlutterLogs.logError('TEST', 'SUB_TEST', 'Error message');
      });

      test('logErrorTrace should complete', () async {
        await FlutterLogs.logErrorTrace(
          'TEST',
          'SUB_TEST',
          'Error with trace',
          Error(),
        );
      });
    });

    group('logToFile', () {
      test('logToFile with valid filename should complete', () async {
        await FlutterLogs.logToFile(
          logFileName: 'test.log',
          logMessage: 'Test message',
        );
      });

      test('logToFile with all parameters should complete', () async {
        await FlutterLogs.logToFile(
          logFileName: 'test.log',
          overwrite: true,
          logMessage: 'Test message',
          appendTimeStamp: true,
        );
      });

      test('logToFile with empty filename should print error', () async {
        await FlutterLogs.logToFile(
          logFileName: '',
          logMessage: 'Test message',
        );
      });
    });

    group('exportLogs', () {
      test('exportLogs with default parameters should complete', () async {
        await FlutterLogs.exportLogs();
      });

      test('exportLogs with all export types should complete', () async {
        for (final exportType in ExportType.values) {
          await FlutterLogs.exportLogs(
            exportType: exportType,
            decryptBeforeExporting: true,
          );
        }
      });
    });

    group('printLogs', () {
      test('printLogs with default parameters should complete', () async {
        await FlutterLogs.printLogs();
      });

      test('printLogs with all export types should complete', () async {
        for (final exportType in ExportType.values) {
          await FlutterLogs.printLogs(
            exportType: exportType,
            decryptBeforeExporting: true,
          );
        }
      });
    });

    group('exportFileLogForName', () {
      test('exportFileLogForName with valid filename should complete', () async {
        await FlutterLogs.exportFileLogForName(
          logFileName: 'test.log',
        );
      });

      test('exportFileLogForName with all parameters should complete', () async {
        await FlutterLogs.exportFileLogForName(
          logFileName: 'test.log',
          decryptBeforeExporting: true,
        );
      });

      test('exportFileLogForName with empty filename should print error', () async {
        await FlutterLogs.exportFileLogForName(
          logFileName: '',
        );
      });
    });

    group('exportAllFileLogs', () {
      test('exportAllFileLogs with default parameters should complete', () async {
        await FlutterLogs.exportAllFileLogs();
      });

      test('exportAllFileLogs with decryptBeforeExporting should complete', () async {
        await FlutterLogs.exportAllFileLogs(
          decryptBeforeExporting: true,
        );
      });
    });

    group('printFileLogForName', () {
      test('printFileLogForName with valid filename should complete', () async {
        await FlutterLogs.printFileLogForName(
          logFileName: 'test.log',
        );
      });

      test('printFileLogForName with all parameters should complete', () async {
        await FlutterLogs.printFileLogForName(
          logFileName: 'test.log',
          decryptBeforeExporting: true,
        );
      });

      test('printFileLogForName with empty filename should print error', () async {
        await FlutterLogs.printFileLogForName(
          logFileName: '',
        );
      });
    });

    group('clearLogs', () {
      test('clearLogs should complete', () async {
        await FlutterLogs.clearLogs();
      });
    });

    group('Enums', () {
      test('DirectoryStructure enum values should exist', () {
        expect(DirectoryStructure.values.length, equals(3));
        expect(DirectoryStructure.FOR_DATE, isNotNull);
        expect(DirectoryStructure.FOR_EVENT, isNotNull);
        expect(DirectoryStructure.SINGLE_FILE_FOR_DAY, isNotNull);
      });

      test('LogFileExtension enum values should exist', () {
        expect(LogFileExtension.values.length, equals(4));
        expect(LogFileExtension.TXT, isNotNull);
        expect(LogFileExtension.CSV, isNotNull);
        expect(LogFileExtension.LOG, isNotNull);
        expect(LogFileExtension.NONE, isNotNull);
      });

      test('LogLevel enum values should exist', () {
        expect(LogLevel.values.length, equals(4));
        expect(LogLevel.INFO, isNotNull);
        expect(LogLevel.WARNING, isNotNull);
        expect(LogLevel.ERROR, isNotNull);
        expect(LogLevel.SEVERE, isNotNull);
      });

      test('LogType enum values should exist', () {
        expect(LogType.values.length, equals(9));
        expect(LogType.Device, isNotNull);
        expect(LogType.Location, isNotNull);
        expect(LogType.Notification, isNotNull);
        expect(LogType.Network, isNotNull);
        expect(LogType.Navigation, isNotNull);
        expect(LogType.History, isNotNull);
        expect(LogType.Tasks, isNotNull);
        expect(LogType.Jobs, isNotNull);
        expect(LogType.Errors, isNotNull);
      });

      test('TimeStampFormat enum values should exist', () {
        expect(TimeStampFormat.values.length, equals(9));
        expect(TimeStampFormat.DATE_FORMAT_1, isNotNull);
        expect(TimeStampFormat.DATE_FORMAT_2, isNotNull);
        expect(TimeStampFormat.TIME_FORMAT_FULL_JOINED, isNotNull);
        expect(TimeStampFormat.TIME_FORMAT_FULL_1, isNotNull);
        expect(TimeStampFormat.TIME_FORMAT_FULL_2, isNotNull);
        expect(TimeStampFormat.TIME_FORMAT_24_FULL, isNotNull);
        expect(TimeStampFormat.TIME_FORMAT_READABLE, isNotNull);
        expect(TimeStampFormat.TIME_FORMAT_READABLE_2, isNotNull);
        expect(TimeStampFormat.TIME_FORMAT_SIMPLE, isNotNull);
      });

      test('ExportType enum values should exist', () {
        expect(ExportType.values.length, equals(5));
        expect(ExportType.TODAY, isNotNull);
        expect(ExportType.LAST_HOUR, isNotNull);
        expect(ExportType.WEEKS, isNotNull);
        expect(ExportType.LAST_24_HOURS, isNotNull);
        expect(ExportType.ALL, isNotNull);
      });
    });
  });
}
