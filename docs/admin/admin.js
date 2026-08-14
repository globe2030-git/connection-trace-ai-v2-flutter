// 커넥션센스 관리자 콘솔.
//
// 관리자 등록 방식(2026-08-06): Firebase 콘솔에 들어가 계정을 만들거나
// Firestore에 문서를 손으로 추가할 필요가 없다. 이 페이지에서 지정된
// 이메일(firestore.rules의 isAdmin() 허용목록)로 직접 회원가입하면
// 이메일 인증 후 그대로 관리자가 된다.
// ⚠️ 관리자를 추가/제거하려면 firestore.rules의 isAdmin() 배열과
// functions/src/adminEmails.ts의 ADMIN_EMAILS를 **둘 다** 고쳐야 한다
// (2026-08-14, ADMIN-VULN-001) — 자세한 절차는 docs/admin/README.md
// "관리자 판별 방식" 참고.
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
import {
  getAuth, signInWithEmailAndPassword, createUserWithEmailAndPassword,
  sendEmailVerification, onAuthStateChanged, signOut,
  GoogleAuthProvider, signInWithPopup,
  setPersistence, browserSessionPersistence,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";
import {
  getFirestore, collection, doc, getDoc, getDocs, addDoc, updateDoc, deleteDoc,
  setDoc, query, where, orderBy, limit, startAfter, serverTimestamp, Timestamp,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-firestore.js";
import {
  getFunctions, httpsCallable,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-functions.js";

const firebaseConfig = {
  apiKey: "AIzaSyA71ZLPoz3YZR0X3-g2P_uBXM4rK41D3kU",
  authDomain: "connection-sense.firebaseapp.com",
  projectId: "connection-sense",
  storageBucket: "connection-sense.firebasestorage.app",
  appId: "1:79345379389:web:483f3096c5d7d484182254",
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
// 관리자 세션은 탭/브라우저를 닫으면 끝나도록 session persistence로 고정한다
// (ADMIN-VULN-012). 기본값(browserLocalPersistence)은 브라우저를 껐다 켜도
// 세션이 복원돼, 공유·타인 단말에 관리자 세션이 남는 위험이 있었다.
// setPersistence는 이후의 signIn에 적용되므로 로그인보다 먼저 건다.
setPersistence(auth, browserSessionPersistence).catch((e) =>
  console.warn("세션 지속성 설정 실패:", e.message));
const db = getFirestore(app);
// Cloud Functions는 서울 리전(asia-northeast3)에 배포돼 있다 — 리전을 안 맞추면
// httpsCallable이 기본(us-central1)으로 호출해 not-found가 난다.
const functions = getFunctions(app, "asia-northeast3");
const getUserUsageFn = httpsCallable(functions, "getUserUsage");
const grantSupportCreditsFn = httpsCallable(functions, "grantSupportCredits");

const $ = (sel) => document.querySelector(sel);
const loginScreen = $("#loginScreen");
const dashboard = $("#dashboard");

// ---------- 관리자 감사 로그 (ADMIN-VULN-010, 인터림) ----------
// 대상 문서 쓰기(예: config/billing 저장)와 이 기록 생성이 같은 트랜잭션이
// 아니라서, 악성/탈취 관리자가 대상 문서만 쓰고 이 호출을 의도적으로
// 생략하면 감사에 안 남는다 — 완전한 위조 방지가 아니라 인터림 조치다
// (firestore.rules의 adminAuditLogs 주석 참고). 그래서 주 작업이 이미
// 성공한 직후에만 호출하고, 이 기록 자체의 실패는 조용히 흡수해 주 작업을
// 되돌리지 않는다. summary에는 절대 이메일·문의 본문 등 개인정보를 넣지 않는다.
async function logAdminAudit(action, target, summary) {
  try {
    await addDoc(collection(db, "adminAuditLogs"), {
      actorUid: auth.currentUser.uid,
      actorEmail: auth.currentUser.email,
      action, target, summary,
      at: serverTimestamp(),
    });
  } catch (e) {
    console.warn("감사 기록 실패(주 작업은 이미 완료됨):", e.message);
  }
}

// ---------- 로그인 / 회원가입 ----------

$("#loginBtn").addEventListener("click", async () => {
  const email = $("#loginEmail").value.trim();
  const password = $("#loginPassword").value;
  $("#loginError").innerHTML = "";
  if (!email || !password) return;
  try {
    await signInWithEmailAndPassword(auth, email, password);
  } catch (e) {
    $("#loginError").innerHTML =
      `<div class="error">로그인에 실패했습니다: ${escapeHtml(e.message)}</div>`;
  }
});

$("#signupToggle").addEventListener("click", () => {
  const isSignup = $("#signupFields").style.display !== "none";
  $("#signupFields").style.display = isSignup ? "none" : "block";
  $("#loginBtn").style.display = isSignup ? "inline-block" : "none";
  $("#signupBtn").style.display = isSignup ? "none" : "inline-block";
  $("#signupToggle").textContent = isSignup ? "회원가입" : "로그인 화면으로";
  $("#loginError").innerHTML = "";
});

$("#signupBtn").addEventListener("click", async () => {
  const email = $("#loginEmail").value.trim();
  const password = $("#loginPassword").value;
  const passwordConfirm = $("#signupPasswordConfirm").value;
  $("#loginError").innerHTML = "";
  if (!email || !password) return;
  if (password !== passwordConfirm) {
    $("#loginError").innerHTML = `<div class="error">비밀번호가 서로 다릅니다.</div>`;
    return;
  }
  try {
    const cred = await createUserWithEmailAndPassword(auth, email, password);
    await sendEmailVerification(cred.user);
    await signOut(auth);
    $("#loginError").innerHTML =
      `<div class="error" style="background:var(--good-soft); color:var(--good);">` +
      `가입되었습니다. ${escapeHtml(email)}으로 보낸 인증 메일의 링크를 클릭한 뒤 로그인해주세요.</div>`;
  } catch (e) {
    $("#loginError").innerHTML =
      `<div class="error">가입에 실패했습니다: ${escapeHtml(e.message)}</div>`;
  }
});

// 구글 계정 로그인 — 이메일/비밀번호와 달리 별도 이메일 인증이 필요 없다
// (구글이 이미 소유를 확인했으므로). 이미 앱에서 구글 로그인을 쓰는
// creamhouse.net 계정들(예: globe@creamhouse.net)은 비밀번호가 아예
// 없는 구글 전용 계정이라, 이 버튼으로만 관리자 콘솔에 들어올 수 있다.
$("#googleLoginBtn").addEventListener("click", async () => {
  $("#loginError").innerHTML = "";
  try {
    await signInWithPopup(auth, new GoogleAuthProvider());
  } catch (e) {
    $("#loginError").innerHTML =
      `<div class="error">구글 로그인에 실패했습니다: ${escapeHtml(e.message)}</div>`;
  }
});

// 로그아웃은 세션 종료 후 페이지를 새로고침해 렌더된 DOM(문의 이메일·UID·
// 정산 등)과 메모리 상태를 통째로 버린다(ADMIN-VULN-012). 예전엔 signOut만
// 호출해 대시보드를 숨기기만 했고, 민감 데이터가 DOM/JS에 그대로 남았다.
$("#logoutBtn").addEventListener("click", async () => {
  try {
    await signOut(auth);
  } finally {
    location.reload();
  }
});

onAuthStateChanged(auth, async (user) => {
  if (!user) {
    loginScreen.style.display = "block";
    dashboard.classList.remove("visible");
    return;
  }
  if (!user.emailVerified) {
    const pendingUser = user;
    $("#loginError").innerHTML = `
      <div class="error">이메일 인증이 필요합니다. 받은 메일함에서 인증 링크를 클릭한 뒤 다시 로그인해주세요.</div>
      <div class="row" style="margin-top:8px;">
        <button class="btn-ghost" id="resendVerificationBtn" type="button">인증 메일 재발송</button>
      </div>
    `;
    $("#resendVerificationBtn").addEventListener("click", async () => {
      try {
        await sendEmailVerification(pendingUser);
        $("#loginError").innerHTML =
          `<div class="error" style="background:var(--good-soft); color:var(--good);">` +
          `인증 메일을 다시 보냈습니다. 메일함을 확인해주세요.</div>`;
      } catch (e) {
        $("#loginError").innerHTML = `<div class="error">재발송 실패: ${escapeHtml(e.message)}</div>`;
      }
    });
    await signOut(auth);
    return;
  }
  // 이메일이 firestore.rules의 허용목록에 없으면 "관리자만 통과하는 쿼리"가
  // 그대로 실패한다 — notices를 published 필터 없이 전부 조회하는 건
  // isAdmin()만 통과할 수 있다.
  try {
    await getDocs(collection(db, "notices"));
  } catch (e) {
    $("#loginError").innerHTML =
      `<div class="error">이 계정(${escapeHtml(user.email ?? "")})은 관리자로 등록되지 않았습니다.</div>`;
    await signOut(auth);
    return;
  }
  $("#whoAmI").textContent = user.email ?? "";
  loginScreen.style.display = "none";
  dashboard.classList.add("visible");
  initTabs();
  await loadNotices();
  await loadInquiries();
  await loadLegalDocs();
  loadReports();
  await loadBilling();
  await loadTesters();
  await loadUsageLogs();
  await loadOcrStats();
  await loadAppUpdate();
});

// ---------- 경영 리포트 ----------
// (2026-08-14, ADMIN-VULN-008로 정정) 예전에는 이 목록의 파일들을
// docs/admin/reports/ 아래 정적 HTML로 두고 admin hosting 타겟과 함께
// 그대로 배포했다 — 그런데 admin hosting 타겟에는 인증이 없어서 임원용
// 손익보고서가 로그인 없이 누구나 열람 가능한 URL로 공개돼 버렸다(취약점
// ADMIN-VULN-008). 그래서 해당 문서를 docs/planning/business/ 아래
// 저장소 전용 위치로 되돌렸다 — Hosting에는 올라가지 않고, 이 화면에는
// 링크 대신 "저장소에서 직접 열람하라"는 안내만 보여준다.
const REPORTS = [
  {
    title: "프리미엄 구독 손익분석",
    desc: "무료:유료 전환 시나리오, 규모별 손익, AI 파싱 도입 영향 등",
    repoPath: "docs/planning/business/pnl-analysis-freemium.html",
  },
];

function loadReports() {
  const panel = $("#tab-reports");
  panel.innerHTML = `
    <div class="card">
      <p class="hint" style="margin-top:0;">
        경영 리포트는 비공개 내부 문서라 Hosting에 배포하지 않습니다.
        아래 목록의 저장소 경로에서 직접 열어 확인하세요.
      </p>
      <div id="reportList"></div>
    </div>
  `;
  const list = $("#reportList");
  list.innerHTML = "";
  for (const r of REPORTS) {
    const item = document.createElement("div");
    item.className = "list-item";
    item.innerHTML = `
      <div>
        <div class="title">${escapeHtml(r.title)}</div>
        <div class="meta">${escapeHtml(r.desc)}</div>
      </div>
      <div class="meta" style="text-align:right; max-width:60%;">
        이 문서는 Hosting에 배포하지 않는 비공개 내부 문서입니다.<br/>
        저장소 <code>${escapeHtml(r.repoPath)}</code>에서 직접 열람하세요.
      </div>
    `;
    list.appendChild(item);
  }
}

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str ?? "";
  return div.innerHTML;
}

// ---------- 충전 관리 ----------
// 과금 모델은 충전형(소모성)이다(2026-08-11 결정, backlog 추가 153):
// 무료 10회 이후 1,000/3,000/5,000/10,000/30,000/50,000/100,000원 충전. 이 탭은 세 가지를 맡는다.
// ① 상품 설정: 티어별 제공 회수·무료 횟수(config/billing) — 회수는 테스트
//    기간 AI 비용 실측 후 확정하므로 코드 배포 없이 여기서 조정한다.
// ② 충전 내역 조회(고객응대): "결제했는데 안 들어왔어요" 문의 대응.
// ③ 정산 요약: 월별 충전 건수·금액·예상 정산액 + CSV 내려받기.
// purchases 기록은 영수증 검증 서버(P1-4)만 쓴다 — IAP 구현 전까지는
// 기록이 없는 게 정상이고, 빈 상태를 그대로 보여준다(가짜 데이터 금지).

const TIER_PRICES = [1000, 3000, 5000, 10000, 30000, 50000, 100000];
// 부가세 제외(÷1.1) 후 스토어 수수료 15% 공제 — backlog 추가 153의 정산 감각.
const NET_RATE = (1 / 1.1) * 0.85;

async function getBillingConfig() {
  const snap = await getDoc(doc(db, "config", "billing"));
  const data = snap.exists() ? snap.data() : {};
  return {
    // 과금 모델 스위치(reset/wallet, 2026-08-14 U1). 문서에 필드가 없으면
    // 반드시 "reset"으로 표시한다 — docs/planning/ai-credit-wallet-spec.md
    // §2-4, §3-2. 서버(functions/src/walletCredits.ts)도 같은 폴백 규칙을 쓴다.
    model: data.model === "wallet" ? "wallet" : "reset",
    freeCredits: data.freeCredits ?? 10,
    tiers: TIER_PRICES.map((price) => {
      const found = (data.tiers ?? []).find((t) => t.priceKrw === price);
      return {
        priceKrw: price,
        credits: found?.credits ?? null,
        active: found?.active ?? false,
        // 스토어(App Store Connect/Play Console) 소모성 상품 ID. 아직 실제
        // 상품이 등록되지 않았다(2026-08-15 기준, 스토어 등록은 사용자만
        // 할 수 있는 작업) — 등록 전까지는 비워 두거나 placeholder 문자열을
        // 넣어 둔다. 서버(functions/src/purchases.ts)가 나중에 이 값으로
        // 결제 상품↔크레딧을 매칭한다(U7 "뼈대만", 실제 영수증 검증은
        // 아직 미구현).
        productId: found?.productId ?? "",
      };
    }),
  };
}

async function loadBilling() {
  const panel = $("#tab-billing");
  panel.innerHTML = `
    <div class="card">
      <h3 style="margin-top:0;">충전 상품 설정</h3>
      <p class="hint">
        가격 7단계는 확정, <strong>제공 회수는 테스트 기간 AI 비용 실측 후 확정</strong>
        (미정이면 비워 두세요). 여기 저장한 값은 영수증 검증 서버가 크레딧 지급량으로,
        앱이 충전 화면 표시용으로 읽습니다 — 회수 조정에 앱 배포가 필요 없습니다.
      </p>
      <p class="hint">
        <strong>상품ID</strong>는 App Store Connect/Play Console에 실제 소모성 상품을
        등록한 뒤 그 상품ID를 그대로 붙여넣는 칸입니다. <strong>아직 스토어에 상품이
        등록되지 않았으므로 지금은 비워 두세요</strong> — 비워 두면 결제 검증 서버가
        이 티어를 결제와 매칭하지 못해 크레딧을 지급하지 않습니다(의도된 동작, 결제
        기능 자체가 아직 준비 중입니다).
      </p>
      <div id="tierRows"></div>
      <label style="margin-top:12px;">무료 제공 횟수 (신규 가입 시)</label>
      <div class="row">
        <input type="number" id="freeCredits" min="0" style="width:120px;">
        <button class="btn-primary" id="billingSaveBtn">저장</button>
      </div>
      <div id="billingMsg"></div>
    </div>

    <div class="card">
      <h3 style="margin-top:0;">과금 모델</h3>
      <p class="hint">
        <strong>reset(리셋형)</strong>이 기본값입니다 — 지금 라이브가 쓰는 모델로,
        하루/월 한도가 매일·매월 초기화됩니다.
        <strong>wallet(지갑형)</strong>로 바꾸면 리셋이 사라지고, 무료(가입 시 1회성)
        + 충전 잔액을 다 쓸 때까지 소진하는 방식으로 전환됩니다.
        결제(IAP)가 아직 준비되지 않았다면 반드시 reset을 유지하세요 — wallet
        전환은 결제 버튼이 열린 뒤에만 해야 합니다
        (docs/planning/ai-credit-wallet-spec.md 9절 전환 체크리스트 참고).
      </p>
      <div class="row">
        <select id="billingModel" style="width:220px;">
          <option value="reset">reset — 리셋형 (기본값)</option>
          <option value="wallet">wallet — 지갑형 (리셋 없음)</option>
        </select>
        <button class="btn-primary" id="billingModelSaveBtn">저장</button>
      </div>
      <div id="billingModelMsg"></div>
    </div>

    <div class="card">
      <h3 style="margin-top:0;">충전 내역 조회 (고객응대용)</h3>
      <p class="hint">
        "결제했는데 충전이 안 됐어요" 문의 대응용. 앱 로그인 이메일로 검색합니다.
        기록은 영수증 검증 서버만 남기므로 결제 기능(IAP) 출시 전에는 비어 있는 게 정상입니다.
      </p>
      <div class="row">
        <input type="email" id="purchaseEmail" placeholder="사용자 로그인 이메일" style="flex:1;">
        <button class="btn-primary" id="purchaseSearchBtn">조회</button>
      </div>
      <div id="purchaseResult"></div>
    </div>

    <div class="card">
      <h3 style="margin-top:0;">정산 요약</h3>
      <p class="hint">
        월별 충전 실적. 예상 정산액은 부가세 제외 후 스토어 수수료 15% 공제 기준
        (판매가의 약 77%) — 실제 정산서와는 환율·조정액만큼 다를 수 있습니다.
      </p>
      <div class="row">
        <input type="month" id="settleMonth">
        <button class="btn-primary" id="settleBtn">집계</button>
        <button class="btn-primary" id="settleCsvBtn" style="display:none;">CSV 내려받기</button>
      </div>
      <div id="settleResult"></div>
    </div>
  `;

  // ① 상품 설정 — 현재값 로드
  // ⚠️ 2026-08-15(ADMIN-VULN-004): 예전에는 여기서 Firestore 값(t.credits,
  // t.active)을 innerHTML 템플릿의 HTML 속성(value="...", checked) 안에
  // 이스케이프 없이 그대로 넣었다. firestore.rules의 config/billing 쓰기에
  // 스키마 검증이 없던 시절엔 관리자 세션(탈취/오조작)이 credits에
  // `"><script>...` 같은 문자열을 넣으면 다음 로그인 때 속성탈출 XSS가
  // 실행됐다. 지금은 rules가 스키마를 강제하지만(아래 값들은 안전), 방어
  // 원칙 자체는 유지한다 — 빈 input/checkbox만 innerHTML로 렌더링하고,
  // 실제 값은 loadAppUpdate()와 같은 패턴으로 DOM 프로퍼티로 안전하게 채운다.
  const cfg = await getBillingConfig();
  $("#freeCredits").value = cfg.freeCredits;
  $("#billingModel").value = cfg.model;
  $("#tierRows").innerHTML = cfg.tiers.map((t, i) => `
    <div class="row" style="align-items:center; margin-bottom:6px;">
      <div style="width:110px; font-weight:700;">${t.priceKrw.toLocaleString()}원</div>
      <input type="number" id="tierCredits${i}" min="1" placeholder="회수 미정" style="width:120px;">
      <span class="hint" style="margin:0 4px;">회 제공</span>
      <label style="margin:0; display:flex; align-items:center; gap:4px;">
        <input type="checkbox" id="tierActive${i}"> 판매
      </label>
      <input type="text" id="tierProductId${i}" placeholder="상품ID (스토어 등록 전엔 비워둠)"
        value="${escapeHtml(t.productId ?? "")}" style="flex:1; min-width:160px;">
    </div>
  `).join("");
  cfg.tiers.forEach((t, i) => {
    $(`#tierCredits${i}`).value = t.credits ?? "";
    $(`#tierActive${i}`).checked = !!t.active;
  });

  $("#billingSaveBtn").addEventListener("click", async () => {
    const tiers = TIER_PRICES.map((price, i) => {
      const raw = $(`#tierCredits${i}`).value.trim();
      return {
        priceKrw: price,
        credits: raw === "" ? null : Math.max(1, parseInt(raw, 10) || 0),
        active: $(`#tierActive${i}`).checked,
        // 스토어 상품ID — 등록 전이면 빈 문자열 그대로 저장(placeholder,
        // 서버는 이 값이 실제 판매 중인 productId와 매칭될 때만 크레딧을
        // 지급한다, functions/src/purchases.ts 참고).
        productId: $(`#tierProductId${i}`).value.trim(),
      };
    });
    const bad = tiers.find((t) => t.active && !t.credits);
    if (bad) {
      $("#billingMsg").innerHTML =
        `<div class="error">${bad.priceKrw.toLocaleString()}원 상품은 회수를 정해야 판매로 켤 수 있습니다.</div>`;
      return;
    }
    const freeCredits = Math.max(0, parseInt($("#freeCredits").value, 10) || 0);
    await setDoc(doc(db, "config", "billing"),
      { freeCredits, tiers, updatedAt: serverTimestamp() }, { merge: true });
    await logAdminAudit("billing.save", "config/billing",
      `무료 ${freeCredits}회, 활성 티어 ${tiers.filter((t) => t.active).length}개`);
    $("#billingMsg").innerHTML = `<div class="hint">저장했습니다.</div>`;
  });

  // 과금 모델 스위치 — 상품 설정(회수·가격)과 별개 버튼으로 저장한다.
  // wallet 전환은 되돌리기가 매끄럽지 않은 결정(스펙 §9 롤백 항목)이라
  // 회수 값을 고치다가 실수로 같이 넘어가는 걸 막기 위해서다.
  $("#billingModelSaveBtn").addEventListener("click", async () => {
    const model = $("#billingModel").value === "wallet" ? "wallet" : "reset";
    await setDoc(doc(db, "config", "billing"),
      { model, updatedAt: serverTimestamp() }, { merge: true });
    $("#billingModelMsg").innerHTML = `<div class="hint">저장했습니다. (현재: ${model})</div>`;
  });

  // ② 충전 내역 조회 (이메일)
  $("#purchaseSearchBtn").addEventListener("click", async () => {
    const email = $("#purchaseEmail").value.trim().toLowerCase();
    const box = $("#purchaseResult");
    if (!email) return;
    box.innerHTML = `<p class="hint">조회 중…</p>`;
    try {
      const snap = await getDocs(query(
        collection(db, "purchases"), where("email", "==", email), limit(50)));
      if (snap.empty) {
        box.innerHTML = `<p class="hint">이 이메일의 충전 기록이 없습니다.</p>`;
        return;
      }
      const rows = snap.docs.map((d) => ({ id: d.id, ...d.data() }))
        .sort((a, b) => (b.purchasedAt?.seconds ?? 0) - (a.purchasedAt?.seconds ?? 0));
      box.innerHTML = rows.map((p) => `
        <div class="list-item">
          <div>
            <div class="title">${(p.priceKrw ?? 0).toLocaleString()}원 · ${p.credits ?? "?"}회 충전
              ${p.status === "refunded" ? '<span style="color:#EF4444;">(환불됨)</span>' : ""}</div>
            <div class="hint">${formatDate(p.purchasedAt)} · ${p.platform ?? "-"} ·
              거래 ID ${escapeHtml(p.transactionId ?? p.id)}</div>
          </div>
        </div>
      `).join("");
    } catch (e) {
      box.innerHTML = `<div class="error">조회 실패: ${escapeHtml(e.message)}</div>`;
    }
  });

  // ③ 정산 요약 (월)
  let settleRows = [];
  $("#settleBtn").addEventListener("click", async () => {
    const ym = $("#settleMonth").value; // "2026-08"
    const box = $("#settleResult");
    if (!ym) return;
    box.innerHTML = `<p class="hint">집계 중…</p>`;
    $("#settleCsvBtn").style.display = "none";
    try {
      const [y, m] = ym.split("-").map(Number);
      const start = Timestamp.fromDate(new Date(y, m - 1, 1));
      const end = Timestamp.fromDate(new Date(y, m, 1));
      const snap = await getDocs(query(
        collection(db, "purchases"),
        where("purchasedAt", ">=", start), where("purchasedAt", "<", end)));
      settleRows = snap.docs.map((d) => ({ id: d.id, ...d.data() }))
        .filter((p) => p.status !== "refunded");
      const refunded = snap.size - settleRows.length;
      if (settleRows.length === 0) {
        box.innerHTML = `<p class="hint">${ym} 충전 기록이 없습니다.${refunded ? ` (환불 ${refunded}건 제외)` : ""}</p>`;
        return;
      }
      const total = settleRows.reduce((s, p) => s + (p.priceKrw ?? 0), 0);
      const byTier = TIER_PRICES.map((price) =>
        ({ price, n: settleRows.filter((p) => p.priceKrw === price).length }))
        .filter((t) => t.n > 0);
      box.innerHTML = `
        <div class="list-item"><div>
          <div class="title">${ym} — 총 ${settleRows.length}건 · ${total.toLocaleString()}원</div>
          <div class="hint">예상 정산액 약 ${Math.round(total * NET_RATE).toLocaleString()}원
            (부가세·수수료 15% 공제)${refunded ? ` · 환불 ${refunded}건 제외` : ""}</div>
          <div class="hint">${byTier.map((t) => `${t.price.toLocaleString()}원 ×${t.n}`).join(" · ")}</div>
        </div></div>`;
      $("#settleCsvBtn").style.display = "";
    } catch (e) {
      box.innerHTML = `<div class="error">집계 실패: ${escapeHtml(e.message)}</div>`;
    }
  });

  $("#settleCsvBtn").addEventListener("click", () => {
    const header = "purchasedAt,priceKrw,credits,platform,email,uid,transactionId,status";
    const lines = settleRows.map((p) => [
      p.purchasedAt?.toDate?.().toISOString() ?? "", p.priceKrw ?? "", p.credits ?? "",
      p.platform ?? "", p.email ?? "", p.uid ?? "", p.transactionId ?? p.id, p.status ?? "paid",
    ].map((v) => `"${String(v).replaceAll('"', '""')}"`).join(","));
    const blob = new Blob(["﻿" + [header, ...lines].join("\n")], { type: "text/csv" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `settlement_${$("#settleMonth").value}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
  });
}

// ---------- 테스터 관리 ----------
// 스토어(TestFlight/Play)를 거치지 않은 테스트 빌드는 App Check 토큰을 못 만들어
// AI 대화 가이드가 막힌다. 여기 등록한 이메일(직원 로그인 계정)은 서버
// (generateBriefing)가 App Check 없이도 AI 호출을 허용한다. 일일 한도는 그대로
// 적용되므로 비용은 상한이 있다. ⚠️ 테스트 종료 후 목록을 비울 것 — 등록된
// 계정은 앱 무결성 검증을 우회하는 권한을 갖는다. 저장 위치: config/testers.emails.

async function getTesterEmails() {
  const snap = await getDoc(doc(db, "config", "testers"));
  return snap.exists() ? (snap.data().emails ?? []) : [];
}

async function saveTesterEmails(emails) {
  await setDoc(
    doc(db, "config", "testers"),
    { emails, updatedAt: serverTimestamp() },
    { merge: true },
  );
}

async function loadTesters() {
  const panel = $("#tab-testers");
  panel.innerHTML = `
    <div class="card">
      <p class="hint" style="margin-top:0;">
        여기 등록된 이메일(직원 로그인 계정)은 스토어를 거치지 않은 테스트
        빌드에서도 <strong>AI 대화 가이드</strong>를 쓸 수 있습니다. 일일 사용
        한도는 그대로 적용됩니다. <strong>테스트가 끝나면 목록을 비우세요</strong> —
        등록된 계정은 앱 무결성 검증(App Check)을 우회합니다.
      </p>
      <label>테스터 이메일 추가 (로그인에 쓰는 Google 계정)</label>
      <div class="row">
        <input type="email" id="testerEmail" placeholder="name@example.com" style="flex:1;">
        <button class="btn-primary" id="testerAddBtn">추가</button>
      </div>
      <div id="testerError"></div>
    </div>
    <div class="card">
      <h3 style="margin-top:0;">등록된 테스터 (<span id="testerCount">…</span>)</h3>
      <div id="testerList"></div>
    </div>
  `;

  $("#testerAddBtn").addEventListener("click", async () => {
    const raw = $("#testerEmail").value.trim().toLowerCase();
    $("#testerError").innerHTML = "";
    if (!raw) return;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(raw)) {
      $("#testerError").innerHTML = `<div class="error">이메일 형식이 올바르지 않습니다.</div>`;
      return;
    }
    const emails = await getTesterEmails();
    if (emails.map((e) => String(e).toLowerCase()).includes(raw)) {
      $("#testerError").innerHTML = `<div class="error">이미 등록된 이메일입니다.</div>`;
      return;
    }
    await saveTesterEmails([...emails, raw]);
    await logAdminAudit("testers.add", "config/testers", raw);
    $("#testerEmail").value = "";
    await loadTesters();
  });

  $("#testerEmail").addEventListener("keydown", (e) => {
    if (e.key === "Enter") $("#testerAddBtn").click();
  });

  const emails = await getTesterEmails();
  $("#testerCount").textContent = emails.length;
  const list = $("#testerList");
  if (emails.length === 0) {
    list.innerHTML = `<p class="hint">등록된 테스터가 없습니다.</p>`;
    return;
  }
  list.innerHTML = "";
  for (const email of emails) {
    const item = document.createElement("div");
    item.className = "list-item";
    item.innerHTML = `
      <div class="title">${escapeHtml(email)}</div>
      <button class="btn-danger" data-action="remove">삭제</button>
    `;
    item.querySelector('[data-action="remove"]').addEventListener("click", async () => {
      if (!confirm(`${email} 을(를) 테스터에서 제거할까요? 제거하면 이 계정은 테스트 빌드에서 AI를 쓸 수 없게 됩니다.`)) return;
      const current = await getTesterEmails();
      await saveTesterEmails(current.filter((e) => String(e).toLowerCase() !== String(email).toLowerCase()));
      await logAdminAudit("testers.remove", "config/testers", email);
      await loadTesters();
    });
    list.appendChild(item);
  }
}

function formatDate(ts) {
  if (!ts) return "";
  const d = ts.toDate ? ts.toDate() : new Date(ts);
  return `${d.getFullYear()}.${String(d.getMonth() + 1).padStart(2, "0")}.${String(d.getDate()).padStart(2, "0")} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

// ---------- 사용량 · AI 호출 로그 ----------
// 불만 처리·비용(손익분기) 추적용. 사용자 본인은 로그인 계정(이메일/uid)으로
// 찾을 수 있고(명함 등 제3자 정보만 암호화됨), AI 사용량과 호출 로그를 여기서
// 본다. 로그에는 계정 식별자·성공여부·토큰만 남고 명함/프롬프트 내용은 없다.

async function loadUsageLogs() {
  const panel = $("#tab-usage");
  panel.innerHTML = `
    <div class="card">
      <h3 style="margin-top:0;">사용자 AI 사용량 조회</h3>
      <label>사용자 로그인 이메일</label>
      <div class="row">
        <input type="email" id="usageEmail" placeholder="name@example.com" style="flex:1;">
        <button class="btn-primary" id="usageLookupBtn">조회</button>
      </div>
      <div id="usageResult" style="margin-top:12px;"></div>
    </div>
    <div class="card">
      <h3 style="margin-top:0;">최근 AI 호출 로그 (최대 100건)</h3>
      <p class="hint" style="margin-top:0;">
        돈이 나가는 호출 기록입니다. 계정 식별자·성공여부·토큰만 남기며,
        명함/프롬프트 내용은 저장하지 않습니다.
      </p>
      <div class="row" style="margin-bottom:10px;">
        <input type="email" id="logFilterEmail" placeholder="이메일로 필터 (비우면 전체)" style="flex:1;">
        <button class="btn-ghost" id="logRefreshBtn">새로고침</button>
      </div>
      <div id="auditLogList"></div>
    </div>
  `;

  $("#usageLookupBtn").addEventListener("click", async () => {
    const email = $("#usageEmail").value.trim().toLowerCase();
    const box = $("#usageResult");
    if (!email) return;
    box.innerHTML = `<p class="hint">조회 중…</p>`;
    try {
      const res = await getUserUsageFn({ email });
      const d = res.data;
      box.innerHTML = `
        <div class="list-item"><div class="title">오늘</div>
          <div>${d.dailyCount} / ${d.dailyLimit} <span class="hint">(남은 ${Math.max(0, d.dailyLimit - d.dailyCount)}회)</span></div></div>
        <div class="list-item"><div class="title">이번 달</div>
          <div>${d.monthlyCount} / ${d.monthlyLimit} <span class="hint">(남은 ${Math.max(0, d.monthlyLimit - d.monthlyCount)}회)</span></div></div>
        <div class="list-item"><div class="title">무료 회차 잔액 (추가 지급분)</div>
          <div id="bonusBalance">${d.bonusCredits ?? 0}회</div></div>
        <div class="meta" style="margin-top:8px;">uid: ${escapeHtml(d.uid)}</div>
        <div class="row" style="margin-top:12px; align-items:center;">
          <input type="number" id="grantAmount" placeholder="지급할 회차 (예: 5)" style="width:180px;">
        </div>
        <div class="row" style="margin-top:8px; align-items:center;">
          <input type="text" id="grantReason" placeholder="지급 사유 (필수, 예: 테스터 보상)" style="flex:1;">
        </div>
        <div class="row" style="margin-top:8px;">
          <button class="btn-primary" id="grantBtn">무료 회차 지급</button>
        </div>
        <p class="hint" style="margin-top:6px;">일/월 한도를 다 쓴 뒤 이 잔액이 먼저 소진됩니다. 음수를 넣으면 회수(0 미만으로는 안 내려감). 사유는 감사 기록에 남습니다(필수).</p>
        <div id="grantResult"></div>
      `;
      $("#grantBtn").addEventListener("click", async () => {
        const amount = parseInt($("#grantAmount").value, 10);
        const reason = $("#grantReason").value.trim();
        const out = $("#grantResult");
        if (!Number.isFinite(amount) || amount === 0) {
          out.innerHTML = `<div class="error">0이 아닌 정수를 입력해 주세요.</div>`;
          return;
        }
        if (!reason) {
          out.innerHTML = `<div class="error">지급 사유를 입력해 주세요.</div>`;
          return;
        }
        // 재시도/중복 클릭을 서버가 구분할 수 있도록, 버튼을 누른 그 자리에서
        // 1회만 생성한다(같은 클릭 안에서 재사용하지 않음 — 실패해도 새로
        // 누르면 새 operationId로 다시 시도된다).
        const operationId = crypto.randomUUID();
        const grantBtn = $("#grantBtn");
        grantBtn.disabled = true;
        out.innerHTML = `<p class="hint">지급 중…</p>`;
        try {
          const gr = await grantSupportCreditsFn({ email, amount, reason, operationId });
          $("#bonusBalance").textContent = `${gr.data.bonusCredits}회`;
          $("#grantAmount").value = "";
          $("#grantReason").value = "";
          out.innerHTML = `<div class="hint">완료 — 현재 무료 회차 잔액 ${gr.data.bonusCredits}회.</div>`;
        } catch (e) {
          out.innerHTML = `<div class="error">${escapeHtml(e.message)}</div>`;
        } finally {
          grantBtn.disabled = false;
        }
      });
    } catch (e) {
      box.innerHTML = `<div class="error">${escapeHtml(e.message)}</div>`;
    }
  });
  $("#usageEmail").addEventListener("keydown", (e) => {
    if (e.key === "Enter") $("#usageLookupBtn").click();
  });
  $("#logRefreshBtn").addEventListener("click", () => renderAuditLogs());
  $("#logFilterEmail").addEventListener("keydown", (e) => {
    if (e.key === "Enter") renderAuditLogs();
  });

  await renderAuditLogs();
}

async function renderAuditLogs() {
  const list = $("#auditLogList");
  if (!list) return;
  const filter = ($("#logFilterEmail")?.value ?? "").trim().toLowerCase();
  list.innerHTML = `<p class="hint">불러오는 중…</p>`;
  let snap;
  try {
    // 복합 인덱스가 필요 없도록 최근 100건만 받아 이메일은 클라이언트에서 거른다.
    snap = await getDocs(query(collection(db, "aiAuditLogs"), orderBy("at", "desc"), limit(100)));
  } catch (e) {
    list.innerHTML = `<div class="error">로그 조회 실패: ${escapeHtml(e.message)}</div>`;
    return;
  }
  let rows = [];
  snap.forEach((d) => rows.push(d.data()));
  if (filter) rows = rows.filter((l) => String(l.email ?? "").toLowerCase() === filter);
  if (rows.length === 0) {
    list.innerHTML = `<p class="hint">기록이 없습니다.</p>`;
    return;
  }
  list.innerHTML = "";
  for (const l of rows) {
    const item = document.createElement("div");
    item.className = "list-item";
    const badge = l.ok
      ? `<span class="badge good">성공</span>`
      : `<span class="badge warn">실패: ${escapeHtml(l.errorCode ?? "")}</span>`;
    const via = l.appCheckVerified ? "정식앱" : (l.viaAllowlist ? "테스터" : "-");
    item.innerHTML = `
      <div>
        <div class="title">${escapeHtml(l.email ?? l.uid ?? "")} ${badge}</div>
        <div class="meta">${formatDate(l.at)} · ${via} · 토큰 ${l.totalTokenCount ?? "-"} (사고 ${l.thoughtsTokenCount ?? "-"})</div>
      </div>
    `;
    list.appendChild(item);
  }
}

// ---------- 명함 인식 통계 ----------
// 앱이 올린 형태 통계(ocrStats/{uid})를 전 사용자 합산해 인식률을 본다.
// 개인정보(이름/전화/이메일/주소 원문)는 담기지 않고 카운트만 있다.

const OCR_FIELD_LABELS = {
  name: "이름", company: "회사명", title: "직함", mobile: "휴대폰",
  office: "사무실 전화", email: "이메일", address: "주소",
  addressDetail: "상세주소", postal: "우편번호",
};
const OCR_NAME_SOURCE_LABELS = {
  keywordSplit: "직함 줄에서 분리", koreanStripped: "한글 이름줄",
  mixedTokenFront: "혼용줄 앞 토큰", mixedTokenLast: "혼용줄 끝 토큰",
  fontSizePreferred: "글자 크기 폴백(개선)", leftoverFallback: "맨 앞 줄 폴백(약함)",
  none: "못 찾음",
};
const OCR_COMPANY_SOURCE_LABELS = {
  keyword: "회사 키워드", leftoverPick: "남은 줄에서 선택", none: "못 찾음",
};

function ocrPct(n, total) {
  if (!total || total <= 0) return "0%";
  return Math.round((n * 100) / total) + "%";
}

function addCounts(target, src) {
  if (!src || typeof src !== "object") return;
  for (const [k, v] of Object.entries(src)) {
    if (typeof v === "number") target[k] = (target[k] ?? 0) + v;
  }
}

async function loadOcrStats() {
  const panel = $("#tab-ocr");
  panel.innerHTML = `<p class="hint">불러오는 중…</p>`;
  let snap;
  try {
    snap = await getDocs(collection(db, "ocrStats"));
  } catch (e) {
    panel.innerHTML = `<div class="error">명함 인식 통계 조회 실패: ${escapeHtml(e.message)}</div>`;
    return;
  }

  const agg = {
    scans: 0, correctedCards: 0, users: 0,
    filled: {}, nameSource: {}, companySource: {}, corrections: {},
    platform: {},
  };
  snap.forEach((d) => {
    const s = d.data();
    agg.users += 1;
    agg.scans += Number(s.scans ?? 0);
    agg.correctedCards += Number(s.correctedCards ?? 0);
    addCounts(agg.filled, s.filled);
    addCounts(agg.nameSource, s.nameSource);
    addCounts(agg.companySource, s.companySource);
    for (const [field, byKind] of Object.entries(s.corrections ?? {})) {
      agg.corrections[field] = agg.corrections[field] ?? {};
      addCounts(agg.corrections[field], byKind);
    }
    const plat = s.platform ?? "기타";
    agg.platform[plat] = agg.platform[plat] ?? { users: 0, scans: 0 };
    agg.platform[plat].users += 1;
    agg.platform[plat].scans += Number(s.scans ?? 0);
  });

  if (agg.users === 0 || agg.scans === 0) {
    panel.innerHTML = `<div class="card"><p class="hint" style="margin:0;">아직 수집된 명함 인식 통계가 없습니다. 앱에서 명함을 스캔·저장하면 여기에 쌓입니다.</p></div>`;
    return;
  }

  const row = (label, value) =>
    `<div class="list-item"><div class="title">${escapeHtml(label)}</div><div>${escapeHtml(value)}</div></div>`;

  const platformRows = Object.entries(agg.platform)
    .map(([p, v]) => row(p, `사용자 ${v.users}명 · 스캔 ${v.scans}회`))
    .join("");

  const fieldRows = Object.keys(OCR_FIELD_LABELS)
    .map((k) => row(OCR_FIELD_LABELS[k], `${agg.filled[k] ?? 0}/${agg.scans} (${ocrPct(agg.filled[k] ?? 0, agg.scans)})`))
    .join("");

  const nameRows = Object.entries(agg.nameSource)
    .sort((a, b) => b[1] - a[1])
    .map(([k, v]) => row(OCR_NAME_SOURCE_LABELS[k] ?? k, `${v} (${ocrPct(v, agg.scans)})`))
    .join("");

  const companyRows = Object.entries(agg.companySource)
    .sort((a, b) => b[1] - a[1])
    .map(([k, v]) => row(OCR_COMPANY_SOURCE_LABELS[k] ?? k, `${v} (${ocrPct(v, agg.scans)})`))
    .join("");

  const correctionRows = Object.keys(OCR_FIELD_LABELS)
    .map((k) => {
      const bk = agg.corrections[k];
      if (!bk) return "";
      const edited = bk.edited ?? 0, cleared = bk.cleared ?? 0;
      if (edited === 0 && cleared === 0) return "";
      return row(OCR_FIELD_LABELS[k], `고침 ${edited} · 지움 ${cleared}`);
    })
    .filter(Boolean)
    .join("") || `<p class="hint" style="margin:0;">아직 수정 기록이 없습니다.</p>`;

  panel.innerHTML = `
    <div class="card">
      <p class="hint" style="margin-top:0;">
        앱이 올린 <b>형태 통계</b>만 표시합니다 — 이름·전화·이메일·주소 원문이나
        명함 이미지는 포함되지 않습니다. 필드별 인식률과 사용자가 자동 인식을
        고친 정도로 어디를 개선할지 판단합니다.
      </p>
      <div class="row"><button class="btn-ghost" id="ocrRefreshBtn">새로고침</button></div>
    </div>
    <div class="card">
      <h3 style="margin-top:0;">전체</h3>
      ${row("수집된 사용자 수", `${agg.users}명`)}
      ${row("스캔 파싱 횟수(합계)", `${agg.scans}회`)}
      ${row("자동 인식을 고친 명함", `${agg.correctedCards}건 (${ocrPct(agg.correctedCards, agg.scans)})`)}
      ${platformRows}
    </div>
    <div class="card">
      <h3 style="margin-top:0;">필드별 인식률 (채워진 비율)</h3>
      ${fieldRows}
    </div>
    <div class="card">
      <h3 style="margin-top:0;">이름을 뽑은 경로</h3>
      <p class="hint" style="margin-top:0;">"맨 앞 줄 폴백(약함)"과 "못 찾음" 비율이 높으면 파싱이 병목입니다.</p>
      ${nameRows}
    </div>
    <div class="card">
      <h3 style="margin-top:0;">회사명을 뽑은 경로</h3>
      ${companyRows}
    </div>
    <div class="card">
      <h3 style="margin-top:0;">필드별 사용자 수정 (오인식 신호)</h3>
      <p class="hint" style="margin-top:0;">주소는 앱의 도로명 자동변환이 "고침"에 섞일 수 있어(참고) 순수 오인식보다 높게 보일 수 있습니다.</p>
      ${correctionRows}
    </div>
  `;
  $("#ocrRefreshBtn")?.addEventListener("click", () => loadOcrStats());
}

// ---------- 앱 업데이트(버전 게이트, P1-45) ----------
// 앱이 시작 시 config/appUpdate를 읽어 빌드 번호를 비교한다. 여기 값을 바꾸면
// 앱 배포 없이 강제/권장 업데이트 안내가 바뀐다.
//
// 최소/최신 빌드는 플랫폼별로 나뉜다(iOS/Android 각각) — 두 스토어의 심사
// 통과 시점이 달라 배포된 최신 빌드번호가 어긋날 수 있어서다. 레거시 단일
// 필드(minSupportedBuild/latestBuild)는 구버전 앱(플랫폼 필드를 모르는 앱)
// 이 계속 읽으므로, 저장할 때 두 플랫폼 값 중 **낮은 쪽**을 함께 써서 구버전
// 앱이 실수로 강제 업데이트에 막히지 않게 한다.

function _numOrZero(value) {
  const n = parseInt(value, 10);
  return Number.isFinite(n) ? Math.max(0, n) : 0;
}

async function loadAppUpdate() {
  const panel = $("#tab-appupdate");
  let d = {};
  try {
    const snap = await getDoc(doc(db, "config", "appUpdate"));
    if (snap.exists()) d = snap.data();
  } catch (e) {
    panel.innerHTML = `<div class="error">설정 조회 실패: ${escapeHtml(e.message)}</div>`;
    return;
  }
  panel.innerHTML = `
    <div class="card">
      <h3 style="margin-top:0;">앱 업데이트 안내 (버전 게이트)</h3>
      <p class="hint">
        기준은 <b>빌드 번호</b>(pubspec <code>1.0.0+N</code>의 N). 앱이 시작할 때 자기
        플랫폼(iOS/Android) 값과 비교해 안내합니다 — <b>두 스토어의 배포 빌드가 다를
        수 있어 iOS/Android를 각각 설정</b>합니다. <b>값을 바꾸면 앱 배포 없이 즉시
        반영</b>됩니다.
        <br>· <b>최소 지원 빌드</b>: 이 미만이면 <b>강제</b>(닫기 불가, 스토어로만 이동).
        <br>· <b>최신 빌드</b>: 이 미만이면 <b>권장</b>("나중에" 허용).
        <br>둘 다 비우거나 0이면 아무 안내도 하지 않습니다.
      </p>
      <label>iOS</label>
      <div class="field-2col">
        <div>
          <span class="field-sublabel">최소 지원 빌드 번호</span>
          <input type="number" id="auMinIos" min="0">
        </div>
        <div>
          <span class="field-sublabel">최신 빌드 번호</span>
          <input type="number" id="auLatestIos" min="0">
        </div>
      </div>
      <label>Android</label>
      <div class="field-2col">
        <div>
          <span class="field-sublabel">최소 지원 빌드 번호</span>
          <input type="number" id="auMinAndroid" min="0">
        </div>
        <div>
          <span class="field-sublabel">최신 빌드 번호</span>
          <input type="number" id="auLatestAndroid" min="0">
        </div>
      </div>
      <label>iOS 스토어 URL (App Store)</label>
      <input type="text" id="auIos" placeholder="https://apps.apple.com/app/id...">
      <p class="hint">
        <code>https://apps.apple.com/app/id</code> 뒤에 <b>숫자(Apple ID)</b>만
        붙이면 됩니다. 예: <code>https://apps.apple.com/app/id6501234567</code>
        <br>그 숫자는 어디서? → <b>App Store Connect → 해당 앱 선택 → "앱
        정보"(App Information) → "Apple ID"</b> 항목에 적힌 숫자를 그대로
        복사합니다(개발자 계정 Apple ID와는 다른, 앱마다 하나씩 자동으로
        부여되는 번호입니다).
      </p>
      <label>Android 스토어 URL (Play)</label>
      <input type="text" id="auAndroid" placeholder="https://play.google.com/store/apps/details?id=...">
      <p class="hint">
        <code>https://play.google.com/store/apps/details?id=</code> 뒤에
        <b>패키지명</b>만 붙이면 됩니다. 예:
        <code>https://play.google.com/store/apps/details?id=com.connectiontrace.connection_trace_ai_flutter</code>
        <br>패키지명은 이미 정해져 있고 앞으로도 안 바뀝니다 —
        <code>com.connectiontrace.connection_trace_ai_flutter</code>를 그대로
        복사해 붙이면 끝입니다.
      </p>
      <p class="hint" style="color:var(--warn); background:var(--warn-soft); border-radius:8px; padding:10px 12px;">
        ⚠️ <b>베타 심사 중 주의</b>: 두 URL 모두 스토어에 <b>정식 공개(또는
        공개 트랙)되기 전</b>에는 눌러도 빈 페이지이거나 "찾을 수 없음"이
        뜹니다. 지금은 URL만 미리 채워 두고, <b>"최소 지원 빌드 번호"는
        반드시 0(강제 없음)</b>으로 두세요. 최소값을 0보다 높게 걸면, 아직
        스토어에 앱이 없는 상태에서 강제 업데이트가 발동해 사용자를 갈 곳
        없는 빈 스토어 페이지로 보내고 <b>앱만 막는 사고</b>가 납니다. 정식
        공개가 확정된 뒤에 최소값을 올리세요.
      </p>
      <label>안내 문구 (선택 — 비우면 기본 문구)</label>
      <input type="text" id="auMsg" placeholder="예: 중요한 개선이 있어요. 업데이트해 주세요.">
      <div class="row" style="margin-top:14px;">
        <button class="btn-primary" id="auSaveBtn">저장</button>
      </div>
      <div id="auMsgOut"></div>
    </div>
  `;
  // 값은 innerHTML 대신 프로퍼티로 넣어 따옴표 이스케이프 문제를 피한다.
  // 플랫폼 필드가 없으면(구 설정) 레거시 단일값으로 채운다 — 폴백은 앱
  // 쪽(app_update_service.dart)과 같은 원칙.
  $("#auMinIos").value = d.minSupportedBuildIos ?? d.minSupportedBuild ?? "";
  $("#auMinAndroid").value =
    d.minSupportedBuildAndroid ?? d.minSupportedBuild ?? "";
  $("#auLatestIos").value = d.latestBuildIos ?? d.latestBuild ?? "";
  $("#auLatestAndroid").value = d.latestBuildAndroid ?? d.latestBuild ?? "";
  $("#auIos").value = d.iosUrl ?? "";
  $("#auAndroid").value = d.androidUrl ?? "";
  $("#auMsg").value = d.message ?? "";

  $("#auSaveBtn").addEventListener("click", async () => {
    const minIos = _numOrZero($("#auMinIos").value);
    const minAndroid = _numOrZero($("#auMinAndroid").value);
    const latestIos = _numOrZero($("#auLatestIos").value);
    const latestAndroid = _numOrZero($("#auLatestAndroid").value);
    const payload = {
      minSupportedBuildIos: minIos,
      minSupportedBuildAndroid: minAndroid,
      latestBuildIos: latestIos,
      latestBuildAndroid: latestAndroid,
      // 레거시 단일 필드는 구버전 앱을 위한 하위호환용 — 두 플랫폼 중
      // 낮은 쪽을 넣어야, 플랫폼 필드를 모르는 구버전 앱이 실수로 강제
      // 업데이트에 막히지 않는다.
      minSupportedBuild: Math.min(minIos, minAndroid),
      latestBuild: Math.min(latestIos, latestAndroid),
      iosUrl: $("#auIos").value.trim(),
      androidUrl: $("#auAndroid").value.trim(),
      message: $("#auMsg").value.trim(),
      updatedAt: serverTimestamp(),
    };
    try {
      await setDoc(doc(db, "config", "appUpdate"), payload, { merge: true });
      await logAdminAudit("appUpdate.save", "config/appUpdate",
        `iOS min=${minIos}/latest=${latestIos}, Android min=${minAndroid}/latest=${latestAndroid}`);
      $("#auMsgOut").innerHTML = `<div class="hint">저장했습니다. 앱을 다시 켜면 반영됩니다.</div>`;
    } catch (e) {
      $("#auMsgOut").innerHTML = `<div class="error">저장 실패: ${escapeHtml(e.message)}</div>`;
    }
  });
}

// ---------- 탭 ----------

function initTabs() {
  document.querySelectorAll(".tab-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".tab-btn").forEach((b) => b.classList.remove("active"));
      document.querySelectorAll(".tab-panel").forEach((p) => (p.style.display = "none"));
      btn.classList.add("active");
      $(`#tab-${btn.dataset.tab}`).style.display = "block";
    });
  });
}

// ---------- 공지사항 ----------

async function loadNotices() {
  const panel = $("#tab-notices");
  panel.innerHTML = `
    <div class="card">
      <h3 style="margin-top:0;">새 공지 작성</h3>
      <label>제목</label>
      <input type="text" id="noticeTitle">
      <label>내용 (마크다운)</label>
      <textarea id="noticeBody"></textarea>
      <div class="checkbox-row">
        <input type="checkbox" id="noticePinned"> <label style="margin:0;" for="noticePinned">상단 고정</label>
      </div>
      <div class="checkbox-row">
        <input type="checkbox" id="noticePublished" checked> <label style="margin:0;" for="noticePublished">즉시 게시</label>
      </div>
      <div class="row" style="margin-top:14px;">
        <button class="btn-primary" id="noticeSaveBtn">등록</button>
      </div>
    </div>
    <div class="card"><h3 style="margin-top:0;">전체 공지 (${"..."})</h3><div id="noticeList"></div></div>
  `;

  $("#noticeSaveBtn").addEventListener("click", async () => {
    const title = $("#noticeTitle").value.trim();
    const bodyMarkdown = $("#noticeBody").value.trim();
    if (!title || !bodyMarkdown) return;
    const ref = await addDoc(collection(db, "notices"), {
      title,
      bodyMarkdown,
      pinned: $("#noticePinned").checked,
      published: $("#noticePublished").checked,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await logAdminAudit("notice.create", ref.id, title);
    await loadNotices();
  });

  const snap = await getDocs(query(collection(db, "notices"), orderBy("createdAt", "desc")));
  const list = $("#noticeList");
  panel.querySelector("h3:last-of-type") &&
    (panel.querySelectorAll("h3")[1].textContent = `전체 공지 (${snap.size})`);
  if (snap.empty) {
    list.innerHTML = `<p class="hint">등록된 공지가 없습니다.</p>`;
    return;
  }
  list.innerHTML = "";
  snap.forEach((docSnap) => {
    const n = docSnap.data();
    const item = document.createElement("div");
    item.className = "list-item";
    item.innerHTML = `
      <div>
        <div class="title">${n.pinned ? "📌 " : ""}${escapeHtml(n.title)}</div>
        <div class="meta">${formatDate(n.createdAt)} ·
          <span class="badge ${n.published ? "good" : "warn"}">${n.published ? "게시중" : "비공개"}</span>
        </div>
      </div>
      <div class="row">
        <button class="btn-ghost" data-action="toggle">${n.published ? "비공개로" : "게시하기"}</button>
        <button class="btn-danger" data-action="delete">삭제</button>
      </div>
    `;
    item.querySelector('[data-action="toggle"]').addEventListener("click", async () => {
      await updateDoc(doc(db, "notices", docSnap.id), {
        published: !n.published,
        updatedAt: serverTimestamp(),
      });
      await logAdminAudit("notice.toggle", docSnap.id, `게시여부 → ${!n.published}`);
      await loadNotices();
    });
    item.querySelector('[data-action="delete"]').addEventListener("click", async () => {
      if (!confirm("이 공지를 삭제할까요?")) return;
      await deleteDoc(doc(db, "notices", docSnap.id));
      await logAdminAudit("notice.delete", docSnap.id, n.title);
      await loadNotices();
    });
    list.appendChild(item);
  });
}

// ---------- 1:1 문의 ----------
// (2026-08-15, ADMIN-VULN-006) 예전에는 loadInquiries()가 limit 없이 전체
// 문의를 조회했다 — 목록 렌더 자체는 subject/userEmail/status만 써서 가볍지만
// (message 원문은 openInquiry()에서 클릭 시에만 읽는 lazy 로드), 문의 건수가
// 무제한이라 대량 생성 시 관리자 로그인마다 읽기 비용·대기시간이 무한정
// 커질 수 있었다(관리자 대상 DoS). 50건씩 페이지네이션으로 바꾼다.
//
// UID/IP별 문의 "생성" 속도 자체를 제한하는 rate limit은 이번 범위 밖이다.
// Firestore Rules는 "이미 존재하는 문서 개수"를 세는 내장 기능이 없고,
// 집계 카운터 문서를 따로 두면 그 카운터 자체가 클라이언트 위조 대상이 되어
// 오히려 새 취약점이 된다 — 진짜 rate limit은 App Check + 문의 제출을
// Callable Function으로 옮기는 인프라 변경이 필요해 후속 과제로 남긴다.
const INQUIRY_PAGE_SIZE = 50;
let _inquiryLastVisible = null;

async function loadInquiries() {
  const panel = $("#tab-inquiries");
  panel.innerHTML = `
    <div class="card">
      <h3 style="margin-top:0;">문의 목록</h3>
      <div id="inquiryList"></div>
      <div class="row" style="margin-top:10px;">
        <button class="btn-ghost" id="inquiryMoreBtn" style="display:none;">더 보기</button>
      </div>
    </div>
    <div id="inquiryDetail"></div>
  `;

  const list = $("#inquiryList");
  const moreBtn = $("#inquiryMoreBtn");
  _inquiryLastVisible = null; // 탭을 새로 열 때마다 페이지네이션 상태 초기화

  const renderInquiryItem = (docSnap) => {
    const inquiry = docSnap.data();
    const item = document.createElement("div");
    item.className = "list-item";
    item.style.cursor = "pointer";
    item.innerHTML = `
      <div>
        <div class="title">${escapeHtml(inquiry.subject)}</div>
        <div class="meta">${escapeHtml(inquiry.userEmail)} · ${formatDate(inquiry.createdAt)}</div>
      </div>
      <span class="badge ${inquiry.status === "answered" ? "good" : "warn"}">${inquiry.status === "answered" ? "답변완료" : "답변대기"}</span>
    `;
    item.addEventListener("click", () => openInquiry(docSnap.id, inquiry));
    list.appendChild(item);
  };

  const loadPage = async (append) => {
    let q = query(collection(db, "inquiries"), orderBy("createdAt", "desc"), limit(INQUIRY_PAGE_SIZE));
    if (append && _inquiryLastVisible) {
      q = query(collection(db, "inquiries"), orderBy("createdAt", "desc"),
        startAfter(_inquiryLastVisible), limit(INQUIRY_PAGE_SIZE));
    }
    const snap = await getDocs(q);
    if (!append && snap.empty) {
      list.innerHTML = `<p class="hint">등록된 문의가 없습니다.</p>`;
      moreBtn.style.display = "none";
      return;
    }
    if (!append) list.innerHTML = "";
    snap.forEach(renderInquiryItem);
    if (!snap.empty) _inquiryLastVisible = snap.docs[snap.docs.length - 1];
    // 이번 페이지가 꽉 찼으면(=더 있을 가능성) "더 보기"를 계속 보여주고,
    // 꽉 차지 않았으면(마지막 페이지) 숨긴다.
    moreBtn.style.display = snap.size === INQUIRY_PAGE_SIZE ? "" : "none";
  };

  moreBtn.addEventListener("click", () => loadPage(true));
  await loadPage(false);
}

async function openInquiry(id, inquiry) {
  const detail = $("#inquiryDetail");
  // limit(200): 극단적으로 큰 답변 스레드에 대한 방어적 상한(ADMIN-VULN-006).
  // 비용은 거의 안 들지만(문의 하나당 답변 수는 보통 적음) 안전장치로 둔다.
  const repliesSnap = await getDocs(
    query(collection(db, "inquiries", id, "replies"), orderBy("createdAt"), limit(200)),
  );
  let thread = `<div class="bubble user">${escapeHtml(inquiry.message)}</div>`;
  repliesSnap.forEach((r) => {
    const reply = r.data();
    thread += `<div class="bubble ${reply.from === "admin" ? "admin" : "user"}">${escapeHtml(reply.message)}</div>`;
  });

  detail.innerHTML = `
    <div class="card">
      <h3 style="margin-top:0;">${escapeHtml(inquiry.subject)}</h3>
      <div class="hint">${escapeHtml(inquiry.userEmail)}</div>
      <div class="thread">${thread}</div>
      <label>답변 작성</label>
      <textarea id="replyBox" style="min-height:80px;"></textarea>
      <div class="row" style="margin-top:12px;">
        <button class="btn-primary" id="replySendBtn">답변 보내기</button>
        ${inquiry.status !== "answered" ? '<button class="btn-ghost" id="markAnsweredBtn">답변완료로 표시만</button>' : ""}
      </div>
    </div>
  `;

  $("#replySendBtn").addEventListener("click", async () => {
    const message = $("#replyBox").value.trim();
    if (!message) return;
    await addDoc(collection(db, "inquiries", id, "replies"), {
      from: "admin",
      message,
      createdAt: serverTimestamp(),
    });
    await updateDoc(doc(db, "inquiries", id), { status: "answered" });
    // summary에는 답변 내용이나 문의자 이메일을 절대 넣지 않는다(개인정보 원칙).
    await logAdminAudit("inquiry.reply", id, "답변 등록, 상태 answered로 변경");
    await loadInquiries();
    detail.innerHTML = "";
  });

  const markBtn = $("#markAnsweredBtn");
  if (markBtn) {
    markBtn.addEventListener("click", async () => {
      await updateDoc(doc(db, "inquiries", id), { status: "answered" });
      await logAdminAudit("inquiry.markAnswered", id, "답변 없이 완료 표시만");
      await loadInquiries();
      detail.innerHTML = "";
    });
  }
}

// ---------- 법적 문서 ----------

const LEGAL_SLUGS = [
  ["privacy-policy", "개인정보처리방침"],
  ["terms-of-service", "서비스 이용약관"],
  ["app-permissions", "앱 접근권한 안내"],
  ["account-deletion", "계정 및 데이터 삭제 안내"],
];

async function loadLegalDocs() {
  const panel = $("#tab-legal");
  panel.innerHTML = `
    <div class="card">
      <p class="hint" style="margin-top:0; color:var(--warn); background:var(--warn-soft); border-radius:8px; padding:10px 12px;">
        ⚠️ <b>이 편집 기능은 현재 비활성화돼 있습니다.</b> 여기서 무엇을
        바꿔도 앱·스토어 심사가 보는 문서에는 반영되지 않습니다. 아래
        목록은 Firestore에 저장된 옛 내용을 참고용으로만 보여줍니다.
        실제 문안을 바꾸려면 저장소 <code>docs/legal/*.html</code>을 고친
        뒤 <code>firebase deploy --only hosting:legal</code>로 배포해야
        합니다.
      </p>
      <div id="legalDocList"></div>
    </div>
    <div id="legalDocEditor"></div>
  `;
  const list = $("#legalDocList");
  list.innerHTML = "";
  for (const [slug, title] of LEGAL_SLUGS) {
    const item = document.createElement("div");
    item.className = "list-item";
    item.style.cursor = "pointer";
    const snap = await getDoc(doc(db, "legalDocs", slug));
    const updatedAt = snap.exists() ? snap.data().updatedAt : null;
    item.innerHTML = `
      <div>
        <div class="title">${escapeHtml(title)}</div>
        <div class="meta">${snap.exists() ? `최근 수정 ${formatDate(updatedAt)}` : "아직 등록되지 않음"}</div>
      </div>
      <span class="badge ${snap.exists() ? "good" : "warn"}">${snap.exists() ? "등록됨" : "미등록"}</span>
    `;
    item.addEventListener("click", () => editLegalDoc(slug, title));
    list.appendChild(item);
  }
}

// 읽기 전용 뷰어 — 편집/저장/삭제 기능은 없다(2026-08-14 비활성화). 실제
// 게시 문서는 docs/legal/*.html + Hosting 배포뿐이다. 이 화면은 Firestore
// legalDocs/{slug}에 남아 있는 옛 내용을 참고용으로 보여주기만 한다.
async function editLegalDoc(slug, title) {
  const editor = $("#legalDocEditor");
  const snap = await getDoc(doc(db, "legalDocs", slug));
  const data = snap.exists() ? snap.data() : { bodyHtml: "" };
  editor.innerHTML = `
    <div class="card">
      <h3 style="margin-top:0;">${escapeHtml(title)} (읽기 전용)</h3>
      <p class="hint" style="margin-top:0;">
        편집·저장 기능이 없습니다. 실제 문안을 바꾸려면
        <code>docs/legal/${slug}.html</code>을 고친 뒤
        <code>firebase deploy --only hosting:legal</code>로 배포하세요.
      </p>
      <label>참고용 본문 (Firestore에 저장된 옛 내용, HTML)</label>
      <textarea id="legalDocBody" readonly disabled style="min-height:320px;">${escapeHtml(data.bodyHtml ?? "")}</textarea>
    </div>
  `;
}
