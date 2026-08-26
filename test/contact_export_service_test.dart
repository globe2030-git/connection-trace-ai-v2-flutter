import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/contact_export_service.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// 내보내기 임시 파일이 **남지 않는지** 잰다(추가 492).
///
/// ## 🚨 왜 이걸 재나
///
/// `.vcf` 안에는 제3자(명함 주인) 개인정보가 **평문으로** 들어간다. 이 앱은
/// 명함을 암호화해 보관하는데 캐시에 평문이 남으면 그 의미가 깎인다 —
/// 이 저장소는 스캔 임시 파일에서 같은 자리를 두 번 겪었다(추가 247·253).
///
/// ⚠️ **"공유가 끝나기 전에 지워서 전송이 실패하는 것 아닌가"를 의심해 지연
/// 삭제로 바꿔 봤으나, 그게 아니었다**(2026-08-26). `share_plus` 는 넘겨받은
/// 파일을 자기 폴더로 **복사한 뒤** 공유하므로(`Share.kt:181`) 원본을 지워도
/// 상관없다. **늦게 지우면 평문만 오래 남는다.**
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

ContactModel makeContact({String name = '홍길동'}) => ContactModel(
      id: 'id',
      name: name,
      company: '가상상사',
      title: '영업팀장',
      phone: '010-0000-0001',
      email: 'example@example.invalid',
      tags: const [],
      talkingPoints: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late List<MethodCall> shareCalls;
  late List<String> pathsSeenByShare;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('export_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    shareCalls = [];
    pathsSeenByShare = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (call) async {
        shareCalls.add(call);
        // 🚨 **공유가 도는 그 시점에** 파일이 있어야 한다. 실기기에서도
        //    share_plus 가 이 안에서 자기 폴더로 복사한다.
        final args = call.arguments;
        if (args is Map) {
          final paths = args['paths'];
          if (paths is List) {
            for (final p in paths) {
              if (p is String && File(p).existsSync()) pathsSeenByShare.add(p);
            }
          }
        }
        return 'dev.fluttercommunity.plus/share/success';
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      null,
    );
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('🚨 평문이 남지 않는다', () {
    test('⭐ 공유가 끝나면 .vcf 가 지워진다', () async {
      final ok = await ContactExportService().shareAsVCard(makeContact());
      expect(ok, isTrue);
      expect(shareCalls, hasLength(1));
      final left = root.listSync().whereType<File>().toList();
      expect(
        left,
        isEmpty,
        reason: '캐시에 제3자 개인정보가 평문으로 남으면 암호화 보관의 의미가 '
            '깎인다(추가 247·253)',
      );
    });

    test('⭐ 공유가 도는 동안에는 파일이 있다', () async {
      await ContactExportService().shareAsVCard(makeContact());
      expect(
        pathsSeenByShare,
        hasLength(1),
        reason: 'share_plus 가 이 시점에 자기 폴더로 복사한다. 그 전에 '
            '지워지면 넘길 것이 없다',
      );
      expect(pathsSeenByShare.single, endsWith('홍길동.vcf'));
    });

    test('여러 번 내보내도 쌓이지 않는다', () async {
      final service = ContactExportService();
      await service.shareAsVCard(makeContact(name: '홍길동'));
      await service.shareAsVCard(makeContact(name: '김철수'));
      expect(root.listSync().whereType<File>(), isEmpty);
    });
  });

  group('내용', () {
    test('vCard 로 쓴다', () async {
      String? body;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'),
        (call) async {
          final args = call.arguments;
          if (args is Map) {
            final paths = args['paths'];
            if (paths is List && paths.isNotEmpty) {
              body = File(paths.first as String).readAsStringSync();
            }
          }
          return 'dev.fluttercommunity.plus/share/success';
        },
      );
      await ContactExportService().shareAsVCard(makeContact());
      expect(body, isNotNull);
      expect(body, startsWith('BEGIN:VCARD'));
      expect(body, contains('FN:홍길동'));
    });
  });
}
