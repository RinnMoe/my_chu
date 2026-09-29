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

/**
 * 文本工具类,提供空值判断、字符数组转换、忽略大小写比较及 HCI 状态码映射等静态方法。
 */
export default class TextUtils {
  /**
   * 判断字符串是否为空(null/undefined/长度为 0 均视为空)。
   * @param text 待判断的字符串。
   * @returns 为空返回 true。
   */
  public static isEmpty(text: string): boolean {
    return text === null || text === undefined || text.length === 0;
  }

  /**
   * 将字符串拆成单字符数组(每元素为单个字符)。
   * @param text 待拆分的字符串。
   * @returns 单字符数组。
   */
  public static toCharArray(text: string): string[] {
    let arr: string[] = new Array(text.length);
    for (let i = 0; i < text.length; i++) {
      arr[i] = text.charAt(i);
    }
    return arr;
  }

  /**
   * 忽略大小写比较两字符串是否相等。
   * @param s1 第一个字符串。
   * @param s2 第二个字符串。
   * @returns 忽略大小写后相等返回 true。
   */
  public static equalsIgnoreCase(s1: string, s2: string): boolean {
    return s1.toLowerCase() === s2.toLowerCase();
  }

  /**
   * 忽略大小比较两字符串的字典序。
   * @param s1 第一个字符串。
   * @param s2 第二个字符串。
   * @returns s1 小于/等于/大于 s2 分别返回负数/0/正数。
   */
  public static compareToIgnoreCase(s1: string, s2: string): number {
    let n1: number = s1.length;
    let n2: number = s2.length;
    let min: number = Math.min(n1, n2);
    for (let i = 0; i < min; i++) {
      let c1: string = s1.charAt(i);
      let c2: string = s2.charAt(i);
      if (c1 !== c2) {
        c1 = c1.toUpperCase();
        c2 = c2.toUpperCase();
        if (c1 !== c2) {
          return c1.charCodeAt(0) - c2.charCodeAt(0);
        }
      }
    }
    return n1 - n2;
  }

  /**
   * 将 HCI 状态码映射为可读字符串。当前仅识别 SUCCESS(0x00),其余返回 UNKNOWN。
   * @param value HCI 状态码。
   * @returns 可读状态字符串。
   */
  public static hciStatusString(value: number): string {
    switch (value) {
      case 0x00:
        return 'SUCCESS';
      case 0x08:
        return 'CONNECTION TIMEOUT';
      case 0x13:
        return 'REMOTE USER TERMINATED';
      case 0x16:
        return 'CONNECTION TERMINATED BY LOCAL HOST';
      case 0x22:
        return 'CONNECTION FAIL TO ESTABLISH';
      case 23789258:
        return 'USER CANCELED';
      default:
        return 'UNKNOWN_HCI_ERROR (' + value + ')';
    }
  }
}
