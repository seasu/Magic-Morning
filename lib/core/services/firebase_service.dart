import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class FirebaseService {
  static FirebaseCrashlytics get crashlytics => FirebaseCrashlytics.instance;

  static void log(String message) {
    crashlytics.log(message);
  }

  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    await crashlytics.recordError(
      error,
      stack,
      reason: reason,
      fatal: fatal,
    );
  }
}
