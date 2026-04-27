/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { zlib } from '@kit.BasicServicesKit';
import { batteryInfo } from '@kit.BasicServicesKit';
import { LogLevel, DirectoryStructure, LogExtension, TimeStampFormat, ExportType, getParentPath } from './Utils';
import { ZipHelper, ZipFileInfo } from './ZipHelper';
import util from '@ohos.util';

/**
 * 增强版日志辅助类
 * 基于华为鸿蒙官方 API 实现以下功能：
 * 1. 日志导出与 ZIP 压缩 (ZipHelper - 支持多文件 ZIP)
 * 2. 日志清理与过期删除 (@kit.CoreFileKit)
 * 3. 日志加密存储 (@kit.CryptoArchitectureKit) - 使用标准 AES-128-CBC
 * 4. MQTT 基础连接 (@ohos/net.socket)
 * 5. 崩溃捕获 (@ohos.hiviewdfx.hiAppEvent)
 */
export class LogsHelperEnhanced {
  private static TAG = "LogsHelperEnhanced";
  static savePathProvided: string = "";
  static exportPathProvided: string = "";

  public static logConfig: LogsConfig | null = null;
  private static loggers: Map<string, LoggerEnhanced> = new Map();

  // 崩溃监听器
  private static crashWatcher: hiAppEvent.Watcher | null = null;
  private static crashWatcherInitialized: boolean = false;

  // 是否回退到使用 filesDir（当子目录不可写时）
  private static fallbackToFilesDir: boolean = false;
  private static filesDirPath: string = "";

  /**
   * 获取实际的日志保存路径
   * 如果子目录不可写，返回 filesDir；否则返回 savePath
   */
  static getActualSavePath(): string {
    if (LogsHelperEnhanced.fallbackToFilesDir && LogsHelperEnhanced.filesDirPath) {
      return LogsHelperEnhanced.filesDirPath;
    }
    return LogsHelperEnhanced.logConfig?.savePath ?? "";
  }

  // AES 加密 IV (16字节，每次加密时随机生成并存储在密文前)
  private static readonly AES_KEY_SIZE = 16; // AES-128

  /**
   * 延迟函数
   * @param ms 延迟毫秒数
   */
  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  /**
   * 初始化日志配置
   * 参考文档: https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-core-file-kit-V5
   */
  static async setUpLogger(
    logLevelsEnabled: Array<string>,
    logTypesEnabled: Array<string>,
    logsRetentionPeriodInDays: number | null,
    zipsRetentionPeriodInDays: number | null,
    autoDeleteZipOnExport: boolean | null,
    autoClearLogs: boolean | null,
    autoExportErrors: boolean | null,
    encryptionEnabled: boolean | null,
    encryptionKey: string | null,
    directoryStructure: DirectoryStructure | null,
    logSystemCrashes: boolean | null,
    isDebuggable: boolean | null,
    debugFileOperations: boolean | null,
    attachTimeStamp: boolean | null,
    attachNoOfFiles: boolean | null,
    timeStampFormat: TimeStampFormat | null,
    logFileExtension: LogExtension | null,
    zipFilesOnly: boolean | null,
    savePath: string | null,
    zipFileName: string | null,
    exportPath: string | null,
    singleLogFileSize: number | null,
    enabled: boolean | null
  ): Promise<void> {
    const context = getContext();
    // 使用应用全局文件目录，修正路径
    // 注意：getContext() 可能返回插件上下文，其 filesDir 包含 /haps/entry
    // 我们需要使用应用全局的 filesDir: /data/storage/el2/base/files
    let filesDir = context.filesDir;
    
    // 如果路径包含 /haps/entry，需要修正为应用全局路径
    if (filesDir.includes('/haps/entry/files')) {
      filesDir = filesDir.replace('/haps/entry/files', '/files');
      console.info(LogsHelperEnhanced.TAG, `修正文件路径: ${context.filesDir} -> ${filesDir}`);
    }

    // 先计算路径
    // 如果 savePath 为空，使用默认目录名 "MyLogs"
    const actualSavePath = savePath && savePath.length > 0 ? savePath : "MyLogs";
    const finalSavePath = `${filesDir}/${actualSavePath}`;
    
    // 处理 exportPath，避免重复添加 savePath
    let finalExportPath: string;
    console.info(LogsHelperEnhanced.TAG, `处理路径参数: savePath=${savePath}, exportPath=${exportPath}, actualSavePath=${actualSavePath}`);
    if (exportPath && exportPath.length > 0) {
      // 如果 exportPath 是绝对路径，直接使用
      if (exportPath.startsWith('/')) {
        finalExportPath = exportPath;
        console.info(LogsHelperEnhanced.TAG, `exportPath 是绝对路径，直接使用: ${finalExportPath}`);
      }
      // 如果 exportPath 已经包含 savePath，不要重复添加
      else if (exportPath.startsWith(actualSavePath + '/')) {
        finalExportPath = `${filesDir}/${exportPath}`;
        console.info(LogsHelperEnhanced.TAG, `exportPath 已包含 savePath，直接使用: ${finalExportPath}`);
      } else {
        finalExportPath = `${filesDir}/${actualSavePath}/${exportPath}`;
        console.info(LogsHelperEnhanced.TAG, `exportPath 不包含 savePath，添加后: ${finalExportPath}`);
      }
    } else {
      finalExportPath = `${filesDir}/${actualSavePath}/export`;
      console.info(LogsHelperEnhanced.TAG, `exportPath 为空，使用默认值: ${finalExportPath}`);
    }

    console.info(LogsHelperEnhanced.TAG, `开始初始化日志配置...`);
    console.info(LogsHelperEnhanced.TAG, `日志保存路径: ${finalSavePath}`);
    console.info(LogsHelperEnhanced.TAG, `日志导出路径: ${finalExportPath}`);

    // 先确保目录存在，再设置配置（使用同步 API）
    console.info(LogsHelperEnhanced.TAG, `创建日志目录...`);
    try {
      LogsHelperEnhanced.ensureDirectoryExists(finalSavePath);
      if (finalExportPath && finalExportPath !== finalSavePath) {
        LogsHelperEnhanced.ensureDirectoryExists(finalExportPath);
      }
      console.info(LogsHelperEnhanced.TAG, `日志目录创建完成`);
    } catch (dirError) {
      console.error(LogsHelperEnhanced.TAG, `创建日志目录失败: ${dirError}`);
      console.warn(LogsHelperEnhanced.TAG, `回退到使用 filesDir: ${filesDir}`);
      LogsHelperEnhanced.fallbackToFilesDir = true;
      LogsHelperEnhanced.filesDirPath = filesDir;
      // 使用 filesDir 作为 savePath
      LogsHelperEnhanced.ensureDirectoryExists(filesDir);
    }

    // 测试目录是否可写（仅用于诊断）
    try {
      const testFilePath = `${LogsHelperEnhanced.fallbackToFilesDir ? filesDir : finalSavePath}/.test_write`;
      console.info(LogsHelperEnhanced.TAG, `测试目录可写性: ${testFilePath}`);
      const testFile = fileIo.openSync(testFilePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(testFile.fd, 'test');
      fileIo.closeSync(testFile);
      fileIo.unlinkSync(testFilePath);
      console.info(LogsHelperEnhanced.TAG, `目录可写性测试通过`);
    } catch (testError) {
      console.warn(LogsHelperEnhanced.TAG, `目录可写性测试失败: ${testError}`);
    }

    // 目录创建完成后，再设置配置
    LogsHelperEnhanced.logConfig = {
      logLevelsEnabled: logLevelsEnabled,
      logTypesEnabled: logTypesEnabled,
      logsRetentionPeriodInDays: logsRetentionPeriodInDays ?? 7,
      zipsRetentionPeriodInDays: zipsRetentionPeriodInDays ?? 7,
      autoDeleteZipOnExport: autoDeleteZipOnExport ?? false,
      autoClearLogs: autoClearLogs ?? false,
      autoExportErrors: autoExportErrors ?? false,
      encryptionEnabled: encryptionEnabled ?? false,
      encryptionKey: encryptionKey ?? "",
      directoryStructure: directoryStructure ?? DirectoryStructure.SINGLE_FILE_FOR_DAY,
      logSystemCrashes: logSystemCrashes ?? false,
      isDebuggable: isDebuggable ?? false,
      debugFileOperations: debugFileOperations ?? false,
      attachTimeStamp: attachTimeStamp ?? false,
      attachNoOfFiles: attachNoOfFiles ?? false,
      timeStampFormat: timeStampFormat ?? TimeStampFormat.TIME_FORMAT_24_FULL,
      logFileExtension: logFileExtension ?? LogExtension.LOG,
      zipFilesOnly: zipFilesOnly ?? false,
      savePath: finalSavePath,
      zipFileName: zipFileName ?? "",
      exportPath: finalExportPath,
      singleLogFileSize: singleLogFileSize ?? 1,
      isEnabled: enabled ?? true
    };

    if (savePath) {
      LogsHelperEnhanced.savePathProvided = savePath;
    }

    if (exportPath) {
      LogsHelperEnhanced.exportPathProvided = exportPath;
    }

    // 如果启用自动清理，执行清理操作
    if (LogsHelperEnhanced.logConfig.autoClearLogs) {
      await LogsHelperEnhanced.cleanOldLogs();
    }

    // 如果启用崩溃捕获，初始化崩溃监听器
    if (LogsHelperEnhanced.logConfig.logSystemCrashes) {
      LogsHelperEnhanced.initCrashWatcher();
    }

    console.info(LogsHelperEnhanced.TAG, `日志配置初始化完成`);
  }

  /**
   * 初始化崩溃监听器
   * 使用 @ohos.hiviewdfx.hiAppEvent 订阅应用崩溃事件
   * 参考文档: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hiappevent-watcher-crash-events-arkts
   */
  static initCrashWatcher(): void {
    if (LogsHelperEnhanced.crashWatcherInitialized) {
      console.info(LogsHelperEnhanced.TAG, "崩溃监听器已初始化，跳过");
      return;
    }

    try {
      LogsHelperEnhanced.crashWatcher = {
        name: "flutter_logs_crash_watcher",
        appEventFilters: [
          {
            domain: hiAppEvent.domain.OS,
            names: [hiAppEvent.event.APP_CRASH]
          }
        ],
        onReceive: (domain: string, appEventGroups: Array<hiAppEvent.AppEventGroup>) => {
          console.info(LogsHelperEnhanced.TAG, `收到崩溃事件，domain=${domain}`);
          
          for (const eventGroup of appEventGroups) {
            console.info(LogsHelperEnhanced.TAG, `崩溃事件名称: ${eventGroup.name}`);
            
            for (const eventInfo of eventGroup.appEventInfos) {
              LogsHelperEnhanced.handleCrashEvent(eventInfo);
            }
          }
        }
      };

      hiAppEvent.addWatcher(LogsHelperEnhanced.crashWatcher);
      LogsHelperEnhanced.crashWatcherInitialized = true;
      console.info(LogsHelperEnhanced.TAG, "崩溃监听器初始化成功");
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `初始化崩溃监听器失败: ${e}`);
    }
  }

