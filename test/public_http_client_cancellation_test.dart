import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychu/services/public_http_client.dart';

void main() {
  test('authenticated transport never follows redirects', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var redirected = 0;
    server.listen((request) async {
      if (request.uri.path == '/other') {
        redirected++;
        request.response.write('unexpected');
      } else {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/other');
      }
      await request.response.close();
    });
    final client = PublicHttpClient();
    try {
      final response = await client.postJson(
        Uri.parse('http://127.0.0.1:${server.port}/scan'),
        body: {'out_number': 'fixture'},
        headers: {'Authorization': 'Bearer synthetic-test'},
        followRedirects: false,
      );
      expect(response.statusCode, 302);
      expect(redirected, 0);
    } finally {
      client.close();
      await server.close(force: true);
    }
  });

  for (final explicitCancel in [true, false]) {
    test(
      'transport physically aborts ${explicitCancel ? 'cancelled' : 'timed out'} requests',
      () async {
        HttpOverrides.global = null;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final received = Completer<void>();
        server.listen((request) {
          if (!received.isCompleted) received.complete();
        });
        final abort = Completer<void>();
        final client = PublicHttpClient();
        try {
          final request = client.postJson(
            Uri.parse('http://127.0.0.1:${server.port}/scan'),
            body: {},
            followRedirects: false,
            timeout:
                explicitCancel
                    ? const Duration(seconds: 3)
                    : const Duration(milliseconds: 100),
            abortTrigger: abort.future,
          );
          final assertion = expectLater(
            request,
            throwsA(isA<PublicHttpException>()),
          );
          await received.future;
          if (explicitCancel) abort.complete();
          await assertion;
        } finally {
          client.close();
          await server.close(force: true);
        }
      },
    );
  }
}
