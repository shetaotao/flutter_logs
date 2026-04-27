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
import { LogLevel, DirectoryStructure, LogExtension, TimeStampFormat, ExportType } from './Utils';
import util from '@ohos.util';

export class LogsHelper {
  private static TAG = "LogsHelper";
  static savePathProvided: string = "";
  static exportPathProvided: string = "";

  // 当前使用鸿蒙 fileIo API 实现基础文件日志功能
  private static logConfig: LogsConfig | null = null;
  private static loggers: Map<string, Logger> = new Map();

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
    const filesDir = context.filesDir;

    // 先计算路径
    const finalSavePath = savePath ? `${filesDir}/${savePath}` : filesDir;
    const finalExportPath = exportPath ? `${filesDir}/${savePath}/${exportPath}` : filesDir;

    console.info(LogsHelper.TAG, `开始初始化日志配置...`);
    console.info(LogsHelper.TAG, `日志保存路径: ${finalSavePath}`);
    console.info(LogsHelper.TAG, `日志导出路径: ${finalExportPath}`);

    // 先确保目录存在，再设置配置
    console.info(LogsHelper.TAG, `创建日志目录...`);
    await LogsHelper.ensureDirectoryExists(finalSavePath);
    if (finalExportPath && finalExportPath !== finalSavePath) {
      await LogsHelper.ensureDirectoryExists(finalExportPath);
    }
    console.info(LogsHelper.TAG, `日志目录创建完成`);

    // 目录创建完成后，再设置配置
    LogsHelper.logConfig = {
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
      LogsHelper.savePathProvided = savePath;
    }

    if (exportPath) {
      LogsHelper.exportPathProvided = exportPath;
    }

