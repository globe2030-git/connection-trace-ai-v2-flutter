/**
 * 인증번호를 **보내는 곳**. 이 파일 하나가 발송사에 묶인 전부다.
 *
 * ## 왜 떼어 냈나
 *
 * 발송사(알리고) 키가 아직 없다. `phoneOtp.ts`가 *"만들고·재고·판정하는"*
 * 전부를 키 없이 하고, **키가 필요한 조각은 여기 하나**다. 키가 오면
 * 이 파일의 구현체 하나만 갈아 끼운다.
 *
 * ## 구현체가 셋인 이유
 *
 * ```
 * NoKeySender    키가 하나도 없다      안 보낸다. 테스트 번호 + 고정 코드
 * AligoSender    키 있음 · testMode Y  알리고까지 왕복하되 실제 발송 X
 * AligoSender    키 있음 · testMode N  실제로 보낸다
 * ```
 *
 * ⭐ 알리고가 `testMode`를 직접 준다(공식 예제 `6_send_alimtalk.py`). 그래서
 * **키가 생기면 우리가 발송을 흉내 낼 필요가 없다.** ⚠️ 다만 `testMode`도
 * apikey·userid·senderkey·tpl_code가 있어야 부를 수 있어서, **키가 하나도
 * 없는 지금은 [NoKeySender]가 여전히 필요하다.**
 *
 * ## 🚨 이 파일이 절대 하지 않는 것
 *
 * ```
 * 인증번호를 로그에 찍지 않는다
 * 전화번호를 로그에 찍지 않는다        있음/없음·길이만
 * 키를 로그·에러 메시지에 담지 않는다
 * ```
 */

/**
 * 🚨 **알림톡 템플릿 본문. 등록도 발송도 이 상수 하나로 한다.**
 *
 * 알리고 공식 예제가 못박은 함정이 여기 있다 —
 * *"등록한 템플릿이랑 **개행문자 포함 동일하게** 입력."*
 * **한 글자, 줄바꿈 하나만 달라도 발송이 거부된다.**
 *
 * 📌 그래서 문안을 **두 벌로 두지 않는다.** 템플릿을 등록할 때도 이 상수를
 * 쓰고 보낼 때도 이 상수를 쓴다. 두 벌이면 언젠가 어긋나고, 어긋나면
 * **템플릿 재심사(영업일 2일)**가 든다.
 *
 * 확정 문안 출처: `docs/marketing/alimtalk-application-kit-2026-08-27.md` 3-1.
 * ⚠️ **「3분」이 본문에 박혀 있다** — `OTP_TTL_MS`를 바꾸면 이 문안도 바뀌고,
 * 그러면 재심사다. 두 값이 함께 움직인다는 것을 잊지 말 것.
 */
/**
 * 🚨 **서비스 이름이 나오는 자리는 여기 하나다.**
 *
 * 앱 이름이 아직 안 정해졌다 — 2026-08-28에 「기별」이 취소되고
 * **커넥션센스 · 컨택센스 · 커넥트센스 중 미정**이다. 그 사이에 문안이
 * 흩어져 있으면 이름이 정해질 때 **어디를 고쳐야 하는지 세어야 한다.**
 *
 * 📌 지금 값은 **「커넥션센스」**다 — 홈페이지·개인정보처리방침·이용약관이
 * 아직 그 이름이고, 알림톡 심사는 **채널명·홈페이지·사업자등록증의 대응**을
 * 본다(추가 548). 문안만 앞서 나가면 그 대응이 깨진다.
 *
 * 🚨 **이 값을 바꾸면 템플릿 재심사다**(영업일 2일). 그래서 **심사 신청 전에
 * 이름이 확정돼야 한다.** 코드에는 자리만 만들어 두고, 실제 심사는 이름이
 * 정해진 뒤에 넣는다.
 */
export const OTP_SERVICE_NAME = "커넥션센스";

export const OTP_TEMPLATE_BODY = `[${OTP_SERVICE_NAME}] 휴대폰 인증

요청하신 인증번호는 #{인증번호} 입니다.
3분 안에 앱 화면에 입력해 주세요.

본인이 요청하지 않았다면 다른 분이 번호를 잘못 입력했을 수 있습니다.
인증번호는 누구에게도 알려주지 마세요.`;

/** 템플릿 변수 이름. 본문의 `#{인증번호}`와 짝이다. */
export const OTP_TEMPLATE_VARIABLE = "#{인증번호}";

/**
 * 알림톡 제목. ⚠️ **수신자에게는 안 보인다**(공식 예제 주석). 발송 기록을
 * 사람이 알아보기 위한 값이다.
 */
export const OTP_TEMPLATE_SUBJECT = "휴대폰 인증";

