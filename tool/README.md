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

## 알려진 제약

- `verify_device_local.py`는 **Android 전용**이다. iOS는 샌드박스라 앱 내부
  저장소를 열 수 없다. iOS 쪽 확인은 화면에 거리가 표시되는지로 간접 확인해야
  한다.
- `run-as`는 **디버그 빌드에서만** 동작한다. 릴리스 빌드로 테스트 중이라면 이
  점검을 위해 디버그 빌드를 잠시 설치해야 한다.
- 규칙 검증은 로컬 에뮬레이터가 아니라 **Firebase 규칙 테스트 API**를 쓴다. 이
  환경의 JDK(IBM Semeru 26)에서 Firestore 에뮬레이터의 규칙 엔진이 뜨지 않기
  때문이다(전부 허용하는 최소 규칙조차 실패하는 것으로 확인). 서버 평가라
  실제 배포와 같은 엔진이고 운영 데이터에 영향이 없다.
- `analyze_ai_cost.py`는 페이지네이션 없이 한 번의 `:runQuery`로 최대
  20,000건까지 읽는다(베타 규모에서는 충분 — 다른 도구들의 `pageSize` 상한
  관례와 동일). 그 상한에 닿으면 경고만 하니, 대량 데이터가 쌓이면 `--from`/
  `--to`로 기간을 좁혀서 나눠 돌릴 것. 날짜 경계(일별 추이·영업일 판정)는
  KST(UTC+9) 기준이고, 한국은 서머타임이 없어 고정 오프셋으로 계산한다.
