import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_grsai_video_gen/models/asset.dart';
import 'package:flutter_grsai_video_gen/models/film_scene_asset.dart';
import 'package:flutter_grsai_video_gen/models/film_tab.dart';
import 'package:flutter_grsai_video_gen/models/shot.dart';
import 'package:flutter_grsai_video_gen/services/api_service.dart';
import 'package:flutter_grsai_video_gen/services/film_workshop_service.dart';

void main() {
  group('Film scene asset extraction', () {
    test('parses and deduplicates AI assets with source shot indexes', () {
      final assets = FilmWorkshopService.parseSceneAssetExtraction('''
分析过程...
{"assets":[
  {"name":"江帆","category":"人物","description":"穿灰色风衣的男主角","sourceShotIndexes":[0,1]},
  {"name":"江帆","category":"character","description":"穿灰色风衣的男主角，脸上有雨水","sourceShotIndexes":[2]},
  {"name":"旧工厂","category":"场景","description":"废弃厂房内部","sourceShotIndexes":[0]},
  {"name":"红色钥匙","category":"prop","description":"红色金属钥匙","sourceShotIndexes":[1]}
]}
''');

      expect(assets, hasLength(3));
      final hero = assets.firstWhere((asset) => asset.name == '江帆');
      expect(hero.category, 'Person');
      expect(hero.sourceShotIndexes, [0, 1, 2]);
      expect(hero.description, contains('雨水'));
      expect(
        assets.map((asset) => asset.category),
        containsAll(['Scene', 'Prop']),
      );
    });

    test('repairs lightly malformed AI JSON before parsing assets', () {
      final assets = FilmWorkshopService.parseSceneAssetExtraction(r'''
{"assets":[
  {"name":"反派头目","category":"Person","description":"黑色长风衣，手持金属钢笔武器","sourceShotIndexes":[6,7]},
  \{"name钢笔武器","category":"Prop","description":"表面刻有纹路的黑色金属钢笔武器，可作为近景关键道具","sourceShotIndexes":[7]\}
]}
''');

      expect(assets, hasLength(2));
      final prop = assets.firstWhere((asset) => asset.name == '钢笔武器');
      expect(prop.category, 'Prop');
      expect(prop.sourceShotIndexes, [7]);
      expect(prop.description, contains('黑色金属'));
    });

    test('repairs name fields separated by whitespace instead of colon', () {
      final assets = FilmWorkshopService.parseSceneAssetExtraction(r'''
{"assets":[
  {"name":"瘦猴","category":"Person","description":"身材瘦小，眼神狡黠，躲在废墟后监视","sourceShotIndexes":[4,5]},
  {"name 瘦猴的灰色夹克","category":"Prop","description":"破旧灰色夹克，袖口磨损明显","sourceShotIndexes":[4,5]}
]}
''');

      expect(assets.map((asset) => asset.name), contains('瘦猴的灰色夹克'));
    });

    test('builds stable six-view names and sanitizes filenames', () {
      expect(FilmSceneAssetViews.names, [
        '正面',
        '左侧',
        '右侧',
        '45度左侧',
        '45度右侧',
        '背面',
      ]);
      expect(
        FilmWorkshopService.buildSceneAssetFileName('江帆:主角', '45度左侧'),
        '江帆_主角-45度左侧.png',
      );
    });

    test('scene assets only require a primary reference view', () {
      const sceneAsset = FilmSceneAsset(
        id: 'scene-ruins',
        name: '积雪工业废墟',
        category: 'Scene',
        description: '被厚积雪覆盖的废弃工业区域',
        viewImages: {'正面': 'scene-front.png'},
      );
      const personAsset = FilmSceneAsset(
        id: 'scene-hero',
        name: '江帆',
        category: 'Person',
        description: '灰色风衣男主角',
        viewImages: {'正面': 'hero-front.png'},
      );

      expect(
        FilmSceneAssetViews.requiredForCategory('Scene').map((v) => v.name),
        ['正面'],
      );
      expect(sceneAsset.isComplete, isTrue);
      expect(personAsset.isComplete, isFalse);
    });

    test(
      'builds generation sequence with front view as the consistency base',
      () {
        expect(
          FilmSceneAssetViews.buildGenerationSequence(
            'Person',
            onlyViewName: '左侧',
            hasFrontImage: false,
          ).map((view) => view.name),
          ['正面', '左侧'],
        );
        expect(
          FilmSceneAssetViews.buildGenerationSequence(
            'Person',
            onlyViewName: '左侧',
            hasFrontImage: true,
          ).map((view) => view.name),
          ['左侧'],
        );
        expect(
          FilmSceneAssetViews.buildGenerationSequence(
            'Scene',
          ).map((view) => view.name),
          ['正面'],
        );
      },
    );

    test('filters transient props and generic costumes from extraction', () {
      final assets = FilmWorkshopService.parseSceneAssetExtraction('''
{"assets":[
  {"name":"江帆","category":"Person","description":"末日求生的成年男性，面部有疤痕","sourceShotIndexes":[0,1,2,3]},
  {"name":"江帆御寒外套","category":"Costume","description":"末日款耐磨旧御寒外套，有使用磨损痕迹","sourceShotIndexes":[0,1,2,3]},
  {"name":"包裹雪人的外套","category":"Costume","description":"厚实的旧冬装外套，用于包裹固定雪人","sourceShotIndexes":[0,2,3]},
  {"name":"雪地摩托车","category":"Prop","description":"老旧越野款摩托车，表面有积雪和使用痕迹","sourceShotIndexes":[0,1,2,3]},
  {"name":"雪人","category":"Prop","description":"被外套严实包裹的雪人，是主角末日求生的陪伴物","sourceShotIndexes":[0,1,2,3]},
  {"name":"干燥树枝","category":"Prop","description":"拾荒所得的生存物资，用于生火取暖","sourceShotIndexes":[0]},
  {"name":"废弃木屑","category":"Prop","description":"拾荒所得的生存物资，用作生火助燃物","sourceShotIndexes":[0]},
  {"name":"可食用野菜","category":"Prop","description":"雪地废墟周边的求生食材","sourceShotIndexes":[0]},
  {"name":"绿色种子","category":"Prop","description":"体积小巧、饱满有光泽的绿色植物种子，是主角收藏的希望象征物","sourceShotIndexes":[0]},
  {"name":"钢管武器","category":"Prop","description":"金属材质的长条钢管，是反派团伙使用的武器","sourceShotIndexes":[1]},
  {"name":"废弃车辆残骸","category":"Prop","description":"末日废弃的机动车残骸，部分被积雪掩埋","sourceShotIndexes":[3]},
  {"name":"积雪覆盖的工业废墟","category":"Scene","description":"被厚积雪覆盖的废弃工业区域","sourceShotIndexes":[0,1,2]}
]}
''');

      expect(assets.map((asset) => asset.name), isNot(contains('江帆御寒外套')));
      expect(assets.map((asset) => asset.name), isNot(contains('包裹雪人的外套')));
      expect(assets.map((asset) => asset.name), isNot(contains('干燥树枝')));
      expect(assets.map((asset) => asset.name), isNot(contains('废弃木屑')));
      expect(assets.map((asset) => asset.name), isNot(contains('可食用野菜')));
      expect(assets.map((asset) => asset.name), isNot(contains('废弃车辆残骸')));
      expect(
        assets.map((asset) => asset.name),
        containsAll(['江帆', '雪地摩托车', '雪人', '绿色种子', '钢管武器']),
      );
    });

    test(
      'keeps distinctive costume assets when design itself is important',
      () {
        final assets = FilmWorkshopService.parseSceneAssetExtraction('''
{"assets":[
  {"name":"花旦","category":"Person","description":"戏班女主角","sourceShotIndexes":[0]},
  {"name":"花旦红金戏服","category":"Costume","description":"红金配色戏服，带刺绣、水袖和金属头冠","sourceShotIndexes":[0]}
]}
''');

        expect(assets.map((asset) => asset.name), contains('花旦红金戏服'));
      },
    );

    test(
      'extractSceneAssets uses structured JSON chat before parsing',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        Map<String, dynamic>? submittedBody;

        server.listen((request) async {
          request.response.headers.contentType = ContentType.json;
          submittedBody =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          request.response.write(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'assets': [
                        {
                          'name': '江帆',
                          'category': 'Person',
                          'description': '骑摩托车的末日男性，侧脸有疤痕',
                          'sourceShotIndexes': [0],
                        },
                        {
                          'name': '绿色种子',
                          'category': 'Prop',
                          'description': '饱满有光泽的绿色小种子，象征希望',
                          'sourceShotIndexes': [0],
                        },
                      ],
                    }),
                  },
                },
              ],
            }),
          );
          await request.response.close();
        });

        try {
          final apiOrigin = 'http://${server.address.address}:${server.port}';
          final service = FilmWorkshopService(ApiService());
          final assets = await service.extractSceneAssets(
            apiUrl: apiOrigin,
            apiKey: 'test-key',
            model: 'deepseek-v4-flash',
            fullScript: '江帆骑着摩托车，在雪地废墟中发现绿色种子。',
            shots: [
              Shot(
                shotType: '中景',
                prompt: '江帆骑着摩托车，在雪地废墟中发现绿色种子。',
                movement: '固定镜头',
              ),
            ],
          );

          expect(submittedBody, isNotNull);
          expect(submittedBody!['response_format'], {'type': 'json_object'});
          expect(submittedBody!['stream'], isNull);
          expect(
            assets.map((asset) => asset.name),
            containsAll(['江帆', '绿色种子']),
          );
        } finally {
          await server.close(force: true);
        }
      },
    );
  });

  group('Film scene asset storage mapping', () {
    test(
      'maps front view to Asset.imagePath and other views to Asset.images',
      () {
        const sceneAsset = FilmSceneAsset(
          id: 'scene-hero',
          name: '江帆',
          category: 'Person',
          description: '灰色风衣男主角',
          viewImages: {
            '正面': 'front.png',
            '左侧': 'left.png',
            '右侧': 'right.png',
            '45度左侧': 'left45.png',
            '45度右侧': 'right45.png',
            '背面': 'back.png',
          },
        );

        final asset = FilmWorkshopService.buildGlobalAssetFromSceneAsset(
          sceneAsset: sceneAsset,
          assetId: 'global-hero',
        );

        expect(asset.id, 'global-hero');
        expect(asset.imagePath, 'front.png');
        expect(asset.images, hasLength(5));
        expect(asset.images.map((image) => image.name), contains('江帆-45度左侧'));
      },
    );

    test('round trips scene assets through FilmTab JSON', () {
      const sceneAsset = FilmSceneAsset(
        id: 'scene-key',
        name: '红色钥匙',
        category: 'Prop',
        description: '红色金属钥匙',
        viewImages: {'正面': 'key-front.png'},
        assetId: 'global-key',
      );

      final restored = FilmTab.fromJson(
        FilmTab(
          id: 'tab',
          name: '默认标签',
          sceneAssets: const [sceneAsset],
        ).toJson(),
      );

      expect(restored.sceneAssets, hasLength(1));
      expect(restored.sceneAssets.first.name, '红色钥匙');
      expect(restored.sceneAssets.first.assetId, 'global-key');
    });
  });

  group('Film scene asset matching', () {
    test(
      'combines slot references and scene asset views without duplicate paths',
      () {
        final references = FilmWorkshopService.buildMatchingReferenceImages(
          slotReferenceImages: const ['', 'hero-front.png'],
          slotRemarks: const {0: '空槽', 1: '江帆主图'},
          slotAssetIds: const {1: 'asset-hero'},
          globalAssets: [
            Asset(
              id: 'asset-hero',
              name: '江帆',
              category: 'Person',
              imagePath: 'hero-front.png',
              description: '灰色风衣',
              images: [
                AssetRefImage(
                  path: 'shared-left.png',
                  name: '江帆-左侧',
                  description: '左侧视图',
                ),
              ],
            ),
          ],
          sceneAssets: const [
            FilmSceneAsset(
              id: 'scene-hero',
              name: '江帆',
              category: 'Person',
              description: '灰色风衣',
              viewImages: {
                '正面': 'scene-front.png',
                '左侧': 'shared-left.png',
                '右侧': 'scene-right.png',
              },
            ),
          ],
        );

        final paths = references.map((item) => item.imagePath).toList();
        expect(paths.toSet(), hasLength(paths.length));
        expect(
          paths,
          containsAll(['hero-front.png', 'shared-left.png', 'scene-front.png']),
        );
        expect(references.map((item) => item.effectiveName), contains('江帆-正面'));
      },
    );

    test('copyWith matching update preserves shot fields', () {
      final shot = Shot(
        shotNumber: '01',
        shotName: '雨夜回头',
        shotType: '近景',
        cameraAngle: '低机位',
        lighting: '冷色雨夜',
        sceneDescription: '旧工厂外',
        sceneDetails: '地面积水',
        textInFrame: '无',
        objectState: '钥匙沾水',
        characterName: '江帆',
        costume: '灰色风衣',
        action: '回头',
        expression: '警觉',
        props: '红色钥匙',
        prompt: '江帆在雨中回头',
        movement: '缓慢推进',
      );

      final updated = shot.copyWith(
        prompt: '江帆-正面是第1张提供的图片[Image1]。江帆在雨中回头',
        referenceImagePaths: const ['front.png'],
        manualReferenceImages: const [],
        assetRemarks: const {'front.png': '江帆-正面'},
      );

      expect(updated.shotType, shot.shotType);
      expect(updated.cameraAngle, shot.cameraAngle);
      expect(updated.sceneDescription, shot.sceneDescription);
      expect(updated.characterName, shot.characterName);
      expect(updated.costume, shot.costume);
      expect(updated.props, shot.props);
      expect(updated.referenceImagePaths, ['front.png']);
      expect(updated.assetRemarks!['front.png'], '江帆-正面');
    });
  });
}
