class GalleryImage {
  final String filename;
  final String path;
  final String url;
  final int timestamp;
  final String prompt;

  GalleryImage({
    required this.filename,
    required this.path,
    required this.url,
    required this.timestamp,
    this.prompt = '',
  });

  Map<String, dynamic> toJson() => {
    'filename': filename,
    'path': path,
    'url': url,
    'timestamp': timestamp,
    'prompt': prompt,
  };

  factory GalleryImage.fromJson(Map<String, dynamic> json) => GalleryImage(
    filename: json['filename'],
    path: json['path'],
    url: json['url'],
    timestamp: json['timestamp'],
    prompt: json['prompt'] ?? '',
  );
}
