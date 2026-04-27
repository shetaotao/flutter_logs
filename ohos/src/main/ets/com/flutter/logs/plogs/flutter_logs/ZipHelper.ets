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
import { zlib } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import util from '@ohos.util';

/**
 * ZIP 文件格式帮助类
 * 实现多文件 ZIP 压缩和解压功能
 * 参考 ZIP 文件格式规范：https://en.wikipedia.org/wiki/ZIP_(file_format)
 */
export class ZipHelper {
  private static TAG = "ZipHelper";

  /**
   * 创建多文件 ZIP 压缩包
   * 使用 HarmonyOS zlib.compressFile 接口压缩文件夹
   * @param files 文件列表，每个文件包含路径和名称
   * @param outputPath 输出 ZIP 文件路径
   * @returns 是否成功
   */
  static async createZip(files: Array<ZipFileInfo>, outputPath: string): Promise<boolean> {
    try {
      console.info(ZipHelper.TAG, `开始创建 ZIP 文件: ${outputPath}, 文件数: ${files.length}`);

      if (files.length === 0) {
        console.warn(ZipHelper.TAG, `文件列表为空，无法创建 ZIP`);
        return false;
      }

      // 确保输出目录存在
      const outputDir = outputPath.substring(0, outputPath.lastIndexOf('/'));
      console.info(ZipHelper.TAG, `确保输出目录存在: ${outputDir}`);
      ZipHelper.ensureDirectoryExists(outputDir);
      console.info(ZipHelper.TAG, `输出目录已确保存在: ${outputDir}`);

      // 创建临时文件夹用于存放要压缩的文件
      const tempDir = outputDir + '/.temp_zip_' + Date.now();
      console.info(ZipHelper.TAG, `创建临时文件夹: ${tempDir}`);
      ZipHelper.ensureDirectoryExists(tempDir);

      try {
        // 将所有文件复制到临时文件夹
        let copiedCount = 0;
        for (const file of files) {
          try {
            // 检查源文件是否存在
            fileIo.accessSync(file.path);
            console.info(ZipHelper.TAG, `源文件存在: ${file.path}`);

            // 复制文件到临时文件夹
            const destPath = tempDir + '/' + file.name;
            fileIo.copyFileSync(file.path, destPath);
            console.info(ZipHelper.TAG, `文件已复制到临时文件夹: ${destPath}`);
            copiedCount++;
          } catch (e) {
            console.error(ZipHelper.TAG, `复制文件失败 ${file.path}: ${e}`);
            // 继续处理其他文件
          }
        }

        if (copiedCount === 0) {
          console.error(ZipHelper.TAG, `没有成功复制任何文件到临时文件夹`);
          return false;
        }

        console.info(ZipHelper.TAG, `成功复制 ${copiedCount} 个文件到临时文件夹`);

        // 使用 zlib.compressFile 压缩临时文件夹
        console.info(ZipHelper.TAG, `开始压缩临时文件夹: ${tempDir} -> ${outputPath}`);

        const options: zlib.Options = {
          level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
          memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
          strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
        };

        await zlib.compressFile(tempDir, outputPath, options);
        console.info(ZipHelper.TAG, `ZIP 文件创建成功: ${outputPath}`);
        return true;
      } finally {
        // 清理临时文件夹
        try {
          fileIo.rmdirSync(tempDir);
          console.info(ZipHelper.TAG, `临时文件夹已清理: ${tempDir}`);
        } catch (e) {
          console.warn(ZipHelper.TAG, `清理临时文件夹失败: ${e}`);
        }
      }
    } catch (e) {
      console.error(ZipHelper.TAG, `创建 ZIP 文件失败: ${e}`);
      return false;
    }
  }

