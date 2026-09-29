/*
* Copyright (c) 2024 Hunan OpenValley Digital Industry Development Co., Ltd.
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

export default class URLUtil {
  static guessFileName(url: string, contentDisposition: string | null, mimeType: string | null): string | null {
    let filename: string | null = null;
    if (contentDisposition) {
      const filenameRegex = /filename[^;=\n]*=((['"]).*?\2|[^;\n]*)/;
      const matches = filenameRegex.exec(contentDisposition);
      if (matches && matches[1]) {
        filename = matches[1].replace(/['"]/g, '');
      }
    }
    if (!filename) {
      const urlParts = url.split('/');
      filename = decodeURIComponent(urlParts[urlParts.length - 1]);
    }

    if (!filename) {
      filename = "downloadfile";
    }

    let dotIndex = filename.indexOf('.');
    if (dotIndex < 0 && mimeType) {
      const extension = mimeType.split('/')[1]; // 假设 MIME 类型是 'type/subtype'
      filename = `${filename}.${extension}`;
    }
    return filename
  }
}