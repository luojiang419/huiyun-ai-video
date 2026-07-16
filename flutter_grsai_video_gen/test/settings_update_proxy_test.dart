import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/models/settings.dart';
import 'package:flutter_grsai_video_gen/services/update_service.dart';

void main() {
  test('settings defaults to automatic updates and automatic proxy', () {
    final settings = Settings.fromJson({
      'uploadMethod': Settings.uploadMethodBase64,
    });

    expect(settings.updatePolicy, Settings.updatePolicyAutomatic);
    expect(settings.updateNetworkMode, Settings.updateNetworkAutomaticProxy);
    expect(settings.updateManualProxyUrl, Settings.defaultUpdateManualProxyUrl);
  });

  test('settings migrates legacy custom proxy fields', () {
    final settings = Settings.fromJson({
      'updateDownloadProxyMode': 'custom_proxy',
      'updateDownloadProxyAddress': '127.0.0.1:7890',
    });

    expect(settings.updateNetworkMode, Settings.updateNetworkManualProxy);
    expect(settings.updateManualProxyUrl, '127.0.0.1:7890');
  });

  test('all update policy and network mode combinations round-trip', () {
    const policies = [
      Settings.updatePolicyAutomatic,
      Settings.updatePolicyManual,
      Settings.updatePolicyDisabled,
    ];
    const networkModes = [
      Settings.updateNetworkAutomaticProxy,
      Settings.updateNetworkManualProxy,
      Settings.updateNetworkDirect,
    ];

    for (final policy in policies) {
      for (final networkMode in networkModes) {
        final settings = Settings.defaultSettings().copyWith(
          updatePolicy: policy,
          updateNetworkMode: networkMode,
          updateManualProxyUrl: 'http://127.0.0.1:7890',
        );
        final decoded = Settings.fromJson(settings.toJson());
        expect(decoded.updatePolicy, policy);
        expect(decoded.updateNetworkMode, networkMode);
        expect(decoded.updateManualProxyUrl, 'http://127.0.0.1:7890');
      }
    }
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

  test('direct network mode always carries no proxy', () {
    const settings = UpdateDownloadProxySettings(
      mode: Settings.updateNetworkDirect,
      customAddress: 'http://127.0.0.1:7890',
    );

    expect(settings.mode, Settings.updateNetworkDirect);
    expect(UpdateService.buildCustomProxyRule('not-a-proxy'), 'DIRECT');
  });
}