  /**
   * 解压 ZIP 文件
   * @param zipPath ZIP 文件路径
   * @param outputDir 输出目录
   * @returns 解压的文件列表
   */
  static async extractZip(zipPath: string, outputDir: string): Promise<Array<string>> {
    const extractedFiles: Array<string> = [];

    try {
      console.info(ZipHelper.TAG, `开始解压 ZIP 文件: ${zipPath}`);

      // 确保输出目录存在
      await ZipHelper.ensureDirectoryExists(outputDir);

      // 打开 ZIP 文件
      const zipFile = await fileIo.open(zipPath, fileIo.OpenMode.READ_ONLY);

      try {
        // 读取中央目录结束标记
        const eocd = await ZipHelper.readEndOfCentralDirectory(zipFile);
        console.info(ZipHelper.TAG, `ZIP 文件包含 ${eocd.totalEntries} 个文件`);

        // 读取中央目录
        const entries = await ZipHelper.readCentralDirectory(zipFile, eocd);

        // 解压每个文件
        for (const entry of entries) {
          try {
            const outputPath = `${outputDir}/${entry.fileName}`;
            await ZipHelper.extractFile(zipFile, entry, outputPath);
            extractedFiles.push(outputPath);
            console.info(ZipHelper.TAG, `已解压文件: ${entry.fileName}`);
          } catch (e) {
            console.error(ZipHelper.TAG, `解压文件失败 ${entry.fileName}: ${e}`);
          }
        }
      } finally {
        await fileIo.close(zipFile);
      }

      console.info(ZipHelper.TAG, `ZIP 解压完成，共 ${extractedFiles.length} 个文件`);
      return extractedFiles;
    } catch (e) {
      console.error(ZipHelper.TAG, `解压 ZIP 文件失败: ${e}`);
      return extractedFiles;
    }
  }

  /**
   * 写入本地文件头 + 压缩数据
   */
  private static async writeLocalFile(outputFile: fileIo.File, file: ZipFileInfo, currentOffset: number): Promise<ZipEntry> {
    // 检查源文件是否存在
    try {
      fileIo.accessSync(file.path);
      console.info(ZipHelper.TAG, `源文件检查通过: ${file.path}`);
    } catch (e) {
      console.error(ZipHelper.TAG, `源文件不存在: ${file.path}`);
      throw new Error(`源文件不存在: ${file.path}`);
    }
    
    // 读取源文件
    console.info(ZipHelper.TAG, `打开源文件: ${file.path}`);
    let srcFile: fileIo.File;
    try {
      srcFile = fileIo.openSync(file.path, fileIo.OpenMode.READ_ONLY);
      console.info(ZipHelper.TAG, `源文件已打开: ${file.path}`);
    } catch (e) {
      console.error(ZipHelper.TAG, `打开源文件失败: ${file.path}, 错误: ${e}`);
      throw new Error(`打开源文件失败: ${file.path}, 错误: ${e}`);
    }
    
    const stat = fileIo.statSync(file.path);
    console.info(ZipHelper.TAG, `源文件大小: ${stat.size}`);
    const fileData = new ArrayBuffer(stat.size);
    const readBytes = fileIo.readSync(srcFile.fd, fileData);
    console.info(ZipHelper.TAG, `源文件读取完成: ${readBytes} bytes`);
    if (readBytes !== stat.size) {
      console.error(ZipHelper.TAG, `源文件读取不完整: ${readBytes} != ${stat.size}`);
    }
    fileIo.closeSync(srcFile);

    // 压缩数据
    const compressedData = await ZipHelper.compressData(fileData);
    const isCompressed = compressedData.byteLength < fileData.byteLength;
    const finalData = isCompressed ? compressedData : fileData;

    // 构建本地文件头
    const fileNameBytes = ZipHelper.stringToBytes(file.name);
    const localHeader = ZipHelper.buildLocalFileHeader(
      fileNameBytes,
      finalData.byteLength,
      fileData.byteLength,
      isCompressed
    );

    // 写入本地文件头
    const headerWritten = fileIo.writeSync(outputFile.fd, localHeader);
    console.info(ZipHelper.TAG, `本地文件头已写入: ${headerWritten} bytes, 预期: ${localHeader.byteLength} bytes`);
    if (headerWritten !== localHeader.byteLength) {
      console.error(ZipHelper.TAG, `本地文件头写入不完整: ${headerWritten} != ${localHeader.byteLength}`);
    }

    // 写入压缩数据
    const dataWritten = fileIo.writeSync(outputFile.fd, finalData);
    console.info(ZipHelper.TAG, `压缩数据已写入: ${dataWritten} bytes, 预期: ${finalData.byteLength} bytes`);
    if (dataWritten !== finalData.byteLength) {
      console.error(ZipHelper.TAG, `压缩数据写入不完整: ${dataWritten} != ${finalData.byteLength}`);
    }

    return {
      fileName: file.name,
      fileNameBytes: fileNameBytes,
      compressedSize: finalData.byteLength,
      uncompressedSize: fileData.byteLength,
      isCompressed: isCompressed,
      localHeaderSize: localHeader.byteLength,
      crc32: 0
    };
  }

