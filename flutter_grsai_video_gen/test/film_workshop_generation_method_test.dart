import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/controllers/film_workshop_controller.dart';
import 'package:flutter_grsai_video_gen/models/shot.dart';
import 'package:flutter_grsai_video_gen/services/generate_logic_service.dart';

void main() {
  group('FilmWorkshopController generation reference helpers', () {
    test('uses manual reference images before matched reference images', () {
      final shot = Shot(
        shotType: '近景',
        prompt: '角色看向窗外',
        movement: '固定镜头',
        referenceImagePaths: const ['matched_a.png', 'matched_b.png'],
        manualReferenceImages: const ['manual_a.png', 'manual_b.png'],
      );

      final refs = FilmWorkshopController.buildBoundReferenceImages(shot);

      expect(refs, ['manual_a.png', 'manual_b.png']);
    });

    test(
      'falls back to matched reference images when no manual images exist',
      () {
        final shot = Shot(
          shotType: '近景',
          prompt: '角色看向窗外',
          movement: '固定镜头',
          referenceImagePaths: const ['matched_a.png', '', 'matched_a.png'],
        );

        final refs = FilmWorkshopController.buildBoundReferenceImages(shot);

        expect(refs, ['matched_a.png']);
      },
    );

    test('cleans old image mappings before deterministic prompt rebuild', () {
      final cleaned = FilmWorkshopController.cleanShotPrompt(
        '江帆是第1张提供的图片[Image1]，钥匙是第2张提供的图片[Image2]。'
        '江帆拿起红色钥匙。',
      );

      expect(cleaned, '江帆拿起红色钥匙。');
    });

    test('builds mappings from bound images without AI matching', () {
      final mapping = FilmWorkshopController.buildReferenceMappings(
        const ['hero.png', 'key.png', 'scene.png'],
        referenceImages: const ['hero.png', 'key.png', 'scene.png'],
        imageRemarks: const {0: '江帆', 1: '红色钥匙', 2: '参考图3'},
        assetRemarks: const {'key.png': '主角的钥匙'},
      );

      expect(
        mapping,
        '江帆是第1张提供的图片[Image1]，主角的钥匙是第2张提供的图片[Image2]，参考图是第3张提供的图片[Image3]',
      );
    });

    test(
      'builds shared image task request from deterministic shot bindings',
      () {
        final shot = Shot(
          shotType: '中景',
          cameraAngle: '平视',
          lighting: '自然光',
          sceneDescription: '旧工厂内部',
          action: '江帆拿起钥匙',
          movement: '固定镜头',
          prompt: '江帆是第1张提供的图片[Image1]。江帆拿起钥匙。',
          referenceImagePaths: const ['matched_a.png'],
          manualReferenceImages: const ['manual_a.png', 'manual_b.png'],
          assetRemarks: const {'manual_a.png': '江帆', 'manual_b.png': '旧钥匙'},
        );

        final request = FilmWorkshopController.buildShotGenerationTask(
          shot: shot,
          selectedModel: 'gpt-image-1',
          selectedAspectRatio: '16:9',
          selectedImageSize: '2K',
          selectedImageQuality: 'high',
          sampleSteps: 28,
          referenceImages: const ['matched_a.png'],
          imageRemarks: const {0: '江帆'},
        );

        expect(request, isA<GenerateImageTaskRequest>());
        expect(request.model, 'gpt-image-1');
        expect(request.aspectRatio, '16:9');
        expect(request.imageSize, '2K');
        expect(request.imageQuality, 'high');
        expect(request.sampleSteps, 28);
        expect(request.referenceImages, isEmpty);
        expect(request.referenceImagePaths, ['manual_a.png', 'manual_b.png']);
        expect(request.prompt, contains('江帆是第1张提供的图片[Image1]'));
        expect(request.prompt, contains('旧钥匙是第2张提供的图片[Image2]'));
        expect(request.prompt, contains('[景别]'));
        expect(request.prompt, contains('中景'));
        expect(request.prompt, contains('[画面描述]'));
        expect(request.prompt, contains('江帆拿起钥匙。'));
      },
    );
  });
}
