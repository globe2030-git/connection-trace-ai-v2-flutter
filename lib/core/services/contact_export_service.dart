import 'dart:io';

import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/contact_model.dart';
import '../utils/contact_export_name.dart';
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
/// ## 🚨 임시 파일을 곧바로 지운다
///
/// `.vcf` 안에는 **제3자(명함 주인) 개인정보가 평문으로** 들어간다. 이 앱은
/// 명함을 암호화해 보관하는데, 캐시에 평문이 남으면 **그 암호화의 의미가
/// 깎인다.** 이 저장소는 스캔 임시 파일에서 같은 자리를 두 번 겪었다
/// (backlog 추가 247·253).
///
/// 그래서 공유가 끝나면 `finally` 에서 지운다. 취소해도, 예외가 나도 지운다.
///
/// ⚠️ **"너무 빨리 지워서 공유가 실패하는 것 아닌가"를 의심해 지연 삭제로
/// 바꿔 봤으나, 그게 아니었다**(2026-08-26). `share_plus` 는 넘겨받은 파일을
/// **자기 폴더(`caches/share_plus`)로 복사한 뒤** 공유하므로
/// (`Share.kt:181` `copyToShareCacheFolder`), 우리가 원본을 지워도 상관없다.
/// **원본을 늦게 지우면 평문만 오래 남는다.**
///
/// ## 📌 카카오톡·문자 전송 — 원인은 **MIME 타입**이었다
///
/// 2026-08-26 폴드 실측. 처음에는 공유 시트에서 카카오톡을 고르면 **앱이
/// 열리기는 하는데 아무것도 안 받았다.** 공유 대상 선택 화면조차 안 뜨고
/// 메인 화면만 떴다. ⚠️ **로그에 오류가 하나도 안 찍혔다.**
///
/// 원인은 [_vcardMimeType] 주석에 적었다 — `text/*` 를 주면 카카오톡이
/// **텍스트 공유로 처리하고 `EXTRA_STREAM` 을 무시**한다. `application/octet-stream`
/// 으로 바꾸니 **카카오톡·문자 둘 다 전송됐다.**
///
/// ## ⚠️ 이 결함을 쫓으며 세 번 헛짚었다 — 지우지 않고 남긴다
///
/// | 의심한 것 | 재 본 결과 |
/// |---|---|
/// | 임시 파일을 너무 빨리 지워서 | `share_plus` 가 복사한다(`Share.kt:181`). 무관 |
/// | `<queries>` 에 `ACTION_SEND` 가 없어서 | 권한은 정상 부여됐다(`dumpsys activity permissions` 로 확인) |
/// | URI 제공자 차이(MediaStore vs FileProvider) | **아니었다.** 아래 참고 |
///
/// 🚨 **셋째가 특히 위험한 오진이었다.** `adb shell am start` 로 재서
/// *"MediaStore 는 되고 우리 FileProvider 는 안 된다"* 고 좁혔는데, **그 방식이
/// 카카오톡 프로세스 상태에 좌우돼 같은 조건을 두 번 재면 다른 결과가 나온다.**
/// 콜드 스타트일 때만 공유 화면이 떴고, 그것을 URI 차이로 읽었다.
///
/// 📌 **`am start` 로 이 경로를 재지 마라. 실제 공유 시트로만 갈린다.**
class ContactExportService {
  /// 🚨 **`text/vcard` 가 아니라 `application/octet-stream` 이다.**
  ///
  /// vCard 의 정식 타입은 `text/vcard`(RFC 6350)인데, **그것으로 보내면
  /// 카카오톡에 파일이 도착하지 않는다**(2026-08-26 폴드 실측).
  ///
  /// ## 무슨 일이 일어나나
  ///
  /// ```
  /// text/vcard · text/x-vcard   카카오톡이 "텍스트 공유"로 처리하고
  ///                             EXTRA_STREAM 을 무시한다.
  ///                             → 앱은 열리는데 아무것도 안 받는다
  /// application/octet-stream    파일로 처리한다 → 전송된다
  /// ```
  ///
  /// 카카오톡 인텐트 필터에 `text` 가 들어 있어(`StaticType: text`) **공유
  /// 시트에는 뜬다.** 그래서 *"고를 수는 있는데 아무 일도 안 일어나는"* 모양이
  /// 된다. ⚠️ **로그에 오류가 하나도 안 찍힌다** — 우리 쪽은 공유 시트를 띄운
  /// 것까지 성공했고, 실패는 받는 앱 안에서 조용히 난다.
  ///
  /// 📌 카카오 데브톡에도 *"`application/*` 으로는 단일 파일 공유가 된다"* 는
  /// 보고가 있다. **카카오톡의 공식 파일 공유 가이드는 존재하지 않는다** —
  /// 지원 MIME 범위가 공개돼 있지 않아 실측 말고는 알 방법이 없었다.
  ///
  /// ## ⚠️ 대가
  ///
  /// 파일 타입이 뭉뚱그려지므로 **연락처 앱이 공유 시트 후보에서 빠질 수
  /// 있다**(연락처 앱은 보통 `text/x-vcard` 로 필터를 건다). 받는 쪽은
  /// **확장자 `.vcf`** 로 판별한다 — 그래서 [vcardFileName] 이 확장자를 반드시
  /// 붙인다.
  ///
  /// ## 📌 이 값을 다시 만지기 전에
  ///
  /// **`adb shell am start` 로 재지 마라.** 그 방식은 카카오톡 프로세스 상태에
  /// 좌우돼 **같은 조건을 두 번 재면 다른 결과가 나온다.** 이 결함을 쫓는 동안
  /// 그 방식으로 세 번 헛짚었다(임시 파일 삭제 시점 · MIME 무관 · `<queries>`).
  /// **실제 공유 시트로만 갈렸다.**
  static const String _vcardMimeType = 'application/octet-stream';


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
    ContactExportNameFormat nameFormat = ContactExportNameFormat.nameOnly,
  }) async {
    File? file;
    try {
      file = await _writeTempVCard(contact, nameFormat);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: _vcardMimeType)],
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

  Future<File> _writeTempVCard(
    ContactModel contact,
    ContactExportNameFormat nameFormat,
  ) async {
    final dir = await getTemporaryDirectory();
    // ⚠️ 파일 이름은 **형식과 무관하게 순수 이름**이다. 회사명이 든 파일
    //    이름은 공유 시트에서 길게 잘려 무엇인지 더 안 보인다.
    final file = File('${dir.path}/${vcardFileName(contact.name)}');
    await file.writeAsString(
      VCardUtil.encodeContact(contact, nameFormat: nameFormat),
    );
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
