// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

enum LogLevels { warning, info, progress }

final _controller = new StreamController<LogMessage>(sync: true);

Stream<LogMessage> get logEvents => _controller.stream;

class LogMessage {
  final LogLevels level;
  final Object message;

  LogMessage(this.level, this.message);
}

void logWarning(Object message) {
  _controller.add(new LogMessage(LogLevels.warning, message));
}

void logInfo(Object message) {
  _controller.add(new LogMessage(LogLevels.info, message));
}

void logProgress(Object message) {
  _controller.add(new LogMessage(LogLevels.progress, message));
}
