import 'dart:async';
import 'dart:io';

Future<void Function()?> connectReportsWebSocket(
  String wsUrl, {
  required void Function() onUpdate,
  void Function()? onDone,
}) async {
  try {
    final socket = await WebSocket.connect(wsUrl)
        .timeout(const Duration(seconds: 8));
    final sub = socket.listen(
      (_) => onUpdate(),
      onDone: onDone,
      onError: (_) => onDone?.call(),
      cancelOnError: true,
    );
    return () {
      unawaited(sub.cancel());
      unawaited(socket.close());
    };
  } catch (_) {
    onDone?.call();
    return null;
  }
}
