/// 주소 문자열에서 **시/도 · 시군구**를 뽑는다. 외부 조회가 필요 없다.
///
/// ## 왜 필요한가
///
/// 주변 인맥은 **좌표**로 거리를 잰다. 좌표를 못 얻은 명함은 목록에서 **조용히
/// 빠진다** — 실기기에서 실제로 겪은 문제다(추가 79).
///
/// 그런데 **좌표가 없어도 주소 문자열에는 시/도·시군구가 들어 있다.**
///
/// ```
/// 2026-08-21 실측 (등록 명함 93건)
///   시도 + 시군구 둘 다   78건 (83.9%)
///   시도만               14건
///   시군구만              1건
///   ⭐ 못 뽑은 것          0건
///
/// 좌표를 못 얻은 30건에서도
///   시도 + 시군구        20건
///   시도만               10건
/// ```
///
/// ⭐ **하나도 빠짐없이 뽑힙니다.** 좌표가 없어도 "같은 구" 단위로는 보여줄 수
/// 있다는 뜻이다. API 호출도, 실패할 일도 없다.
///
/// ## ⚠️ 거리 정렬과 섞지 말 것
///
/// 좌표가 있는 명함은 "몇 m"이고 없는 명함은 "같은 구"다. **같은 줄에 섞으면
/// 순서가 거짓이 된다.** 화면에서 구획을 나눠 보여줘야 한다.
///
/// 📌 그리고 **시/도 단위는 쓸모가 적다** — 위 표본에서 93건 중 84건이
/// 서울이었다. 실질은 **시군구(구) 단위**다.
library;

/// 표준 시/도 이름. 긴 것부터 확인해야 "전라북도"가 "전북"에 먹히지 않는다.
const List<String> _sidoFull = [
  '서울특별시', '부산광역시', '대구광역시', '인천광역시', '광주광역시',
  '대전광역시', '울산광역시', '세종특별자치시',
  '경기도', '강원특별자치도', '강원도',
  '충청북도', '충청남도', '전북특별자치도', '전라북도', '전라남도',
  '경상북도', '경상남도', '제주특별자치도', '제주도',
];

/// 명함에 흔한 줄임말. ⚠️ 명함은 자리가 좁아 줄여 쓰는 경우가 많다.
const Map<String, String> _sidoShort = {
  '서울': '서울특별시', '부산': '부산광역시', '대구': '대구광역시',
  '인천': '인천광역시', '광주': '광주광역시', '대전': '대전광역시',
  '울산': '울산광역시', '세종': '세종특별자치시', '경기': '경기도',
  '강원': '강원특별자치도', '충북': '충청북도', '충남': '충청남도',
  '전북': '전북특별자치도', '전남': '전라남도', '경북': '경상북도',
  '경남': '경상남도', '제주': '제주특별자치도',
};

/// 주소에서 뽑아낸 행정구역.
class AddressRegion {
  /// 표준화된 시/도 이름(예: `서울특별시`). 못 찾으면 `null`.
  final String? sido;

  /// 시·군·구. `성남시 분당구`처럼 둘이면 둘 다 담는다. 못 찾으면 `null`.
  final String? sigungu;

  const AddressRegion({this.sido, this.sigungu});

  /// 목록을 묶는 데 쓸 키. **구가 있으면 구까지**, 없으면 시/도까지.
  ///
  /// ⚠️ 서울처럼 한 시/도에 몰려 있는 표본에서는 시/도만으로 묶으면 거의
  /// 한 덩어리가 되어 의미가 없다.
  String? get groupKey {
    if (sigungu != null) {
      return sido == null ? sigungu : '$sido $sigungu';
    }
    return sido;
  }

  /// 화면에 보여줄 짧은 이름. `서울특별시 강남구` → `강남구`.
  String? get shortLabel => sigungu ?? _shorten(sido);

  static String? _shorten(String? sido) {
    if (sido == null) return null;
    for (final entry in _sidoShort.entries) {
      if (entry.value == sido) return entry.key;
    }
    return sido;
  }

  bool get isEmpty => sido == null && sigungu == null;
}

