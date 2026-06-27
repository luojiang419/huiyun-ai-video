class FavoriteImage {
  final String url;
  final String prompt;
  final int timestamp;

  FavoriteImage({
    required this.url,
    required this.prompt,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'prompt': prompt,
        'timestamp': timestamp,
      };

  factory FavoriteImage.fromJson(Map<String, dynamic> json) => FavoriteImage(
        url: json['url'],
        prompt: json['prompt'],
        timestamp: json['timestamp'],
      );
}
