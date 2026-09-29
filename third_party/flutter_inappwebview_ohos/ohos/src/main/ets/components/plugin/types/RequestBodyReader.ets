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

import { Log } from '@ohos/flutter_ohos';
import web_webview from '@ohos.web.webview';
import ContentBlockerUtil from '../content_blocker/ContentBlockerUtil';

const TAG = 'RequestBodyReader';
const READ_CHUNK_SIZE: number = 8192;

type HttpBodyStreamFactory = () => web_webview.WebHttpBodyStream | null;

export default class RequestBodyReader {
  static needsRequestBody(method: string): boolean {
    const upper = method.toUpperCase();
    return upper === 'POST' || upper === 'PUT' || upper === 'PATCH';
  }

  /** WebResourceRequest from onInterceptRequest cannot expose POST body on OHOS. */
  static startReading(nativeRequest: WebResourceRequest): Promise<ArrayBuffer | null> {
    return RequestBodyReader.readFromStream(RequestBodyReader.tryGetHttpBodyStreamFromResourceRequest(nativeRequest));
  }

  /** WebSchemeHandlerRequest exposes getHttpBodyStream() for POST/PUT/PATCH. */
  static startReadingFromSchemeRequest(
    schemeRequest: web_webview.WebSchemeHandlerRequest
  ): Promise<ArrayBuffer | null> {
    let stream: web_webview.WebHttpBodyStream | null = null;
    try {
      stream = schemeRequest.getHttpBodyStream();
    } catch (error) {
      Log.e(TAG, 'getHttpBodyStream failed on scheme request: ' + error);
    }
    return RequestBodyReader.readFromStream(stream);
  }

  private static tryGetHttpBodyStreamFromResourceRequest(
    nativeRequest: WebResourceRequest
  ): web_webview.WebHttpBodyStream | null {
    let requestObject = nativeRequest as Object;
    let getter: Object | null | undefined = ContentBlockerUtil.getObjectValue(requestObject, 'getHttpBodyStream');
    if (getter == null || getter === undefined || typeof getter !== 'function') {
      return null;
    }
    try {
      return (getter as HttpBodyStreamFactory)();
    } catch (error) {
      Log.e(TAG, 'getHttpBodyStream failed on resource request: ' + error);
      return null;
    }
  }

  private static async readFromStream(stream: web_webview.WebHttpBodyStream | null): Promise<ArrayBuffer | null> {
    try {
      if (stream == null) {
        Log.w(TAG, 'No http body stream available');
        return null;
      }
      await stream.initialize();
      const chunks: Uint8Array[] = [];
      const totalSize = stream.getSize();
      if (totalSize > 0) {
        const buffer = await stream.read(totalSize);
        if (buffer.byteLength > 0) {
          chunks.push(new Uint8Array(buffer));
        }
      } else {
        while (!stream.isEof()) {
          const buffer = await stream.read(READ_CHUNK_SIZE);
          if (buffer.byteLength === 0) {
            break;
          }
          chunks.push(new Uint8Array(buffer));
        }
      }
      if (chunks.length === 0) {
        Log.w(TAG, 'Http body stream is empty');
        return null;
      }
      const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
      Log.i(TAG, 'Read request body: ' + totalLength + ' bytes');
      const merged = new Uint8Array(totalLength);
      let offset = 0;
      for (const chunk of chunks) {
        merged.set(chunk, offset);
        offset += chunk.length;
      }
      return merged.buffer;
    } catch (error) {
      Log.e(TAG, 'Failed to read request body: ' + error);
      return null;
    }
  }
}
