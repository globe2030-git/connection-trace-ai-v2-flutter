// 커넥션센스 관리자 콘솔.
//
// 관리자 등록 방식(2026-08-06): Firebase 콘솔에 들어가 계정을 만들거나
// Firestore에 문서를 손으로 추가할 필요가 없다. 이 페이지에서 지정된
// 이메일(firestore.rules의 isAdmin() 허용목록)로 직접 회원가입하면
// 이메일 인증 후 그대로 관리자가 된다. 관리자를 추가/제거하려면
// firestore.rules의 이메일 목록만 고치고 배포하면 된다.
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
import {
  getAuth, signInWithEmailAndPassword, createUserWithEmailAndPassword,
  sendEmailVerification, onAuthStateChanged, signOut,
  GoogleAuthProvider, signInWithPopup,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";
import {
  getFirestore, collection, doc, getDoc, getDocs, addDoc, updateDoc, deleteDoc,
  setDoc, query, where, orderBy, limit, serverTimestamp, Timestamp,
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
const db = getFirestore(app);
// Cloud Functions는 서울 리전(asia-northeast3)에 배포돼 있다 — 리전을 안 맞추면
// httpsCallable이 기본(us-central1)으로 호출해 not-found가 난다.
const functions = getFunctions(app, "asia-northeast3");
const getUserUsageFn = httpsCallable(functions, "getUserUsage");

const $ = (sel) => document.querySelector(sel);
const loginScreen = $("#loginScreen");
const dashboard = $("#dashboard");

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

$("#logoutBtn").addEventListener("click", () => signOut(auth));

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
// 공지/문의/법적문서와 달리 Firestore가 아니라 docs/admin/reports/ 아래
// 정적 HTML 파일 그대로 서빙한다 — 임원 보고용 문서라 편집 UI 없이,
// 파일을 고치고 `firebase deploy --only hosting:admin`으로 재배포하면
// 이 목록에서 항상 최신 버전이 열린다(새로고침만 하면 됨, 별도 동기화
// 절차 없음).
const REPORTS = [
  {
    file: "reports/pnl-analysis-freemium.html",
    title: "프리미엄 구독 손익분석",
    desc: "무료:유료 전환 시나리오, 규모별 손익, AI 파싱 도입 영향 등",
  },
];

function loadReports() {
  const panel = $("#tab-reports");
  panel.innerHTML = `
    <div class="card">
      <p class="hint" style="margin-top:0;">
        여기 목록은 정적 문서라 이 화면에서 직접 편집할 수 없습니다.
        내용을 갱신하려면 해당 HTML 파일을 고치고 다시 배포해야 합니다 —
        배포만 되면 아래 링크는 항상 최신 버전을 엽니다.
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
      <a class="btn-ghost" style="text-decoration:none; display:inline-block;" href="${r.file}" target="_blank" rel="noopener">열기 →</a>
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
// 무료 10회 이후 1,000/3,000/5,000/10,000원 충전. 이 탭은 세 가지를 맡는다.
// ① 상품 설정: 티어별 제공 회수·무료 횟수(config/billing) — 회수는 테스트
//    기간 AI 비용 실측 후 확정하므로 코드 배포 없이 여기서 조정한다.
// ② 충전 내역 조회(고객응대): "결제했는데 안 들어왔어요" 문의 대응.
// ③ 정산 요약: 월별 충전 건수·금액·예상 정산액 + CSV 내려받기.
// purchases 기록은 영수증 검증 서버(P1-4)만 쓴다 — IAP 구현 전까지는
// 기록이 없는 게 정상이고, 빈 상태를 그대로 보여준다(가짜 데이터 금지).

const TIER_PRICES = [1000, 3000, 5000, 10000];
// 부가세 제외(÷1.1) 후 스토어 수수료 15% 공제 — backlog 추가 153의 정산 감각.
const NET_RATE = (1 / 1.1) * 0.85;

async function getBillingConfig() {
  const snap = await getDoc(doc(db, "config", "billing"));
  const data = snap.exists() ? snap.data() : {};
  return {
    freeCredits: data.freeCredits ?? 10,
    tiers: TIER_PRICES.map((price) => {
      const found = (data.tiers ?? []).find((t) => t.priceKrw === price);
      return { priceKrw: price, credits: found?.credits ?? null, active: found?.active ?? false };
    }),
  };
}

async function loadBilling() {
  const panel = $("#tab-billing");
  panel.innerHTML = `
    <div class="card">
      <h3 style="margin-top:0;">충전 상품 설정</h3>
      <p class="hint">
        가격 4단계는 확정, <strong>제공 회수는 테스트 기간 AI 비용 실측 후 확정</strong>
        (미정이면 비워 두세요). 여기 저장한 값은 영수증 검증 서버가 크레딧 지급량으로,
        앱이 충전 화면 표시용으로 읽습니다 — 회수 조정에 앱 배포가 필요 없습니다.
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
  const cfg = await getBillingConfig();
  $("#freeCredits").value = cfg.freeCredits;
  $("#tierRows").innerHTML = cfg.tiers.map((t, i) => `
    <div class="row" style="align-items:center; margin-bottom:6px;">
      <div style="width:110px; font-weight:700;">${t.priceKrw.toLocaleString()}원</div>
      <input type="number" id="tierCredits${i}" min="1" placeholder="회수 미정"
        value="${t.credits ?? ""}" style="width:120px;">
      <span class="hint" style="margin:0 4px;">회 제공</span>
      <label style="margin:0; display:flex; align-items:center; gap:4px;">
        <input type="checkbox" id="tierActive${i}" ${t.active ? "checked" : ""}> 판매
      </label>
    </div>
  `).join("");

  $("#billingSaveBtn").addEventListener("click", async () => {
    const tiers = TIER_PRICES.map((price, i) => {
      const raw = $(`#tierCredits${i}`).value.trim();
      return {
        priceKrw: price,
        credits: raw === "" ? null : Math.max(1, parseInt(raw, 10) || 0),
        active: $(`#tierActive${i}`).checked,
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
    $("#billingMsg").innerHTML = `<div class="hint">저장했습니다.</div>`;
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
        <div class="meta" style="margin-top:8px;">uid: ${escapeHtml(d.uid)}</div>
      `;
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
        기준은 <b>빌드 번호</b>(pubspec <code>1.0.0+N</code>의 N). 앱이 시작할 때 이
        값과 비교해 안내합니다. <b>값을 바꾸면 앱 배포 없이 즉시 반영</b>됩니다.
        <br>· <b>최소 지원 빌드</b>: 이 미만이면 <b>강제</b>(닫기 불가, 스토어로만 이동).
        <br>· <b>최신 빌드</b>: 이 미만이면 <b>권장</b>("나중에" 허용).
        <br>둘 다 비우거나 0이면 아무 안내도 하지 않습니다.
      </p>
      <label>최소 지원 빌드 번호</label>
      <input type="number" id="auMin" min="0" style="width:140px;">
      <label>최신 빌드 번호</label>
      <input type="number" id="auLatest" min="0" style="width:140px;">
      <label>iOS 스토어 URL (App Store)</label>
      <input type="text" id="auIos" placeholder="https://apps.apple.com/app/id...">
      <label>Android 스토어 URL (Play)</label>
      <input type="text" id="auAndroid" placeholder="https://play.google.com/store/apps/details?id=...">
      <label>안내 문구 (선택 — 비우면 기본 문구)</label>
      <input type="text" id="auMsg" placeholder="예: 중요한 개선이 있어요. 업데이트해 주세요.">
      <div class="row" style="margin-top:14px;">
        <button class="btn-primary" id="auSaveBtn">저장</button>
      </div>
      <div id="auMsgOut"></div>
    </div>
  `;
  // 값은 innerHTML 대신 프로퍼티로 넣어 따옴표 이스케이프 문제를 피한다.
  $("#auMin").value = d.minSupportedBuild ?? "";
  $("#auLatest").value = d.latestBuild ?? "";
  $("#auIos").value = d.iosUrl ?? "";
  $("#auAndroid").value = d.androidUrl ?? "";
  $("#auMsg").value = d.message ?? "";

  $("#auSaveBtn").addEventListener("click", async () => {
    const min = parseInt($("#auMin").value, 10);
    const latest = parseInt($("#auLatest").value, 10);
    const payload = {
      minSupportedBuild: Number.isFinite(min) ? Math.max(0, min) : 0,
      latestBuild: Number.isFinite(latest) ? Math.max(0, latest) : 0,
      iosUrl: $("#auIos").value.trim(),
      androidUrl: $("#auAndroid").value.trim(),
      message: $("#auMsg").value.trim(),
      updatedAt: serverTimestamp(),
    };
    try {
      await setDoc(doc(db, "config", "appUpdate"), payload, { merge: true });
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
    await addDoc(collection(db, "notices"), {
      title,
      bodyMarkdown,
      pinned: $("#noticePinned").checked,
      published: $("#noticePublished").checked,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
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
      await loadNotices();
    });
    item.querySelector('[data-action="delete"]').addEventListener("click", async () => {
      if (!confirm("이 공지를 삭제할까요?")) return;
      await deleteDoc(doc(db, "notices", docSnap.id));
      await loadNotices();
    });
    list.appendChild(item);
  });
}

// ---------- 1:1 문의 ----------

async function loadInquiries() {
  const panel = $("#tab-inquiries");
  panel.innerHTML = `<div class="card"><h3 style="margin-top:0;">문의 목록</h3><div id="inquiryList"></div></div><div id="inquiryDetail"></div>`;

  const snap = await getDocs(query(collection(db, "inquiries"), orderBy("createdAt", "desc")));
  const list = $("#inquiryList");
  if (snap.empty) {
    list.innerHTML = `<p class="hint">등록된 문의가 없습니다.</p>`;
    return;
  }
  list.innerHTML = "";
  snap.forEach((docSnap) => {
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
  });
}

async function openInquiry(id, inquiry) {
  const detail = $("#inquiryDetail");
  const repliesSnap = await getDocs(
    query(collection(db, "inquiries", id, "replies"), orderBy("createdAt")),
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
    await loadInquiries();
    detail.innerHTML = "";
  });

  const markBtn = $("#markAnsweredBtn");
  if (markBtn) {
    markBtn.addEventListener("click", async () => {
      await updateDoc(doc(db, "inquiries", id), { status: "answered" });
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
      <p class="hint" style="margin-top:0;">
        여기서 수정하면 앱 재배포 없이 바로 반영됩니다. 다만 이 회사의
        실제 정책 검토 없이 문구를 바꾸는 건 법적 리스크가 있으니, 반드시
        내부 검토를 거친 문안만 게시하세요.
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

async function editLegalDoc(slug, title) {
  const editor = $("#legalDocEditor");
  const snap = await getDoc(doc(db, "legalDocs", slug));
  const data = snap.exists() ? snap.data() : { bodyHtml: "" };
  editor.innerHTML = `
    <div class="card">
      <h3 style="margin-top:0;">${escapeHtml(title)} 편집</h3>
      <label>본문 (HTML)</label>
      <textarea id="legalDocBody" style="min-height:320px;">${escapeHtml(data.bodyHtml ?? "")}</textarea>
      <div class="hint">docs/legal/${slug}.html의 본문 영역과 같은 HTML 마크업을 그대로 붙여넣으면 됩니다.</div>
      <div class="row" style="margin-top:14px;">
        <button class="btn-primary" id="legalDocSaveBtn">저장</button>
        ${snap.exists() ? '<button class="btn-danger" id="legalDocDeleteBtn" type="button">삭제</button>' : ""}
      </div>
    </div>
  `;
  $("#legalDocSaveBtn").addEventListener("click", async () => {
    const bodyHtml = $("#legalDocBody").value;
    await setDoc(
      doc(db, "legalDocs", slug),
      { title, bodyHtml, updatedAt: serverTimestamp() },
      { merge: true },
    );
    await loadLegalDocs();
    editor.innerHTML = `<div class="card">저장했습니다.</div>`;
  });

  const deleteBtn = $("#legalDocDeleteBtn");
  if (deleteBtn) {
    deleteBtn.addEventListener("click", async () => {
      if (!confirm(`"${title}" 문서를 삭제할까요? 삭제하면 앱/웹에서 바로 미등록 상태로 보입니다.`)) return;
      await deleteDoc(doc(db, "legalDocs", slug));
      await loadLegalDocs();
      editor.innerHTML = `<div class="card">삭제했습니다.</div>`;
    });
  }
}
