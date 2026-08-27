import 'package:flutter/material.dart';

import '../../../../core/services/geo_failure_lookup.dart';
import '../../../../core/theme/app_colors.dart';

/// 이 명함이 **주변 화면에서 왜 그렇게 보이는지** 한 줄로 알린다(P1-25).
///
/// ## 🚨 경고가 아니다 — 선택지다
///
/// 좌표를 못 얻은 명함이라도 **대부분은 지역 묶음으로 잘 보인다**(2026-08-21
/// 실측: 좌표 없는 30건이 **전부** 그랬다). 그것들은 **고장이 아니다.**
///
/// ⚠️ **그래서 「고쳐야 할 것」처럼 보이면 안 된다.** 붉은색·경고 아이콘·굵은
/// 글씨를 쓰지 않는다. 하는 말은 *"주소를 고치면 거리로도 보인다"* 는
/// **선택지**이지 *"뭔가 잘못됐다"* 가 아니다.
///
/// 📌 처음에 후보로 나온 문구 *"주소 위치를 확인할 수 없습니다"* 는 **버렸다.**
/// 지역으로 잘 보이는 30건에 대해 **사실이 아니고**, 멀쩡한 것을 고장으로
/// 읽게 만든다.
///
/// ## 이 화면에 주소 칸이 없다는 것
///
/// 상세 시트는 **휴대폰·이메일 세 줄**뿐이고 주소는 [편집]에서 본다
/// (2026-08-19 사용자 확정, 추가 332 — *"자료가 많은 명함이 답답하다"*).
///
/// 📌 **그 확정과 부딪히지 않는다.** 332가 줄인 것은 **필드**이고 이 줄이
/// 더하는 것은 **상태**다 — *"이 명함이 주변에서 왜 다르게 보이는지"*. 그래서
/// 주소 값을 여기 되살리지 않고, 고치러 갈 길만 연다.
///
/// ⚠️ **시각 요소는 최소로 둔다.** 배치·무게는 설계 세션이 캔버스에 그린 뒤
/// 맞춘다.
class GeoNoticeRow extends StatelessWidget {
  const GeoNoticeRow({
    super.key,
    required this.state,
    required this.onEditAddress,
  });

  final GeoNoticeState state;

  /// [주소 수정]을 눌렀을 때. 편집 화면을 여는 것은 부르는 쪽이 정한다.
  final VoidCallback onEditAddress;

  /// 상태별 문구. **둘만 말하고 나머지는 침묵한다.**
  ///
  /// - `located` — 거리로 잘 보인다. 할 말이 없다.
  /// - `noAddress` — 주소가 아예 없다. **지오코딩 실패가 아니라 입력 누락**이라
  ///   성격이 다르다(*"주소를 넣으면…"* 은 권유가 된다). **별건으로 둔다.**
  static String? messageFor(GeoNoticeState state) => switch (state) {
        GeoNoticeState.regionOnly =>
          '정확한 위치를 찾지 못해 지역으로만 표시됩니다',
        GeoNoticeState.hidden => '주소로 위치를 찾지 못해 주변에 표시되지 않습니다',
        GeoNoticeState.located || GeoNoticeState.noAddress => null,
      };

  @override
  Widget build(BuildContext context) {
    final message = messageFor(state);
    if (message == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            // ⚠️ 경고 아이콘(느낌표·삼각형)을 쓰지 않는다 — 고장이 아니다.
            const Icon(
              Icons.place_outlined,
              size: 17,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: onEditAddress,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentText,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('주소 수정', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }
}