/**
 * 대체문자(failover) 본문. 알림톡이 실패하면 **알리고가 같은 호출 안에서**
 * 문자로 떨어뜨린다 — 우리가 두 번 부르지 않는다.
 *
 * ⚠️ 공식 예제 주석의 함정: *"템플릿 신청시 대체문자 발송으로 설정하였더라도
 * **Y로 입력해야 합니다**"* — **둘 다** 해야 한다.
 *
 * 📌 문자는 길이 제한이 빡빡하므로 알림톡 본문보다 짧게 둔다.
 */
export const OTP_FAILOVER_BODY = `[${OTP_SERVICE_NAME}] 인증번호 #{인증번호}
3분 안에 입력해 주세요.`;

export const OTP_FAILOVER_SUBJECT = `${OTP_SERVICE_NAME} 인증번호`;

/**
 * 템플릿 본문에 인증번호를 끼워 넣는다.
 *
 * 🚨 **변수만 바꾸고 나머지는 한 글자도 건드리지 않는다.** 그것이 발송이
 * 거부되지 않는 유일한 방법이다.
 */
export function renderOtpMessage(code: string, template: string): string {
  return template.split(OTP_TEMPLATE_VARIABLE).join(code);
}

/** 발송 결과. 🚨 성공/실패와 「왜」만 담는다 — 번호·코드는 담지 않는다. */
export type SendOutcome =
  | {sent: true; via: "aligo" | "aligo-test" | "none"}
  | {sent: false; reason: string};

/** 인증번호를 보내는 곳. 이 인터페이스가 발송사와 나머지를 가른다. */
export interface OtpSender {
  send(e164: string, code: string): Promise<SendOutcome>;
}

/**
 * 키가 하나도 없을 때 쓰는 발송기. **아무것도 보내지 않는다.**
 *
 * ⭐ 테스트 번호는 `phoneOtp.TEST_PHONE_FIXED_CODE`를 쓰므로 **인증번호를 아예 만들지
 * 않는다** — 화면·응답·로그 어디로도 흐를 경로가 없다. 테스트용으로 코드를
 * 응답에 실어 주는 방식이었다면, 그 코드가 실수로 운영에 남는 순간 전부
 * 뚫린다.
 *
 * 🚨 **테스트 번호가 아닌 번호로 이 발송기가 불리면 실패로 답한다.** 조용히
 * 성공을 돌려주면 *"문자가 안 오는데 화면은 다음으로 넘어가는"* 상태가 되고,
 * 그건 고장보다 나쁘다.
 */
export class NoKeySender implements OtpSender {
  async send(): Promise<SendOutcome> {
    return {
      sent: false,
      reason: "발송사 키가 아직 없습니다(테스트 번호만 가능).",
    };
  }
}

/** 알리고 호출에 필요한 값들. 🚨 전부 시크릿이고 저장소에 두지 않는다. */
export interface AligoConfig {
  apikey: string;
  userid: string;
  /** 발신프로필 키. */
  senderkey: string;
  /** 템플릿 코드. */
  tplCode: string;
  /** 발신번호. */
  sender: string;
  /** `true`면 `testMode: 'Y'` — 알리고까지 가되 실제 발송은 안 한다. */
  testMode: boolean;
}

/** 알리고에 보낼 발송 파라미터. 공식 예제 `6_send_alimtalk.py`의 키 이름 그대로. */
export interface AligoSendPayload {
  /**
   * 값이 전부 문자열이라 인덱스 시그니처를 둔다 — form-urlencoded로 그대로
   * 넘기기 위해서다. 필드가 늘어도 문자열이어야 한다는 규칙이 남는다.
   */
  [key: string]: string;
  apikey: string;
  userid: string;
  token: string;
  senderkey: string;
  tpl_code: string;
  sender: string;
  receiver_1: string;
  subject_1: string;
  message_1: string;
  failover: "Y" | "N";
  fsubject_1: string;
  fmessage_1: string;
  testMode: "Y" | "N";
}

/**
 * 발송 파라미터를 만든다. **HTTP를 타지 않는 순수 함수라 테스트할 수 있다.**
 *
 * 🚨 `receiver`는 알리고가 **국내 번호 형식(`01012345678`)**을 받는다 —
 * 우리 내부 표준인 E.164(`+8210…`)를 그대로 넣으면 안 된다.
 */
export function buildAligoSendPayload(
  config: AligoConfig,
  token: string,
  e164: string,
  code: string,
): AligoSendPayload {
  return {
    apikey: config.apikey,
    userid: config.userid,
    token,
    senderkey: config.senderkey,
    tpl_code: config.tplCode,
    sender: config.sender,
    receiver_1: e164ToKrLocal(e164),
    subject_1: OTP_TEMPLATE_SUBJECT,
    message_1: renderOtpMessage(code, OTP_TEMPLATE_BODY),
    // ⚠️ 템플릿 신청에서 대체문자를 켰더라도 여기서 Y를 줘야 한다(공식 예제 주석).
    failover: "Y",
    fsubject_1: OTP_FAILOVER_SUBJECT,
    fmessage_1: renderOtpMessage(code, OTP_FAILOVER_BODY),
    testMode: config.testMode ? "Y" : "N",
  };
}