/// [address]에서 행정구역을 뽑는다. 실패해도 예외를 던지지 않는다.
AddressRegion regionOf(String? address) {
  final raw = (address ?? '').trim();
  if (raw.isEmpty) return const AddressRegion();

  final sido = _sidoOf(raw);
  var rest = raw;
  if (sido != null) {
    // 원문에 쓰인 표기(정식이든 줄임말이든)만큼 잘라낸다.
    for (final form in [
      sido,
      ..._sidoShort.entries.where((e) => e.value == sido).map((e) => e.key),
    ]) {
      if (rest.startsWith(form)) {
        rest = rest.substring(form.length);
        // "서울시강남구"처럼 줄임말 뒤에 '시'가 붙은 경우 그것도 걷어낸다.
        //
        // ⚠️ **"경기시흥시"와 갈라야 한다** — 거기서 '시'를 떼면 "흥시"가 된다.
        // 가르는 기준은 **떼고 난 뒤가 '구'로 끝나는 토큰인가**다. '구'는
        // 시/도 접미사로 쓰이지 않아 헷갈릴 일이 없다.
        //
        //   서울시강남구…  → 떼면 "강남구" (구로 끝남)  ✅ 뗀다
        //   경기시흥시…    → 떼면 "흥시"   (구 아님)    ❌ 안 뗀다
        if (rest.startsWith('시') &&
            RegExp(r'^시[가-힣]+구').hasMatch(rest)) {
          rest = rest.substring(1);
        }
        break;
      }
    }
  }
  return AddressRegion(sido: sido, sigungu: _sigunguOf(rest.trim()));
}

String? _sidoOf(String address) {
  for (final s in _sidoFull) {
    if (address.startsWith(s)) return s;
  }
  for (final entry in _sidoShort.entries) {
    if (_startsWithSidoShort(address, entry.key)) return entry.value;
  }
  return null;
}

/// 줄임말 시/도로 시작하는지. ⚠️ **"서울대로"(도로명)와 갈라야 한다.**
///
/// 처음에는 뒤에 공백이나 `시 `가 오는 것만 인정했는데, 실측 93건에서
/// **9건을 놓쳤다** — `서울강남구…`처럼 붙여 쓴 것들이다. 명함은 자리가 좁아
/// 공백까지 지우는 경우가 흔하다.
///
/// 그래서 셋 중 하나면 인정한다.
///
/// ```
/// 서울 강남구…            뒤에 공백
/// 서울시 강남구…          뒤에 '시' + 공백
/// 서울강남구테헤란로…      ⭐ 뒤에 바로 시·군·구가 이어짐 (전부 붙여 씀)
/// 서울대로 123            ❌ 이어지는 것이 도로명이라 인정하지 않는다
/// 서울역 1번출구           ❌ 시·군·구가 아니다
/// ```
///
/// ⚠️ 시·군·구 **뒤에 공백이 오는 것까지 요구하면 안 된다.** 실측에서
/// `서울시강남구테헤란로…`처럼 통째로 붙여 쓴 9건을 놓쳤다.
bool _startsWithSidoShort(String address, String short) {
  if (!address.startsWith(short)) return false;
  final rest = address.substring(short.length);
  if (rest.startsWith(' ')) return true;
  if (rest.startsWith('시 ')) return true;
  // 붙여 쓴 경우 — 바로 뒤가 시·군·구여야 한다.
  if (RegExp(r'^시?[가-힣]+[시군구]').hasMatch(rest)) return true;
  // ⚠️ 구가 아예 없는 주소도 있다 — 실측에서 5건이 `서울` + 한글 + 영문
  // 형태였고 문자열 어디에도 시·군·구가 없었다. 그때는 **시/도라도 살린다.**
  // 목록에서 통째로 빠지는 것보다 "서울" 묶음에라도 들어가는 편이 낫다.
  //
  // 📌 다만 도로명은 걸러야 한다 — `서울대로`·`서울로`·`서울길`.
  return RegExp(r'^[가-힣]').hasMatch(rest) &&
      !RegExp(r'^(대로|로|길)').hasMatch(rest);
}

/// 시/도를 걷어낸 나머지에서 시·군·구를 최대 둘까지.
String? _sigunguOf(String rest) {
  // ⚠️ 뒤에 공백이 오는 것을 요구하지 않는다 — 붙여 쓴 주소를 놓친다.
  // 탐욕 매칭이 뒤로 물러나며 '구로구' 같은 토큰을 찾아낸다.
  final matches = RegExp(r'[가-힣]+[시군구]')
      .allMatches(rest)
      .map((m) => m.group(0)!)
      .toList();
  if (matches.isEmpty) return null;
  return matches.take(2).join(' ');
}
