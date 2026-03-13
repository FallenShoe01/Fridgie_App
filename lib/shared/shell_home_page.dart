import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class ShellHomePage extends StatelessWidget {
  const ShellHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text('app_title'.tr()),
      ),
    );
  }
}
