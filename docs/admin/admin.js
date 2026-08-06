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
  setDoc, query, orderBy, serverTimestamp,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-firestore.js";

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
});

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str ?? "";
  return div.innerHTML;
}

function formatDate(ts) {
  if (!ts) return "";
  const d = ts.toDate ? ts.toDate() : new Date(ts);
  return `${d.getFullYear()}.${String(d.getMonth() + 1).padStart(2, "0")}.${String(d.getDate()).padStart(2, "0")} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
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