    console.info(LogsHelper.TAG, `日志配置初始化完成`);
  }

  static writeLogToFile(type: string, data: string | null, appendTimeStamp: boolean): void {
    try {
      const logger = LogsHelper.getLoggerFor(type);
      if (logger) {
        const timestamp = appendTimeStamp ? ` [${LogsHelper.getFormattedTime()}]` : "";
        const logData = `${data}${timestamp}\n`;
        logger.appendToFile(logData);
      }
    } catch (e) {
      console.error("LogsHelper", `写入日志失败: ${e}`);
    }
  }

  static overWriteLogToFile(type: string, data: string | null, appendTimeStamp: boolean): void {
    try {
      const logger = LogsHelper.getLoggerFor(type);
      if (logger) {
        const timestamp = appendTimeStamp ? ` [${LogsHelper.getFormattedTime()}]` : "";
        const logData = data ? `${data}${timestamp}` : "";
        logger.overwriteToFile(logData);
      }
    } catch (e) {
      console.error("LogsHelper", `覆盖日志失败: ${e}`);
    }
  }

  static setupForELKStack(
    appId: string | null,
    appName: string | null,
    appVersion: string | null,
    deviceId: string | null,
    environmentId: string | null,
    environmentName: string | null,
    organizationId: string | null,
    organizationUnitId: string | null,
    language: string | null,
    userId: string | null,
    userName: string | null,
    userEmail: string | null,
    deviceSerial: string | null,
    deviceBrand: string | null,
    deviceName: string | null,
    deviceManufacturer: string | null,
    deviceModel: string | null,
    deviceSdkInt: string | null,
    deviceBatteryPercent: string | null,
    latitude: string | null,
    longitude: string | null
  ): void {
    // TODO: ELK Stack 支持在鸿蒙侧需要重新评估实现方式
    // 当前保留元数据信息供后续扩展使用
    const metaInfo: MetaInfo = {
      appId: appId ?? "",
      appName: appName ?? "",
      appVersion: appVersion ?? "",
      deviceId: deviceId ?? "",
      environmentId: environmentId ?? "",
      environmentName: environmentName ?? "",
      organizationId: organizationId ?? "",
      organizationUnitId: organizationUnitId ?? "",
      language: language ?? "",
      userId: userId ?? "",
      userName: userName ?? "",
      userEmail: userEmail ?? "",
      deviceSerial: deviceSerial ?? "",
      deviceBrand: deviceBrand ?? "",
      deviceName: deviceName ?? "",
      deviceManufacturer: deviceManufacturer ?? "",
      deviceModel: deviceModel ?? "",
      deviceSdkInt: deviceSdkInt ?? "",
      batteryPercent: deviceBatteryPercent ?? "",
      latitude: latitude ? parseFloat(latitude) : 0.0,
      longitude: longitude ? parseFloat(longitude) : 0.0
    };

    // 存储元数据供日志使用
    AppStorage.setOrCreate('elkMetaInfo', metaInfo);
  }

  static setMQTT(
    writeLogsToLocalStorage: boolean | null,
    topic: string | null,
    brokerUrl: string,
    certificateInputStream: Uint8Array | null,
    clientId: string | null,
    port: string | null,
    qos: number | null,
    retained: boolean | null,
    debug: boolean | null,
    initialDelaySecondsForPublishing: number | null
  ): void {
    // TODO: MQTT 功能在鸿蒙侧需要使用鸿蒙 MQTT 客户端库重新实现
    // 参考：@ohos/net.socket 或第三方 MQTT HAR 包
    if (brokerUrl && brokerUrl.length > 0) {
      console.info("LogsHelper", "MQTT 配置已请求 - OpenHarmony 实现待完成");
      // 保留配置供后续实现
      const mqttConfig: MQTTConfig = {
        writeLogsToLocalStorage: writeLogsToLocalStorage ?? true,
        topic: topic ?? "",
        brokerUrl: brokerUrl,
        certificate: certificateInputStream,
        clientId: clientId ?? "",
        port: port ?? "",
        qos: qos ?? 0,
        retained: retained ?? false,
        debug: debug ?? true,
        initialDelaySecondsForPublishing: initialDelaySecondsForPublishing ?? 30
      };
      AppStorage.setOrCreate('mqttConfig', mqttConfig);
    }
  }

  // 内部方法：获取或创建 Logger
  private static getLoggerFor(type: string): Logger | null {
    if (!LogsHelper.logConfig?.isEnabled) {
      return null;
    }

    if (!LogsHelper.loggers.has(type)) {
      const logFilePath = LogsHelper.getLogFilePath(type);
      LogsHelper.loggers.set(type, new Logger(logFilePath));
    }
    return LogsHelper.loggers.get(type) ?? null;
  }

  // 内部方法：生成日志文件路径
  private static getLogFilePath(type: string): string {
    const config = LogsHelper.logConfig;
    if (!config) return "";

    const date = new Date();
    const dateStr = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;

    let fileName = type;
    if (config.attachTimeStamp) {
      fileName += `_${dateStr}`;
    }
    fileName += `.${config.logFileExtension}`;

    switch (config.directoryStructure) {
      case DirectoryStructure.FOR_DATE:
        return `${config.savePath}/${dateStr}/${fileName}`;
      case DirectoryStructure.FOR_EVENT:
        return `${config.savePath}/${type}/${fileName}`;
      case DirectoryStructure.SINGLE_FILE_FOR_DAY:
      default:
        return `${config.savePath}/${fileName}`;
    }
  }

  // 内部方法：确保目录存在
  private static async ensureDirectoryExists(dirPath: string): Promise<void> {
    await LogsHelper.ensureDirectoryExistsRecursive(dirPath);
  }

  /**
   * 递归创建目录及其所有父目录
   * @param dirPath 要创建的目录路径
   */
  public static async ensureDirectoryExistsRecursive(dirPath: string): Promise<void> {
    try {
      // 先检查目录是否存在
      await fileIo.access(dirPath);
      return; // 目录已存在，直接返回
    } catch (e) {
      // 目录不存在，需要创建
    }

    // 递归创建父目录
    const lastSlashIndex = dirPath.lastIndexOf('/');
    if (lastSlashIndex > 0) {
      const parentDir = dirPath.substring(0, lastSlashIndex);
      // 避免无限递归（当父目录已经是根目录时）
      if (parentDir !== dirPath && parentDir.length > 0) {
        await LogsHelper.ensureDirectoryExistsRecursive(parentDir);
      }
    }

    // 创建当前目录
    try {
      await fileIo.mkdir(dirPath);
    } catch (mkdirError) {
      // 如果创建失败，可能是目录已存在（并发情况），忽略错误
      try {
        await fileIo.access(dirPath);
      } catch (accessError) {
        console.error("LogsHelper", `创建目录失败: ${dirPath}, 错误: ${mkdirError}`);
      }
    }
  }

  // 内部方法：格式化时间
  private static getFormattedTime(): string {
    const date = new Date();
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    const seconds = String(date.getSeconds()).padStart(2, '0');
    return `${hours}:${minutes}:${seconds}`;
  }
}

