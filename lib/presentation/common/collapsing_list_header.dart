import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 스크롤에 따라 큰 제목은 접어 흘려보내고, 검색·정렬 같은 도구줄은 화면
/// 위에 고정해 두는 목록 머리글(UI 개선 ⑦, 2026-08-21 확정).
///
/// 지갑 화면에 맞춰 처음 만들었지만 위젯 자체는 화면을 모른다 — 무엇을
/// 접을지([expandedTop]/[collapsedTop])와 항상 보일 도구줄([pinnedTools])을
/// 호출부가 채운다. 주변 탭(⑦ 후속, `radar_view.dart`)도 같은 컴포넌트를
/// 그대로 쓸 수 있게 하려는 설계다 — 화면별 내용(태그 칩, 반경 칩 등)만
/// 다르고 접힘 자체의 규칙(무엇이 고정이고 무엇이 흘러가는지, 그림자 표현)은
/// 하나로 통일된다.
///
/// ### 왜 `SliverAppBar`가 아니라 직접 만들었나
/// 지갑·주변 목록은 초성 점프(`ItemScrollController`)가 필요해
/// `scrollable_positioned_list` 패키지를 쓰는데, 이 패키지는 자체
/// `Scrollable`/뷰포트를 들고 있어 `CustomScrollView`의 슬리버로 편입되지
/// 않는다(패키지 소스 확인, 2026-08-21 — `ScrollablePositionedList`가 내부
/// `ListView`를 직접 그린다). 그래서 목록의 스크롤 알림
/// (`NotificationListener<ScrollNotification>`)을 받아 "접을지"만 판정하고
/// ([HeaderCollapseTracker]), 머리글은 리스트 밖에서 별도로 접었다 편다 —
/// 겉보기 동작은 `SliverAppBar(pinned: true)`와 같지만 구현은 슬리버가
/// 아니다.
class CollapsingListHeader extends StatelessWidget {
  const CollapsingListHeader({
    super.key,
    required this.collapsed,
    required this.expandedTop,
    required this.collapsedTop,
    required this.pinnedTools,
    this.duration = const Duration(milliseconds: 180),
  });

  /// 접힌 상태인가 — 스크롤 위치 판정은 호출부가 [HeaderCollapseTracker]로
  /// 미리 계산해 넘긴다. 이 위젯은 그 결과만 그린다.
  final bool collapsed;

  /// 맨 위(스크롤 안 한 상태)에서만 보이는 큰 제목 블록. 태그 칩처럼 "같이
  /// 흘려보내야 할" 요소가 있으면 이 안에 함께 넣는다.
  final Widget expandedTop;

  /// 접혔을 때만 보이는 축약 제목 줄.
  final Widget collapsedTop;

  /// 스크롤·접힘과 무관하게 항상 보이는 도구줄(검색창·정렬 칩 등).
  final Widget pinnedTools;

  final Duration duration;

  /// 테스트에서 그림자 유무를 직접 찾을 수 있도록 붙인 키(내부용).
  static const shadowBoxKey = ValueKey('collapsingListHeaderShadowBox');

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: shadowBoxKey,
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        // 고정 상태에서만 그림자를 넣어 목록 위에 "떠 있는 층"임을 보인다
        // (브리프 지시: "고정 상태에서 아래 그림자로 층 표현").
        boxShadow: collapsed
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: duration,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                // 세로축 위쪽 기준으로 접힌다(구 axisAlignment: -1과 동일).
                alignment: const Alignment(-1.0, -1.0),
                child: child,
              ),
            ),
            child: collapsed
                ? KeyedSubtree(
                    key: const ValueKey('collapsed'),
                    child: collapsedTop,
                  )
                : KeyedSubtree(
                    key: const ValueKey('expanded'),
                    child: expandedTop,
                  ),
          ),
          pinnedTools,
        ],
      ),
    );
  }
}

/// 목록 스크롤 알림에서 "머리글을 접을지"를 판정하는 작은 도우미.
///
/// 경계값 하나로만 판정하면 스크롤이 딱 그 지점에서 위아래로 떨릴 때
/// 접힘·펼침이 반복해서 깜빡인다. 접는 지점([collapseAt])과 펴는 지점
/// ([expandAt])을 다르게 둬서(히스테리시스) 막는다.
///
/// 위젯이 아니라 순수 상태 계산기다 — `State`에 하나 들고 있다가
/// `NotificationListener<ScrollNotification>`에서 [update]를 부르고,
/// 반환값이 true일 때만 `setState`하면 된다.
class HeaderCollapseTracker {
  HeaderCollapseTracker({this.collapseAt = 28, this.expandAt = 6})
    : assert(
        expandAt < collapseAt,
        'expandAt은 collapseAt보다 작아야 히스테리시스가 성립한다',
      );

  final double collapseAt;
  final double expandAt;

  bool _collapsed = false;
  bool get collapsed => _collapsed;

  /// 새 스크롤 픽셀 위치를 반영한다. 상태가 실제로 바뀌었을 때만 true를
  /// 돌려준다 — 매 스크롤 프레임마다 불필요한 `setState`를 막기 위함이다.
  bool update(double pixels) {
    if (!_collapsed && pixels > collapseAt) {
      _collapsed = true;
      return true;
    }
    if (_collapsed && pixels < expandAt) {
      _collapsed = false;
      return true;
    }
    return false;
  }

  /// 목록이 비어 스크롤할 것이 없어졌을 때 등, 외부 사정으로 강제로 편다.
  void reset() => _collapsed = false;
}

/// 접힌 축약 제목 옆에 붙는 개수 배지(예: 명함 지갑의 전체 인맥 수).
class HeaderCountBadge extends StatelessWidget {
  const HeaderCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.accentText,
        ),
      ),
    );
  }
}
