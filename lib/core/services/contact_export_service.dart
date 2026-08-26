import 'dart:io';

import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/contact_model.dart';
import '../utils/vcard_util.dart';

/// 명함을 **폰 주소록으로 내보낸다**(추가 492).
///
/// vCard(`.vcf`) 파일을 만들어 **OS 공유 시트에 넘기는 것**이 전부다. 연락처
/// 앱이 그 파일을 받아 *"연락처에 추가"*를 띄운다.
///
/// ## 왜 연락처 플러그인을 안 쓰나
///
/// | | 새 플러그인(flutter_contacts 등) | **이 방식** |
/// |---|---|---|
/// | 새 의존성 | 필요 | **없다** — `share_plus`·`path_provider` 가 이미 있다 |
/// | 권한 | `WRITE_CONTACTS` / `NSContactsUsageDescription` | **없다** |
/// | 스토어 심사 | 연락처 권한은 사유 설명이 필요하다 | **해당 없음** |
/// | 이용자가 보는 것 | 우리가 몰래 쓴다 | **어디로 보낼지 본인이 고른다** |
///
/// 마지막 줄이 중요하다. 주소록에 직접 쓰면 **앱이 이용자 주소록을 만질 수 있는
/// 상태**가 되지만, 공유 시트는 **이용자가 그 자리에서 목적지를 고른다.**
///
/// 📌 저장소에 선례가 있다 — 같은 형식 `.vcf`(224 bytes)를 카카오톡으로 보내
/// 열었더니 *"연락처에 가져오기"*가 실제로 떴다(2026-08-25 폴드 실측,
/// HANDOFF 644~666행). ⚠️ **iOS 는 아직 실측 전이다.**
///
/// ## 🚨 임시 파일을 반드시 지운다
///
/// `.vcf` 안에는 **제3자(명함 주인) 개인정보가 평문으로** 들어간다. 이 앱은
/// 명함을 암호화해 보관하는데, 캐시에 평문이 남으면 **그 암호화의 의미가
/// 깎인다.** 이 저장소는 스캔 임시 파일에서 같은 자리를 두 번 겪었다
/// (backlog 추가 247·253).
///
/// 그래서 공유가 끝나면 `finally` 에서 지운다. 공유를 취소해도, 예외가 나도
/// 지운다.
class ContactExportService {
  /// 명함 하나를 vCard 로 만들어 공유 시트에 넘긴다.
  ///
  /// 공유 시트를 띄웠으면 `true`. 파일을 만들지 못했거나 공유가 실패하면
  /// `false` — 부르는 쪽이 이유를 알려야 한다.
  ///
  /// [sharePositionOrigin] 은 아이패드에서 팝오버가 뜰 위치다. 넘기지 않으면
  /// 아이패드에서 공유 시트가 뜨지 않을 수 있다.
  Future<bool> shareAsVCard(
    ContactModel contact, {
    Rect? sharePositionOrigin,
  }) async {
    File? file;
    try {
      file = await _writeTempVCard(contact);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/vcard')],
          // ⚠️ 제목에 이름이 들어간다. 메신저에 따라 미리보기로 보이므로
          //    보내는 사람이 무엇을 보내는지 알 수 있어야 한다.
          subject: '${contact.name} 연락처',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      return true;
    } catch (e) {
      // 이름·번호를 로그에 남기지 않는다. 종류만 찍는다.
      debugPrint('명함 내보내기 실패: ${e.runtimeType}');
      return false;
    } finally {
      await _deleteQuietly(file);
    }
  }

  Future<File> _writeTempVCard(ContactModel contact) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${vcardFileName(contact.name)}');
    await file.writeAsString(VCardUtil.encodeContact(contact));
    return file;
  }

  /// 지우기는 실패해도 흐름을 막지 않는다. 다만 **조용히 삼키지는 않는다** —
  /// 남았다는 사실이 로그에는 남아야 다음에 확인할 수 있다.
  Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('명함 vCard 임시 파일 정리 실패: ${e.runtimeType}');
    }
  }
}

/// 공유 시트와 받는 쪽에 보이는 파일 이름.
///
/// 이름을 쓰는 이유는 **받는 사람이 무엇인지 알아야** 하기 때문이다. 대신
/// 파일 이름으로 못 쓰는 글자를 걸러 낸다 — 걸러 낸 뒤 비면 `contact` 로
/// 떨어뜨린다(이름이 전부 특수문자인 명함이 실제로 있을 수 있다).
///
/// ⚠️ 이 파일은 **공유가 끝나면 지워진다.** 이름에 사람 이름이 들어가도 캐시에
/// 남지 않는 것이 전제다 — [ContactExportService] 의 `finally` 참조.
@visibleForTesting
String vcardFileName(String name) {
  final safe = name
      .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1F]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${safe.isEmpty ? 'contact' : safe}.vcf';
}
