import 'package:meta/meta.dart';

import 'parsers/robots_txt.dart';

const robotName = 'linkcheck';

class ServerInfo {
  /// Minimum delay between requests sent to a single server.
  static const Duration minimumDelay = Duration(milliseconds: 100);

  /// No duration.
  static const immediate = Duration();

  final String host;

  final int? port;

  RobotsBouncer? bouncer;

  /// The total count of connection attempts, both successful and failed.
  int connectionAttempts = 0;

  /// The total count of times this server didn't even connect (socket errors
  /// etc.)
  int didNotConnectCount = 0;

  /// The total count of 401 and 403 return codes from this server.
  int unauthorizedCount = 0;

  /// The total count of 503 return codes (often due to throttling).
  int serviceUnavailableCount = 0;

  /// Whenever a status code is not one of the ones covered by
  /// [unauthorizedCount], [serviceUnavailableCount] etc., it'll be counted
  /// here.
  int otherErrorCount = 0;

  /// Server doesn't seem to understand HTTP HEAD requests (returned 501
  /// or 405).
  bool hasFailedHeadRequest = false;

  DateTime? _lastRequest;

  ServerInfo(String authority)
      : host = authority.split(':').first,
        port = authority.contains(':')
            ? int.parse(authority.split(':').last)
            : null;

  String get authority => "$host${port == null ? '' : ':$port'}";

  bool get hasNotConnected =>
      didNotConnectCount > 0 && didNotConnectCount == connectionAttempts;

  bool get isLocalhost => host == 'localhost' || host == '127.0.0.1';

  /// Creates the minimum duration to wait before the server should be bothered
  /// again.
  Duration getThrottlingDuration() {
    final lastRequest = _lastRequest;
    if (lastRequest == null) return immediate;
    if (isLocalhost) return immediate;
    final sinceLastRequest = DateTime.now().difference(lastRequest);
    if (sinceLastRequest.isNegative) {
      // There's a request scheduled in the future.
      return -sinceLastRequest + minimumDelay;
    }
    if (sinceLastRequest >= minimumDelay) return immediate;
    return minimumDelay - sinceLastRequest;
  }

  /// Before any request, this should be called.
  void markRequestStart(Duration delay) {
    _lastRequest = DateTime.now().add(delay);
  }

  void updateFromServerCheck(ServerInfoUpdate result) {
    connectionAttempts += 1;
    if (result.didNotConnect) {
      didNotConnectCount += 1;
      return;
    }
    bouncer = RobotsBouncer(result.robotsTxtContents.split('\n'),
        forRobot: robotName);
  }

  void updateFromStatusCode(int? statusCode) {
    connectionAttempts += 1;
    if (statusCode == null) {
      didNotConnectCount += 1;
      return;
    }
    switch (statusCode) {
      case 200:
        break;
      case 401:
      case 403:
        unauthorizedCount += 1;
      case 503:
        serviceUnavailableCount += 1;
      default:
        otherErrorCount += 1;
    }
  }
}

/// To be sent from Worker to main thread.
@immutable
class ServerInfoUpdate {
  final String host;
  final bool didNotConnect;
  final String robotsTxtContents;

  ServerInfoUpdate(this.host,
      {this.robotsTxtContents = '', this.didNotConnect = false});

  ServerInfoUpdate.didNotConnect(String host) : this(host, didNotConnect: true);
}
