/// 화면에서 돌린 각도를 실제 이미지 파일에 굽는다(F-03).
///
/// ## 왜 위젯 밖으로 뺐나
///
/// 원래 [CameraScanModalView]의 확인 화면 전용 private 메서드였다. P2-③에서
/// 크롭 화면(`manual_crop_view.dart`)도 같은 회전이 필요해졌는데, **새
/// 회전 코드를 또 만들지 않는다** — 두 화면이 각자 다르게 굽기 시작하면
/// 그건 이 저장소가 이미 두 번 겪은 "좌표계가 둘이 되는" 문제와 같은
/// 종류다.
///
/// ⚠️ **여전히 "회전과 자르기를 섞지 않는다" 원칙을 지킨다.** 이 함수는
/// 각도만큼 **새 파일을 만들어 돌려줄 뿐**이고, 크롭 좌표 계산과는 아무
/// 관계가 없다 — 부르는 쪽이 이 함수가 돌려준 "똑바로 선" 파일을 받은
/// 뒤에 크롭 좌표를 새로 잡아야 한다(예전 좌표를 재사용하면 섞인다).
library;

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'scan_rotation.dart';

/// [degrees]가 0이면(제자리로 돌아온 경우 포함) **원본을 그대로 돌려준다** —
/// 재인코딩은 화질만 깎고 결과는 같다.
///
/// 실패하면 원본을 쓴다. 회전을 못 했다고 인식/자르기 자체를 막는 것보다,
/// 방향이 어긋난 채로라도 계속 진행하는 편이 낫다.
///
/// ⚠️ **먼저 EXIF 방향을 굽는다**(추가 397 조사 중 추가). `warpCardToFile`이
/// 자기 소스를 읽을 때 이미 하는 것과 같은 순서다(`card_quad_warp.dart`
/// 주석 참고) — 이 함수만 빠져 있었다. 소스에 방향 태그가 남아 있는 채로
/// `copyRotate`만 하면, 물리적으로는 돌아간 픽셀 위에 **예전 방향 태그가
/// 그대로 복제되어 남는다**(`image` 패키지의 `copyRotate`는 회전 전
/// exif를 그대로 복제한다 — 지우지 않는다). Flutter의 `Image.file`은 이
/// 태그를 그대로 반영하지 않는 것으로 보이는 반면, 이 저장소의 크롭
/// 함수(`warpCardToFile`)는 자기 소스를 읽을 때 **항상** exif 방향을
/// 구워 반영한다 — 같은 파일을 두 곳이 다른 방향으로 읽는 조합이 된다.
/// 실촬영 원본에 남아 있을 수 있는 태그를 여기서 먼저 지워 두면, 그
/// 조합 자체가 생기지 않는다.
Future<XFile> bakeImageRotation(
  XFile source,
  int degrees, {
  String? outputDirectoryPath,
}) async {
  if (!needsRebake(degrees)) return source;
  try {
    final bytes = await source.readAsBytes();
    var decoded = img.decodeImage(bytes);
    if (decoded == null) return source;
    decoded = img.bakeOrientation(decoded);
    final rotated = img.copyRotate(decoded, angle: normalizeTurn(degrees));
    final jpgBytes = img.encodeJpg(rotated, quality: 100);
    final dir = outputDirectoryPath ?? Directory.systemTemp.path;
    final outPath = '$dir/card_rot_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(outPath).writeAsBytes(jpgBytes);
    return XFile(outPath);
  } catch (_) {
    return source;
  }
}
