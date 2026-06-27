String displayFileNameFromPath(String imagePath) {
  final parts = imagePath.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? imagePath : parts.last;
}

String buildReferenceCopyFileName(String originalFileName, int timestamp) {
  final dotIndex = originalFileName.lastIndexOf('.');
  final rawBase = dotIndex > 0
      ? originalFileName.substring(0, dotIndex)
      : originalFileName;
  final rawExt = dotIndex > 0 ? originalFileName.substring(dotIndex) : '.png';
  final safeBase = _sanitizeFileNamePart(rawBase);
  final safeExt = RegExp(r'^\.[A-Za-z0-9]{1,8}$').hasMatch(rawExt)
      ? rawExt.toLowerCase()
      : '.png';
  return 'ref_${timestamp}_$safeBase$safeExt';
}

String _sanitizeFileNamePart(String value) {
  final sanitized = value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .trim();
  return sanitized.isEmpty ? 'image' : sanitized;
}
