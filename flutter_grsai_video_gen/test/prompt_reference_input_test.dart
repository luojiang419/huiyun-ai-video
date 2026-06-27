import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/utils/prompt_text_insertion.dart';
import 'package:flutter_grsai_video_gen/utils/reference_image_file_name.dart';

void main() {
  group('insertTextAtSelection', () {
    test('inserts text at a valid cursor position', () {
      final next = insertTextAtSelection(
        value: const TextEditingValue(
          text: '开头结尾',
          selection: TextSelection.collapsed(offset: 2),
        ),
        insertion: '根据 test.png，生成一组连续的分镜图',
      );

      expect(next.text, '开头根据 test.png，生成一组连续的分镜图结尾');
      expect(next.selection.baseOffset, 2 + '根据 test.png，生成一组连续的分镜图'.length);
    });

    test('appends text when selection is invalid', () {
      final next = insertTextAtSelection(
        value: const TextEditingValue(
          text: '已有内容',
          selection: TextSelection.collapsed(offset: -1),
        ),
        insertion: '根据 image.png，生成一组连续的分镜图',
      );

      expect(next.text, '已有内容根据 image.png，生成一组连续的分镜图');
      expect(next.selection.baseOffset, next.text.length);
    });

    test('inserts into an empty input', () {
      final next = insertTextAtSelection(
        value: const TextEditingValue(),
        insertion: '根据 image.png，生成一组连续的分镜图',
      );

      expect(next.text, '根据 image.png，生成一组连续的分镜图');
      expect(next.selection.baseOffset, next.text.length);
    });
  });

  group('reference copy file names', () {
    test('keeps original display name from Windows path', () {
      expect(displayFileNameFromPath(r'G:\data\output\角色.png'), '角色.png');
    });

    test('builds unique safe copy file name without losing extension', () {
      expect(
        buildReferenceCopyFileName('bad:name.png', 123),
        'ref_123_bad_name.png',
      );
      expect(buildReferenceCopyFileName('image', 456), 'ref_456_image.png');
    });
  });
}