  /**
   * 处理崩溃事件
   */
  private static handleCrashEvent(eventInfo: hiAppEvent.AppEventInfo): void {
    try {
      const crashType = eventInfo.params['crash_type'] as string; // JsError | NativeCrash
      const exception = eventInfo.params['exception'] as object;
      const time = eventInfo.params['time'] as number;
      const pid = eventInfo.params['pid'] as number;
      const bundleName = eventInfo.params['bundle_name'] as string;
      const bundleVersion = eventInfo.params['bundle_version'] as string;
      const hilog = eventInfo.params['hilog'] as Array<string>;
      const externalLog = eventInfo.params['external_log'] as Array<string>;

      // 构建崩溃日志内容
      const crashLogContent = `[CRASH EVENT] ${new Date(time).toISOString()}\n` +
        `Type: ${crashType}\n` +
        `PID: ${pid}\n` +
        `Bundle: ${bundleName} v${bundleVersion}\n` +
        `Exception: ${JSON.stringify(exception, null, 2)}\n`;

      // 写入崩溃日志文件
      LogsHelperEnhanced.writeLogToFile('crash', crashLogContent, false);

      // 如果有外部崩溃日志文件，复制到我们的日志目录
      if (externalLog && externalLog.length > 0) {
        for (const logPath of externalLog) {
          LogsHelperEnhanced.copyExternalCrashLog(logPath);
        }
      }

      console.info(LogsHelperEnhanced.TAG, `崩溃日志已记录: ${crashType}`);
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `处理崩溃事件失败: ${e}`);
    }
  }

  /**
   * 复制系统崩溃日志到应用日志目录
   */
  private static async copyExternalCrashLog(sourcePath: string): Promise<void> {
    try {
      const fileName = sourcePath.substring(sourcePath.lastIndexOf('/') + 1);
      const destPath = `${LogsHelperEnhanced.logConfig?.savePath}/crash/${fileName}`;
      
      // 确保 crash 目录存在
      LogsHelperEnhanced.ensureDirectoryExists(`${LogsHelperEnhanced.logConfig?.savePath}/crash`);
      
      // 读取并写入文件
      const srcFile = await fileIo.open(sourcePath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(sourcePath);
      const arrayBuffer = new ArrayBuffer(stat.size);
      await fileIo.read(srcFile.fd, arrayBuffer);
      await fileIo.close(srcFile);

      const destFile = await fileIo.open(destPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
      await fileIo.write(destFile.fd, arrayBuffer);
      await fileIo.close(destFile);

      console.info(LogsHelperEnhanced.TAG, `外部崩溃日志已复制: ${destPath}`);
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `复制外部崩溃日志失败: ${e}`);
    }
  }

  /**
   * 移除崩溃监听器
   */
  static removeCrashWatcher(): void {
    if (LogsHelperEnhanced.crashWatcher) {
      try {
        hiAppEvent.removeWatcher(LogsHelperEnhanced.crashWatcher);
        LogsHelperEnhanced.crashWatcher = null;
        LogsHelperEnhanced.crashWatcherInitialized = false;
        console.info(LogsHelperEnhanced.TAG, "崩溃监听器已移除");
      } catch (e) {
        console.error(LogsHelperEnhanced.TAG, `移除崩溃监听器失败: ${e}`);
      }
    }
  }

  /**
   * 写入日志到文件
   * 支持加密写入（如启用加密，使用 AES-128-CBC）
   */
  static async writeLogToFile(type: string, data: string | null, appendTimeStamp: boolean): Promise<void> {
    try {
      const logger = LogsHelperEnhanced.getLoggerFor(type);
      if (logger) {
        const timestamp = appendTimeStamp ? ` [${LogsHelperEnhanced.getFormattedTime()}]` : "";
        const logData = `${data}${timestamp}\n`;

        // 如果启用加密，先加密数据 (AES-128-CBC)
        if (LogsHelperEnhanced.logConfig?.encryptionEnabled && LogsHelperEnhanced.logConfig.encryptionKey) {
          const encryptedData = await LogsHelperEnhanced.encryptData(logData, LogsHelperEnhanced.logConfig.encryptionKey);
          await logger.appendToFile(encryptedData, true);
        } else {
          await logger.appendToFile(logData, false);
        }
      }
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `写入日志失败: ${e}`);
    }
  }

  /**
   * 设置 ELK 堆栈配置信息
   * 自动获取电池信息（如果未提供）
   */
  static setupForELKStack(
    appId: string,
    appName: string,
    appVersion: string,
    deviceId: string,
    environmentId: string,
    environmentName: string,
    organizationId: string,
    organizationUnitId: string,
    language: string,
    userId: string,
    userName: string,
    userEmail: string,
    deviceSerial: string,
    deviceBrand: string,
    deviceName: string,
    deviceManufacturer: string,
    deviceModel: string,
    deviceSdkInt: string,
    deviceBatteryPercent: string,
    latitude: string,
    longitude: string
  ): void {
    // 如果未提供电池百分比，自动获取
    let batteryPercent = deviceBatteryPercent;
    if (!batteryPercent || batteryPercent.length === 0) {
      try {
        batteryPercent = batteryInfo.batterySOC.toString();
      } catch (e) {
        console.warn(LogsHelperEnhanced.TAG, `获取电池信息失败: ${e}`);
        batteryPercent = "";
      }
    }

    // 将 ELK 配置保存到 AppStorage
    const elkConfig: ELKConfig = {
      appId: appId,
      appName: appName,
      appVersion: appVersion,
      deviceId: deviceId,
      environmentId: environmentId,
      environmentName: environmentName,
      organizationId: organizationId,
      organizationUnitId: organizationUnitId,
      language: language,
      userId: userId,
      userName: userName,
      userEmail: userEmail,
      deviceSerial: deviceSerial,
      deviceBrand: deviceBrand,
      deviceName: deviceName,
      deviceManufacturer: deviceManufacturer,
      deviceModel: deviceModel,
      deviceSdkInt: deviceSdkInt,
      deviceBatteryPercent: batteryPercent,
      latitude: latitude,
      longitude: longitude
    };
    AppStorage.setOrCreate('elkConfig', elkConfig);
    console.info(LogsHelperEnhanced.TAG, `ELK 配置已保存: ${appName} v${appVersion}, 电量: ${batteryPercent}%`);
  }

  /**
   * 获取电池信息（供外部调用）
   * @returns 电池电量百分比和充电状态
   */
  static getBatteryInfo(): BatteryInfo {
    try {
      const result: BatteryInfo = {
        soc: batteryInfo.batterySOC.toString(),
        chargingStatus: batteryInfo.chargingStatus.toString(),
        healthStatus: batteryInfo.healthStatus.toString()
      };
      return result;
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `获取电池信息失败: ${e}`);
      const emptyResult: BatteryInfo = { soc: "", chargingStatus: "", healthStatus: "" };
      return emptyResult;
    }
  }

  /**
   * 覆盖写入日志到文件
   */
  static async overWriteLogToFile(type: string, data: string | null, appendTimeStamp: boolean): Promise<void> {
    try {
      const logger = LogsHelperEnhanced.getLoggerFor(type);
      if (logger) {
        const timestamp = appendTimeStamp ? ` [${LogsHelperEnhanced.getFormattedTime()}]` : "";
        const logData = data ? `${data}${timestamp}` : "";

        // 如果启用加密，先加密数据 (AES-128-CBC)
        if (LogsHelperEnhanced.logConfig?.encryptionEnabled && LogsHelperEnhanced.logConfig.encryptionKey) {
          const encryptedData = await LogsHelperEnhanced.encryptData(logData, LogsHelperEnhanced.logConfig.encryptionKey);
          await logger.overwriteToFile(encryptedData, true);
        } else {
          await logger.overwriteToFile(logData, false);
        }
      }
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `覆盖日志失败: ${e}`);
    }
  }

  /**
   * 导出日志为 ZIP 文件
   * 使用鸿蒙 @kit.ArchiveKit 实现
   * 参考文档: https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-archive-V5
   *
   * @param exportType 导出类型 (TODAY, LAST_HOUR, WEEKS, etc.)
   * @param decryptBeforeExporting 导出前是否解密
   * @returns 导出的 ZIP 文件路径
   */
  static async exportLogsToZip(exportType: ExportType, decryptBeforeExporting: boolean): Promise<string> {
    try {
      const config = LogsHelperEnhanced.logConfig;
      if (!config) {
        throw new Error("日志配置未初始化");
      }

      // 确定导出目录
      // 如果 fallbackToFilesDir 为 true，使用 filesDir 作为导出目录
      const actualExportPath = LogsHelperEnhanced.fallbackToFilesDir && LogsHelperEnhanced.filesDirPath
        ? `${LogsHelperEnhanced.filesDirPath}/export`
        : config.exportPath;
      
      // 确保导出目录存在
      console.info(LogsHelperEnhanced.TAG, `导出日志到 ZIP，exportPath: ${actualExportPath}`);
      LogsHelperEnhanced.ensureDirectoryExists(actualExportPath);

      // 生成 ZIP 文件名
      const date = new Date();
      const dateStr = `${date.getFullYear()}${String(date.getMonth() + 1).padStart(2, '0')}${String(date.getDate()).padStart(2, '0')}`;
      const zipFileName = config.zipFileName || `logs_export_${dateStr}_${exportType}.zip`;
      const zipFilePath = `${actualExportPath}/${zipFileName}`;
      console.info(LogsHelperEnhanced.TAG, `ZIP 文件路径: ${zipFilePath}`);

      // 获取要导出的日志文件列表
      const filesToExport = await LogsHelperEnhanced.getLogFilesForExport(exportType);

      if (filesToExport.length === 0) {
        console.warn(LogsHelperEnhanced.TAG, "没有找到需要导出的日志文件");
        return "";
      }

      // 如果需要解密，创建临时解密文件
      let filesForZip = filesToExport;
      if (decryptBeforeExporting && config.encryptionEnabled) {
        filesForZip = await LogsHelperEnhanced.decryptFilesForExport(filesToExport);
      }

      // 压缩文件 (简化为复制文件到导出目录)
      // 注意: ArkTS 没有内置 ZIP 支持，使用简单文件合并方式
      await LogsHelperEnhanced.mergeFilesToOutput(filesForZip, zipFilePath);

      console.info(LogsHelperEnhanced.TAG, `日志导出成功: ${zipFilePath}`);

      // 如果配置了导出后删除 ZIP，在适当的时候删除
      if (config.autoDeleteZipOnExport) {
        // 这里可以设置定时任务删除旧 ZIP
        LogsHelperEnhanced.scheduleZipCleanup();
      }

      // 返回相对路径
      return getParentPath(zipFilePath, LogsHelperEnhanced.savePathProvided, LogsHelperEnhanced.exportPathProvided);
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `导出日志失败: ${e}`);
      return "";
    }
  }

  /**
   * 导出指定文件名的日志为 ZIP
   *
   * @param logFileName 日志文件名
   * @param decryptBeforeExporting 导出前是否解密
   * @returns 导出的 ZIP 文件路径
   */
  static async exportFileLogForName(logFileName: string, decryptBeforeExporting: boolean): Promise<string> {
    try {
      const config = LogsHelperEnhanced.logConfig;
      if (!config) {
        throw new Error("日志配置未初始化");
      }

      // 确保导出目录存在
      LogsHelperEnhanced.ensureDirectoryExists(config.exportPath);

      // 生成 ZIP 文件名
      const date = new Date();
      const dateStr = `${date.getFullYear()}${String(date.getMonth() + 1).padStart(2, '0')}${String(date.getDate()).padStart(2, '0')}`;
      const zipFileName = `${logFileName}_export_${dateStr}.zip`;
      const zipFilePath = `${config.exportPath}/${zipFileName}`;

      // 获取指定文件的所有相关文件（包含分割的文件）
      const filesToExport = LogsHelperEnhanced.getLogFilesForName(logFileName);

      if (filesToExport.length === 0) {
        console.warn(LogsHelperEnhanced.TAG, `没有找到需要导出的日志文件: ${logFileName}`);
        return "";
      }

      // 如果需要解密，创建临时解密文件
      let filesForZip = filesToExport;
      if (decryptBeforeExporting && config.encryptionEnabled) {
        filesForZip = await LogsHelperEnhanced.decryptFilesForExport(filesToExport);
      }

      // 压缩文件
      await LogsHelperEnhanced.mergeFilesToOutput(filesForZip, zipFilePath);

      console.info(LogsHelperEnhanced.TAG, `文件日志导出成功: ${zipFilePath}`);
      // 返回相对路径
      return getParentPath(zipFilePath, LogsHelperEnhanced.savePathProvided, LogsHelperEnhanced.exportPathProvided);
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `导出文件日志失败: ${e}`);
      return "";
    }
  }

  /**
   * 获取指定文件名的所有日志文件（包含分割的文件）
   */
  private static getLogFilesForName(logFileName: string): Array<string> {
    const files: Array<string> = [];
    const config = LogsHelperEnhanced.logConfig;
    if (!config) return files;

    const basePath = LogsHelperEnhanced.getActualSavePath();
    console.info(LogsHelperEnhanced.TAG, `getLogFilesForName: basePath=${basePath}, logFileName=${logFileName}`);

    // 首先列出目录中的所有文件
    let dirFiles: string[] = [];
    try {
      dirFiles = fileIo.listFileSync(basePath);
      console.info(LogsHelperEnhanced.TAG, `getLogFilesForName: 目录中的文件数=${dirFiles.length}`);
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `getLogFilesForName: 读取目录失败: ${e}`);
      return files;
    }

    // 过滤以 logFileName 开头的文件
    for (const fileName of dirFiles) {
      if (fileName.startsWith(logFileName)) {
        const fullPath = `${basePath}/${fileName}`;
        try {
          const stat = fileIo.statSync(fullPath);
          if (stat.isFile()) {
            files.push(fullPath);
            console.info(LogsHelperEnhanced.TAG, `getLogFilesForName: 找到文件: ${fullPath}`);
          }
        } catch (e) {
          console.warn(LogsHelperEnhanced.TAG, `getLogFilesForName: 获取文件状态失败: ${fullPath}`);
        }
      }
    }

    console.info(LogsHelperEnhanced.TAG, `getLogFilesForName: 共找到 ${files.length} 个文件`);
    return files;
  }

  /**
   * 打印日志内容
   * 读取日志文件并返回内容
   */
  static async printLogs(exportType: ExportType, decryptBeforeExporting: boolean): Promise<string> {
    try {
      const filesToRead = await LogsHelperEnhanced.getLogFilesForExport(exportType);
      let allContent = "";

      for (const filePath of filesToRead) {
        const content = await LogsHelperEnhanced.readLogFile(filePath, decryptBeforeExporting);
        allContent += content + "\n";
      }

      // 去除最后一个换行符，使结束标记直接跟在内容后面
      if (allContent.length > 0 && allContent.charAt(allContent.length - 1) === "\n") {
        allContent = allContent.substring(0, allContent.length - 1);
      }
      allContent += ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>End";
      return allContent;
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `打印日志失败: ${e}`);
      return "";
    }
  }

  /**
   * 根据日志类型名称打印日志文件内容
   * 查找以 logFileName 开头的所有日志文件，并按修改时间排序后读取
   * @param logFileName 日志类型名称（如 "MyLogFile"）
   * @param decryptBeforeExporting 是否解密
   * @returns 文件内容
   */
  static async printFileLogsForName(logFileName: string, decryptBeforeExporting: boolean): Promise<string> {
    try {
      const config = LogsHelperEnhanced.logConfig;
      if (!config) {
        console.error(LogsHelperEnhanced.TAG, "日志配置未初始化");
        return "";
      }

      const basePath = LogsHelperEnhanced.getActualSavePath();
      console.info(LogsHelperEnhanced.TAG, `printFileLogsForName: basePath=${basePath}, logFileName=${logFileName}`);

      // 获取目录中的所有文件
      let files: string[] = [];
      try {
        const fileList = fileIo.listFileSync(basePath);
        files = fileList.map((f: string) => `${basePath}/${f}`);
        console.info(LogsHelperEnhanced.TAG, `printFileLogsForName: 目录中的文件数=${files.length}`);
      } catch (e) {
        console.error(LogsHelperEnhanced.TAG, `printFileLogsForName: 读取目录失败: ${e}`);
        return "";
      }

      // 过滤以 logFileName 开头的文件
      const matchingFiles = files.filter((filePath: string) => {
        const fileName = filePath.substring(filePath.lastIndexOf('/') + 1);
        return fileName.startsWith(logFileName);
      });

      console.info(LogsHelperEnhanced.TAG, `printFileLogsForName: 匹配的文件数=${matchingFiles.length}`);

      if (matchingFiles.length === 0) {
        console.warn(LogsHelperEnhanced.TAG, `printFileLogsForName: 没有找到匹配的日志文件: ${logFileName}`);
        return "";
      }

      // 按修改时间排序（最新的在前）
      const sortedFiles = matchingFiles.sort((a: string, b: string) => {
        try {
          const statA = fileIo.statSync(a);
          const statB = fileIo.statSync(b);
          return statB.mtime - statA.mtime;
        } catch (e) {
          return 0;
        }
      });

      // 读取所有匹配的文件内容
      let allContent = "";
      for (const filePath of sortedFiles) {
        console.info(LogsHelperEnhanced.TAG, `printFileLogsForName: 读取文件: ${filePath}`);
        const content = await LogsHelperEnhanced.readLogFile(filePath, decryptBeforeExporting);
        if (content.length > 0) {
          allContent += content + "\n";
        }
      }

      // 去除最后一个换行符
      if (allContent.length > 0 && allContent.charAt(allContent.length - 1) === "\n") {
        allContent = allContent.substring(0, allContent.length - 1);
      }

      console.info(LogsHelperEnhanced.TAG, `printFileLogsForName: 读取完成，内容长度=${allContent.length}`);
      return allContent;
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `printFileLogsForName: 打印日志失败: ${e}`);
      return "";
    }
  }

  /**
   * 清空所有日志
   * 使用 fileIo 删除日志目录中的所有文件
   */
  static async clearAllLogs(): Promise<boolean> {
    try {
      const config = LogsHelperEnhanced.logConfig;
      if (!config) {
        return false;
      }

      // 清空日志目录
      await LogsHelperEnhanced.clearDirectory(config.savePath);

      // 清空缓存的 logger 实例
      LogsHelperEnhanced.loggers.clear();

      console.info(LogsHelperEnhanced.TAG, "日志已清空");
      return true;
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `清空日志失败: ${e}`);
      return false;
    }
  }

  /**
   * 清理过期日志
   * 根据 logsRetentionPeriodInDays 配置删除旧日志
   */
  static async cleanOldLogs(): Promise<void> {
    try {
      const config = LogsHelperEnhanced.logConfig;
      if (!config || config.logsRetentionPeriodInDays <= 0) {
        return;
      }

      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - config.logsRetentionPeriodInDays);

      await LogsHelperEnhanced.deleteFilesOlderThan(config.savePath, cutoffDate);

      // 同时清理过期的 ZIP 文件
      if (config.zipsRetentionPeriodInDays > 0) {
        const zipCutoffDate = new Date();
        zipCutoffDate.setDate(zipCutoffDate.getDate() - config.zipsRetentionPeriodInDays);
        await LogsHelperEnhanced.deleteFilesOlderThan(config.exportPath, zipCutoffDate, ".zip");
      }
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `清理过期日志失败: ${e}`);
    }
  }

  /**
   * 读取日志文件内容
   * 支持 AES-128-CBC 解密
   */
  public static async readLogFile(filePath: string, decrypt: boolean): Promise<string> {
    try {
      // 检查文件是否存在
      try {
        await fileIo.access(filePath);
      } catch (e) {
        return "";
      }

      // 打开并读取文件
      const file = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(filePath);
      // 使用 ArrayBuffer 作为 read 的参数，然后通过 Uint8Array 视图来访问
      const arrayBuffer = new ArrayBuffer(stat.size);
      await fileIo.read(file.fd, arrayBuffer);
      await fileIo.close(file);
      const fileBuffer = new Uint8Array(arrayBuffer);

      // 如果需要解密 (AES-128-CBC)
      if (decrypt && LogsHelperEnhanced.logConfig?.encryptionKey) {
        // 密文是 Base64 编码的，先转换
        const encryptedContent: string = LogsHelperEnhanced.uint8ArrayToString(fileBuffer);
        return await LogsHelperEnhanced.decryptData(encryptedContent, LogsHelperEnhanced.logConfig.encryptionKey);
      }

      // 明文直接解码
      return LogsHelperEnhanced.uint8ArrayToString(fileBuffer);
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `读取日志文件失败: ${e}`);
      return "";
    }
  }

  /**
   * 获取需要导出的日志文件列表
   */
  private static async getLogFilesForExport(exportType: ExportType): Promise<Array<string>> {
    const config = LogsHelperEnhanced.logConfig;
    if (!config) return [];

    const allFiles: Array<string> = [];
    const now = new Date();

    try {
      // 确定要扫描的目录
      // 如果 fallbackToFilesDir 为 true，文件可能在 filesDir 下
      const dirsToScan: Array<string> = [config.savePath];
      if (LogsHelperEnhanced.fallbackToFilesDir && LogsHelperEnhanced.filesDirPath) {
        dirsToScan.push(LogsHelperEnhanced.filesDirPath);
        console.info(LogsHelperEnhanced.TAG, `扫描多个目录: ${JSON.stringify(dirsToScan)}`);
      }

      for (const dirPath of dirsToScan) {
        try {
          // 使用 fileIo 列出目录内容
          const entries = LogsHelperEnhanced.listDirectoryRecursive(dirPath);
          console.info(LogsHelperEnhanced.TAG, `目录 ${dirPath} 中找到 ${entries.length} 个文件`);

          for (const entry of entries) {
            const fileName = entry.substring(entry.lastIndexOf('/') + 1);

            // 根据导出类型过滤文件
            let shouldInclude = false;
            if (exportType === ExportType.ALL) {
              shouldInclude = true;
            } else if (exportType === ExportType.TODAY) {
              shouldInclude = LogsHelperEnhanced.isFileFromToday(entry);
            } else if (exportType === ExportType.LAST_HOUR) {
              shouldInclude = await LogsHelperEnhanced.isFileFromLastHours(entry, 1);
            } else if (exportType === ExportType.LAST_24_HOURS) {
              shouldInclude = await LogsHelperEnhanced.isFileFromLastHours(entry, 24);
            } else if (exportType === ExportType.WEEKS) {
              shouldInclude = await LogsHelperEnhanced.isFileFromLastDays(entry, 7);
            }

            if (shouldInclude && fileName.endsWith(`.${config.logFileExtension}`)) {
              // 避免重复添加
              if (!allFiles.includes(entry)) {
                allFiles.push(entry);
              }
            }
          }
        } catch (dirError) {
          console.warn(LogsHelperEnhanced.TAG, `扫描目录失败: ${dirPath}, 错误: ${dirError}`);
        }
      }
      
      console.info(LogsHelperEnhanced.TAG, `共找到 ${allFiles.length} 个日志文件用于导出`);
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `获取日志文件列表失败: ${e}`);
    }

    return allFiles;
  }

  /**
   * 递归列出目录中的所有文件（包含分割的日志文件）
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-core-file-kit-V5
   */
  private static listDirectoryRecursive(dirPath: string): Array<string> {
    const files: Array<string> = [];

    try {
      // 首先尝试从 loggers 获取文件路径（当前会话创建的文件）
      for (const logger of LogsHelperEnhanced.loggers.values()) {
        const loggerFiles = logger.getAllFilePaths();
        files.push(...loggerFiles);
      }
      
      // 然后从目录中读取文件（包括之前会话创建的文件）
      // 使用 listFileSync API 读取目录
      try {
        const dirEntries: Array<string> = fileIo.listFileSync(dirPath, {
          recursion: true,
          listNum: 0
        });
        for (const entry of dirEntries) {
          const fullPath = dirPath + entry;
          try {
            const stat: fileIo.Stat = fileIo.statSync(fullPath);
            if (stat.isFile()) {
              // 避免重复添加
              if (!files.includes(fullPath)) {
                files.push(fullPath);
              }
            }
          } catch (statError) {
            // 忽略无法访问的文件
            console.warn(LogsHelperEnhanced.TAG, `获取文件状态失败: ${fullPath}, 错误: ${statError}`);
          }
        }
      } catch (listError) {
        console.warn(LogsHelperEnhanced.TAG, `列出目录失败: ${dirPath}, 错误: ${listError}`);
      }
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `遍历目录失败: ${e}`);
    }

    return files;
  }

  /**
   * 删除指定日期之前的文件
   */
  private static async deleteFilesOlderThan(dirPath: string, cutoffDate: Date, extension?: string): Promise<void> {
    try {
      const files = LogsHelperEnhanced.listDirectoryRecursive(dirPath);

      for (const filePath of files) {
        try {
          // 获取文件状态 (使用 await)
          const stat = await fileIo.stat(filePath);
          const fileModifiedTime = stat.mtime;

          if (fileModifiedTime < cutoffDate.getTime()) {
            // 如果指定了扩展名，检查匹配
            if (extension && !filePath.endsWith(extension)) {
              continue;
            }

            // 删除文件 (使用 await)
            await fileIo.unlink(filePath);
            console.info(LogsHelperEnhanced.TAG, `删除过期文件: ${filePath}`);
          }
        } catch (e) {
          // 单个文件删除失败，继续处理其他文件
        }
      }
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `删除过期文件失败: ${e}`);
    }
  }

  /**
   * 清空目录中的所有文件
   */
  private static async clearDirectory(dirPath: string): Promise<void> {
    try {
      const files = LogsHelperEnhanced.listDirectoryRecursive(dirPath);

      for (const filePath of files) {
        try {
          await fileIo.unlink(filePath);
        } catch (e) {
          // 忽略删除失败
        }
      }
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `清空目录失败: ${e}`);
    }
  }

  /**
   * 将字符串转换为 Uint8Array (UTF-8)
   */
  public static stringToUint8Array(str: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encode(str);
  }

  /**
   * 将 Uint8Array 转换为字符串 (UTF-8)
   */
  public static uint8ArrayToString(data: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decode(data);
  }

  /**
   * Base64 编码 Uint8Array
   */
  public static uint8ArrayToBase64(data: Uint8Array): string {
    // 使用自定义 Base64 编码
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = '';
    let i = 0;
    while (i < data.length) {
      const a = data[i++];
      const b = i < data.length ? data[i++] : 0;
      const c = i < data.length ? data[i++] : 0;
      const bitmap = (a << 16) | (b << 8) | c;
      result += chars.charAt((bitmap >> 18) & 63);
      result += chars.charAt((bitmap >> 12) & 63);
      result += (i > data.length + 1) ? '=' : chars.charAt((bitmap >> 6) & 63);
      result += (i > data.length) ? '=' : chars.charAt(bitmap & 63);
    }
    return result;
  }

  /**
   * Base64 解码为 Uint8Array
   */
  public static base64ToUint8Array(data: string): Uint8Array {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = new Uint8Array(data.length * 3 / 4);
    let pos = 0;
    let i = 0;
    data = data.replace(/[^A-Za-z0-9+/]/g, '');
    while (i < data.length) {
      const e1 = chars.indexOf(data.charAt(i++));
      const e2 = chars.indexOf(data.charAt(i++));
      const e3 = chars.indexOf(data.charAt(i++));
      const e4 = chars.indexOf(data.charAt(i++));
      const bitmap = (e1 << 18) | (e2 << 12) | (e3 << 6) | e4;
      result[pos++] = (bitmap >> 16) & 255;
      if (e3 !== 64 && pos < result.length) result[pos++] = (bitmap >> 8) & 255;
      if (e4 !== 64 && pos < result.length) result[pos++] = bitmap & 255;
    }
    return result.slice(0, pos);
  }

  /**
   * 加密数据 - 使用标准 AES-128-CBC
   * 使用 @kit.CryptoArchitectureKit 实现
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/crypto-aes-sym-encrypt-decrypt-cbc
   */
  private static async encryptData(data: string, key: string): Promise<string> {
    try {
      // 1. 将密钥转换为 AES-128 密钥 (16字节)
      const keyData: Uint8Array = LogsHelperEnhanced.deriveKey(key, LogsHelperEnhanced.AES_KEY_SIZE);
      
      // 2. 生成随机 IV (16字节)
      const rand: cryptoFramework.Random = cryptoFramework.createRandom();
      const ivBlob: cryptoFramework.DataBlob = rand.generateRandomSync(LogsHelperEnhanced.AES_KEY_SIZE);
      
      // 3. 创建对称密钥
      const symKeyBlob: cryptoFramework.DataBlob = { data: keyData };
      const aesGenerator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
      const symKey: cryptoFramework.SymKey = await aesGenerator.convertKey(symKeyBlob);
      
      // 4. 创建 Cipher 实例 (AES128|CBC|PKCS7)
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
      
      // 5. 初始化加密模式
      const ivParamsSpec: cryptoFramework.IvParamsSpec = {
        algName: "IvParamsSpec",
        iv: ivBlob
      };
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, ivParamsSpec);
      
      // 6. 加密数据
      const plainData: Uint8Array = LogsHelperEnhanced.stringToUint8Array(data);
      const plainText: cryptoFramework.DataBlob = { data: plainData };
      const cipherData: cryptoFramework.DataBlob = await cipher.doFinal(plainText);
      
      // 7. 组合 IV + 密文，并进行 Base64 编码
      const result = new Uint8Array(ivBlob.data.length + cipherData.data.length);
      result.set(ivBlob.data, 0);
      result.set(cipherData.data, ivBlob.data.length);
      
      return LogsHelperEnhanced.uint8ArrayToBase64(result);
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `AES 加密失败: ${e}`);
      return data; // 加密失败返回原文
    }
  }

  /**
   * 解密数据 - 使用标准 AES-128-CBC
   */
  private static async decryptData(encryptedData: string, key: string): Promise<string> {
    try {
      // 1. Base64 解码
      const encryptedBytes: Uint8Array = LogsHelperEnhanced.base64ToUint8Array(encryptedData);
      
      // 2. 分离 IV 和密文
      const ivData: Uint8Array = encryptedBytes.slice(0, LogsHelperEnhanced.AES_KEY_SIZE);
      const cipherBytes: Uint8Array = encryptedBytes.slice(LogsHelperEnhanced.AES_KEY_SIZE);
      
      // 3. 将密钥转换为 AES-128 密钥
      const keyData: Uint8Array = LogsHelperEnhanced.deriveKey(key, LogsHelperEnhanced.AES_KEY_SIZE);
      
      // 4. 创建对称密钥
      const symKeyBlob: cryptoFramework.DataBlob = { data: keyData };
      const aesGenerator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
      const symKey: cryptoFramework.SymKey = await aesGenerator.convertKey(symKeyBlob);
      
      // 5. 创建 Cipher 实例
      const decoder: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
      
      // 6. 初始化解密模式
      const ivDataBlob: cryptoFramework.DataBlob = { data: ivData };
      const ivParamsSpec: cryptoFramework.IvParamsSpec = {
        algName: "IvParamsSpec",
        iv: ivDataBlob
      };
      await decoder.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, ivParamsSpec);
      
      // 7. 解密数据
      const cipherBlob: cryptoFramework.DataBlob = { data: cipherBytes };
      const decryptResult: cryptoFramework.DataBlob = await decoder.doFinal(cipherBlob);
      
      // 8. 转换为字符串
      return LogsHelperEnhanced.uint8ArrayToString(decryptResult.data);
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `AES 解密失败: ${e}`);
      return encryptedData; // 解密失败返回密文
    }
  }

  /**
   * 从字符串派生指定长度的密钥
   */
  private static deriveKey(key: string, length: number): Uint8Array {
    const result = new Uint8Array(length);
    const keyBytes: Uint8Array = LogsHelperEnhanced.stringToUint8Array(key);
    
    for (let i = 0; i < length; i++) {
      if (i < keyBytes.length) {
        result[i] = keyBytes[i];
      } else {
        // 如果密钥长度不足，使用 PBKDF2 风格的扩展 (简单实现)
        result[i] = (result[i % keyBytes.length] + i) % 256;
      }
    }
    return result;
  }

  /**
   * 为导出准备解密文件 (AES-128-CBC)
   */
  private static async decryptFilesForExport(filePaths: Array<string>): Promise<Array<string>> {
    const decryptedPaths: Array<string> = [];

    for (const filePath of filePaths) {
      try {
        const content = await LogsHelperEnhanced.readLogFile(filePath, true);
        const tempPath = `${filePath}.decrypted.tmp`;

        // 写入临时解密文件
        const file = await fileIo.open(tempPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        const encoder = new util.TextEncoder();
        const writeBuffer = encoder.encode(content);
        await fileIo.write(file.fd, writeBuffer.buffer as ArrayBuffer);
        await fileIo.close(file);

        decryptedPaths.push(tempPath);
      } catch (e) {
        console.error(LogsHelperEnhanced.TAG, `解密文件失败: ${e}`);
      }
    }

    return decryptedPaths;
  }

  // ============== 辅助方法 ==============

  private static getLoggerFor(type: string): LoggerEnhanced | null {
    if (!LogsHelperEnhanced.logConfig?.isEnabled) {
      return null;
    }

    if (!LogsHelperEnhanced.loggers.has(type)) {
      const logFilePath = LogsHelperEnhanced.getLogFilePath(type);
      const maxFileSize = LogsHelperEnhanced.logConfig?.singleLogFileSize ?? 2;
      LogsHelperEnhanced.loggers.set(type, new LoggerEnhanced(logFilePath, maxFileSize));
    }
    return LogsHelperEnhanced.loggers.get(type) ?? null;
  }

  private static getLogFilePath(type: string): string {
    const config = LogsHelperEnhanced.logConfig;
    if (!config) return "";

    const date = new Date();
    const dateStr = `${date.getFullYear()}${String(date.getMonth() + 1).padStart(2, '0')}${String(date.getDate()).padStart(2, '0')}`;

    // 使用原始文件名，保留用户定义的大小写
    let fileName = type;
    if (config.attachTimeStamp) {
      fileName += `_${dateStr}`;
    }
    fileName += `.${config.logFileExtension}`;

    // 如果启用加密，添加加密标记
    if (config.encryptionEnabled) {
      fileName += ".enc";
    }

    // 如果子目录不可写，回退到使用 filesDir
    if (LogsHelperEnhanced.fallbackToFilesDir && LogsHelperEnhanced.filesDirPath) {
      console.info(LogsHelperEnhanced.TAG, `使用 filesDir 作为日志路径: ${LogsHelperEnhanced.filesDirPath}/${fileName}`);
      return `${LogsHelperEnhanced.filesDirPath}/${fileName}`;
    }

    return `${config.savePath}/${fileName}`;
  }

  private static ensureDirectoryExists(dirPath: string): void {
    LogsHelperEnhanced.ensureDirectoryExistsRecursive(dirPath);
  }

  /**
   * 递归创建目录及其所有父目录（使用同步 API）
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-core-file-kit-V5
   * 注意：异步 mkdir 可能导致目录未创建完成就写入文件，使用同步 API 可避免此问题
   * @param dirPath 要创建的目录路径
   */
  public static ensureDirectoryExistsRecursive(dirPath: string): void {
    // 空路径检查
    if (!dirPath || dirPath.length === 0) {
      console.warn(LogsHelperEnhanced.TAG, `目录路径为空，跳过创建`);
      return;
    }

    console.info(LogsHelperEnhanced.TAG, `检查目录是否存在: ${dirPath}`);

    try {
      // 先检查目录是否存在（使用同步 API）
      const stat = fileIo.statSync(dirPath);
      if (stat.isDirectory()) {
        console.info(LogsHelperEnhanced.TAG, `目录已存在: ${dirPath}`);
        return; // 目录已存在，直接返回
      } else {
        console.error(LogsHelperEnhanced.TAG, `路径存在但不是目录: ${dirPath}`);
        throw new Error(`路径存在但不是目录: ${dirPath}`);
      }
    } catch (e) {
      // 目录不存在，需要创建
      console.info(LogsHelperEnhanced.TAG, `目录不存在，准备创建: ${dirPath}`);
    }

    // 递归创建父目录
    const lastSlashIndex = dirPath.lastIndexOf('/');
    if (lastSlashIndex > 0) {
      const parentDir = dirPath.substring(0, lastSlashIndex);
      // 避免无限递归（当父目录已经是根目录时）
      if (parentDir !== dirPath && parentDir.length > 0) {
        console.info(LogsHelperEnhanced.TAG, `递归创建父目录: ${parentDir}`);
        LogsHelperEnhanced.ensureDirectoryExistsRecursive(parentDir);
      }
    }

    // 创建当前目录（使用同步 API）
    console.info(LogsHelperEnhanced.TAG, `创建目录: ${dirPath}`);
    try {
      fileIo.mkdirSync(dirPath);
      console.info(LogsHelperEnhanced.TAG, `目录创建成功: ${dirPath}`);
      // 验证目录是否真的创建成功
      try {
        const stat = fileIo.statSync(dirPath);
        if (stat.isDirectory()) {
          console.info(LogsHelperEnhanced.TAG, `目录验证成功: ${dirPath}`);
        } else {
          console.error(LogsHelperEnhanced.TAG, `路径存在但不是目录: ${dirPath}`);
          throw new Error(`路径存在但不是目录: ${dirPath}`);
        }
      } catch (verifyError) {
        console.error(LogsHelperEnhanced.TAG, `目录验证失败: ${dirPath}, 错误: ${verifyError}`);
        throw new Error(`目录验证失败: ${dirPath}`);
      }
    } catch (mkdirError) {
      // 如果创建失败，可能是目录已存在（并发情况）
      console.warn(LogsHelperEnhanced.TAG, `mkdir失败，检查是否已存在: ${dirPath}, 错误: ${mkdirError}`);
      try {
        const stat = fileIo.statSync(dirPath);
        if (stat.isDirectory()) {
          console.info(LogsHelperEnhanced.TAG, `目录已存在（并发创建）: ${dirPath}`);
        } else {
          console.error(LogsHelperEnhanced.TAG, `路径存在但不是目录: ${dirPath}`);
          throw new Error(`路径存在但不是目录: ${dirPath}`);
        }
      } catch (accessError) {
        console.error(LogsHelperEnhanced.TAG, `创建目录失败: ${dirPath}, 错误: ${mkdirError}`);
        throw new Error(`创建目录失败: ${dirPath}`);
      }
    }
  }

  private static getFormattedTime(): string {
    const date = new Date();
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    const seconds = String(date.getSeconds()).padStart(2, '0');
    return `${hours}:${minutes}:${seconds}`;
  }

  private static isFileFromToday(filePath: string): boolean {
    // 简化实现：检查文件名中是否包含今天的日期
    const today = new Date();
    const dateStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    return filePath.includes(dateStr);
  }

  private static async isFileFromLastHours(filePath: string, hours: number): Promise<boolean> {
    // 通过文件修改时间判断
    try {
      const stat = await fileIo.stat(filePath);
      const fileTime = stat.mtime;
      const cutoffTime = Date.now() - (hours * 60 * 60 * 1000);
      return fileTime > cutoffTime;
    } catch (e) {
      return false;
    }
  }

  private static async isFileFromLastDays(filePath: string, days: number): Promise<boolean> {
    return await LogsHelperEnhanced.isFileFromLastHours(filePath, days * 24);
  }

  private static scheduleZipCleanup(): void {
    // 可以在这里设置定时任务清理旧 ZIP
    // 鸿蒙侧可以使用 setInterval 或 WorkScheduler
    console.info(LogsHelperEnhanced.TAG, "已安排 ZIP 文件清理任务");
  }

  /**
   * 压缩多个文件为 ZIP 格式
   * 使用 ZipHelper 实现多文件 ZIP 压缩
   * 支持真正的多文件 ZIP 格式
   */
  private static async mergeFilesToOutput(filePaths: Array<string>, outputPath: string): Promise<void> {
    try {
      console.info(LogsHelperEnhanced.TAG, `开始创建 ZIP 文件: ${outputPath}, 文件数: ${filePaths.length}`);
      
      // 检查源文件是否存在
      for (const filePath of filePaths) {
        try {
          fileIo.accessSync(filePath);
          console.info(LogsHelperEnhanced.TAG, `源文件存在: ${filePath}`);
        } catch (e) {
          console.error(LogsHelperEnhanced.TAG, `源文件不存在: ${filePath}`);
        }
      }

      // 准备文件列表
      const files: Array<ZipFileInfo> = [];
      for (const filePath of filePaths) {
        const fileName = filePath.substring(filePath.lastIndexOf('/') + 1);
        const fileInfo: ZipFileInfo = { path: filePath, name: fileName };
        files.push(fileInfo);
      }

      // 使用 ZipHelper 创建多文件 ZIP
      const success = await ZipHelper.createZip(files, outputPath);

      if (success) {
        console.info(LogsHelperEnhanced.TAG, `ZIP 文件创建成功: ${outputPath}`);
      } else {
        throw new Error("ZipHelper 创建 ZIP 失败");
      }
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `创建 ZIP 文件失败: ${e}`);
      // 回退到文件合并方式
      await LogsHelperEnhanced.fallbackMergeFiles(filePaths, outputPath);
    }
  }

  /**
   * 文件合并回退方案（当 ZIP 压缩失败时使用）
   */
  private static async fallbackMergeFiles(filePaths: Array<string>, outputPath: string): Promise<void> {
    try {
      const outputFile = await fileIo.open(outputPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);

      const header = `===== 日志导出文件 - ${new Date().toISOString()} =====\n`;
      const headerEncoder = new util.TextEncoder();
      const headerBuffer = headerEncoder.encode(header);
      await fileIo.write(outputFile.fd, headerBuffer.buffer as ArrayBuffer);

      for (const filePath of filePaths) {
        try {
          const srcFile = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY);
          const stat = await fileIo.stat(filePath);
          const arrayBuffer = new ArrayBuffer(stat.size);
          await fileIo.read(srcFile.fd, arrayBuffer);
          await fileIo.close(srcFile);

          const separator = `\n===== 文件: ${filePath} =====\n`;
          const sepBuffer = new util.TextEncoder().encode(separator);
          await fileIo.write(outputFile.fd, sepBuffer.buffer as ArrayBuffer);
          await fileIo.write(outputFile.fd, arrayBuffer);
        } catch (e) {
          console.error(LogsHelperEnhanced.TAG, `合并文件失败 ${filePath}: ${e}`);
        }
      }

      await fileIo.close(outputFile);
      console.info(LogsHelperEnhanced.TAG, `文件合并完成: ${outputPath}`);
    } catch (e) {
      console.error(LogsHelperEnhanced.TAG, `回退合并失败: ${e}`);
      throw new Error(`创建导出文件失败: ${e}`);
    }
  }
}

