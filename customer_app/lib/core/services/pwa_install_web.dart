import 'dart:js_interop';

@JS('_getPwaInstallAvailable')
external JSBoolean _getPwaInstallAvailable();

@JS('_getPwaIsStandalone')
external JSBoolean _getPwaIsStandalone();

@JS('triggerPwaInstall')
external JSPromise<JSString> _triggerPwaInstall();

enum PwaInstallState { alreadyInstalled, available, unavailable }

class PwaInstallService {
  PwaInstallState get state {
    try {
      if (_getPwaIsStandalone().toDart) return PwaInstallState.alreadyInstalled;
      if (_getPwaInstallAvailable().toDart) return PwaInstallState.available;
    } catch (_) {}
    return PwaInstallState.unavailable;
  }

  Future<bool> triggerInstall() async {
    try {
      final result = await _triggerPwaInstall().toDart;
      return result.toDart == 'accepted';
    } catch (_) {
      return false;
    }
  }
}