/** `+821012345678` → `01012345678`. 알리고가 받는 모양으로 되돌린다. */
export function e164ToKrLocal(e164: string): string {
  return e164.startsWith("+82") ? `0${e164.slice(3)}` : e164;
}

/** 토큰 생성 주소. 🚨 유효시간이 짧다 — **보낼 때마다 새로 만든다.** */
export const ALIGO_TOKEN_URL = "https://kakaoapi.aligo.in/akv10/token/create/30/s/";
export const ALIGO_SEND_URL = "https://kakaoapi.aligo.in/akv10/alimtalk/send/";

/**
 * 알리고 응답에서 성공 여부를 읽는다. **순수 함수라 테스트할 수 있다.**
 *
 * ⚠️ 알리고는 HTTP 200으로 실패를 돌려준다 — 본문의 `code`를 봐야 한다.
 * 공식 문서에 코드 표가 없어서(예제가 문서보다 정확하다) **0을 성공으로,
 * 나머지를 실패로** 본다. ⬜ 실제 코드 표는 키가 생긴 뒤 확인한다.
 */
export function readAligoResult(body: unknown): {ok: boolean; message: string} {
  if (body === null || typeof body !== "object") {
    return {ok: false, message: "응답을 읽지 못했습니다."};
  }
  const rec = body as Record<string, unknown>;
  const rawCode = rec.code;
  const code = typeof rawCode === "number" ? rawCode : Number(rawCode);
  const message = typeof rec.message === "string" ? rec.message : "";
  return {ok: code === 0, message};
}

/**
 * 알리고로 실제 호출하는 발송기. `testMode`는 [AligoConfig]에서 온다.
 *
 * 🚨 **토큰을 매번 새로 만든다.** 공식 예제의 토큰 주소가
 * `token/create/30/s/` — **30초**다. 캐시하려면 만료를 직접 관리해야 하는데,
 * 인증번호 발송은 드물어서 **매번 만드는 쪽이 싸고 안전하다.**
 *
 * ⚠️ 이 클래스는 **테스트에서 돌리지 않는다**(HTTP를 탄다). 테스트가 덮는
 * 것은 [buildAligoSendPayload]·[readAligoResult]·[renderOtpMessage] 같은
 * 순수 함수들이고, 그것이 이 파일에서 틀리기 쉬운 전부다.
 */
export class AligoSender implements OtpSender {
  constructor(private readonly config: AligoConfig) {}

  async send(e164: string, code: string): Promise<SendOutcome> {
    let token: string;
    try {
      token = await this.createToken();
    } catch (e) {
      // 🚨 원문 예외를 그대로 올리지 않는다 — 키가 실려 있을 수 있다.
      return {sent: false, reason: `토큰 생성 실패: ${describeError(e)}`};
    }

    const payload = buildAligoSendPayload(this.config, token, e164, code);
    try {
      const res = await postForm(ALIGO_SEND_URL, payload);
      const result = readAligoResult(res);
      if (!result.ok) {
        return {sent: false, reason: `발송 거부: ${result.message}`};
      }
      return {sent: true, via: this.config.testMode ? "aligo-test" : "aligo"};
    } catch (e) {
      return {sent: false, reason: `발송 호출 실패: ${describeError(e)}`};
    }
  }

  private async createToken(): Promise<string> {
    const body = await postForm(ALIGO_TOKEN_URL, {
      apikey: this.config.apikey,
      userid: this.config.userid,
    });
    const rec = body as Record<string, unknown>;
    const token = rec?.token;
    if (typeof token !== "string" || token.length === 0) {
      throw new Error("토큰이 응답에 없습니다.");
    }
    return token;
  }
}

/** form-urlencoded로 POST하고 JSON을 읽는다. */
async function postForm(
  url: string,
  fields: Record<string, string>,
): Promise<unknown> {
  const body = new URLSearchParams(fields).toString();
  const res = await fetch(url, {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body,
  });
  return res.json();
}

/**
 * 예외를 사람이 읽을 한 줄로 줄인다.
 *
 * 🚨 **원문 메시지를 그대로 쓰지 않는다** — 요청 본문이 실려 있으면 키·번호·
 * 인증번호가 그대로 로그로 샌다. 종류만 남긴다.
 */
function describeError(e: unknown): string {
  if (e instanceof Error) return e.name;
  return "알 수 없는 오류";
}
