// TEMPORARY PROBE (safe to delete). Dials the companion with the phone's own
// socket code, pinning the fingerprint, and posts hello+auth. Purpose: prove
// or disprove that the companion receives hello frames from a Dart client.
// clang-format off
import 'dart:async';
import 'dart:io';

import 'package:tapdesk_mobile/transport/socket.dart';

Future<void> main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : '192.168.2.110';
  final fingerprint = args.length > 1 ? args[1] : '';
  // May be stale/expired on purpose; the point is whether hello ARRIVES at
  // all, not whether the token still works.
  final token = args.length > 2 ? args[2] : '';

  stdout.writeln('dialing wss://$host:8765/ pinned to ${fingerprint.substring(0, 12)}…');
  final socket = await PinnedSocket.open(
    host: host,
    port: 8765,
    fingerprint: fingerprint,
  );
  socket.messages.listen(
    (line) => stdout.writeln('PC says: $line'),
    onDone: () => stdout.writeln('PC closed the socket.'),
    onError: (Object error) => stdout.writeln('socket error: $error'),
  );
  stdout.writeln('open; sending hello (device=dart-probe platform=android)');
  socket.send('{"t":"hello","v":1,"device":"dart-probe","platform":"android"}');
  stdout.writeln('sending auth (token len ${token.length})');
  socket.send('{"t":"auth","token":"$token"}');
  await Future<void>.delayed(const Duration(seconds: 6));
  stdout.writeln('sent count: ${socket.sentCount}');
  await socket.close();
}
