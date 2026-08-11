enum PwaInstallState { alreadyInstalled, available, unavailable }

class PwaInstallService {
  PwaInstallState get state => PwaInstallState.unavailable;
  Future<bool> triggerInstall() async => false;
}
