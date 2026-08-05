// 커넥션센스 관리자 콘솔.
//
// ⚠️ 배포 전 반드시 해야 할 일 (README.md 참고):
// 1) 아래 firebaseConfig를 Firebase 콘솔 > 프로젝트 설정 > 앱 추가(웹)에서
//    발급받은 실제 값으로 채울 것 — 지금은 이 프로젝트에 웹 앱이 등록된
//    적이 없어서 placeholder 상태다.
// 2) Firebase 콘솔 > Authentication에서 관리자로 쓸 이메일/비밀번호 계정을
//    직접 만들 것.
// 3) Firestore의 `admins` 컬렉션에 그 계정의 uid를 문서 ID로 하는 빈
//    문서를 하나 만들 것(예: admins/AbCdEf123... , 필드는 아무거나 상관없음).
//    firestore.rules가 이 컬렉션 자체는 클라이언트가 직접 못 읽고 쓰게
//    막아뒀기 때문에 Firebase 콘솔에서 수동으로만 추가할 수 있다.
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
import {
  getAuth, signInWithEmailAndPassword, onAuthStateChanged, signOut,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";
import {
  getFirestore, collection, doc, getDoc, getDocs, addDoc, updateDoc, deleteDoc,
  setDoc, query, orderBy, serverTimestamp,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-firestore.js";

const firebaseConfig = {
  apiKey: "REPLACE_ME",
  authDomain: "connection-sense.firebaseapp.com",
  projectId: "connection-sense",
  storageBucket: "connection-sense.firebasestorage.app",
  appId: "REPLACE_ME",
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

const $ = (sel) => document.querySelector(sel);
const loginScreen = $("#loginScreen");
const dashboard = $("#dashboard");

// ---------- 로그인 ----------

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

$("#logoutBtn").addEventListener("click", () => signOut(auth));

onAuthStateChanged(auth, async (user) => {
  if (!user) {
    loginScreen.style.display = "block";
    dashboard.classList.remove("visible");
    return;
  }
  // admins/{uid} 컬렉션은 규칙상 직접 못 읽으므로, "관리자만 통과하는 쿼리"를
  // 실제로 날려보는 방식으로 판별한다 — notices를 published 필터 없이
  // 전부 조회하는 건 firestore.rules상 isAdmin()만 통과할 수 있다.
  try {
    await getDocs(collection(db, "notices"));
  } catch (e) {
    $("#loginError").innerHTML =
      `<div class="error">이 계정은 관리자 권한이 없습니다.</div>`;
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
}