  /**
   * 构建本地文件头 (Local File Header)
   */
  private static buildLocalFileHeader(
    fileNameBytes: Uint8Array,
    compressedSize: number,
    uncompressedSize: number,
    isCompressed: boolean
  ): ArrayBuffer {
    const headerSize = 30 + fileNameBytes.length;
    const header = new ArrayBuffer(headerSize);
    const view = new DataView(header);
    let offset = 0;

    // 本地文件头签名 (4 bytes)
    view.setUint32(offset, 0x04034b50, true);
    offset += 4;

    // 版本号 (2 bytes)
    view.setUint16(offset, 20, true);
    offset += 2;

    // 通用位标志 (2 bytes)
    view.setUint16(offset, 0, true);
    offset += 2;

    // 压缩方法 (2 bytes) - 0 = 存储, 8 = DEFLATE
    view.setUint16(offset, isCompressed ? 8 : 0, true);
    offset += 2;

    // 文件修改时间 (2 bytes)
    view.setUint16(offset, 0, true);
    offset += 2;

    // 文件修改日期 (2 bytes)
    view.setUint16(offset, 0, true);
    offset += 2;

    // CRC-32 (4 bytes) - 简化实现设为 0
    view.setUint32(offset, 0, true);
    offset += 4;

    // 压缩后大小 (4 bytes)
    view.setUint32(offset, compressedSize, true);
    offset += 4;

    // 未压缩大小 (4 bytes)
    view.setUint32(offset, uncompressedSize, true);
    offset += 4;

    // 文件名长度 (2 bytes)
    view.setUint16(offset, fileNameBytes.length, true);
    offset += 2;

    // 扩展字段长度 (2 bytes)
    view.setUint16(offset, 0, true);
    offset += 2;

    // 文件名
    const headerBytes = new Uint8Array(header);
    headerBytes.set(fileNameBytes, offset);

    return header;
  }

  /**
   * 写入中央目录
   */
  private static writeCentralDirectory(
    outputFile: fileIo.File,
    entries: Array<ZipEntry>,
    offset: number
  ): number {
    let totalSize = 0;
    let currentOffset = 0;  // 相对于文件起始位置的偏移量（用于记录每个本地文件头的位置）

    for (const entry of entries) {
      const cdHeader = ZipHelper.buildCentralDirectoryHeader(entry, currentOffset);
      const written = fileIo.writeSync(outputFile.fd, cdHeader);
      console.info(ZipHelper.TAG, `中央目录头已写入: ${written} bytes, 预期: ${cdHeader.byteLength} bytes, 本地文件头偏移: ${currentOffset}`);
      if (written !== cdHeader.byteLength) {
        console.error(ZipHelper.TAG, `中央目录头写入不完整: ${written} != ${cdHeader.byteLength}`);
      }
      totalSize += cdHeader.byteLength;
      currentOffset += entry.localHeaderSize + entry.compressedSize;
    }

    return totalSize;
  }

