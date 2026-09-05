# Cloud Functions 에 고정 나가는 IP 붙이기 — 알리고 IP 허용목록 (2026-09-06)

> PM 배정. 🚨 **아무것도 실행하지 않았다.** `gcloud` 는 globe2030님 권한이고,
> 이 문서는 **재고 적는 데까지**다.
>
> ⚠️ **결론을 하나로 안 정한다.** 갑/을과 각각의 대가를 놓고 globe2030님이 고르신다.

---

## 0. 🚨 먼저 — ②의 답: **함수별이다**

PM 이 *"이 하나로 오늘 결정할 수 있는지가 갈린다"* 고 한 질문이다.

```
✅ **함수별(per-service)이다.** 프로젝트 전체가 아니다.
```

**근거 셋 — 셋 다 원문/실물이다.**

```
① Cloud Run 공식 문서 (static outbound IP)
   "deploy or update your Cloud Run service with Direct VPC egress or the
    Serverless VPC Access connector, and set the VPC egress to route all
    traffic through the VPC network"
   → **서비스 단위로 건다.** Cloud Functions 2세대는 Cloud Run 서비스다
   https://docs.cloud.google.com/run/docs/configuring/static-outbound-ip (2026-09-06 확인)

② 우리가 쓰는 패키지 실측 — firebase-functions **7.3.2**
   node_modules/firebase-functions/lib/v2/options.d.ts
     vpcConnector · vpcConnectorEgressSettings · vpcEgress   (GlobalOptions 필드)
     NetworkInterface { network, subnetwork, tags }          (Direct VPC egress)
   node_modules/firebase-functions/lib/v2/providers/https.d.ts:14
     interface HttpsOptions extends Omit<GlobalOptions, "region"|"enforceAppCheck">
   → **`onCall({...}, handler)` 에 함수마다 줄 수 있다**

③ 우리 함수는 **2세대가 맞다** — index.ts:41 `from "firebase-functions/v2/https"`
   지역 `asia-northeast3` (index.ts:894)
```

⭐ **그러니 오늘 결정할 수 있는 크기다.** 나머지 함수의 나가는 경로는 안 바뀐다.

### 🚨 다만 「둘」이 아니라 **다른 둘**이다

인계에는 *"`phoneOtpRequest`·`phoneOtpConfirm` 둘에만"* 이라고 돼 있었는데,
**실측하니 발송하는 것은 다음 둘이다.**

```
✅ phoneOtpRequest    AligoSender 를 부른다
✅ adminOtpRequest    AligoSender 를 부른다     ← 인계 목록에 없었다
❌ phoneOtpConfirm    발송 안 한다 (확인만)
❌ adminOtpConfirm    발송 안 한다
```

⚠️ **`adminOtpRequest` 를 빼면 관리자 2차 인증 문자가 안 나간다.** 그런데 그것은
**아직 안 켜져 있어**(`config/phoneVerification` 없음 · `adminSessionRequired()`
= false) **당장은 안 드러나고, 켜는 날 드러난다.**

📌 재는 법: `functions/src/index.ts` 에서 각 진입점 블록 안의 `AligoSender` 참조를
셌다. `phoneOtpSender.ts` 는 모듈이라 그 자체로는 안 나간다.

---

## 1. ① 어떻게 붙이나 — 갑/을 둘 다 **코드로** 된다

### 공통으로 필요한 것 (어느 쪽이든)

```
VPC 네트워크 + 서브넷        (default 도 쓸 수 있다)
Cloud Router                asia-northeast3
예약 고정 외부 IP            asia-northeast3
Cloud NAT 게이트웨이         그 IP 를 나가는 주소로 쓴다
＋ 함수에 vpcEgress = ALL_TRAFFIC
```

⚠️ **`ALL_TRAFFIC` 이어야 한다.** 기본값 `PRIVATE_RANGES_ONLY` 는 사설 대역만
VPC 로 보내므로 **알리고(공인 IP)로 가는 트래픽은 그대로 나간다** — 고정이 안 된다.
(값 이름은 `options.d.ts:16` 실측 · Cloud Run 문서의 `private-ranges-only` /
`all-traffic` 과 같은 것이다.)

