<script setup lang="ts">
import { ref, onUnmounted } from "vue";
import { useRouter } from "vue-router";
import { resolveEntry } from "./entry";
import { scanCode } from "./scan";
const router = useRouter(),
  code = ref(""),
  error = ref(""),
  scanning = ref(false),
  video = ref<HTMLVideoElement>();
let controller: AbortController | undefined;
function enter(value = code.value) {
  const result = resolveEntry(value, location.origin);
  if (!result) {
    error.value = "请输入有效的餐馆码，或扫描本站餐馆／邀请二维码";
    return;
  }
  void router.push(
    `/${result.kind === "restaurant" ? "r" : "s"}/${result.code}`,
  );
}
async function scan() {
  error.value = "";
  scanning.value = true;
  controller = new AbortController();
  await import("vue").then((v) => v.nextTick());
  try {
    if (video.value) enter(await scanCode(video.value, controller.signal));
  } catch {
    error.value = "未能读取二维码。你也可以直接输入餐馆码。";
  } finally {
    scanning.value = false;
  }
}
onUnmounted(() => controller?.abort());
</script>
<template>
  <section class="hero">
    <p class="eyebrow">一桌人，各有喜欢</p>
    <h1>今天，一起吃什么？</h1>
    <p>进入餐馆，看看菜单，再和同行人一起选。</p>
    <button class="primary" @click="scan">扫描餐馆或邀请二维码</button>
    <div v-if="scanning" class="card">
      <video ref="video" autoplay playsinline /><button
        @click="controller?.abort()"
      >
        停止扫码
      </button>
    </div>
    <form @submit.prevent="enter()">
      <label for="restaurant-code">或输入餐馆码</label>
      <div class="row">
        <input
          id="restaurant-code"
          v-model="code"
          placeholder="餐馆提供的短码"
          maxlength="64"
        /><button type="submit">进入餐馆</button>
      </div>
    </form>
    <p v-if="error" role="alert" class="error">{{ error }}</p>
    <RouterLink to="/account">登录 / 我的默认设置 →</RouterLink>
    <p class="hint">无需登录也可以建局、邀请和点菜</p>
  </section>
</template>
