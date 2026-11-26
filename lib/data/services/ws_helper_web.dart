import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void Function()?> connectReportsWebSocket(
  String wsUrl, {
  required void Function() onUpdate,
  void Function()? onDone,
}) async {
  try {
    final socket = web.WebSocket(wsUrl);
    var closed = false;
    void handleDone() {
      if (closed) return;
      closed = true;
      onDone?.call();
    }

    socket.onmessage = ((web.MessageEvent _) {
      if (!closed) onUpdate();
    }).toJS;
    socket.onclose = ((web.CloseEvent _) => handleDone()).toJS;
    socket.onerror = ((web.Event _) => handleDone()).toJS;

    return () {
      closed = true;
      try {
        socket.close();
      } catch (_) {}
    };
  } catch (_) {
    onDone?.call();
    return null;
  }
}
