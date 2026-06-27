import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/models/settings.dart';
import 'package:flutter_grsai_video_gen/services/update_service.dart';

void main() {
  test('settings defaults update download to system proxy', () {
    final settings = Settings.fromJson({
      'uploadMethod': Settings.uploadMethodBase64,
    });

    expect(
      settings.updateDownloadProxyMode,
      Settings.updateDownloadProxySystem,
    );
    expect(
      settings.updateDownloadProxyAddress,
      Settings.defaultUpdateDownloadProxyAddress,
    );
  });

  test('settings keeps custom update download proxy', () {
    final settings = Settings.fromJson({
      'updateDownloadProxyMode': Settings.updateDownloadProxyCustom,
      'updateDownloadProxyAddress': '127.0.0.1:7890',
    });

    expect(
      settings.updateDownloadProxyMode,
      Settings.updateDownloadProxyCustom,
    );
    expect(settings.updateDownloadProxyAddress, '127.0.0.1:7890');
  });

  test('custom proxy address builds HttpClient proxy rule', () {
    expect(
      UpdateService.buildCustomProxyRule('127.0.0.1:7890'),
      'PROXY 127.0.0.1:7890',
    );
    expect(
      UpdateService.buildCustomProxyRule('http://127.0.0.1:7890'),
      'PROXY 127.0.0.1:7890',
    );
    expect(
      UpdateService.buildCustomProxyRule('socks5://127.0.0.1:7890'),
      'SOCKS 127.0.0.1:7890',
    );
  });

  test('localhost update downloads are never proxied', () {
    expect(UpdateService.isLocalUri(Uri.parse('http://127.0.0.1:8080')), true);
    expect(UpdateService.isLocalUri(Uri.parse('http://localhost:8080')), true);
    expect(UpdateService.isLocalUri(Uri.parse('https://github.com')), false);
  });
}
