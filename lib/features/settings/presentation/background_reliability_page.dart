import 'package:android_intent_plus/android_intent.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class BackgroundReliabilityPage extends StatelessWidget {
  const BackgroundReliabilityPage({super.key});

  Future<void> _openBatteryOptimizationSettings() async {
    const AndroidIntent intent = AndroidIntent(
      action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
    );
    await intent.launch();
  }

  Future<void> _openAppDetailsSettings() async {
    const AndroidIntent intent = AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
    );
    await intent.launch();
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
