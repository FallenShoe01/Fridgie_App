class UpdateCheckResult {
  const UpdateCheckResult({
    required this.isUpdateAvailable,
    this.remoteVersion,
    this.releaseNotes,
    this.apkUrl,
    this.apkName,
  });

  final bool isUpdateAvailable;
  final String? remoteVersion;
  final String? releaseNotes;
  final String? apkUrl;
  final String? apkName;
}
