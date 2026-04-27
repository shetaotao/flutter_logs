import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  var _tag = "MyApp";
  var _myLogFileName = "MyLogFile";
  var toggle = false;
  var logStatus = '';
  static Completer _completer = new Completer<String>();

  @override
  void initState() {
    super.initState();
    setUpLogs();
  }

  void setUpLogs() async {
    await FlutterLogs.initLogs(
        logLevelsEnabled: [
          LogLevel.INFO,
          LogLevel.WARNING,
          LogLevel.ERROR,
          LogLevel.SEVERE
        ],
        timeStampFormat: TimeStampFormat.TIME_FORMAT_READABLE,
        directoryStructure: DirectoryStructure.FOR_DATE,
        logTypesEnabled: [_myLogFileName],
        logFileExtension: LogFileExtension.LOG,
        logsWriteDirectoryName: "MyLogs",
        logsExportDirectoryName: "MyLogs/Exported",
        debugFileOperations: true,
        isDebuggable: true,
        enabled: true);

    FlutterLogs.logInfo(_tag, "setUpLogs", "setUpLogs: Setting up logs..");

    FlutterLogs.channel.setMethodCallHandler((call) async {
      if (call.method == 'logsExported') {
        FlutterLogs.logInfo(
            _tag, "setUpLogs", "logsExported: ${call.arguments.toString()}");

        setLogsStatus(
            status: "logsExported: ${call.arguments.toString()}", append: true);

        _completer.complete(call.arguments.toString());
      } else if (call.method == 'logsPrinted') {
        FlutterLogs.logInfo(
            _tag, "setUpLogs", "logsPrinted: ${call.arguments.toString()}");

        setLogsStatus(
            status: "logsPrinted: ${call.arguments.toString()}", append: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Logs'),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.start,
              children: <Widget>[
                Text(
                  logStatus,
                  maxLines: 10,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    logData(isException: false);
                  },
                  child: Text('Log Something', style: TextStyle(fontSize: 20)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    logData(isException: true);
                  },
                  child: Text('Log Exception', style: TextStyle(fontSize: 20)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    logToFile();
                  },
                  child: Text('Log To File', style: TextStyle(fontSize: 20)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    printAllLogs();
                  },
                  child: Text('Print All Logs', style: TextStyle(fontSize: 20)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await exportAllLogs().then((value) async {
                      Directory? externalDirectory;

                      if (Platform.isIOS) {
                        externalDirectory =
                            await getApplicationDocumentsDirectory();
                      } else {
                        externalDirectory = await getExternalStorageDirectory();
                      }

                      FlutterLogs.logInfo(
                          _tag, "found", 'External Storage:$externalDirectory');

                      File file = File("${externalDirectory!.path}/$value");

                      FlutterLogs.logInfo(
                          _tag, "path", 'Path: \n${file.path.toString()}');

                      if (file.existsSync()) {
                        FlutterLogs.logInfo(_tag, "existsSync",
                            'Logs found and ready to export!');
                      } else {
                        FlutterLogs.logError(
                            _tag, "existsSync", "File not found in storage.");
                      }

                      setLogsStatus(
                          status:
                              "All logs exported to: \n\nPath: ${file.path.toString()}");
                    });
                  },
                  child:
                      Text('Export All Logs', style: TextStyle(fontSize: 20)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    printFileLogs();
                  },
                  child:
                      Text('Print File Logs', style: TextStyle(fontSize: 20)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    exportFileLogs();
                  },
                  child:
                      Text('Export File Logs', style: TextStyle(fontSize: 20)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await FlutterLogs.clearLogs();
                    setLogsStatus(status: "Logs cleared");
                  },
                  child: Text('Clear Logs', style: TextStyle(fontSize: 20)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    initMQTT();
                  },
                  child: Text('Init MQTT', style: TextStyle(fontSize: 20)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    setMetaInfo();
                  },
                  child: Text('Set Meta Info', style: TextStyle(fontSize: 20)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    setDebugLevel();
                  },
                  child: Text('Set Debug Level', style: TextStyle(fontSize: 20)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    exportAllFileLogs();
                  },
                  child: Text('Export All File Logs', style: TextStyle(fontSize: 20)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    logWarnMessage();
                  },
                  child: Text('Log Warn', style: TextStyle(fontSize: 20)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    logErrorTraceMessage();
                  },
                  child: Text('Log Error Trace', style: TextStyle(fontSize: 20)),
                ),
                SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void initMQTT() async {
    FlutterLogs.initMQTT(
        topic: "flutter_logs/test",
        brokerUrl: "test.mosquitto.org",
        certificate: "assets/m2mqtt_ca.crt",
        port: "8883",
        writeLogsToLocalStorage: true,
        debug: true,
        initialDelaySecondsForPublishing: 10);
    setLogsStatus(status: "init MQTT");
  }

  void setMetaInfo() async {
    await FlutterLogs.setMetaInfo(
      appId: "flutter_logs_example",
      appName: "Flutter Logs Demo",
      appVersion: "1.0",
      language: "zh-CN",
      deviceId: "test_device_001",
      environmentId: "test_env",
      environmentName: "test",
      organizationId: "test_org",
      organizationUnitId: "test_unit",
      userId: "test_user",
      userName: "test_user_name",
      userEmail: "test@example.com",
      deviceSerial: "TEST123456",
      deviceBrand: "TestBrand",
      deviceName: "TestDevice",
      deviceManufacturer: "TestManufacturer",
      deviceModel: "TestModel",
      deviceSdkInt: "30",
      deviceBatteryPercent: "80",
      latitude: "39.9",
      longitude: "116.4",
      labels: "test,flutter,logs",
    );
    setLogsStatus(status: "Meta info set");
  }

  void setDebugLevel() async {
    FlutterLogs.setDebugLevel(2);
    setLogsStatus(status: "Debug level set to 2 (all messages)");
  }

  void exportAllFileLogs() async {
    await FlutterLogs.exportAllFileLogs(decryptBeforeExporting: true);
    setLogsStatus(status: "All file logs exported");
  }

  void logWarnMessage() async {
    FlutterLogs.logWarn(_tag, "logWarnMessage", "This is a warning message");
    setLogsStatus(status: "Warning message logged");
  }

  void logErrorTraceMessage() async {
    try {
      var i = 100 ~/ 0;
      print("$i");
    } catch (e, stackTrace) {
      if (e is Error) {
        FlutterLogs.logErrorTrace(
            _tag, "logErrorTraceMessage", "Error with trace", e);
        setLogsStatus(status: "Error trace logged: ${e.stackTrace ?? stackTrace}");
      }
    }
  }

  void logData({required bool isException}) {
    var logMessage =
        'This is a log message: ${DateTime.now().millisecondsSinceEpoch}';

    if (!isException) {
      FlutterLogs.logThis(
          tag: _tag,
          subTag: 'logData',
          logMessage: logMessage,
          level: LogLevel.INFO);
    } else {
      try {
        if (toggle) {
          toggle = false;
          var i = 100 ~/ 0;
          print("$i");
        } else {
          toggle = true;
          dynamic i;
          print(i * 10);
        }
      } catch (e) {
        if (e is Error) {
          FlutterLogs.logThis(
              tag: _tag,
              subTag: 'Caught an error.',
              logMessage: 'Caught an exception!',
              error: e,
              level: LogLevel.ERROR);
          logMessage = e.stackTrace.toString();
        } else if (e is Exception) {
          FlutterLogs.logThis(
              tag: _tag,
              subTag: 'Caught an exception.',
              logMessage: 'Caught an exception!',
              exception: e,
              level: LogLevel.ERROR);
          logMessage = e.toString();
        }
      }
    }
    setLogsStatus(status: logMessage);
  }

  void logToFile() {
    var logMessage =
        "This is a log message: ${DateTime.now().millisecondsSinceEpoch}, it will be saved to my log file named: \'$_myLogFileName\'";
    FlutterLogs.logToFile(
        logFileName: _myLogFileName,
        overwrite: false,
        logMessage: logMessage,
        appendTimeStamp: true);
    setLogsStatus(status: logMessage);
  }

  void printAllLogs() {
    FlutterLogs.printLogs(
        exportType: ExportType.ALL, decryptBeforeExporting: true);
    setLogsStatus(status: "All logs printed");
  }

  Future<String> exportAllLogs() async {
    FlutterLogs.exportLogs(exportType: ExportType.ALL);
    return _completer.future as FutureOr<String>;
  }

  void exportFileLogs() {
    FlutterLogs.exportFileLogForName(
        logFileName: _myLogFileName, decryptBeforeExporting: true);
  }

  void printFileLogs() {
    FlutterLogs.printFileLogForName(
        logFileName: _myLogFileName, decryptBeforeExporting: true);
  }

  void setLogsStatus({String status = '', bool append = false}) {
    setState(() {
      logStatus = status;
    });
  }
}