// Logger 类封装文件操作
class Logger {
  private filePath: string;

  constructor(filePath: string) {
    this.filePath = filePath;
    // 注意: 构造函数中不能调用异步方法
    // 目录创建会在首次写入时自动处理
  }

  async appendToFile(data: string): Promise<void> {
    try {
      // 确保目录存在
      await this.ensureDirectoryExists();

      let file: fileIo.File | null = null;
      try {
        // 检查文件是否存在
        let fileExists = false;
        try {
          await fileIo.access(this.filePath);
          fileExists = true;
        } catch (e) {
          // 文件不存在
        }

        if (fileExists) {
          // 文件存在，使用 READ_WRITE 模式
          file = await fileIo.open(this.filePath, fileIo.OpenMode.READ_WRITE);
          // 移动到文件末尾
          try {
            const stat = await fileIo.stat(this.filePath);
            await fileIo.lseek(file.fd, stat.size, fileIo.WhenceType.SEEK_SET);
          } catch (e) {
            // 忽略错误
          }
        } else {
          // 文件不存在，使用 CREATE 模式创建新文件
          file = await fileIo.open(this.filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
        }

        // 写入数据 (使用 Uint8Array 替代 ArrayBuffer)
        const encoder = new util.TextEncoder();
        const buffer = encoder.encode(data);
        await fileIo.write(file.fd, buffer);
      } finally {
        if (file) {
          await fileIo.close(file);
        }
      }
    } catch (e) {
      console.error("FlutterLogsPlugin.LogHelper", `追加文件内容失败: ${e}`);
    }
  }

  async overwriteToFile(data: string): Promise<void> {
    try {
      // 确保目录存在
      await this.ensureDirectoryExists();

      let file: fileIo.File | null = null;
      try {
        // 检查文件是否存在，如果存在则删除后重新创建
        try {
          await fileIo.access(this.filePath);
          await fileIo.unlink(this.filePath);
        } catch (e) {
          // 文件不存在，忽略错误
        }

        // 创建新文件
        file = await fileIo.open(this.filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);

        // 写入数据 (使用 Uint8Array 替代 ArrayBuffer)
        const encoder = new util.TextEncoder();
        const buffer = encoder.encode(data);
        await fileIo.write(file.fd, buffer);
      } finally {
        if (file) {
          await fileIo.close(file);
        }
      }
    } catch (e) {
      console.error("FlutterLogsPlugin.LogHelper", `覆盖文件内容失败: ${e}`);
    }
  }

  /**
   * 确保目录存在（递归创建）
   */
  private async ensureDirectoryExists(): Promise<void> {
    const lastSlashIndex = this.filePath.lastIndexOf('/');
    if (lastSlashIndex > 0) {
      const dirPath = this.filePath.substring(0, lastSlashIndex);
      await LogsHelper.ensureDirectoryExistsRecursive(dirPath);
    }
  }
}

// 日志配置接口定义
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
  savePath: string;
  zipFileName: string;
  exportPath: string;
  singleLogFileSize: number;
  isEnabled: boolean;
}

// ELK 元数据接口定义
interface MetaInfo {
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
  batteryPercent: string;
  latitude: number;
  longitude: number;
}

// MQTT 配置接口定义
interface MQTTConfig {
  writeLogsToLocalStorage: boolean;
  topic: string;
  brokerUrl: string;
  certificate: Uint8Array | null;
  clientId: string;
  port: string;
  qos: number;
  retained: boolean;
  debug: boolean;
  initialDelaySecondsForPublishing: number;
}
