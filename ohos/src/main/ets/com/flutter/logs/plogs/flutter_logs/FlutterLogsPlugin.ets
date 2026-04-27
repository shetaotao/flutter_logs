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

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  EventChannel,
  StreamHandler,
} from '@ohos/flutter_ohos';
import { LogsHelperEnhanced } from './LogsHelperEnhanced';
import {
  getBoolValueById,
  getIntValueById,
  getStringValueById,
  getListOfStringById,
  getLogLevelsById,
  getInputStreamValueById,
  getDirectoryStructure,
  getTimeStampFormat,
  getLogFileExtension,
  getLogLevel,
  getExportType,
  DirectoryStructure,
  TimeStampFormat,
  LogExtension,
  LogLevel,
  ExportType
} from './Utils';
import { fileIo } from '@kit.CoreFileKit';
import { socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

// ============== Socket 消息接口 ==============

interface SocketMessage {
  message: ArrayBuffer;
}

/**
 * FlutterLogsPlugin - OpenHarmony 实现
 * 日志插件主类，处理 Flutter 与原生之间的 MethodChannel 通信
 * 
 * 功能实现状态：
 * ✅ initLogs - 日志配置初始化（支持加密、自动清理、崩溃捕获）
 * ✅ logThis - 写入日志（支持控制台+文件）
 * ✅ logToFile - 写入指定文件
 * ✅ setMetaInfo - ELK 元数据配置（自动获取电池信息）
 * ✅ initMQTT - MQTT 配置（支持 TLS 加密连接）
 * ✅ exportLogs - 导出日志为 ZIP（使用 zlib）
 * ✅ printLogs - 打印日志内容
 * ✅ exportFileLogForName - 导出指定文件
 * ✅ exportAllFileLogs - 导出所有文件
 * ✅ printFileLogForName - 打印指定文件
 * ✅ clearLogs - 清空日志
 * ✅ 日志文件自动分割 - 超过大小自动创建新文件
 * ✅ 崩溃捕获 - 使用 hiAppEvent 监听 JsError/NativeCrash
 * ✅ 标准 AES-128-CBC 加密 - 使用 CryptoArchitectureKit
 * ✅ 电池信息获取 - 使用 batteryInfo API
 * 
 * 参考文档：
 * - 文件操作：https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-core-file-kit-V5
 * - 压缩归档：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/deflate-and-inflate
 * - 加密算法：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/crypto-aes-sym-encrypt-decrypt-cbc
 * - 网络通信：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/socket-connection
 * - 崩溃捕获：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hiappevent-watcher-crash-events-arkts
 * - 电池信息：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-batteryinfo
 */
export default class FlutterLogsPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private static TAG = "FlutterLogsPlugin";
  
  // MQTT 相关 - 支持 TLS 加密连接
  private mqttSocket: socket.TLSSocket | socket.TCPSocket | null = null;
  private mqttConnected: boolean = false;
  private mqttUseTLS: boolean = false;

  constructor() {
  }

  getUniqueClassName(): string {
    return "FlutterLogsPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "flutter_logs");
    this.channel.setMethodCallHandler(this)

    // EventChannel 用于流事件（日志导出/打印回调）
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), "flutter_logs_plugin_stream");
    const streamHandler: StreamHandler = {
      onListen: (args: object | null, events: object | null) => {
        // 如需使用事件流，可在此设置事件接收器
      },
      onCancel: (args: object | null) => {
        // 如需清理资源，可在此处理
      }
    };
    this.eventChannel.setStreamHandler(streamHandler);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
    if (this.eventChannel != null) {
      this.eventChannel.setStreamHandler(null);
    }
    // 断开 MQTT 连接
    this.disconnectMQTT();
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case "initLogs":
        await this.handleInitLogs(call, result);
        break;
      case "initMQTT":
        await this.handleInitMQTT(call, result);
        break;
      case "setMetaInfo":
        this.handleSetMetaInfo(call, result);
        break;
      case "logThis":
        await this.handleLogThis(call, result);
        break;
      case "logToFile":
        await this.handleLogToFile(call, result);
        break;
      case "exportLogs":
        await this.handleExportLogs(call, result);
        break;
      case "printLogs":
        await this.handlePrintLogs(call, result);
        break;
      case "exportFileLogForName":
        await this.handleExportFileLogForName(call, result);
        break;
      case "exportAllFileLogs":
        await this.handleExportAllFileLogs(call, result);
        break;
      case "printFileLogForName":
        await this.handlePrintFileLogForName(call, result);
        break;
      case "clearLogs":
        await this.handleClearLogs(call, result);
        break;
      default:
        result.notImplemented();
    }
  }

  // ==================== 日志初始化 ====================
  
  private async handleInitLogs(call: MethodCall, result: MethodResult): Promise<void> {
    console.info(FlutterLogsPlugin.TAG, `handleInitLogs: 开始初始化日志配置`);
    
    const logLevelsEnabled = getLogLevelsById("logLevelsEnabled", call);
    const logTypesEnabled = getListOfStringById("logTypesEnabled", call);
    const logsRetentionPeriodInDays = getIntValueById("logsRetentionPeriodInDays", call);
    const zipsRetentionPeriodInDays = getIntValueById("zipsRetentionPeriodInDays", call);
    const autoDeleteZipOnExport = getBoolValueById("autoDeleteZipOnExport", call);
    const autoClearLogs = getBoolValueById("autoClearLogs", call);
    const autoExportErrors = getBoolValueById("autoExportErrors", call);
    const encryptionEnabled = getBoolValueById("encryptionEnabled", call);
    const encryptionKey = getStringValueById("encryptionKey", call);
    const directoryStructureStr = getStringValueById("directoryStructure", call);
    const logSystemCrashes = getBoolValueById("logSystemCrashes", call);
    const isDebuggable = getBoolValueById("isDebuggable", call);
    const debugFileOperations = getBoolValueById("debugFileOperations", call);
    const attachTimeStamp = getBoolValueById("attachTimeStamp", call);
    const attachNoOfFiles = getBoolValueById("attachNoOfFiles", call);
    const timeStampFormatStr = getStringValueById("timeStampFormat", call);
    const logFileExtensionStr = getStringValueById("logFileExtension", call);
    const zipFilesOnly = getBoolValueById("zipFilesOnly", call);
    const savePath = getStringValueById("savePath", call);
    const zipFileName = getStringValueById("zipFileName", call);
    const exportPath = getStringValueById("exportPath", call);
    const singleLogFileSize = getIntValueById("singleLogFileSize", call);
    const enabled = getBoolValueById("enabled", call);

    console.info(FlutterLogsPlugin.TAG, `handleInitLogs: savePath=${savePath}, exportPath=${exportPath}`);

    const directoryStructure = getDirectoryStructure(directoryStructureStr || null);
    const timeStampFormat = getTimeStampFormat(timeStampFormatStr || null);
    const logFileExtension = getLogFileExtension(logFileExtensionStr || null);

    // 使用增强版日志辅助类
    console.info(FlutterLogsPlugin.TAG, `handleInitLogs: 调用 LogsHelperEnhanced.setUpLogger`);
    await LogsHelperEnhanced.setUpLogger(
      logLevelsEnabled,
      logTypesEnabled,
      logsRetentionPeriodInDays,
      zipsRetentionPeriodInDays,
      autoDeleteZipOnExport,
      autoClearLogs,
      autoExportErrors,
      encryptionEnabled,
      encryptionKey,
      directoryStructure,
      logSystemCrashes,
      isDebuggable,
      debugFileOperations,
      attachTimeStamp,
      attachNoOfFiles,
      timeStampFormat,
      logFileExtension,
      zipFilesOnly,
      savePath,
      zipFileName,
      exportPath,
      singleLogFileSize,
      enabled
    );

    result.success("Logs Configuration added.");
  }

  // ==================== MQTT 连接 (支持 TLS) ====================
  
  private async handleInitMQTT(call: MethodCall, result: MethodResult): Promise<void> {
    const topic = getStringValueById("topic", call);
    const brokerUrl = getStringValueById("brokerUrl", call);
    const certificate = getInputStreamValueById("certificate", call);
    const clientId = getStringValueById("clientId", call);
    const port = getStringValueById("port", call);
    const qos = getIntValueById("qos", call);
    const retained = getBoolValueById("retained", call);
    const writeLogsToLocalStorage = getBoolValueById("writeLogsToLocalStorage", call);
    const debug = getBoolValueById("debug", call);
    const initialDelaySecondsForPublishing = getIntValueById("initialDelaySecondsForPublishing", call);

    if (!brokerUrl || brokerUrl.length === 0) {
      result.error(FlutterLogsPlugin.TAG, "MQTT Broker URL 不能为空", null);
      return;
    }

    try {
      // 先断开之前的连接
      this.disconnectMQTT();

      // 解析端口（默认 1883，有证书时使用 8883）
      const hasCertificate = !!(certificate && certificate.length > 0);
      const defaultPort = hasCertificate ? 8883 : 1883;
      const brokerPort = port ? parseInt(port, 10) : defaultPort;

      // 判断是否使用 TLS：只有有证书时才使用 TLS
      this.mqttUseTLS = hasCertificate;

      if (this.mqttUseTLS) {
        // 使用 TLS Socket 进行加密连接
        await this.connectMQTTWithTLS(brokerUrl, brokerPort, certificate, clientId, debug);
      } else {
        // 使用普通 TCP Socket
        await this.connectMQTTWithTCP(brokerUrl, brokerPort, clientId, debug);
      }

      this.mqttConnected = true;

      // 保存配置供后续使用
      AppStorage.setOrCreate('mqttConfig', {
        topic: topic || "",
        brokerUrl: brokerUrl,
        clientId: clientId || "",
        port: brokerPort,
        qos: qos || 0,
        retained: retained || false,
        writeLogsToLocalStorage: writeLogsToLocalStorage ?? true,
        debug: debug ?? true,
        useTLS: this.mqttUseTLS
      });

      // 延迟发布初始消息
      if (initialDelaySecondsForPublishing && initialDelaySecondsForPublishing > 0) {
        setTimeout(() => {
          this.publishMQTTMessage("flutter_logs/connected", "Client connected", qos || 0, retained || false);
        }, initialDelaySecondsForPublishing * 1000);
      }

      result.success("MQTT setup added.");
    } catch (e) {
      console.error(FlutterLogsPlugin.TAG, `MQTT 连接失败: ${e}`);
      result.error(FlutterLogsPlugin.TAG, `MQTT 连接失败: ${e}`, null);
    }
  }

  /**
   * 使用 TLS 连接 MQTT Broker
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/socket-connection
   */
  private async connectMQTTWithTLS(
    brokerUrl: string, 
    brokerPort: number, 
    certificate: Uint8Array | null,
    clientId: string,
    debug: boolean
  ): Promise<void> {
    // 创建 TLS Socket 实例
    const tlsSocket: socket.TLSSocket = socket.constructTLSSocketInstance();
    this.mqttSocket = tlsSocket;

    // 绑定本地地址
    await new Promise<void>((resolve, reject) => {
      tlsSocket.bind({
        address: '0.0.0.0',
        port: 0
      }, (err: BusinessError) => {
        if (err) {
          reject(new Error(`TLS bind失败: ${err.message}`));
        } else {
          resolve();
        }
      });
    });

    // 配置 TLS 安全选项
    let caCertArray: Array<string> | undefined = undefined;
    if (certificate && certificate.length > 0) {
      // 将证书转换为字符串 (ArkTS 不支持 Function.apply，使用循环)
      let certStr = "";
      for (let i = 0; i < certificate.length; i++) {
        certStr += String.fromCharCode(certificate[i]);
      }
      caCertArray = [certStr];
    }
    
    const tlsSecureOptions: socket.TLSSecureOptions = {
      ca: caCertArray,
      protocols: [socket.Protocol.TLSv12, socket.Protocol.TLSv13],
      useRemoteCipherPrefer: true,
      cipherSuite: "AES256-SHA256:AES128-SHA256"
    };

    // 配置连接选项
    const tlsConnectOptions: socket.TLSConnectOptions = {
      address: {
        address: brokerUrl,
        port: brokerPort
      },
      secureOptions: tlsSecureOptions
    };

    // 设置消息接收回调
    tlsSocket.on('message', (value: SocketMessage) => {
      const message = this.bufferToString(value.message);
      if (debug) {
        console.info(FlutterLogsPlugin.TAG, `MQTT TLS 收到消息: ${message}`);
      }
    });

    tlsSocket.on('connect', () => {
      if (debug) {
        console.info(FlutterLogsPlugin.TAG, `MQTT TLS 已连接到 ${brokerUrl}:${brokerPort}`);
      }
    });

    tlsSocket.on('close', () => {
      if (debug) {
        console.info(FlutterLogsPlugin.TAG, "MQTT TLS 连接已关闭");
      }
      this.mqttConnected = false;
    });

    // 建立 TLS 连接
    await tlsSocket.connect(tlsConnectOptions);

    // 发送 MQTT CONNECT 报文
    const connectPacket = this.buildMQTTConnectPacket(clientId || "flutter_logs_client");
    await tlsSocket.send(connectPacket);
  }

  /**
   * 使用普通 TCP 连接 MQTT Broker
   */
  private async connectMQTTWithTCP(
    brokerUrl: string, 
    brokerPort: number, 
    clientId: string,
    debug: boolean
  ): Promise<void> {
    // 创建普通 TCP Socket
    const tcpSocket: socket.TCPSocket = socket.constructTCPSocketInstance();
    this.mqttSocket = tcpSocket;
    
    // 绑定本地地址
    const bindAddress: socket.NetAddress = {
      address: '0.0.0.0',
      port: 0
    };
    tcpSocket.bind(bindAddress);

    // 连接到 MQTT Broker
    const connectAddress: socket.NetAddress = {
      address: brokerUrl,
      port: brokerPort
    };
    const tcpConnectOptions: socket.TCPConnectOptions = {
      address: connectAddress,
      timeout: 10000
    };
    await tcpSocket.connect(tcpConnectOptions);

    if (debug) {
      console.info(FlutterLogsPlugin.TAG, `MQTT TCP 已连接到 ${brokerUrl}:${brokerPort}`);
    }

    // 设置消息接收回调
    tcpSocket.on('message', (value: SocketMessage) => {
      const message = this.bufferToString(value.message);
      if (debug) {
        console.info(FlutterLogsPlugin.TAG, `MQTT TCP 收到消息: ${message}`);
      }
    });

    // 发送 MQTT CONNECT 报文
    const connectPacket = this.buildMQTTConnectPacket(clientId || "flutter_logs_client");
    const tcpSendOptions: socket.TCPSendOptions = {
      data: connectPacket,
      encoding: 'buffer'
    };
    tcpSocket.send(tcpSendOptions);
  }

  /**
   * 发送 MQTT 数据（兼容 TLS 和 TCP Socket）
   */
  private sendMQTTData(data: Uint8Array): void {
    if (!this.mqttSocket) {
      return;
    }
    
    if (this.mqttUseTLS) {
      // TLS Socket 直接发送 ArrayBuffer
      const tlsSocket = this.mqttSocket as socket.TLSSocket;
      tlsSocket.send(data.buffer as ArrayBuffer);
    } else {
      // TCP Socket 需要包装成对象
      const tcpSocket = this.mqttSocket as socket.TCPSocket;
      const sendOptions: socket.TCPSendOptions = {
        data: data.buffer as ArrayBuffer,
        encoding: 'buffer'
      };
      tcpSocket.send(sendOptions);
    }
  }

  /**
   * 断开 MQTT 连接
   */
  private disconnectMQTT(): void {
    if (this.mqttSocket && this.mqttConnected) {
      try {
        // 发送 MQTT DISCONNECT 报文
        const disconnectPacket = new Uint8Array([0xE0, 0x00]); // DISCONNECT 报文
        this.sendMQTTData(disconnectPacket);
        
        // 关闭 Socket
        if (this.mqttUseTLS) {
          const tlsSocket = this.mqttSocket as socket.TLSSocket;
          tlsSocket.close((err: BusinessError) => {
            if (err) {
              console.error(FlutterLogsPlugin.TAG, `关闭 MQTT TLS 连接失败: ${err.message}`);
            }
          });
        } else {
          const tcpSocket = this.mqttSocket as socket.TCPSocket;
          tcpSocket.close();
        }
      } catch (e) {
        // 忽略关闭错误
      }
    }
    this.mqttSocket = null;
    this.mqttConnected = false;
    this.mqttUseTLS = false;
  }

  /**
   * 发布 MQTT 消息
   */
  private publishMQTTMessage(topic: string, message: string, qos: number, retained: boolean): void {
    if (!this.mqttSocket || !this.mqttConnected) {
      console.warn(FlutterLogsPlugin.TAG, "MQTT 未连接，无法发布消息");
      return;
    }

    try {
      // 构建 MQTT PUBLISH 报文（简化版 QoS 0）
      const topicBytes: Uint8Array = new Uint8Array(this.stringToBuffer(topic));
      const messageBytes: Uint8Array = new Uint8Array(this.stringToBuffer(message));
      
      // 计算报文长度
      const remainingLength = 2 + topicBytes.length + messageBytes.length;
      
      // 构建报文头
      const header = new Uint8Array([
        0x30 | (qos << 1) | (retained ? 0x01 : 0x00), // PUBLISH 报文类型 + 标志位
        remainingLength
      ]);
      
      // 合并报文
      const packet = new Uint8Array(header.length + remainingLength);
      packet.set(header, 0);
      packet.set(topicBytes, header.length);
      packet.set(messageBytes, header.length + 2 + topicBytes.length);

      this.sendMQTTData(packet);
    } catch (e) {
      console.error(FlutterLogsPlugin.TAG, `MQTT 发布消息失败: ${e}`);
    }
  }

  /**
   * 构建 MQTT CONNECT 报文
   */
  private buildMQTTConnectPacket(clientId: string): Uint8Array {
    const clientIdBytes: Uint8Array = new Uint8Array(this.stringToBuffer(clientId));
    const protocolName: Uint8Array = new Uint8Array(this.stringToBuffer("MQTT"));
    
    // CONNECT 报文可变头
    const variableHeader = new Uint8Array([
      0x00, 0x04, // 协议名长度
      ...protocolName,
      0x04, // 协议级别（MQTT 3.1.1）
      0x02, // 连接标志（Clean Session）
      0x00, 0x3C, // Keep Alive（60秒）
    ]);
    
    // 有效载荷（Client ID）
    const payload = new Uint8Array([
      0x00, clientIdBytes.length,
      ...clientIdBytes
    ]);
    
    // 计算剩余长度
    const remainingLength = variableHeader.length + payload.length;
    
    // 固定头
    const fixedHeader = new Uint8Array([0x10, remainingLength]);
    
    // 合并报文
    const packet = new Uint8Array(fixedHeader.length + remainingLength);
    packet.set(fixedHeader, 0);
    packet.set(variableHeader, fixedHeader.length);
    packet.set(payload, fixedHeader.length + variableHeader.length);
    
    return packet;
  }

  /**
   * 将字符串转换为 ArrayBuffer
   */
  private stringToBuffer(str: string): ArrayBuffer {
    const arrayBuffer = new ArrayBuffer(str.length);
    const view = new Uint8Array(arrayBuffer);
    for (let i = 0; i < str.length; i++) {
      view[i] = str.charCodeAt(i) & 0xFF;
    }
    return arrayBuffer;
  }

  /**
   * 将 ArrayBuffer 转换为字符串
   */
  private bufferToString(arrayBuffer: ArrayBuffer): string {
    const view = new Uint8Array(arrayBuffer);
    let str = "";
    for (let i = 0; i < view.length; i++) {
      str += String.fromCharCode(view[i]);
    }
    return str;
  }

  // ==================== 元数据配置 ====================
  
  private handleSetMetaInfo(call: MethodCall, result: MethodResult): void {
    const appId = getStringValueById("appId", call);
    const appName = getStringValueById("appName", call);
    const appVersion = getStringValueById("appVersion", call);
    const language = getStringValueById("language", call);
    const deviceId = getStringValueById("deviceId", call);
    const environmentId = getStringValueById("environmentId", call);
    const environmentName = getStringValueById("environmentName", call);
    const organizationId = getStringValueById("organizationId", call);
    const organizationUnitId = getStringValueById("organizationUnitId", call);
    const userId = getStringValueById("userId", call);
    const userName = getStringValueById("userName", call);
    const userEmail = getStringValueById("userEmail", call);
    const deviceSerial = getStringValueById("deviceSerial", call);
    const deviceBrand = getStringValueById("deviceBrand", call);
    const deviceName = getStringValueById("deviceName", call);
    const deviceManufacturer = getStringValueById("deviceManufacturer", call);
    const deviceModel = getStringValueById("deviceModel", call);
    const deviceSdkInt = getStringValueById("deviceSdkInt", call);
    const deviceBatteryPercent = getStringValueById("deviceBatteryPercent", call);
    const latitude = getStringValueById("latitude", call);
    const longitude = getStringValueById("longitude", call);

    LogsHelperEnhanced.setupForELKStack(
      appId,
      appName,
      appVersion,
      deviceId,
      environmentId,
      environmentName,
      organizationId,
      organizationUnitId,
      language,
      userId,
      userName,
      userEmail,
      deviceSerial,
      deviceBrand,
      deviceName,
      deviceManufacturer,
      deviceModel,
      deviceSdkInt,
      deviceBatteryPercent,
      latitude,
      longitude
    );

    result.success("Logs MetaInfo added for ELK stack.");
  }

  // ==================== 日志写入 ====================
  
  private async handleLogThis(call: MethodCall, result: MethodResult): Promise<void> {
    const tag = getStringValueById("tag", call);
    const subTag = getStringValueById("subTag", call);
    const logMessage = getStringValueById("logMessage", call);
    const level = getStringValueById("level", call);
    const exception = getStringValueById("e", call);

    const logLevel = getLogLevel(level || null);

    // 根据日志级别输出到控制台
    const logData = exception.length > 0
      ? `[${tag}][${subTag}] ${logMessage} - Exception: ${exception}`
      : `[${tag}][${subTag}] ${logMessage}`;

    switch (logLevel) {
      case LogLevel.INFO:
        console.info(FlutterLogsPlugin.TAG, logData);
        break;
      case LogLevel.WARNING:
        console.warn(FlutterLogsPlugin.TAG, logData);
        break;
      case LogLevel.ERROR:
      case LogLevel.SEVERE:
        console.error(FlutterLogsPlugin.TAG, logData);
        break;
    }

    // 同时写入文件日志 (异步)
    await LogsHelperEnhanced.writeLogToFile(tag, logData, false);

  }

  private async handleLogToFile(call: MethodCall, result: MethodResult): Promise<void> {
    const logFileName = getStringValueById("logFileName", call);
    const overwrite = getBoolValueById("overwrite", call);
    const logMessage = getStringValueById("logMessage", call);
    const appendTimeStamp = getBoolValueById("appendTimeStamp", call);

    if (logFileName.length === 0) {
      result.error(FlutterLogsPlugin.TAG, "logFileName 不能为空", null);
      return;
    }

    if (overwrite) {
      await LogsHelperEnhanced.overWriteLogToFile(logFileName, logMessage, appendTimeStamp);
    } else {
      await LogsHelperEnhanced.writeLogToFile(logFileName, logMessage, appendTimeStamp);
    }

    result.success("");
  }

  // ==================== 日志导出 ====================
  
  private async handleExportLogs(call: MethodCall, result: MethodResult): Promise<void> {
    const exportTypeStr = getStringValueById("exportType", call);
    const decryptBeforeExporting = getBoolValueById("decryptBeforeExporting", call);

    const exportType = getExportType(exportTypeStr || null);

    try {
      const exportPath = await LogsHelperEnhanced.exportLogsToZip(exportType, decryptBeforeExporting);
      
      // 通过 MethodChannel 回调通知
      this.channel?.invokeMethod("logsExported", exportPath);
    } catch (e) {
      result.error(FlutterLogsPlugin.TAG, `导出日志失败: ${e}`, null);
    }
  }

  private async handleExportFileLogForName(call: MethodCall, result: MethodResult): Promise<void> {
    const logFileName = getStringValueById("logFileName", call);
    const decryptBeforeExporting = getBoolValueById("decryptBeforeExporting", call);

    if (logFileName.length === 0) {
      result.error(FlutterLogsPlugin.TAG, "logFileName 不能为空", null);
      return;
    }

    try {
      // 使用 LogsHelperEnhanced 导出指定文件
      const exportPath = await LogsHelperEnhanced.exportFileLogForName(logFileName, decryptBeforeExporting);

      this.channel?.invokeMethod("logsExported", exportPath);
    } catch (e) {
      result.error(FlutterLogsPlugin.TAG, `导出文件失败: ${e}`, null);
    }
  }

  private async handleExportAllFileLogs(call: MethodCall, result: MethodResult): Promise<void> {
    const decryptBeforeExporting = getBoolValueById("decryptBeforeExporting", call);

    try {
      const exportPath = await LogsHelperEnhanced.exportLogsToZip(ExportType.ALL, decryptBeforeExporting);
      
      this.channel?.invokeMethod("logsExported", exportPath);
    } catch (e) {
      result.error(FlutterLogsPlugin.TAG, `导出所有日志失败: ${e}`, null);
    }
  }

  // ==================== 日志打印 ====================
  
  private async handlePrintLogs(call: MethodCall, result: MethodResult): Promise<void> {
    const exportTypeStr = getStringValueById("exportType", call);
    const decryptBeforeExporting = getBoolValueById("decryptBeforeExporting", call);

    const exportType = getExportType(exportTypeStr || null);

    try {
      const logsContent = await LogsHelperEnhanced.printLogs(exportType, decryptBeforeExporting);
      
      // 通过 MethodChannel 回调通知
      this.channel?.invokeMethod("logsPrinted", logsContent);
    } catch (e) {
      result.error(FlutterLogsPlugin.TAG, `打印日志失败: ${e}`, null);
    }
  }

  private async handlePrintFileLogForName(call: MethodCall, result: MethodResult): Promise<void> {
    const logFileName = getStringValueById("logFileName", call);
    const decryptBeforeExporting = getBoolValueById("decryptBeforeExporting", call);

    if (logFileName.length === 0) {
      result.error(FlutterLogsPlugin.TAG, "logFileName 不能为空", null);
      return;
    }

    try {
      // 使用 LogsHelperEnhanced 查找并读取匹配的日志文件
      console.info(FlutterLogsPlugin.TAG, `打印文件日志: logFileName=${logFileName}`);
      const content = await LogsHelperEnhanced.printFileLogsForName(logFileName, decryptBeforeExporting);
      
      // 添加结束标记
      const contentWithEnd = content + ".......................................End";
      
      // 通过 MethodChannel 回调通知
      this.channel?.invokeMethod("logsPrinted", contentWithEnd);
    } catch (e) {
      console.error(FlutterLogsPlugin.TAG, `打印文件失败: ${e}`);
      result.error(FlutterLogsPlugin.TAG, `打印文件失败: ${e}`, null);
    }
  }

  // ==================== 日志清理 ====================

  private async handleClearLogs(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const success = await LogsHelperEnhanced.clearAllLogs();

      if (success) {
        console.info(FlutterLogsPlugin.TAG, `日志已清空`);
        result.success("日志已清空");
      } else {
        result.error(FlutterLogsPlugin.TAG, "清空日志失败", null);
      }
    } catch (e) {
      result.error(FlutterLogsPlugin.TAG, `清空日志失败: ${e}`, null);
    }
  }
}