  /**
   * 构建中央目录头 (Central Directory Header)
   */
  private static buildCentralDirectoryHeader(entry: ZipEntry, localHeaderOffset: number): ArrayBuffer {
    const headerSize = 46 + entry.fileNameBytes.length;
    const header = new ArrayBuffer(headerSize);
    const view = new DataView(header);
    let offset = 0;

    // 中央目录头签名 (4 bytes)
    view.setUint32(offset, 0x02014b50, true);
    offset += 4;

    // 创建版本 (2 bytes)
    view.setUint16(offset, 20, true);
    offset += 2;

    // 解压版本 (2 bytes)
    view.setUint16(offset, 20, true);
    offset += 2;

    // 通用位标志 (2 bytes)
    view.setUint16(offset, 0, true);
    offset += 2;

    // 压缩方法 (2 bytes)
    view.setUint16(offset, entry.isCompressed ? 8 : 0, true);
    offset += 2;

    // 文件修改时间 (2 bytes)
    view.setUint16(offset, 0, true);
    offset += 2;

    // 文件修改日期 (2 bytes)
    view.setUint16(offset, 0, true);
    offset += 2;

    // CRC-32 (4 bytes)
    view.setUint32(offset, entry.crc32, true);
    offset += 4;

    // 压缩后大小 (4 bytes)
    view.setUint32(offset, entry.compressedSize, true);
    offset += 4;

    // 未压缩大小 (4 bytes)
    view.setUint32(offset, entry.uncompressedSize, true);
    offset += 4;

    // 文件名长度 (2 bytes)
    view.setUint16(offset, entry.fileNameBytes.length, true);
    offset += 2;

    // 扩展字段长度 (2 bytes)
    view.setUint16(offset, 0, true);
    offset += 2;

    // 文件注释长度 (2 bytes)
    view.setUint16(offset, 0, true);
    offset += 2;

    // 磁盘号 (2 bytes)
    view.setUint16(offset, 0, true);
    offset += 2;

    // 内部文件属性 (2 bytes)
    view.setUint16(offset, 0, true);
    offset += 2;

    // 外部文件属性 (4 bytes)
    view.setUint32(offset, 0, true);
    offset += 4;

    // 本地文件头相对偏移 (4 bytes)
    view.setUint32(offset, localHeaderOffset, true);
    offset += 4;

    // 文件名
    const headerBytes = new Uint8Array(header);
    headerBytes.set(entry.fileNameBytes, offset);

    return header;
  }

  /**
   * 写入中央目录结束标记
   */
  private static writeEndOfCentralDirectory(
    outputFile: fileIo.File,
    totalEntries: number,
    centralDirectorySize: number,
    centralDirectoryOffset: number
  ): void {
    const eocd = new ArrayBuffer(22);
    const view = new DataView(eocd);
    let offset = 0;

    // 签名 (4 bytes)
    view.setUint32(offset, 0x06054b50, true);
    offset += 4;

    // 磁盘号 (2 bytes)
    view.setUint16(offset, 0, true);
    offset += 2;

    // 中央目录所在磁盘号 (2 bytes)
    view.setUint16(offset, 0, true);
    offset += 2;

    // 本磁盘中央目录记录数 (2 bytes)
    view.setUint16(offset, totalEntries, true);
    offset += 2;

    // 中央目录记录总数 (2 bytes)
    view.setUint16(offset, totalEntries, true);
    offset += 2;

    // 中央目录大小 (4 bytes)
    view.setUint32(offset, centralDirectorySize, true);
    offset += 4;

    // 中央目录起始偏移 (4 bytes)
    view.setUint32(offset, centralDirectoryOffset, true);
    offset += 4;

    // 文件注释长度 (2 bytes)
    view.setUint16(offset, 0, true);

    const written = fileIo.writeSync(outputFile.fd, eocd);
    console.info(ZipHelper.TAG, `中央目录结束标记已写入: ${written} bytes, 预期: ${eocd.byteLength} bytes`);
    if (written !== eocd.byteLength) {
      console.error(ZipHelper.TAG, `中央目录结束标记写入不完整: ${written} != ${eocd.byteLength}`);
    }
  }

  /**
   * 读取中央目录结束标记
   */
  private static async readEndOfCentralDirectory(zipFile: fileIo.File): Promise<EOCD> {
    // 获取文件大小
    const stat = await fileIo.stat(zipFile.fd);
    const fileSize = stat.size;

    // EOCD 最小 22 字节，最大 22 + 65535 字节（注释）
    const searchSize = Math.min(fileSize, 65557);
    const searchBuffer = new ArrayBuffer(searchSize);

    // 读取文件末尾数据
    await fileIo.read(zipFile.fd, searchBuffer, { offset: fileSize - searchSize });
    const view = new DataView(searchBuffer);

    // 从后向前搜索 EOCD 签名 0x06054b50
    for (let i = searchSize - 22; i >= 0; i--) {
      if (view.getUint32(i, true) === 0x06054b50) {
        return {
          totalEntries: view.getUint16(i + 8, true),
          centralDirectorySize: view.getUint32(i + 12, true),
          centralDirectoryOffset: view.getUint32(i + 16, true)
        };
      }
    }

    throw new Error("无法找到 ZIP 中央目录结束标记");
  }

