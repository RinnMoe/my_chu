/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
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

import TextUtils from './TextUtils'

type char = string;
type byte = number;

/**
 * 十六进制编解码工具类,提供字节数组与十六进制字符串/字符数组之间的相互转换。
 */
export default class HexUtil {
  private static readonly DIGITS_LOWER: char[] = ['0', '1', '2', '3', '4', '5',
    '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];
  private static readonly DIGITS_UPPER: char[] = ['0', '1', '2', '3', '4', '5',
    '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'];

  /**
   * 将字节数组编码为十六进制字符数组。
   * @param data 待编码的字节数组。
   * @param toLowerCase 是否输出小写,默认 true。
   * @returns 十六进制字符数组(每字节对应两个字符)。
   */
  public static encodeHex(data: byte[], toLowerCase: boolean = true): char[] {
    return HexUtil.encodeHexInner(data, toLowerCase ? HexUtil.DIGITS_LOWER : HexUtil.DIGITS_UPPER);
  }

  /**
   * 内部方法:用指定数字表将字节数组编码为十六进制字符数组。
   * @param data 待编码的字节数组。
   * @param toDigits 使用的数字字符表(DIGITS_LOWER 或 DIGITS_UPPER)。
   * @returns 十六进制字符数组。
   */
  protected static encodeHexInner(data: byte[], toDigits: char[]): char[] {
    if (!data) {
      return [];
    }
    let l: number = data.length;
    let out: char[] = new Array(l << 1);
    for (let i: number = 0, j: number = 0; i < l; i++) {
      out[j++] = toDigits[(0xF0 & data[i]) >>> 4];
      out[j++] = toDigits[0x0F & data[i]];
    }
    return out;
  }

  /**
   * 将字符数组拼接为字符串。
   * @param data 字符数组。
   * @returns 拼接后的字符串。
   */
  private static byteToString(data: char[]): string {
    let str: string = '';
    for (let i: number = 0; i < data.length; i++) {
      str += data[i];
    }
    return str;
  }


  /**
   * 将字节数组编码为十六进制字符串。
   * @param data 待编码的字节数组。
   * @param toLowerCase 是否输出小写,默认 true。
   * @returns 十六进制字符串。
   */
  public static encodeHexStr(data: byte[], toLowerCase: boolean = true): string {
    return HexUtil.encodeHexStrInner(data, toLowerCase ? HexUtil.DIGITS_LOWER : HexUtil.DIGITS_UPPER);
  }


  /**
   * 内部方法:用指定数字表将字节数组编码为十六进制字符串。
   * @param data 待编码的字节数组。
   * @param toDigits 使用的数字字符表。
   * @returns 十六进制字符串。
   */
  protected static encodeHexStrInner(data: byte[], toDigits: char[]): string {
    return HexUtil.byteToString(HexUtil.encodeHexInner(data, toDigits));
  }

  /**
   * 将 Uint8Array 格式化为十六进制字符串,可选择是否在每字节后加空格。
   * @param data 待格式化的字节数组。
   * @param addSpace 是否在每字节后加空格,默认 false。
   * @returns 十六进制字符串,空输入返回空串。
   */
  public static formatHexString(data: Uint8Array, addSpace: boolean = false): string {
    if (!data || data.length < 1) {
      return '';
    }
    let sb: string = '';
    for (let i: number = 0; i < data.length; i++) {
      let hex: string = (data[i] & 0xFF).toString(16);
      if (hex.length === 1) {
        hex = '0' + hex;
      }
      sb = sb + hex;
      if (addSpace) {
        sb = sb + ' ';
      }
    }
    return sb;
  }

  /**
   * 将十六进制字符数组解码为字节数组。
   * @param data 十六进制字符数组(长度必须为偶数)。
   * @returns 解码后的字节数组。
   */
  public static decodeHex(data: char[]): byte[] {
    let len: number = data.length;

    if ((len & 0x01) !== 0) {
      throw new Error('Odd number of characters.');
    }

    let out: byte[] = new Array(len >> 1);

    // two characters form the hex value.
    for (let i: number = 0, j: number = 0; j < len; i++) {
      let f: number = HexUtil.toDigit(data[j], j) << 4;
      j++;
      f = f | HexUtil.toDigit(data[j], j);
      j++;
      out[i] = (f & 0xFF);
    }

    return out;
  }


  /**
   * 将单个十六进制字符转换为对应数值。
   * @param ch 十六进制字符。
   * @param index 字符在原串中的位置(用于错误提示)。
   * @returns 0-15 的数值,非法字符抛异常。
   */
  protected static toDigit(ch: char, index: number): number {
    let digit: number = HexUtil.charToByte(ch.toUpperCase()); //Character.digit(ch, 16);
    if (digit === -1) {
      throw new Error('Illegal hexadecimal character ' + ch
        + ' at index ' + index);
    }
    return digit;
  }


  /**
   * 将十六进制字符串解码为 Uint8Array。会去除前后空白与中间空格,奇数长度前补 '0'。
   * @param hexString 十六进制字符串。
   * @returns 解码后的 Uint8Array,空串返回 null。
   */
  public static hexStringToBytes(hexString: string): Uint8Array | null {
    if (TextUtils.isEmpty(hexString)) {
      return null;
    }
    hexString = hexString.trim();
    hexString = hexString.toUpperCase();
    hexString = hexString.replace(new RegExp(' ', 'g'), '');
    hexString = hexString.length % 2 === 1 ? '0' + hexString : hexString;
    let length: number = hexString.length / 2;
    let hexChars: char[] = TextUtils.toCharArray(hexString);
    let d: byte[] = new Array(length);
    for (let i: number = 0; i < length; i++) {
      let pos: number = i * 2;
      d[i] = (HexUtil.charToByte(hexChars[pos]) << 4 | HexUtil.charToByte(hexChars[pos + 1]));
    }
    return new Uint8Array(d);
  }

  /**
   * 将单个十六进制字符转换为 0-15 的数值。
   * @param c 十六进制字符(大小写不敏感)。
   * @returns 0-15 的数值,非法字符返回 -1。
   */
  public static charToByte(c: char): byte {
    return '0123456789ABCDEF'.indexOf(c);
  }

  /**
   * 提取字节数组中指定位置的单字节,并格式化为十六进制字符串。
   * @param data 源字节数组。
   * @param position 要提取的字节位置。
   * @returns 该字节的十六进制字符串。
   */
  public static extractData(data: Uint8Array, position: number): string {
    return HexUtil.formatHexString(new Uint8Array([data[position]]));
  }
}
