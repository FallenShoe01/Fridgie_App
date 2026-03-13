import 'package:android_intent_plus/android_intent.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class BackgroundReliabilityPage extends StatelessWidget {
  const BackgroundReliabilityPage({super.key});

  static const String _appPackage = 'com.fridgie_app';

  Future<void> _openBatteryOptimizationSettings() async {
    const AndroidIntent intent = AndroidIntent(
      action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
    );
    await intent.launch();
  }

  Future<void> _openAppDetailsSettings() async {
    const AndroidIntent intent = AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:$_appPackage',
    );
    await intent.launch();
  }

  Future<void> _openExactAlarmSettings() async {
    try {
      const AndroidIntent intent = AndroidIntent(
        action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
        data: 'package:$_appPackage',
      );
      await intent.launch();
    } catch (_) {
      try {
        const AndroidIntent appNotifIntent = AndroidIntent(
          action: 'android.settings.APP_NOTIFICATION_SETTINGS',
          arguments: <String, dynamic>{
            'android.provider.extra.APP_PACKAGE': _appPackage,
          },
        );
        await appNotifIntent.launch();
      } catch (_) {
        await _openAppDetailsSettings();
      }
    }
  }

  Future<void> _openMiuiAutostartSettings() async {
    try {
      const AndroidIntent miuiIntent = AndroidIntent(
        action: 'miui.intent.action.OP_AUTO_START',
      );
      await miuiIntent.launch();
    } catch (_) {
      await _openAppDetailsSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('background_reliability_title'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('background_reliability_intro'.tr()),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: _openBatteryOptimizationSettings,
            child: Text('background_reliability_battery_button'.tr()),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _openAppDetailsSettings,
            child: Text('background_reliability_details_button'.tr()),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _openExactAlarmSettings,
            child: Text('background_reliability_exact_alarm_button'.tr()),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _openMiuiAutostartSettings,
            child: Text('background_reliability_autostart_button'.tr()),
          ),
          const SizedBox(height: 16),
          Text(
            'background_reliability_xiaomi_title'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text('background_reliability_xiaomi_body'.tr()),
        ],
      ),
    );
  }
}
