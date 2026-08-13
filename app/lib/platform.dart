import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// La caja flotante (frameless/translúcida/always-on-top) y el rol de "host"
/// son de escritorio. En Android la app es el cliente y corre a pantalla completa.
bool get isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);
