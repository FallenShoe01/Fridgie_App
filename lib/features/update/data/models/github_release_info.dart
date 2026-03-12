class GithubReleaseInfo {
  const GithubReleaseInfo({
    required this.tag,
    required this.name,
    required this.body,
    required this.apkUrl,
    required this.apkName,
  });

  final String tag;
  final String name;
  final String body;
  final String apkUrl;
  final String apkName;
}
