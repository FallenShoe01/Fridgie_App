class LookupResult {
  const LookupResult({
    required this.barcode,
    required this.name,
    this.category,
    this.imageUrl,
    this.provider,
    this.payloadJson,
  });

  final String barcode;
  final String name;
  final String? category;
  final String? imageUrl;
  final String? provider;
  final String? payloadJson;
}
