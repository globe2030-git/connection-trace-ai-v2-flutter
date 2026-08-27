# 검증 도구

`flutter test`나 화면 QA로는 원리상 잡을 수 없는 것들을 확인하는 스크립트다.

## 왜 필요한가

이 프로젝트에서 실제로 아팠던 결함들은 **코드는 맞는데 실물이 틀린** 유형이었다.

| 결함 | 코드 상태 | 어떻게 잡았나 |
|---|---|---|
| 서버에 명함 개인정보 평문 잔존(5건 중 3건) | 정상 — 암호화 테스트도 통과 | 서버 실물 조회 |
| 좌표 재계산이 복원 경로에서만 호출돼 죽어 있음 | 서비스 테스트 10건 전부 통과 | 기기 저장소 덤프 |
| Firestore 규칙이 AI 호출 한도 리셋을 허용 | 앱이 그 필드를 안 써서 UI로 재현 불가 | 규칙 직접 평가 |

**테스트가 통과했다고 동작하는 게 아니다.** 저장·복원·마이그레이션·권한에
관련된 변경은 이 도구들로 실물을 확인해야 한다.

## 도구

| 스크립트 | 확인하는 것 | 전제 |
|---|---|---|
| `verify_server_privacy.py` | 서버에 평문 문서·좌표가 남아 있지 않은지 | `firebase login` |
| `verify_device_local.py` | 기기 저장분이 암호문인지, 좌표가 채워졌는지, 재계산 실패가 남았는지 | `adb` 연결 + **디버그 빌드** |
| `../test/firestore_rules/verify_rules.py` | 보안 규칙이 의도대로 허용/거부하는지(15건) | `firebase login` |
| `analyze_ai_cost.py` | `aiAuditLogs`로 AI 호출 1회당 실제 원가(KRW)를 집계 — 충전 티어 회차 실측용 | `firebase login` |
| `check_admin_sync.py` | 관리자 이메일 목록이 나오는 모든 소스(현재 `firestore.rules`의 `isAdmin()`, `functions/src/adminEmails.ts`)가 서로 일치하는지(순수 로컬 파일 비교, 소스는 스크립트 내 `SOURCES` 리스트에 등록) | 없음(운영 인프라 무의존, CI에도 포함) |

```bash
python3 tool/verify_server_privacy.py          # 전체 계정
python3 tool/verify_server_privacy.py --uid X  # 특정 계정만
python3 tool/verify_device_local.py
python3 test/firestore_rules/verify_rules.py
python3 tool/analyze_ai_cost.py                                    # 최근 14일(KST)
python3 tool/analyze_ai_cost.py --from 2026-08-01 --to 2026-08-20  # 기간 지정
python3 tool/analyze_ai_cost.py --exchange-rate 1400               # 환율 변경(기본 1430)
python3 tool/check_admin_sync.py             # 관리자 이메일 목록 동기화 확인
python3 tool/check_admin_sync.py --selftest  # 스크립트 자체의 회귀 검증
```

종료 코드는 공통이다 — `0` 통과, `1` 문제 있음, `2` 실행 실패(미연결·인증 실패 등).
`analyze_ai_cost.py`만 `1`의 의미가 다르다 — "문제"가 아니라 **표본 요건
(성공 호출 150건↑ · 참여 uid 5명↑ · 영업일 7일↑, 셋 다) 미충족**이라는 뜻이다.
자세한 배경과 원가 공식·표본 요건 근거는
[`docs/planning/beta-observability-plan.md`](../docs/planning/beta-observability-plan.md)
2-2~2-4절 참고.

## 언제 돌리나

- **저장·암호화·마이그레이션 코드를 고친 뒤** → 서버 + 기기 둘 다
- **`firestore.rules`를 고친 뒤** → 규칙 검증 (배포 **전에**)
- **관리자 이메일을 추가/제거한 뒤** → `check_admin_sync.py` (CI에서도 자동 실행됨)
- **개인정보처리방침 게시 전** → 서버 점검(방침이 사실과 맞는지)
- **릴리스 후보 빌드** → 셋 다
- **충전 티어 회차를 실측으로 확정할 때**(베타 테스트 중 매주 1회 정도) →
  `analyze_ai_cost.py`로 표본 요건 충족 여부부터 확인

서버와 기기는 **짝으로 봐야 한다.** 설계 의도가 "좌표는 기기에만 있고 서버에는
없다"이므로 한쪽만 보면 절반만 확인한 것이다.

## 지켜야 할 원칙

**개인정보 값을 절대 출력하지 않는다.** 이 도구들은 운영 데이터를 읽는다.
이름·전화번호·이메일·주소 대신 "그 키가 있는지 없는지"와 건수만 본다. 이
원칙을 깨는 수정을 하지 말 것.

