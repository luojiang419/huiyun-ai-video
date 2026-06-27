import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/services/api_service.dart';
import 'package:flutter_grsai_video_gen/services/film_workshop_service.dart';

void main() {
  group('FilmReferenceImageAnalysis', () {
    test(
      'builds match description with name, asset metadata and vision text',
      () {
        const analysis = FilmReferenceImageAnalysis(
          imagePath: r'G:\data\assets\jiangfan_front.png',
          displayName: '江帆-正面',
          assetName: '江帆',
          assetCategory: '人物',
          assetDescription: '男主角，灰色风衣',
          imageDescription: '正面半身视图',
          visualDescription: '视觉模型解析：年轻男性，正面站立，灰色风衣，适合中近景。',
        );

        final description = analysis.matchDescription;

        expect(description, contains('名称/备注: 江帆-正面'));
        expect(description, contains('所属资产: 江帆'));
        expect(description, contains('资产类别: 人物'));
        expect(description, contains('图片视图说明: 正面半身视图'));
        expect(description, contains('年轻男性'));
      },
    );

    test('uses filename when display name is empty', () {
      const analysis = FilmReferenceImageAnalysis(
        imagePath: r'G:\data\assets\red_key.png',
        displayName: '',
        visualDescription: '红色钥匙，道具特写。',
      );

      expect(analysis.effectiveName, 'red_key');
      expect(analysis.matchDescription, contains('文件名: red_key.png'));
    });
  });

  group('FilmWorkshopService.parseMatchResult', () {
    test(
      'parses the final imageIndexes JSON when other JSON appears earlier',
      () async {
        final service = FilmWorkshopService(ApiService());

        final result = await service.parseMatchResult(
          '分析过程：参考图画像 {"category":"人物","nameHint":"江帆"}。\n'
          '最终结果：{"imageIndexes":[2, 4]}',
        );

        expect(result, [2, 4]);
      },
    );
  });
}
