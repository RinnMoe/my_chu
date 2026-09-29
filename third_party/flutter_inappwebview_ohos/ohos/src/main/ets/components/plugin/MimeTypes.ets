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

const MIME_TYPES: Record<string, string> = {
  'txt': 'text/plain',
  'html': 'text/html',
  'css': 'text/css',
  'js': 'text/javascript',
  'json': 'application/json',
  'xml': 'application/xml',
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'zip': 'application/zip',
  'gif': 'image/gif',
  'jpeg': 'image/jpeg',
  'jpg': 'image/jpeg',
  'png': 'image/png',
  'svg': 'image/svg+xml',
  'mp3': 'audio/mpeg',
  'mp4': 'video/mp4',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'mpg': 'video/mpeg',
  'mpeg': 'video/mpeg',
  'avi': 'video/x-msvideo',
  'mov': 'video/quicktime',
  'wmv': 'video/x-ms-wmv',
  'flv': 'video/x-flv',
  'odt': 'application/vnd.oasis.opendocument.text',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'odp': 'application/vnd.oasis.opendocument.presentation',
  'csv': 'text/csv',
  'rtf': 'application/rtf',
  'yaml': 'application/x-yaml',
  'ics': 'text/calendar',
  'vcard': 'text/vcard',
  'tar': 'application/x-tar',
  '7z': 'application/x-7z-compressed',
  'rar': 'application/x-rar-compressed',
  'bmp': 'image/bmp',
  'ico': 'image/x-icon',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'webp': 'image/webp',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'eot': 'application/vnd.ms-fontobject',
  'otf': 'font/otf',
  'ttf': 'font/ttf',
  'apk': 'application/vnd.android.package-archive',
  'exe': 'application/x-msdownload',
  'deb': 'application/x-debian-package',
  'rpm': 'application/x-rpm',
  'dmg': 'application/x-apple-diskimage',
  'iso': 'application/x-iso9660-image',
  'tar.gz': 'application/x-tar-gz',
  'tgz': 'application/x-tar-gz',
  'tar.bz2': 'application/x-tar-bz2',
  'tbz': 'application/x-tar-bz2',
  'tar.xz': 'application/x-tar-xz',
  'txz': 'application/x-tar-xz',
  'bin': 'application/octet-stream',
  'dll': 'application/octet-stream',
  'jar': 'application/java-archive',
  'war': 'application/java-archive',
  'ear': 'application/java-archive',
  'swf': 'application/x-shockwave-flash',
  'webm': 'video/webm',
  'wasm': 'application/wasm',
  'ogm': 'video/x-ogm',
  'mkv': 'video/x-matroska',
  'flac': 'audio/flac',
  'ape': 'audio/x-ape',
  'm4a': 'audio/mp4',
  'opus': 'audio/opus',
  'spx': 'audio/ogg',
  'wavpack': 'audio/x-wavpack',
  'wv': 'audio/x-wavpack',
  'tta': 'audio/x-tta',
  'dsf': 'audio/x-dsf',
  'dff': 'audio/x-dff',
  'aac': 'audio/aac',
  'amr': 'audio/amr',
  'ra': 'audio/x-realaudio',
  'rm': 'audio/x-pn-realaudio',
  'ram': 'audio/x-pn-realaudio',
  'm3u': 'audio/x-mpegurl',
  'pls': 'audio/x-scpls',
  'wma': 'audio/x-ms-wma',
  'ogv': 'video/ogg',
  'm4v': 'video/x-m4v',
};


export default class MimeTypes {
  public static getMimeTypeFromExtension(extension: string): string {
    let item = MIME_TYPES[extension];
    return item ? item : extension;
  }
}