`verify_server_privacy.py`·`verify_device_local.py`·`analyze_ai_cost.py`는
Firebase CLI 자격증명으로 **관리자 권한**을 써서 보안 규칙을 우회한다. 규칙
자체를 검증하려면 `verify_rules.py`를 쓸 것 — 이쪽은 규칙 엔진에 직접
물어본다. `analyze_ai_cost.py`는 uid만 쓰고 distinct는 **개수**만 세며,
email은 아예 조회하지 않는다(집계에 필요 없다). 재시도 의심 신호처럼 특정
사례를 짚어야 할 때만 uid 앞 8자를 마스킹해 보여준다(`verify_server_
privacy.py`의 `uid[:10]` 관례와 동일) — 전체 uid 목록을 나열하지는 않는다.

## 의존성

`cryptography` (파이썬). 앱이 쓰는 AES-256-GCM 암호문을 푸는 데 필요하다 —
포맷은 `lib/core/services/data_crypto_service.dart`와 같다(base64(nonce 12B +
암호문 + MAC 16B)). `analyze_ai_cost.py`는 표준 라이브러리만 쓴다(추가 의존성 없음).

## Cloud Storage 실물 조회 (2026-08-26에 처음 씀 — 스크립트가 아직 없다)

⚠️ **명함 사진은 Cloud Storage에 있고, 위 스크립트들은 Firestore만 본다.**
2026-08-26에 추가 517·518을 잡은 것이 이 조회였는데, **방법이 저장소 어디에도
없었다.** 다음 사람이 다시 찾지 않게 적어 둔다.

`firebase` CLI가 없어도 된다 — `gcloud`·`gsutil`로 된다.

```bash
# 개수
gsutil ls -r "gs://connection-sense.firebasestorage.app/**" | grep -c "\.enc$"

# 목록 + 크기 + 시각 (판정은 개수가 아니라 이것으로 한다 — 아래 참고)
gsutil ls -l -r "gs://connection-sense.firebasestorage.app/**" | grep "\.enc$"
```

🚨 **빈 출력을 "0건"으로 읽지 마라.** 목록이 비는 것은 *"정말 없다"*일 수도
있고 *"권한이 없어 안 보인다"*일 수도 있다. 한 단계 더 해서 갈라야 한다.

```bash
gsutil ls -L -b "gs://connection-sense.firebasestorage.app"   # 메타데이터가 읽히면 접근은 되는 것
```

### 🚨 개수로 판정하지 마라 — 목록으로 판정하라

```bash
awk '{print $NF}' 목록.txt | sed -E 's#.*/cards/##' | sort | shasum | cut -c1-12
```

**개수는 같은데 내용이 다를 수 있다.** 삭제가 엉뚱한 것을 지우고 다른 것이 새로
올라오면 개수로는 안 잡힌다. 추가 517에서 이 방법이 *"지워야 할 그 하나가
정확히 남아 있고, 엉뚱한 것은 0건 지워졌다"*까지 갈랐다 — **삭제가 아예 안 도는
것과 엉뚱한 것을 지우는 것은 완전히 다른 결함이다.**

📌 여러 세션이 같은 기기를 쓰면 **시각까지** 봐야 한다(추가 313: 두 세션이 각자
기준선과 비교해 둘 다 "17장"이라고 보고한 사고).

## 배포된 보안 규칙 원문 받기

⚠️ **"배포했다"와 "서버가 그걸 쓴다"는 다르다.** 파일이 아니라 서버가 지금
쓰는 규칙을 받아야 한다.

```bash
TOKEN=$(gcloud auth print-access-token)
# ① 릴리스 목록 — 어느 룰셋을 쓰는지
curl -s -H "Authorization: Bearer $TOKEN" -H "X-Goog-User-Project: connection-sense" \
  "https://firebaserules.googleapis.com/v1/projects/connection-sense/releases"
# ② 그 룰셋 원문
curl -s -H "Authorization: Bearer $TOKEN" -H "X-Goog-User-Project: connection-sense" \
  "https://firebaserules.googleapis.com/v1/projects/connection-sense/rulesets/<ID>"
```

🚨 **`X-Goog-User-Project` 헤더가 없으면 403이 난다** — *"requires a quota
project, which is not set by default"*. 이것 때문에 처음에 권한 문제로 오해했다.

## 실기기 검증에서 시간을 잡아먹은 것들 (2026-08-26)

- 🚨 **폴드는 화면이 둘이라 `screencap`에 디스플레이 id를 줘야 한다.** 안 주면
  경고 문구가 PNG 앞에 섞여 **파일이 깨진다**(이미지 뷰어가 못 연다).

  ```bash
  adb shell dumpsys SurfaceFlinger --display-id      # id 확인
  adb exec-out screencap -p -d <id> > s.png
  ```

- ⚠️ **명함 삭제 경로는 셋인데 두 곳에는 없다.** 상세 화면에도 편집 화면에도
  삭제 버튼이 없다. **목록 행 스와이프** 또는 **선택 모드(✓≡) → 빨간 「N개 삭제」**
  다. 앞의 둘을 뒤지다 시간을 썼다.

