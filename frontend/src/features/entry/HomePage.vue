<script setup lang="ts">
import { ref, onUnmounted } from "vue";
import { useRouter } from "vue-router";
import { api } from "../../shared/api";
import { resolveEntry } from "./entry";
import { scanCode } from "./scan";
import AppIcon from "../../shared/AppIcon.vue";
const router = useRouter(),
  code = ref(""),
  error = ref(""),
  scanning = ref(false),
  entering = ref(false),
  video = ref<HTMLVideoElement>();
let controller: AbortController | undefined;
async function enter(value = code.value) {
  if (entering.value) return;
  error.value = "";
  const result = resolveEntry(value, location.origin);
  if (!result) {
    error.value = "请输入餐馆码、聚餐码或本站链接";
    return;
  }
  entering.value = true;
  try {
    const destination =
      result.kind === "short"
        ? await api<{ kind: "restaurant" | "room"; code: string }>(
            `/api/entry/${encodeURIComponent(result.code)}`,
          )
        : result;
    if (destination.kind === "restaurant")
      await api(
        `/api/restaurants/${encodeURIComponent(destination.code)}/menu`,
      );
    await router.push(
      `/${destination.kind === "restaurant" ? "r" : "s"}/${destination.code}`,
    );
  } catch (e) {
    error.value = (e as Error).message;
  } finally {
    entering.value = false;
  }
}
async function scan() {
  error.value = "";
  scanning.value = true;
  controller = new AbortController();
  await import("vue").then((v) => v.nextTick());
  try {
    if (video.value)
      await enter(await scanCode(video.value, controller.signal));
  } catch {
    error.value = "未能读取二维码。也可以直接输入餐馆码或聚餐码。";
  } finally {
    scanning.value = false;
  }
}
onUnmounted(() => controller?.abort());
</script>
<template>
  <section class="home-page">
    <div class="home-welcome">
      <span class="eyebrow">和喜欢的人，吃喜欢的菜</span>
      <h1>今天，一起吃什么？</h1>
      <p>从这一家餐馆，开始这一桌的好好吃饭。</p>
      <span class="welcome-art" aria-hidden="true"
        ><AppIcon name="dish" :size="100"
      /></span>
    </div>
    <div class="entry-card card">
      <button class="scan-entry" @click="scan">
        <span class="scan-icon"><AppIcon name="scan" :size="34" /></span>
        <span
          ><strong>扫码进入</strong><small>扫描餐馆或邀请二维码</small></span
        >
        <AppIcon name="arrow" :size="20" />
      </button>
      <div v-if="scanning" class="scanner">
        <video ref="video" autoplay playsinline />
        <button @click="controller?.abort()">停止扫码</button>
      </div>
      <form class="code-entry" @submit.prevent="enter()">
        <label for="restaurant-code">或输入餐馆码 / 聚餐码</label>
        <div class="entry-input">
          <AppIcon name="store" :size="20" />
          <input
            id="restaurant-code"
            v-model="code"
            placeholder="餐馆码、聚餐码或邀请链接"
            maxlength="512"
          />
          <button class="primary" type="submit" :disabled="entering">
            {{ entering ? "正在查找…" : "进入" }}
          </button>
        </div>
      </form>
      <p v-if="error" role="alert" class="error">{{ error }}</p>
    </div>
    <div class="section-heading">
      <h2>一桌人的口味，都照顾到</h2>
      <span>一起选，更好点</span>
    </div>
    <div class="dining-steps card">
      <div>
        <span class="step-icon"><AppIcon name="dish" /></span
        ><strong>先看菜单</strong><small>标记今天想吃的菜</small>
      </div>
      <div>
        <span class="step-icon"><AppIcon name="group" /></span
        ><strong>邀请同行人</strong><small>各自填写用餐要求</small>
      </div>
      <div>
        <span class="step-icon"><AppIcon name="check" /></span
        ><strong>一起定方案</strong><small>看看这一桌怎么点</small>
      </div>
    </div>
    <RouterLink to="/account" class="account-entry card">
      <span class="account-icon"><AppIcon name="user" /></span>
      <span
        ><strong>记住你的用餐习惯</strong
        ><small>登录 / 我的默认设置</small></span
      >
      <AppIcon name="arrow" :size="18" />
    </RouterLink>
    <p class="home-footnote">无需登录，也可以建局、邀请和点菜</p>
  </section>
</template>
