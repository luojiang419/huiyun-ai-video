# 修复API错误处理方法

## 问题描述

当API返回错误时，前端显示"生成完成，耗时1秒"而非具体错误信息。

## 根本原因

API返回 `status: 'failed'` 时，流式响应立即结束，但前端未检测失败状态，误判为成功。

## 解决方案

### 1. 修改 api_service.dart

**文件路径：** `lib/services/api_service.dart`

**修改位置：** 第88-125行的 `generateImage` 方法

**修改内容：**

```dart
await for (var chunk in responseStream.stream.map((bytes) => utf8.decode(bytes))) {
  final lines = chunk.split('\n');
  for (var line in lines) {
    if (line.startsWith('data: ')) {
      try {
        final data = jsonDecode(line.substring(6));
        lastProgress = GenerateProgress.fromJson(data);

        // 检测失败状态并立即返回
        if (lastProgress.status == 'failed') {
          yield lastProgress;
          return;
        }

        if (lastProgress.status != 'succeeded') {
          yield lastProgress;
        }
      } catch (e) {
        continue;
      }
    }
  }
}

// 处理流结束后的状态
if (lastProgress != null && lastProgress.status == 'succeeded' && lastProgress.results != null) {
  final localPaths = <String>[];
  for (final url in lastProgress.results!) {
    final localPath = await _downloadAndSaveImage(url);
    localPaths.add(localPath);
  }
  yield GenerateProgress(
    status: 'succeeded',
    progress: 100,
    results: localPaths,
    error: null,
  );
} else if (lastProgress != null && lastProgress.status == 'failed') {
  yield lastProgress;
}
```

**关键改动：**
1. 添加失败状态检测：`if (lastProgress.status == 'failed')`
2. 失败时立即返回错误信息
3. 流结束后再次检查失败状态

### 2. 修改 generate_screen.dart

**文件路径：** `lib/screens/generate_screen.dart`

**修改位置：** 第298-341行的 `_handleGenerate` 方法

**修改内容：**

```dart
try {
  await for (final progress in apiService.generateImage(
    apiUrl: defaultConfig.url,
    apiKey: defaultConfig.key,
    model: _selectedModel,
    prompt: prompt,
    aspectRatio: _aspectRatio,
    imageSize: _imageSize,
    urls: urls,
  )) {
    // 检测失败状态
    if (progress.status == 'failed') {
      timer.cancel();
      final errorMsg = progress.error ?? '未知错误';
      await ref.read(currentSessionProvider.notifier).updateMessage(
        messageIndex,
        Message(type: 'assistant', text: '生成失败: ${ErrorTranslator.translate(errorMsg)}', images: []),
      );
      await ref.read(creditsProvider.notifier).fetchCredits();
      return;
    }

    if (progress.results != null) {
      results.addAll(progress.results!);
    }
  }

  timer.cancel();
  final totalTime = DateTime.now().difference(startTime).inSeconds;
  await ref.read(currentSessionProvider.notifier).updateMessage(
    messageIndex,
    Message(
      type: 'assistant',
      text: '生成完成，耗时 ${totalTime}s',
      images: results,
      params: {'model': _selectedModel, 'aspectRatio': _aspectRatio, 'imageSize': _imageSize, 'time': totalTime},
    ),
  );
  await ref.read(creditsProvider.notifier).fetchCredits();
} catch (e) {
  timer.cancel();
  await ref.read(currentSessionProvider.notifier).updateMessage(
    messageIndex,
    Message(type: 'assistant', text: '生成失败: ${ErrorTranslator.translate(e.toString())}', images: []),
  );
  await ref.read(creditsProvider.notifier).fetchCredits();
}
```

**关键改动：**
1. 在接收进度时检测 `status == 'failed'`
2. 失败时显示具体错误信息
3. 成功时显示"生成完成，耗时 Xs"
4. 无论成功或失败都刷新积分余额

## API错误响应格式

根据API文档，错误响应包含：

```json
{
  "status": "failed",
  "progress": 0,
  "failure_reason": "input_moderation",
  "error": "输入内容违规"
}
```

**错误类型：**
- `input_moderation`: 输入违规
- `output_moderation`: 输出违规
- `error`: 其他错误

## 修复效果

### 修复前
- 显示："生成完成，耗时1秒"
- 无法看到具体错误原因

### 修复后
- 显示："生成失败: [具体错误信息]"
- 错误信息经过翻译为中文
- 失败后自动刷新积分余额

## 适用项目

- flutter_grsai_image_gen (原版)
- flutter_grsai_image_gen_sales (公测版)
- flutter_grsai_image_gen_android (安卓版)
- flutter_grsai_image_gen_sales_android (安卓公测版)

## 相关文件

- [api_service.dart](lib/services/api_service.dart)
- [generate_screen.dart](lib/screens/generate_screen.dart)
- [error_translator.dart](lib/utils/error_translator.dart)