- 🚨 **명함 상세의 전화 아이콘은 시트를 안 거치고 바로 건다.** 목록·주변 화면의
  전화 아이콘만 "어느 번호로 걸까요" 시트를 띄운다. **검증 중에 상세에서 누르면
  실제 사람에게 전화가 걸린다.**

- ⚠️ **`adb shell input text`로는 한글을 넣을 수 없다.** 그래서 한글이 든 칸은
  **비웠다가 되돌릴 수 없다.** 내 명함 주소 검증을 이 이유로 건너뛰었다 —
  **못 되돌릴 것은 건드리지 않는다.**

- ⚠️ **연속으로 여러 칸을 채우면 좌표가 어긋난다.** 한 칸을 채우면 화면이
  밀리는데, 그 상태에서 다음 좌표를 그대로 쓰면 **엉뚱한 칸에 들어간다**(실제로
  회사명이 부서 칸에 들어갔다). CLAUDE.md 4-2절의 *"자동 탭을 보내기 전에 그
  화면을 먼저 확인한다"*가 이 자리에도 그대로 적용된다.

## 알려진 제약

- `verify_device_local.py`는 **Android 전용**이다. iOS는 샌드박스라 앱 내부
  저장소를 열 수 없다. iOS 쪽 확인은 화면에 거리가 표시되는지로 간접 확인해야
  한다.
- `run-as`는 **디버그 빌드에서만** 동작한다. 릴리스 빌드로 테스트 중이라면 이
  점검을 위해 디버그 빌드를 잠시 설치해야 한다.
- ⚠️ **"캐시"는 폴더가 둘이다. 어느 쪽을 보는지부터 정하고 재라**(2026-08-16).

  | 폴더 | 무엇이 들어 있나 | Dart에서 |
  |---|---|---|
  | `cache` | 촬영 원본 `CAP*.jpg`, 갤러리 사본 `<UUID>/사진`, `scaled_*` | `getTemporaryDirectory()` |
  | `code_cache` | 크롭·회전본 `card_scan_*`·`card_rot_*` | **`Directory.systemTemp`** |

  안드로이드가 앱 프로세스의 `TMPDIR`을 `code_cache`로 잡아서, `Directory.systemTemp`에
  쓴 파일은 `cache`에 없다. **한쪽만 보고 "다 지워졌다"고 판정한 전례가 있다** —
  같은 217MB를 두 번 다르게 읽었다(추가 248). 용량은 `du -sk cache code_cache`로
  **둘 다** 재고, 파일 개수는 이름별로 세는 것이 정확하다.

  ⚠️ **`code_cache`는 앱을 업데이트(재설치)하면 안드로이드가 비운다.** 그래서
  `adb install -r` 뒤에 재면 크롭·회전본이 "정리된 것처럼" 보인다. 정리 코드가
  동작한 근거로 쓸 수 없다.

- ⚠️ **`run-as`로는 앱 저장소를 읽을 수만 있고 쓸 수는 없다**(2026-08-16 실측,
  SM-F966N / Android 15). `ls`·`du`·`cat`은 되지만 파일을 만들거나 `touch`로
  시각을 바꾸려 하면 `Permission denied`가 난다 — 디렉터리 권한 문제가 아니라
  (`cache`·`code_cache` 모두 앱 uid 소유의 `drwxrws--x`) **SELinux MLS 카테고리**
  때문이다. `run-as` 셸은 앱 프로세스의 카테고리
  (`app_data_file:s0:c169,c257,...`)를 물려받지 못한다.

  그래서 **"오래된 임시 파일을 심어 두고 정리가 지우는지 본다"는 방식이 안
  된다.** 캐시 정리·나이 기준 같은 검증은 (1) 나이 판단 자체는 `flutter test`로
  (순수 함수로 빼 두면 된다), (2) 실기기에서는 **화면을 실제로 눌러** 파일이
  생기고 사라지는 것을 `ls`로 확인하는 식으로 나눠야 한다. 이걸 모르고 심는
  방법부터 시도하면 시간을 버린다(추가 247에서 실제로 겪음).
- 규칙 검증은 로컬 에뮬레이터가 아니라 **Firebase 규칙 테스트 API**를 쓴다. 이
  환경의 JDK(IBM Semeru 26)에서 Firestore 에뮬레이터의 규칙 엔진이 뜨지 않기
  때문이다(전부 허용하는 최소 규칙조차 실패하는 것으로 확인). 서버 평가라
  실제 배포와 같은 엔진이고 운영 데이터에 영향이 없다.
- `analyze_ai_cost.py`는 페이지네이션 없이 한 번의 `:runQuery`로 최대
  20,000건까지 읽는다(베타 규모에서는 충분 — 다른 도구들의 `pageSize` 상한
  관례와 동일). 그 상한에 닿으면 경고만 하니, 대량 데이터가 쌓이면 `--from`/
  `--to`로 기간을 좁혀서 나눠 돌릴 것. 날짜 경계(일별 추이·영업일 판정)는
  KST(UTC+9) 기준이고, 한국은 서머타임이 없어 고정 오프셋으로 계산한다.
