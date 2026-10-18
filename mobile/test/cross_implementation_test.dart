/// Cross-implementation test: the real phone transport against the real companion.
///
/// Every other test checks one implementation against its own expectations. That
/// is not enough: a phone that speaks a protocol the companion does not
/// understand passes all 154 unit tests and is useless in the hand. Both
/// implementations were written from docs/protocol.md, at different times, so
/// this is exactly where a disagreement would hide.
///
/// So this launches the actual Python companion as a subprocess and drives it
/// with the actual Dart socket, including the actual certificate pin. Nothing
/// is stubbed. If the two disagree about a field name, the handshake order, the
/// fingerprint or the QR payload format, this fails.
///
/// Skipped rather than failed when the companion is not built, so a fresh
/// checkout with no virtualenv can still run the app's tests.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapdesk_mobile/transport/socket.dart';
import 'package:tapdesk_mobile/transport/tapdesk_event.dart';

/// The companion's virtualenv, relative to `mobile/`, where tests run.
final File python = File('../companion/.venv/Scripts/python.exe');

/// Somewhere for the companion to keep its certificate, outside the repo.
final Directory configDir = Directory(
  '${Directory.systemTemp.path}/tapdesk-cross-${DateTime.now().microsecondsSinceEpoch}',
);

const int defaultPort = 8765;

/// A second port, for the fixture companion that approves automatically.
const int approvingPort = 8876;

/// Separate state so the approving fixture's token is its own.
final Directory approvingConfigDir = Directory(
  '${Directory.systemTemp.path}/tapdesk-cross-approve-${DateTime.now().microsecondsSinceEpoch}',
);

/// The test fixture that approves pairing, while it is running.
_Child? approving;

/// The strict companion the shipped entry point starts.
_Child? companion;

bool get built => python.existsSync();

/// Wait for the companion to bind, rather than sleeping and hoping.
///
/// On failure it reports what the child actually printed. "The companion never
/// listened on port 8876" was all the information a failure gave, which is why
/// a slow start was indistinguishable from a broken build - the test was
/// reporting its own impatience as if it were a finding.
/// A launched child process, with its output kept so a failure can explain
/// itself.
///
/// `Process.stderr` is a stream of bytes, not a future of text, so reading it
/// after the fact means subscribing. Keeping a small buffer from launch is what
/// lets a timeout report "here is what the companion said" instead of "the
/// companion never listened", which told nobody anything.
class _Child {
  _Child(this.process);

  final Process process;
  final StringBuffer _err = StringBuffer();
  final StringBuffer _out = StringBuffer();
  final Completer<int> _exited = Completer<int>();

  String get output {
    final text = _err.toString().trim();
    return text.isEmpty ? _out.toString().trim() : text;
  }

  /// Whether it has already exited.
  bool get hasExited => _exited.isCompleted;

  int? get exitCode => _code;
  int? _code;

  static Future<_Child> start(
    String executable,
    List<String> args, {
    required String workingDirectory,
  }) async {
    final child = _Child(
      await Process.start(executable, args, workingDirectory: workingDirectory),
    );
    child.process.stderr
        .transform(const SystemEncoding().decoder)
        .listen(child._err.write)
        .onDone(() {});
    child.process.stdout
        .transform(const SystemEncoding().decoder)
        .listen(child._out.write)
        .onDone(() {});
    unawaited(
      child.process.exitCode.then((code) {
        if (!child._exited.isCompleted) child._exited.complete(code);
      }),
    );
    return child;
  }
}