  /**
   * 读取中央目录
   */
  private static async readCentralDirectory(zipFile: fileIo.File, eocd: EOCD): Promise<Array<CentralDirectoryEntry>> {
    const entries: Array<CentralDirectoryEntry> = [];

    // 读取中央目录数据
    const cdBuffer = new ArrayBuffer(eocd.centralDirectorySize);
    await fileIo.read(zipFile.fd, cdBuffer, { offset: eocd.centralDirectoryOffset });
    const view = new DataView(cdBuffer);
    let offset = 0;

    for (let i = 0; i < eocd.totalEntries; i++) {
      // 验证签名
      if (view.getUint32(offset, true) !== 0x02014b50) {
        throw new Error(`中央目录签名错误，位置: ${offset}`);
      }
      offset += 4;

      // 跳过创建版本和解压版本
      offset += 4;

      // 通用位标志
      offset += 2;

      // 压缩方法
      const compressionMethod = view.getUint16(offset, true);
      offset += 2;

      // 跳过时间和日期
      offset += 4;

      // CRC-32
      offset += 4;

      // 压缩后大小
      const compressedSize = view.getUint32(offset, true);
      offset += 4;

      // 未压缩大小
      const uncompressedSize = view.getUint32(offset, true);
      offset += 4;

      // 文件名长度
      const fileNameLength = view.getUint16(offset, true);
      offset += 2;

      // 扩展字段长度
      const extraFieldLength = view.getUint16(offset, true);
      offset += 2;

      // 文件注释长度
      const commentLength = view.getUint16(offset, true);
      offset += 2;

      // 跳过磁盘号、内部属性、外部属性
      offset += 8;

      // 本地文件头偏移
      const localHeaderOffset = view.getUint32(offset, true);
      offset += 4;

      // 读取文件名
      const fileNameBytes = new Uint8Array(cdBuffer, offset, fileNameLength);
      const fileName = ZipHelper.bytesToString(fileNameBytes);
      offset += fileNameLength;

      // 跳过扩展字段和注释
      offset += extraFieldLength + commentLength;

      entries.push({
        fileName,
        compressionMethod,
        compressedSize,
        uncompressedSize,
        localHeaderOffset
      });
    }

    return entries;
  }