### 갑 — Direct VPC egress (2세대 전용, 커넥터 없음)

```ts
export const phoneOtpRequest = onCall(
  {
    region: "asia-northeast3",
    networkInterface: {network: "default", subnetwork: "default"},
    vpcEgress: "ALL_TRAFFIC",
    // …기존 옵션
  },
  async (request) => { /* … */ },
);
```

⭐ **공식 문서가 이쪽을 권한다**:
> *"Direct VPC egress scales to zero, eliminating the baseline compute overhead
> and idle costs associated with connector instances."*
> — https://docs.cloud.google.com/functions/docs/networking/network-settings (2026-09-06)

### 을 — Serverless VPC Access 커넥터 (구식)

```ts
{ vpcConnector: "projects/…/locations/asia-northeast3/connectors/NAME",
  vpcEgress: "ALL_TRAFFIC" }
```

⚠️ **커넥터 인스턴스가 상시 뜬다** — 위 인용의 *"idle costs"* 가 그것이다.
`networkInterface` 와 **상호 배타**다(`options.d.ts:30·37·43` 이 *"Mutually
exclusive with vpcConnector"* 라고 세 번 적어 두었다).

### ⭐ 비교 — 근거가 있는 것만

| | 갑 Direct VPC egress | 을 커넥터 |
|---|---|---|
| 상시 인스턴스 | **없다** (0으로 줄어든다) | **있다** |
| 만들 것 | 없음 (함수 옵션만) | 커넥터 리소스 |
| 공식 권고 | ✅ *"consider switching to Direct VPC egress"* | 전환 대상으로 언급됨 |
| 2세대 필요 | 필요 (우리는 2세대다) | 1세대에서도 됨 |

📌 **단순함·비용 둘 다 갑이 낫다는 것이 공식 문서의 서술이다.** ⬜ 다만 **금액으로는
못 쟀다**(아래 §2).

---

## 2. ③ 비용 — 🚨 **못 쟀다**

⚠️ **못 잰 것을 「싸다」로 적지 않는다.**

```
확인된 것   과금 항목(SKU)의 **이름**은 확인했다
            Networking Cloud Nat Gateway Uptime     32E2-4EFC-EF9F
            Networking Cloud Nat Data Processing    015F-5732-FFF0
            Networking Cloud NAT IP Usage           8515-9425-D2CE
            https://cloud.google.com/skus/sku-groups/nat-gateway (2026-09-06)

못 잰 것    🚨 **요율(시간당·GB당)** — 가격 표가 스크립트로 그려져 원문에서 숫자를
            못 읽었다. `cloud.google.com/nat/pricing` · `vpc/network-pricing` 둘 다
            같았다
            🚨 **asia-northeast3 요율이 다른지**
            🚨 **무료 등급이 있는지**
```

📌 **재는 법**: Google Cloud 가격 계산기에서 지역 `asia-northeast3` 로 넣거나,
콘솔의 **가격 책정** 화면에서 위 SKU ID 로 조회하면 나온다. **globe2030님 계정이
있어야 한다.**

⭐ **다만 트래픽 전제는 적어 둔다** — 인증 문자는 **건당 수 KB 미만**이고 발송
건수도 적다. **데이터 처리 요금은 사실상 무시할 수 있고, 고정비(게이트웨이 가동
시간 + IP 예약)가 사실상 전부**일 것으로 보인다. ⚠️ **이것은 계산이지 실측이 아니다.**

🚨 **그리고 예약 IP 는 「안 쓰면 더 비싸지는」 종류다** — 만들어 놓고 안 붙이면
유휴 요금이 붙는 것이 GCP 의 일반적 구조다. ⬜ **이것도 요율을 못 읽어 확인 못 했다.**

---

## 3. ④ 명령 — 🚨 **적어만 둔다. 실행하지 않았다**

`gcloud` 는 globe2030님 권한이다. **되돌리는 명령을 함께 적는다** — 잘못 만들면
**돈이 계속 나간다.**

```bash
PROJECT=connection-sense
REGION=asia-northeast3
NET=default                 # 기존 VPC 를 쓴다면
ROUTER=otp-router
IPNAME=otp-egress-ip
NAT=otp-nat

# ① Cloud Router
gcloud compute routers create $ROUTER --network=$NET --region=$REGION --project=$PROJECT

# ② 고정 외부 IP 예약  ← 🚨 알리고에 등록할 그 주소가 여기서 나온다
gcloud compute addresses create $IPNAME --region=$REGION --project=$PROJECT
gcloud compute addresses describe $IPNAME --region=$REGION --project=$PROJECT --format='value(address)'

# ③ Cloud NAT
gcloud compute routers nats create $NAT \
  --router=$ROUTER --region=$REGION --project=$PROJECT \
  --nat-custom-subnet-ip-ranges=$NET \
  --nat-external-ip-pool=$IPNAME

# ④ 함수는 gcloud 가 아니라 **코드 옵션 + firebase deploy** 로 건다 (§1)
```

### 되돌리기 — 만든 역순

```bash
gcloud compute routers nats delete $NAT --router=$ROUTER --region=$REGION --project=$PROJECT
gcloud compute routers delete $ROUTER --region=$REGION --project=$PROJECT
gcloud compute addresses delete $IPNAME --region=$REGION --project=$PROJECT   # 🚨 이걸 빼면 계속 과금된다
# 함수 쪽은 옵션을 지우고 다시 배포하면 원래대로 나간다
```

⚠️ **순서가 중요하다** — NAT 가 IP 를 쓰는 동안에는 IP 를 못 지운다.

### 🚨 확인 — 정말 그 IP 로 나가는가

**만들고 끝내면 안 된다.** 함수에서 바깥 IP 조회 서비스를 한 번 부르거나,
**알리고에 등록한 뒤 실제로 문자 한 통을 보내 본다.** 📌 **「설정했다」가 「그 IP 로
나간다」가 아니다** — 이 저장소가 오늘 하루에 그 구분으로 네 번 틀렸다.

---

## 4. ⑤ 다른 길 — 사실만

```
알리고 IP 제한 해제      ⬜ **확인 못 했다.** 문의 창구가 있는지도 안 봤다
                        📌 PM 이 매뉴얼 원문을 확인했다 —
                        "국내 모든 문자 서비스 사업자는 미리 등록된 IP 주소에서만
                         문자를 보낼 수 있게 허용합니다"
                        (manual.themango.co.kr/aligo_api · PM 이 2026-09-06 확인)
                        ⚠️ **나는 이 문장을 직접 안 봤다** — 전달받은 것이다

다른 대행사로 옮기기      템플릿 **재심사 영업일 2일**이 든다.
                        globe2030님이 *"지금 템플릿은 수정 못 해"* 라고 하셨다
                        ⚠️ 사실만 적는다. 권하지 않는다

등록 가능 IP 수          약 40개 · **추가 가능** (globe2030님 화면 확인)
🚨 기존 IP 1.220.56.227  **절대 지우지 않는다** — 회사 기존 서비스가 그날로 멈춘다
                        **옆에 추가**하는 것이다
```

---

## 5. ⬜ 이 조사가 못 본 것

```
⬜ 요율(금액) — §2. **가장 큰 구멍이다**
⬜ 알리고가 IP 를 **몇 개까지** 실제로 받는지 · 등록에 걸리는 시간
⬜ Direct VPC egress 가 `asia-northeast3` 에서 되는지 — 지역 제한을 못 확인했다
⬜ 우리 프로젝트에 VPC/서브넷이 지금 어떤 상태인지 — `gcloud` 를 안 돌렸다
⬜ ALL_TRAFFIC 으로 바꾸면 **그 함수의 다른 바깥 호출**(Gemini·카카오·네이버)도
   같은 길로 간다. **함수별이라 범위는 좁지만 0은 아니다**
   🚨 `phoneOtpRequest`·`adminOtpRequest` 가 알리고 말고 또 무엇을 부르는지 안 셌다
```

⚠️ **마지막 줄이 중요하다.** 「함수별이라 안전하다」가 「그 함수 안에서도 알리고만
바뀐다」는 뜻이 아니다 — **그 함수의 모든 바깥 호출이 NAT 를 탄다.**
