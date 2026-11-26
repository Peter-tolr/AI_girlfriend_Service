<script setup>
import {computed, nextTick, onMounted, onUnmounted, ref} from "vue";
import axios from "axios";
import avatarHer from "./assets/images/her.jpg";
import avatarMe from "./assets/images/me.jpg";

/* 前后端同源，用相对地址；开发模式（npm run dev）由 vite 代理到 5501 */
const API_ORIGIN = "";
const CHAT_STREAM = "/api/v1/chat/stream";
const STORAGE_KEY = "zhangxuexiangmei.conversationId";

/* 一个浏览器一个会话 id：刷新不丢记忆，"重新开始"换一个 */
function newConversationId() {
  return globalThis.crypto?.randomUUID?.()
      ?? "s-" + Date.now() + "-" + Math.random().toString(36).slice(2);
}

function savedConversationId() {
  try {
    return localStorage.getItem(STORAGE_KEY) || newConversationId();
  } catch {
    return newConversationId();
  }
}

const conversationId = ref(savedConversationId());

/* 聊天记录：每条 message 下挂多个气泡，模拟她连发几条 */
const messages = ref([
  {role: "ai", bubbles: ["在呢"], time: now()},
]);

const msg = ref("");
const isReplying = ref(false);
const listRef = ref(null);
const modelInfo = ref(null);
let sse;

const statusText = computed(() => {
  const model = modelInfo.value?.model;
  return model ? "在线 · " + model : "在线";
});

async function sendMsg() {
  const text = msg.value.trim();
  if (!text || isReplying.value) return;

  msg.value = "";
  isReplying.value = true;
  messages.value.push({role: "user", bubbles: [text], time: now()});
  messages.value.push({role: "ai", bubbles: [""], time: now(), streaming: true});
  await scrollToBottom();

  openStream(buildUrl(text));
}

function openStream(url) {
  if (sse) sse.close();
  sse = new EventSource(url);

  sse.onmessage = async (ev) => {
    if (ev.data === "[over]") {
      finishReply();
      return;
    }
    const item = messages.value[messages.value.length - 1];
    item.raw = (item.raw ?? "") + ev.data;
    item.bubbles = splitBubbles(item.raw);
    await scrollToBottom();
  };

  // EventSource 默认会自动重连，必须手动关掉，否则会一直重发
  sse.onerror = async () => {
    const item = messages.value[messages.value.length - 1];
    if (!item?.raw) {
      item.bubbles = ["连不上了，看看后端起来没"];
    }
    finishReply();
  };
}

/* 她一条消息一行：后端把换行换成了 \u0001，这里拆回多个气泡 */
function splitBubbles(raw) {
  const parts = raw.split("\u0001").map((s) => s.trim()).filter(Boolean);
  return parts.length ? parts : [""];
}

function finishReply() {
  if (sse) sse.close();
  sse = undefined;
  const item = messages.value[messages.value.length - 1];
  if (item) delete item.streaming;
  isReplying.value = false;
  scrollToBottom();
}

function resetChat() {
  if (sse) sse.close();
  sse = undefined;
  isReplying.value = false;
  conversationId.value = newConversationId();
  try {
    localStorage.setItem(STORAGE_KEY, conversationId.value);
  } catch {
    // 隐私模式下 localStorage 可能不可用，忽略
  }
  messages.value = [{role: "ai", bubbles: ["咋了"], time: now()}];
}

function buildUrl(text) {
  const params = new URLSearchParams({
    msg: text,
    conversationId: conversationId.value,
  });
  return API_ORIGIN + CHAT_STREAM + "?" + params.toString();
}

async function scrollToBottom() {
  await nextTick();
  const el = listRef.value;
  if (el) el.scrollTop = el.scrollHeight;
}

function now() {
  const d = new Date();
  return d.toLocaleTimeString("zh-CN", {hour: "2-digit", minute: "2-digit"});
}

onUnmounted(() => sse?.close());

onMounted(async () => {
  try {
    localStorage.setItem(STORAGE_KEY, conversationId.value);
  } catch {
    // 忽略
  }
  try {
    const res = await axios.get(API_ORIGIN + "/api/v1/info", {timeout: 5000});
    modelInfo.value = res.data;
  } catch {
    // 服务还没起来就算了，不影响聊天
  }
  await scrollToBottom();
});
</script>

<template>
  <div class="chat-header">
    <el-avatar :size="46" :src="avatarHer"/>
    <div class="header-text">
      <div class="name">张雪香美</div>
      <div class="sub" :title="modelInfo?.chatUrl ?? ''">{{ statusText }}</div>
    </div>
    <el-button class="reset" text @click="resetChat">重新开始</el-button>
  </div>

  <div ref="listRef" class="chat-list">
    <div v-for="(m, i) in messages" :key="i" class="msg-row" :class="m.role">
      <el-avatar :size="36" :src="m.role === 'user' ? avatarMe : avatarHer"/>
      <div class="msg-body">
        <div v-for="(b, j) in m.bubbles" :key="j" class="bubble" :class="m.role">
          {{ b }}
        </div>
        <div class="time">{{ m.time }}</div>
      </div>
    </div>
  </div>

  <div class="composer">
    <el-input class="send-ipt"
              v-model="msg"
              placeholder="跟她说点什么…"
              @keydown.enter="sendMsg"/>
    <el-button type="primary" :loading="isReplying" @click="sendMsg">发送</el-button>
  </div>
</template>