  /**
   * 解压单个文件
   */
  private static async extractFile(
    zipFile: fileIo.File,
    entry: CentralDirectoryEntry,
    outputPath: string
  ): Promise<void> {
    // 读取本地文件头
    const localHeaderBuffer = new ArrayBuffer(30);
    await fileIo.read(zipFile.fd, localHeaderBuffer, { offset: entry.localHeaderOffset });
    const view = new DataView(localHeaderBuffer);

    // 验证签名
    if (view.getUint32(0, true) !== 0x04034b50) {
      throw new Error(`本地文件头签名错误: ${entry.fileName}`);
    }

    // 获取文件名长度
    const fileNameLength = view.getUint16(26, true);
    const extraFieldLength = view.getUint16(28, true);

    // 计算数据偏移
    const dataOffset = entry.localHeaderOffset + 30 + fileNameLength + extraFieldLength;

    // 读取压缩数据
    const compressedData = new ArrayBuffer(entry.compressedSize);
    await fileIo.read(zipFile.fd, compressedData, { offset: dataOffset });

    // 解压数据
    let outputData: ArrayBuffer;
    if (entry.compressionMethod === 8) {
      // DEFLATE 压缩
      outputData = await ZipHelper.decompressData(compressedData, entry.uncompressedSize);
    } else {
      // 无压缩
      outputData = compressedData;
    }

    // 确保输出目录存在
    const outputDir = outputPath.substring(0, outputPath.lastIndexOf('/'));
    await ZipHelper.ensureDirectoryExists(outputDir);

    // 写入输出文件
    const outputFile = await fileIo.open(outputPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    await fileIo.write(outputFile.fd, outputData);
    await fileIo.close(outputFile);
  }

  /**
   * 压缩数据 - 使用 zlib.createZipSync
   */
  private static async compressData(data: ArrayBuffer): Promise<ArrayBuffer> {
    try {
      // 创建 zip 实例
      const zip = zlib.createZipSync();

      // 计算压缩缓冲区大小上限
      const bound = await zip.compressBound(data.byteLength);
      const destBuffer = new ArrayBuffer(bound);

      // 压缩数据
      const result = await zip.compress(destBuffer, data, data.byteLength);

      // 返回实际压缩后的数据
      return destBuffer.slice(0, result.destLen);
    } catch (e) {
      console.warn(ZipHelper.TAG, `压缩失败，使用原始数据: ${e}`);
      return data;
    }
  }

  /**
   * 解压数据 - 使用 zlib.createZipSync
   */
  private static async decompressData(compressedData: ArrayBuffer, uncompressedSize: number): Promise<ArrayBuffer> {
    try {
      // 创建 zip 实例
      const zip = zlib.createZipSync();

      const destBuffer = new ArrayBuffer(uncompressedSize);
      const result = await zip.uncompress(destBuffer, compressedData, compressedData.byteLength);

      // 返回实际解压后的数据
      return destBuffer.slice(0, result.destLen);
    } catch (e) {
      console.error(ZipHelper.TAG, `解压失败: ${e}`);
      throw new Error(`解压失败: ${e}`);
    }
  }

  /**
   * 字符串转字节数组
   */
  private static stringToBytes(str: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encode(str);
  }

  /**
   * 字节数组转字符串
   */
  private static bytesToString(bytes: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decode(bytes);
  }

  /**
   * 确保目录存在
   */
  private static ensureDirectoryExists(dirPath: string): void {
    try {
      const stat = fileIo.statSync(dirPath);
      if (stat.isDirectory()) {
        console.info(ZipHelper.TAG, `目录已存在: ${dirPath}`);
        return;
      } else {
        console.error(ZipHelper.TAG, `路径存在但不是目录: ${dirPath}`);
        throw new Error(`路径存在但不是目录: ${dirPath}`);
      }
    } catch (e) {
      // 目录不存在，递归创建
      console.info(ZipHelper.TAG, `目录不存在，准备创建: ${dirPath}`);
      const parentPath = dirPath.substring(0, dirPath.lastIndexOf('/'));
      if (parentPath && parentPath !== dirPath) {
        ZipHelper.ensureDirectoryExists(parentPath);
      }
      try {
        fileIo.mkdirSync(dirPath);
        console.info(ZipHelper.TAG, `目录创建成功: ${dirPath}`);
        // 验证目录是否真的创建成功
        const stat = fileIo.statSync(dirPath);
        if (!stat.isDirectory()) {
          console.error(ZipHelper.TAG, `路径创建成功但不是目录: ${dirPath}`);
          throw new Error(`路径创建成功但不是目录: ${dirPath}`);
        }
      } catch (mkdirError) {
        // 如果创建失败，可能是目录已存在（并发情况）
        try {
          const stat = fileIo.statSync(dirPath);
          if (stat.isDirectory()) {
            console.info(ZipHelper.TAG, `目录已存在（并发创建）: ${dirPath}`);
          } else {
            console.error(ZipHelper.TAG, `路径存在但不是目录: ${dirPath}`);
            throw new Error(`路径存在但不是目录: ${dirPath}`);
          }
        } catch (accessError) {
          console.error(ZipHelper.TAG, `目录创建失败: ${dirPath}, 错误: ${mkdirError}`);
          throw new Error(`目录创建失败: ${dirPath}, 错误: ${mkdirError}`);
        }
      }
    }
  }
}

// ============== 接口定义 ==============

export interface ZipFileInfo {
  path: string;
  name: string;
}

interface ZipEntry {
  fileName: string;
  fileNameBytes: Uint8Array;
  compressedSize: number;
  uncompressedSize: number;
  isCompressed: boolean;
  localHeaderSize: number;
  crc32: number;
}

interface EOCD {
  totalEntries: number;
  centralDirectorySize: number;
  centralDirectoryOffset: number;
}

interface CentralDirectoryEntry {
  fileName: string;
  compressionMethod: number;
  compressedSize: number;
  uncompressedSize: number;
  localHeaderOffset: number;
}

export default ZipHelper;