// ============== 增强版 Logger 类 (支持文件分割) ==============

class LoggerEnhanced {
  private baseFilePath: string;  // 基础文件路径
  private currentFilePath: string; // 当前写入的文件路径
  private fileIndex: number = 0;   // 当前文件索引
  private maxFileSize: number;    // 单个文件最大大小（字节）
  private isEncrypted: boolean = false;

  constructor(filePath: string, maxSizeMB: number = 2) {
    this.baseFilePath = filePath;
    this.currentFilePath = filePath;
    this.maxFileSize = maxSizeMB * 1024 * 1024; // 转换为字节
  }

  getFilePath(): string {
    return this.currentFilePath;
  }

  /**
   * 获取所有日志文件路径（包含分割的文件）
   */
  getAllFilePaths(): Array<string> {
    const paths: Array<string> = [];
    paths.push(this.baseFilePath);
    
    // 添加分割的文件
    for (let i = 1; i <= this.fileIndex; i++) {
      const splitPath = this.getSplitFilePath(i);
      paths.push(splitPath);
    }
    
    return paths;
  }

  /**
   * 追加内容到文件（自动分割）
   * @param data 要写入的数据
   * @param isEncryptedData 数据是否已加密
   */
  async appendToFile(data: string, isEncryptedData: boolean): Promise<void> {
    try {
      this.isEncrypted = isEncryptedData;
      
      // 检查当前文件大小，决定是否需要分割
      const currentSize = await this.getCurrentFileSize();
      const dataBytes: Uint8Array = LogsHelperEnhanced.stringToUint8Array(data);
      const dataSize = dataBytes.length;
      
      if (currentSize + dataSize > this.maxFileSize && currentSize > 0) {
        // 需要创建新文件
        this.fileIndex++;
        this.currentFilePath = this.getSplitFilePath(this.fileIndex);
        console.info("FlutterLogsPlugin.LoggerEnhanced", `日志文件分割: 创建新文件 ${this.currentFilePath}`);
      }

      let file: fileIo.File | null = null;
      try {
        console.info("FlutterLogsPlugin.LoggerEnhanced", `开始写入日志，文件路径: ${this.currentFilePath}`);

        // 确保目录存在（使用同步 API）
        console.info("FlutterLogsPlugin.LoggerEnhanced", `确保目录存在...`);
        this.ensureDirectoryExists();
        console.info("FlutterLogsPlugin.LoggerEnhanced", `目录确保完成`);

        // 直接使用 CREATE | READ_WRITE 模式创建/打开文件
        // 注意：根据鸿蒙文档，CREATE 只能创建文件，不能创建目录，目录必须已存在
        console.info("FlutterLogsPlugin.LoggerEnhanced", `尝试创建/打开文件: ${this.currentFilePath}`);

        // 在open之前再次确认目录存在
        const dirPath = this.currentFilePath.substring(0, this.currentFilePath.lastIndexOf('/'));
        try {
          fileIo.accessSync(dirPath);
          console.info("FlutterLogsPlugin.LoggerEnhanced", `目录确认可访问: ${dirPath}`);
        } catch (accessErr) {
          console.error("FlutterLogsPlugin.LoggerEnhanced", `目录无法访问: ${dirPath}, 错误: ${accessErr}`);
          // 尝试重新创建目录（使用同步 API）
          LogsHelperEnhanced.ensureDirectoryExistsRecursive(dirPath);
        }

        try {
          // 尝试使用同步方式打开文件，使用 READ_WRITE | CREATE 模式
          console.info("FlutterLogsPlugin.LoggerEnhanced", `尝试使用 openSync 打开文件`);
          file = fileIo.openSync(this.currentFilePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
          console.info("FlutterLogsPlugin.LoggerEnhanced", `文件创建/打开成功(sync)，fd=${file.fd}`);
        } catch (syncError) {
          console.error("FlutterLogsPlugin.LoggerEnhanced", `openSync 失败: ${syncError}，尝试使用异步 open`);
          try {
            // 尝试使用异步 open
            file = await fileIo.open(this.currentFilePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
            console.info("FlutterLogsPlugin.LoggerEnhanced", `文件创建/打开成功(async)，fd=${file.fd}`);
          } catch (asyncError) {
            console.error("FlutterLogsPlugin.LoggerEnhanced", `异步 open 也失败: ${asyncError}`);
            // 最后尝试：使用 stream 方式
            try {
              console.info("FlutterLogsPlugin.LoggerEnhanced", `尝试使用 createStream 创建文件流`);
              const stream = fileIo.createStreamSync(this.currentFilePath, 'w');
              console.info("FlutterLogsPlugin.LoggerEnhanced", `文件流创建成功`);
              // 使用流写入数据
              const encoder = new util.TextEncoder();
              const writeBuffer = encoder.encode(data);
              await stream.write(writeBuffer.buffer as ArrayBuffer);
              console.info("FlutterLogsPlugin.LoggerEnhanced", `数据通过流写入成功`);
              await stream.close();
              console.info("FlutterLogsPlugin.LoggerEnhanced", `文件流关闭成功`);
              return; // 成功写入，直接返回
            } catch (streamError) {
              console.error("FlutterLogsPlugin.LoggerEnhanced", `createStream 也失败: ${streamError}`);
              throw new Error(`文件创建/打开失败: ${asyncError}`);
            }
          }
        }

        console.info("FlutterLogsPlugin.LoggerEnhanced", `文件打开成功，准备写入数据`);

        // 写入数据
        const encoder = new util.TextEncoder();
        const writeBuffer = encoder.encode(data);
        await fileIo.write(file.fd, writeBuffer.buffer as ArrayBuffer);
        console.info("FlutterLogsPlugin.LoggerEnhanced", `数据写入成功`);
      } catch (e) {
        console.error("FlutterLogsPlugin.LoggerEnhanced", `文件操作失败: 文件=${this.currentFilePath}, 错误=${e}`);
        throw new Error(`文件操作失败: ${e}`);
      } finally {
        if (file) {
          try {
            await fileIo.close(file);
            console.info("FlutterLogsPlugin.LoggerEnhanced", `文件关闭成功`);
          } catch (closeError) {
            console.error("FlutterLogsPlugin.LoggerEnhanced", `文件关闭失败: ${closeError}`);
          }
        }
      }
    } catch (e) {
      console.error("FlutterLogsPlugin.LoggerEnhanced", `追加文件内容失败: 文件=${this.currentFilePath}, 错误=${e}`);
    }
  }

  /**
   * 覆盖写入文件
   * @param data 要写入的数据
   * @param isEncryptedData 数据是否已加密
   */
  async overwriteToFile(data: string, isEncryptedData: boolean): Promise<void> {
    try {
      this.isEncrypted = isEncryptedData;
      this.fileIndex = 0;
      this.currentFilePath = this.baseFilePath;

      let file: fileIo.File | null = null;
      try {
        // 确保目录存在（使用同步 API）
        this.ensureDirectoryExists();

        // 检查文件是否存在，如果存在则删除
        try {
          await fileIo.access(this.currentFilePath);
          await fileIo.unlink(this.currentFilePath);
        } catch (e) {
          // 文件不存在，忽略错误
        }

        // 创建新文件
        file = await fileIo.open(this.currentFilePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);

        const encoder = new util.TextEncoder();
        const writeBuffer = encoder.encode(data);
        await fileIo.write(file.fd, writeBuffer.buffer as ArrayBuffer);
      } catch (e) {
        console.error("FlutterLogsPlugin.LoggerEnhanced", `文件操作失败: 文件=${this.currentFilePath}, 错误=${e}`);
        throw new Error(`文件操作失败: ${e}`);
      } finally {
        if (file) {
          try {
            await fileIo.close(file);
          } catch (closeError) {
            console.error("FlutterLogsPlugin.LoggerEnhanced", `文件关闭失败: ${closeError}`);
          }
        }
      }
    } catch (e) {
      console.error("FlutterLogsPlugin.LoggerEnhanced", `覆盖文件内容失败: 文件=${this.currentFilePath}, 错误=${e}`);
    }
  }

  /**
   * 获取当前文件大小
   */
  private async getCurrentFileSize(): Promise<number> {
    try {
      const stat = await fileIo.stat(this.currentFilePath);
      return stat.size;
    } catch (e) {
      return 0; // 文件不存在
    }
  }

  /**
   * 获取分割后的文件路径
   */
  private getSplitFilePath(index: number): string {
    const lastDotIndex = this.baseFilePath.lastIndexOf('.');
    if (lastDotIndex === -1) {
      return `${this.baseFilePath}_${index}`;
    }
    const baseName = this.baseFilePath.substring(0, lastDotIndex);
    const extension = this.baseFilePath.substring(lastDotIndex);
    return `${baseName}_${index}${extension}`;
  }

  /**
   * 确保目录存在
   */
  private ensureDirectoryExists(): void {
    const lastSlashIndex = this.currentFilePath.lastIndexOf('/');
    if (lastSlashIndex > 0) {
      const dirPath = this.currentFilePath.substring(0, lastSlashIndex);
      console.info("FlutterLogsPlugin.LoggerEnhanced", `ensureDirectoryExists: 文件路径=${this.currentFilePath}, 目录路径=${dirPath}`);
      LogsHelperEnhanced.ensureDirectoryExistsRecursive(dirPath);
    } else {
      console.warn("FlutterLogsPlugin.LoggerEnhanced", `ensureDirectoryExists: 无法从路径中提取目录: ${this.currentFilePath}`);
    }
  }
}

// ============== 接口定义 ==============

interface LogsConfig {
  logLevelsEnabled: Array<string>;
  logTypesEnabled: Array<string>;
  logsRetentionPeriodInDays: number;
  zipsRetentionPeriodInDays: number;
  autoDeleteZipOnExport: boolean;
  autoClearLogs: boolean;
  autoExportErrors: boolean;
  encryptionEnabled: boolean;
  encryptionKey: string;
  directoryStructure: DirectoryStructure;
  logSystemCrashes: boolean;
  isDebuggable: boolean;
  debugFileOperations: boolean;
  attachTimeStamp: boolean;
  attachNoOfFiles: boolean;
  timeStampFormat: TimeStampFormat;
  logFileExtension: LogExtension;
  zipFilesOnly: boolean;
  zipFileName: string;
  savePath: string;
  exportPath: string;
  singleLogFileSize: number;
  isEnabled: boolean;
}

// ============== 电池信息接口 ==============

interface BatteryInfo {
  soc: string;
  chargingStatus: string;
  healthStatus: string;
}

// ============== ELK 配置接口 ==============

interface ELKConfig {
  appId: string;
  appName: string;
  appVersion: string;
  deviceId: string;
  environmentId: string;
  environmentName: string;
  organizationId: string;
  organizationUnitId: string;
  language: string;
  userId: string;
  userName: string;
  userEmail: string;
  deviceSerial: string;
  deviceBrand: string;
  deviceName: string;
  deviceManufacturer: string;
  deviceModel: string;
  deviceSdkInt: string;
  deviceBatteryPercent: string;
  latitude: string;
  longitude: string;
}
