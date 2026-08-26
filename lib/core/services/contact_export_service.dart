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
/// ## 🚨 카카오톡 전송이 아직 안 된다 (미해결)
///
/// 2026-08-26 폴드 실측: 공유 시트에서 카카오톡을 고르면 **카카오톡이
/// 열리기는 하는데 아무것도 안 받는다.** 공유 대상 선택 화면조차 안 뜨고
/// 메인 화면만 뜬다. **로그에 오류가 하나도 안 찍힌다** — 우리 쪽은 공유
/// 시트를 띄운 것까지 성공했고, 실패는 받는 앱 안에서 조용히 난다.
///
/// 📌 **같은 `.vcf` 를 「내 파일」앱에서 보내면 정상으로 간다**(대화방에
/// *"홍길동 · 연락처 · 자세히 보기"* 카드가 뜬다). 경로만 다르다.
///
/// ⚠️ **다음 사람이 같은 셋을 다시 밟지 않도록 적어 둔다 — 셋 다 아니었다.**
///
/// | 의심한 것 | 재 본 결과 |
/// |---|---|
/// | 임시 파일을 너무 빨리 지워서 | `share_plus` 가 복사한다. 무관 |
/// | MIME 이 `text/vcard` 라서 | `text/x-vcard` 로 바꿔도 그대로 |
/// | 매니페스트 `<queries>` 에 `ACTION_SEND` 가 없어서 | 추가해도 그대로 |
///
/// **재는 방법**(빌드 없이 `adb` 로 변수를 하나씩 끈다):
///
/// ```
/// adb shell "am start -a android.intent.action.SEND -t text/x-vcard \
///   --eu android.intent.extra.STREAM content://media/external/file/<id> \
///   -n com.kakao.talk/com.kakao.talk.activity.RecentExcludeIntentFilterActivity \
///   --grant-read-uri-permission"
/// ```
///
/// 이렇게 하면 **공유 대상 선택 화면이 뜬다**(subject 를 붙여도 뜬다). 즉
/// 남은 차이는 **URI 를 어디서 주느냐** 하나다 — MediaStore ✅ vs 우리
/// FileProvider ❌.
///
/// **다음에 볼 순서**: ① `grantUriPermission` 이 카카오톡에 실제로 붙는지
/// ② FileProvider authority 충돌 ③ 파일 앱 경로와 인텐트 덤프 비교.
/// 🚫 `share_plus` 13.x 올리기는 **막혔다** — `win32` 6.x → `package_info_plus`
/// 10.1+ → `flutter_secure_storage` 10.x 로 이어져 **암호화 저장 패키지까지
/// 갈아야 한다.**
class ContactExportService {
  /// vCard 의 MIME 타입. RFC 6350 의 정식 타입이다.
  ///
  /// ⚠️ **`text/x-vcard` 로 바꿔 봤으나 아무것도 달라지지 않았다**(2026-08-26
  /// 폴드 실측). 파일 앱이 그 타입을 쓰기에 *"그 차이겠거니"* 했는데 **틀렸다.**
  /// `adb` 로 인텐트를 직접 만들어 재 보니 MIME 도 `EXTRA_SUBJECT` 도 무관했고,
  /// **차이는 URI 를 어디서 주느냐**였다(MediaStore ✅ / 우리 FileProvider ❌).
  ///
  /// 📌 그러니 **여기를 다시 만지지 마라.** 원인은 아래쪽 URI 전달 경로에 있다.
  static const String _vcardMimeType = 'text/vcard';


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
