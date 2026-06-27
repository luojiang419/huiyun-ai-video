class ErrorTranslator {
  static String translate(String message) {
    if (message.isEmpty) return '未知错误';

    final normalized = message
        .replaceFirst(RegExp(r'^Exception:\s*', caseSensitive: false), '')
        .trim();
    final lower = normalized.toLowerCase();
    if (lower == 'error') {
      return '生成服务异常，请尝试重新提交';
    }
    if (lower == 'apikey error' ||
        lower == 'api key error' ||
        lower.contains('invalid api key') ||
        lower.contains('invalid apikey')) {
      return 'API Key 无效或未配置，请检查图片生成 API Key';
    }

    final translations = {
      // API文档中的错误类型 (failure_reason)
      'output_moderation': '生成内容违规，请修改提示词',
      'input_moderation': '输入提示词违规，请修改后重试',

      // API文档中的错误详情 (error)
      'Invalid input parameters': '输入参数无效',
      'model_not_found': '模型未找到或不可用',
      'insufficient_quota': '账户余额不足',
      'insufficient_credits': '积分不足',

      // 常见错误信息
      'This content may violate our policies': '此内容可能违反我们的政策',
      'You can try changing the prompt words or changing the image, and then try again':
          '您可以尝试更改提示词或更换图片后重试',
      'timeout': '请求超时',
      'Timeout': '请求超时',
      'network error': '网络错误',
      'Network error': '网络错误',
      'failed to fetch': '网络请求失败',
      'Failed to fetch': '网络请求失败',
      'Connection refused': '连接被拒绝',
      'Connection timeout': '连接超时',
      'No internet connection': '无网络连接',
    };

    String result = normalized.isEmpty ? message : normalized;
    translations.forEach((en, zh) {
      result = result.replaceAll(RegExp(en, caseSensitive: false), zh);
    });

    return result;
  }
}
