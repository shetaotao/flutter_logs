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

import { MethodCall } from '@ohos/flutter_ohos';

export function getLogLevelsById(key: string, call: MethodCall): Array<string> {
  const listOfLogLevels: Array<string> = [];
  const value = call.argument(key) as string | null;
  if (value) {
    value.split(",").forEach((item) => {
      listOfLogLevels.push(getLogLevel(item));
    });
    return listOfLogLevels;
  }
  return [];
}

export function getListOfStringById(key: string, call: MethodCall): Array<string> {
  const logTypesList: Array<string> = [];
  const value = call.argument(key) as string | null;
  if (value) {
    value.split(",").forEach((item) => {
      logTypesList.push(item);
    });
    return logTypesList;
  }
  return [];
}

export function getStringValueById(key: string, call: MethodCall): string {
  const value = call.argument(key) as string | null;
  if (value) {
    return value;
  }
  return "";
}

export function getIntValueById(key: string, call: MethodCall): number | null {
  const value = call.argument(key) as number | null;
  if (value !== undefined && value !== null) {
    return value;
  }
  return null;
}

export function getBoolValueById(key: string, call: MethodCall): boolean {
  const value = call.argument(key) as boolean | null;
  if (value !== undefined && value !== null) {
    return value;
  }
  return false;
}

export function getInputStreamValueById(key: string, call: MethodCall): Uint8Array | null {
  const value = call.argument(key) as Uint8Array | null;
  if (value) {
    return value;
  }
  return null;
}

export function getDirectoryStructure(type: string | null): DirectoryStructure {
  switch (type) {
    case "FOR_DATE":
      return DirectoryStructure.FOR_DATE;
    case "FOR_EVENT":
      return DirectoryStructure.FOR_EVENT;
    case "SINGLE_FILE_FOR_DAY":
      return DirectoryStructure.SINGLE_FILE_FOR_DAY;
    default:
      return DirectoryStructure.SINGLE_FILE_FOR_DAY;
  }
}

export function getLogFileExtension(type: string | null): LogExtension {
  switch (type) {
    case "TXT":
      return LogExtension.TXT;
    case "CSV":
      return LogExtension.CSV;
    case "LOG":
      return LogExtension.LOG;
    case "NONE":
      return LogExtension.NONE;
    default:
      return LogExtension.LOG;
  }
}

export function getLogLevel(type: string | null): LogLevel {
  switch (type) {
    case "INFO":
      return LogLevel.INFO;
    case "WARNING":
      return LogLevel.WARNING;
    case "ERROR":
      return LogLevel.ERROR;
    case "SEVERE":
      return LogLevel.SEVERE;
    default:
      return LogLevel.INFO;
  }
}

export function getExportType(type: string | null): ExportType {
  switch (type) {
    case "TODAY":
      return ExportType.TODAY;
    case "LAST_HOUR":
      return ExportType.LAST_HOUR;
    case "WEEKS":
      return ExportType.WEEKS;
    case "LAST_24_HOURS":
      return ExportType.LAST_24_HOURS;
    case "ALL":
      return ExportType.ALL;
    default:
      return ExportType.ALL;
  }
}

export function getTimeStampFormat(type: string | null): TimeStampFormat {
  switch (type) {
    case "DATE_FORMAT_1":
      return TimeStampFormat.DATE_FORMAT_1;
    case "DATE_FORMAT_2":
      return TimeStampFormat.DATE_FORMAT_2;
    case "TIME_FORMAT_FULL_JOINED":
      return TimeStampFormat.TIME_FORMAT_FULL_JOINED;
    case "TIME_FORMAT_FULL_1":
      return TimeStampFormat.TIME_FORMAT_FULL_1;
    case "TIME_FORMAT_FULL_2":
      return TimeStampFormat.TIME_FORMAT_FULL_2;
    case "TIME_FORMAT_24_FULL":
      return TimeStampFormat.TIME_FORMAT_24_FULL;
    case "TIME_FORMAT_READABLE":
      return TimeStampFormat.TIME_FORMAT_READABLE;
    case "TIME_FORMAT_READABLE_2":
      return TimeStampFormat.TIME_FORMAT_READABLE_2;
    case "TIME_FORMAT_SIMPLE":
      return TimeStampFormat.TIME_FORMAT_SIMPLE;
    default:
      return TimeStampFormat.TIME_FORMAT_24_FULL;
  }
}

export function getParentPath(path: string, savePath: string, exportPath: string): string {
  // 从完整路径中提取文件名
  const pathParts = path.split('/');
  const fileName = pathParts[pathParts.length - 1];
  
  // 如果 savePath 和 exportPath 为空，直接返回文件名
  if (!savePath && !exportPath) {
    return fileName;
  }
  
  // 构建相对路径
  // 注意：如果 exportPath 已经包含 savePath，不要重复添加
  let result = '';
  
  if (exportPath) {
    // 如果 exportPath 已经包含 savePath，直接使用 exportPath
    if (savePath && exportPath.startsWith(savePath + '/')) {
      result = exportPath;
    } else if (savePath) {
      // 否则，拼接 savePath 和 exportPath
      result = `${savePath}/${exportPath}`;
    } else {
      result = exportPath;
    }
  } else if (savePath) {
    result = savePath;
  }
  
  result = result ? `${result}/${fileName}` : fileName;
  
  return result;
}

// Enums
export enum DirectoryStructure {
  FOR_DATE = "FOR_DATE",
  FOR_EVENT = "FOR_EVENT",
  SINGLE_FILE_FOR_DAY = "SINGLE_FILE_FOR_DAY"
}

export enum LogExtension {
  TXT = "txt",
  CSV = "csv",
  LOG = "log",
  NONE = ""
}

export enum LogLevel {
  INFO = "INFO",
  WARNING = "WARNING",
  ERROR = "ERROR",
  SEVERE = "SEVERE"
}

export enum ExportType {
  TODAY = "TODAY",
  LAST_HOUR = "LAST_HOUR",
  WEEKS = "WEEKS",
  LAST_24_HOURS = "LAST_24_HOURS",
  ALL = "ALL"
}

export enum TimeStampFormat {
  DATE_FORMAT_1 = "yyyy-MM-dd",
  DATE_FORMAT_2 = "dd-MM-yyyy",
  TIME_FORMAT_FULL_JOINED = "yyyyMMddHHmmss",
  TIME_FORMAT_FULL_1 = "yyyy-MM-dd HH:mm:ss",
  TIME_FORMAT_FULL_2 = "dd-MM-yyyy HH:mm:ss",
  TIME_FORMAT_24_FULL = "HH:mm:ss",
  TIME_FORMAT_READABLE = "MMM dd, yyyy HH:mm:ss",
  TIME_FORMAT_READABLE_2 = "dd MMM, yyyy HH:mm:ss",
  TIME_FORMAT_SIMPLE = "HH:mm"
}
