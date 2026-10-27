// Public client sync configuration from Qishihe/longsong-chd-charger.
// Source: db59b0ed0513b252dbd7b1c59bd8a9643e667ef1, campus-pile-kit/chd-charge/index.html.
// Public decryption configuration, never a live JWT; do not log it.
import 'dart:convert';

final chargingMailboxSyncKey = utf8.decode(
  base64Decode('REhOMlVJTU5qN3NXRHlPY3FKY0gxNDZpMDVOb1hqbjNkZ2hZZzhETUV1bw=='),
);