/// Wait for a companion to bind, rather than sleeping and hoping.
Future<void> _waitForPort(
  int port, {
  required _Child child,
  String label = 'companion',
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (child.hasExited) {
      fail(
        'the $label exited before it could listen (exit ${child.exitCode}).\n'
        'Its own output:\n${child.output}',
      );
    }
    try {
      final socket =
          await Socket.connect('127.0.0.1', port, timeout: const Duration(seconds: 1));
      socket.destroy();
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  fail(
    'the $label never listened on port $port within ${timeout.inSeconds}s.\n'
    'It has not exited, so this is a slow start or a port clash rather than a '
    'crash.\nIts own output:\n${child.output}',
  );
}

/// Start a companion on [port].
Future<void> _startCompanion(int port) async {
  companion = await _Child.start(
    python.path,
    [
      '-m',
      'tapdesk.app',
      '--headless',
      '--port',
      '$port',
      '--config-dir',
      configDir.path,
    ],
    workingDirectory: '../companion',
  );
  await _waitForPort(port, child: companion!);
}

/// Start the test fixture that approves pairing.
///
/// Not a flag on the shipped CLI: a switch that hands control of a computer to
/// anyone who can reach the port is exactly what the Allow prompt exists to
/// withhold, and it should not be one mistyped argument away from every user.
Future<void> _startApprovingCompanion() async {
  approving = await _Child.start(
    python.path,
    [
      'tests/approve_server.py',
      '--port',
      '$approvingPort',
      '--config-dir',
      approvingConfigDir.path,
    ],
    workingDirectory: '../companion',
  );
  await _waitForPort(approvingPort, child: approving!, label: 'approving fixture');
}

/// The companion's own view of its pairing link.
class _Link {
  const _Link(this.fingerprint, this.token);

  final String fingerprint;
  final String token;
}

/// Ask the companion to print its link, and decode it the way the phone does.
///
/// This also pins down the QR payload format across implementations. If the two
/// disagreed about the deep link, nothing would pair in the real world and every
/// other test here would still pass.
Future<_Link> _printLink(int port, {Directory? from}) async {
  final configDirForLink = from ?? configDir;
  final result = await Process.run(
    python.path,
    [
      '-m',
      'tapdesk.app',
      '--print-link',
      '--port',
      '$port',
      '--config-dir',
      configDirForLink.path,
    ],
    workingDirectory: '../companion',
  );
  // Split on newlines only, then trim each: on Windows the line endings are
  // CRLF, and a stray \r left at the end of the base64 payload is an invalid
  // character that looks like a corrupted deep link rather than a line ending.
  final lines =
      (result.stdout as String).split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final link = lines.first;
  final fingerprint = lines.firstWhere((l) => l.startsWith('fingerprint ')).split(' ').last;

  final encoded = link.split('d=').last;
  final padding = (4 - encoded.length % 4) % 4;
  final decoded = jsonDecode(
    utf8.decode(base64Url.decode(encoded.padRight(encoded.length + padding, '='))),
  ) as Map<String, Object?>;

  // Exactly the fields docs/protocol.md section 2.3 lists.
  expect(decoded['v'], 1);
  expect(decoded['name'], isA<String>());
  expect(decoded['ips'], isA<List<Object?>>());
  expect(decoded['port'], port);
  expect(decoded['token'], isA<String>());
  expect(decoded['fp'], fingerprint);

  return _Link(fingerprint, decoded['token'] as String);
}

/// Reads frames from a socket.
///
/// The socket's message stream is single-subscription by design - the session
/// owns it in production - so `stream.first` can only ever be called once.
/// Tests need to read several frames in order, which is what this is for.
class _Frames {
  _Frames(Stream<String> stream) {
    _subscription = stream.listen(_add);
  }

  final List<String> _received = [];
  final List<Completer<String>> _waiting = [];
  late final StreamSubscription<String> _subscription;

  void _add(String frame) {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete(frame);
    } else {
      _received.add(frame);
    }
  }

  /// The next frame, waiting for it if it has not arrived yet.
  Future<Map<String, Object?>> next() async {
    if (_received.isNotEmpty) {
      return _decode(_received.removeAt(0));
    }
    final completer = Completer<String>();
    _waiting.add(completer);
    return _decode(await completer.future);
  }

  /// Whether anything has arrived that nothing has read.
  bool get hasUnread => _received.isNotEmpty;

  /// The next frame, or null if none arrives within [timeout].
  ///
  /// Used for the assertion that *nothing* comes back: "no complaint" needs a
  /// real wait, not an instant check that would pass even if the reply were
  /// merely slow.
  Future<Map<String, Object?>?> nextOrNull(Duration timeout) async {
    if (_received.isNotEmpty) return _decode(_received.removeAt(0));
    final completer = Completer<String>();
    _waiting.add(completer);
    try {
      return _decode(await completer.future.timeout(timeout));
    } on TimeoutException {
      return null;
    }
  }

  static Map<String, Object?> _decode(String frame) =>
      jsonDecode(frame) as Map<String, Object?>;

  Future<void> dispose() => _subscription.cancel();
}

void main() {
  setUpAll(() {
    if (!built) {
      markTestSkipped('companion not built: create companion/.venv first');
    }
    if (!configDir.existsSync()) configDir.createSync(recursive: true);
    if (!approvingConfigDir.existsSync()) approvingConfigDir.createSync(recursive: true);
  });

  setUp(() async {
    if (built) await _startCompanion(defaultPort);
  });

  tearDown(() {
    companion?.process.kill(ProcessSignal.sigterm);
    companion = null;
    approving?.process.kill(ProcessSignal.sigterm);
    approving = null;
  });

  tearDownAll(() {
    for (final dir in [configDir, approvingConfigDir]) {
      if (dir.existsSync()) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {
          // A companion may still hold the directory on Windows.
        }
      }
    }
  });

  test('the QR payload has the shape the phone expects', () async {
    final link = await _printLink(defaultPort);

    // 64 hex characters. A QR carrying anything else would pin a fingerprint
    // the phone can never match, and every pair would fail for no visible
    // reason.
    expect(link.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(link.token, isNotEmpty);
  });

test('a real pinned socket completes the handshake', () async {
    final link = await _printLink(defaultPort);

    final socket = await PinnedSocketFactory().connect(
      host: '127.0.0.1',
      port: defaultPort,
      fingerprint: link.fingerprint,
    );
    final frames = _Frames(socket.messages);
    addTearDown(frames.dispose);

    socket.send(jsonEncode({
      't': 'hello',
      'v': 1,
      'device': 'CrossTest',
      'platform': 'android',
    }));
    final helloOk = await frames.next();
    expect(helloOk['t'], 'hello_ok');
    // The PC name is what the pairing screen shows, so the field name matters.
    expect((helloOk['pc'] as Map)['name'], isA<String>());

    socket.send(jsonEncode({'t': 'auth', 'token': link.token}));

    // Two replies, not one: the companion says it is asking its user before it
    // answers. Reading a single frame and calling it the result is what made
    // this look like a bug in the companion when it was correct all along.
    expect((await frames.next())['t'], 'auth_pending');

    // Headless has nobody to ask, so it refuses. That is the correct outcome,
    // and the next test asserts it explicitly.
    final decision = await frames.next();
    expect(decision['t'], 'auth_err');
    expect(decision['code'], 'E_DENIED');

    await socket.close();
  });

  test('a fingerprint that does not match is refused', () async {
    // The whole security model, end to end across both implementations. If this
    // connected, anything on the network could impersonate a paired PC.
    Object? failure;
    try {
      await PinnedSocketFactory().connect(
        host: '127.0.0.1',
        port: defaultPort,
        fingerprint: 'b' * 64,
      );
    } catch (error) {
      failure = error;
    }

    expect(failure, isA<HandshakeException>());
    expect(
      (failure! as HandshakeException).reason,
      HandshakeFailure.fingerprintMismatch,
    );
  });

test('a phone that scans a code gets nothing without approval', () async {
    // The shipped entry point, with no window and nobody to ask. This is the
    // single most important safety property in the product, checked from the
    // phone's side as well as the companion's own tests: a missing window
    // must mean "no", never "yes".
    final link = await _printLink(defaultPort);

    final socket = await PinnedSocketFactory().connect(
      host: '127.0.0.1',
      port: defaultPort,
      fingerprint: link.fingerprint,
    );
    final frames = _Frames(socket.messages);
    addTearDown(frames.dispose);

    socket.send(jsonEncode({
      't': 'hello',
      'v': 1,
      'device': 'NobodyHome',
      'platform': 'android',
    }));
    await frames.next();

    socket.send(jsonEncode({'t': 'auth', 'token': link.token}));

    // auth_pending first: the companion is asking its user, who is not there.
    expect((await frames.next())['t'], 'auth_pending');

    final decision = await frames.next();
    expect(decision['t'], 'auth_err');
    expect(decision['code'], 'E_DENIED');

    await socket.close();
  });

  test('every frame the phone sends passes the companion validation', () async {
    // Needs an approved pairing, because a denied socket is closed and no
    // input frame ever gets as far as being validated. The companion is started
    // from the test fixture that approves, never from a flag on the shipped CLI.
    await _startApprovingCompanion();

    final link = await _printLink(approvingPort, from: approvingConfigDir);

    final socket = await PinnedSocketFactory().connect(
      host: '127.0.0.1',
      port: approvingPort,
      fingerprint: link.fingerprint,
    );
    final frames = _Frames(socket.messages);
    addTearDown(frames.dispose);

    socket.send(jsonEncode({
      't': 'hello',
      'v': 1,
      'device': 'CrossTest',
      'platform': 'android',
    }));
    await frames.next();

    socket.send(jsonEncode({'t': 'auth', 'token': link.token}));
    // The fixture answers Yes immediately, so there is no auth_pending to read
    // past: the decision and the grant arrive together.
    var decision = await frames.next();
    expect(decision['t'], 'auth_pending');
    decision = await frames.next();
    expect(decision['t'], 'auth_ok');

    // Then a welcome carrying the server's limits. The app ignores it today,
    // but it is the frame that tells it maxText and stickHz, so it is read
    // here rather than left to turn up as an unexpected frame later.
    final welcome = await frames.next();
    expect(welcome['t'], 'welcome');
    expect(welcome['maxText'], isA<int>());
    expect(welcome['stickHz'], isA<int>());

    // The companion tells the phone what it is doing the moment it connects,
    // so the greeting is not finished yet. This one is read explicitly rather
    // than being allowed to turn up later and be mistaken for a complaint -
    // which is exactly what happened when it was added.
    final settings = await frames.next();
    expect(settings['t'], 'settings');
    expect(settings['cursorSpeed'], isA<num>());
    expect(settings['accel'], isA<num>());
    expect(settings['safeMode'], isA<bool>());

    // Every frame the tabs really produce, encoded exactly as the app encodes
    // them, decoded and validated by a different implementation.
    //
    // Paced rather than fired at once. The companion rate-limits input, and
    // twelve frames back to back trips the limiter - which closes the socket
    // and makes everything after it look fine because nothing is listening.
    // A real thumb cannot produce this burst either.
    for (final event in <TapDeskEvent>[
      SlideEvent(SlideAction.next),
      SlideEvent(SlideAction.prev),
      SlideEvent(SlideAction.blank),
      TextEvent('السلام'),
      TextEvent('hello world'),
      ClickEvent(MouseButton.left, ClickAction.click),
      ClickEvent(MouseButton.right, ClickAction.double),
      ScrollEvent(3),
      KeyEvent('enter', 'tap'),
      KeyEvent('ctrl', 'press'),
      ComboEvent(['ctrl', 'shift', 'p']),
      StickEvent(0.5, -0.5),
      // The settings screen's own frame. A partial `set` is what the app sends
      // when only one slider moved, so the companion has to accept exactly
      // that shape as well as a full one.
      const SetEvent(cursorSpeed: 1.75),
    ]) {
      socket.send(event.encode());
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }

    // One reply is expected: the companion echoes what it actually applied
    // after a `set`. It is read and checked rather than skipped, because an
    // echo the phone cannot read is the same failure as no echo at all.
    final reply = await frames.nextOrNull(const Duration(milliseconds: 2000));
    expect(reply?['t'], 'settings',
        reason: 'the companion must answer a set with the settings it applied');
    expect(reply?['cursorSpeed'], 1.75);

    // Nothing else may come back. The wait is real rather than
    // instantaneous, so a slow complaint is still caught.
    final complaint = await frames.nextOrNull(const Duration(milliseconds: 1500));

    expect(socket.isOpen, isTrue);
    expect(
      complaint,
      isNull,
      reason: 'the companion rejected a frame the app produces: $complaint',
    );

    await socket.close();
  });

  test('an unknown field does not break the handshake', () async {
    // The protocol is additive. If the companion rejected unknown fields, every
    // future PC would break every phone already in a user's pocket.
    final link = await _printLink(defaultPort);

    final socket = await PinnedSocketFactory().connect(
      host: '127.0.0.1',
      port: defaultPort,
      fingerprint: link.fingerprint,
    );
    final frames = _Frames(socket.messages);
    addTearDown(frames.dispose);

    socket.send(jsonEncode({
      't': 'hello',
      'v': 1,
      'device': 'CrossTest',
      'platform': 'android',
      'somethingFromTheFuture': 42,
    }));
    final helloOk = await frames.next();

    expect(helloOk['t'], 'hello_ok');

    await socket.close();
  });
}
