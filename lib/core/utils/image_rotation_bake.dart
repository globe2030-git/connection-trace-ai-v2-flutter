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
///
/// ## ⚠️ 무거운 부분은 `compute()`로 돌린다(폴드 실측 2~3초 지연, P2-③ 후속)
///
/// `img.decodeImage`(순수 Dart JPEG 디코드) + 회전 + 재인코딩은 4000px급
/// 사진 한 장에서 메인 아이솔레이트를 통째로 막을 만큼 무겁다 — 그동안
/// 스피너 애니메이션조차 끊겨 보였다. `warpCardToFile`(`card_quad_warp.dart`)이
/// 같은 이유로 `compute()`를 요구하는 것과 같은 사정이라, 여기도 같은
/// 패턴을 쓴다: 인자는 평평한 값(파일 경로·정수)만 담아 isolate 경계를
/// 넘기고, 실제 디코드·회전·파일 쓰기는 톱레벨 동기 함수([_bakeRotationSync])
/// 안에 둔다.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'scan_rotation.dart';

/// [_bakeRotationSync]에 넘길 인자 묶음 — isolate 경계를 넘기므로 평범한
/// 값만 담는다(`card_quad_warp.dart`의 `CardWarpRequest`와 같은 이유).
class _BakeRotationRequest {
  const _BakeRotationRequest({
    required this.sourcePath,
    required this.degrees,
    required this.outputDirectoryPath,
  });

  final String sourcePath;
  final int degrees;
  final String outputDirectoryPath;
}

/// 실제 디코드·회전·인코딩·파일 쓰기 — `compute()`가 별도 isolate에서 돈다.
///
/// 실패하면 null(부르는 쪽은 원본을 쓴다). 톱레벨 동기 함수라야 `compute()`가
/// 클로저 캡처 없이 다른 isolate로 그대로 옮길 수 있다.
String? _bakeRotationSync(_BakeRotationRequest request) {
  try {
    final bytes = File(request.sourcePath).readAsBytesSync();
    var decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    decoded = img.bakeOrientation(decoded);
    final rotated = img.copyRotate(decoded, angle: normalizeTurn(request.degrees));
    final jpgBytes = img.encodeJpg(rotated, quality: 100);
    final outPath =
        '${request.outputDirectoryPath}/card_rot_${DateTime.now().millisecondsSinceEpoch}.jpg';
    File(outPath).writeAsBytesSync(jpgBytes);
    return outPath;
  } catch (_) {
    return null;
  }
}

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
    final outPath = await compute(
      _bakeRotationSync,
      _BakeRotationRequest(
        sourcePath: source.path,
        degrees: degrees,
        outputDirectoryPath: outputDirectoryPath ?? Directory.systemTemp.path,
      ),
    );
    if (outPath == null) return source;
    return XFile(outPath);
  } catch (_) {
    return source;
  }
}

/// **EXIF 방향만** 굽는다 — 화면에서 돌린 각도(위 [degrees]) 없이도 항상
/// 굽는다(398, 갤러리 자르기).
///
/// ⚠️ [bakeImageRotation]은 `degrees`가 0이면 **원본을 그대로 돌려준다**
/// (재인코딩 낭비를 막으려는 것) — 그런데 그 판단은 "사용자가 화면에서
/// 돌리지 않았다"는 뜻이지 "EXIF 방향 태그가 없다"는 뜻이 아니다. 갤러리
/// 사진(카메라 앱·다른 기기 촬영본)은 이 화면에서 돌린 적이 없어도 **파일
/// 자체에 방향 태그가 남아 있는 경우가 흔하다** — 촬영 경로의 원본과 달리
/// 이 앱이 만든 파일이 아니라서 어떤 방향 태그가 붙어 있을지 알 수 없다.
///
/// 그 태그가 안 구워진 채로 [ManualCropView]에 넘기면, 그 화면(Flutter
/// `Image.file`)이 보여주는 방향과 [warpCardToFile]이 자기 소스를 다시 읽을
/// 때 굽는 방향(`img.bakeOrientation`, 그쪽은 **항상** 돈다)이 달라질 수
/// 있다 — 그 차이가 `cornersAreImageRelative` 우회의 전제(두 디코더가 같은
/// 이미지 크기에 합의한다)를 깨고, 자른 결과가 명함과 안 맞는 결함으로
/// 이어진다(추가 397이 회전 버튼에서 겪은 것과 같은 종류의 어긋남).
///
/// 그래서 이 함수는 방향 태그가 이미 "정상"인지 미리 가리지 않고 **항상**
/// 다시 인코딩한다 — 갤러리 선택마다(최대 2장) 한 번씩만 불려 비용도 작다.
Future<XFile> bakeExifOrientation(
  XFile source, {
  String? outputDirectoryPath,
}) async {
  try {
    final bytes = await source.readAsBytes();
    var decoded = img.decodeImage(bytes);
    if (decoded == null) return source;
    decoded = img.bakeOrientation(decoded);
    final jpgBytes = img.encodeJpg(decoded, quality: 100);
    final dir = outputDirectoryPath ?? Directory.systemTemp.path;
    final outPath = '$dir/card_rot_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(outPath).writeAsBytes(jpgBytes);
    return XFile(outPath);
  } catch (_) {
    return source;
  }
}
