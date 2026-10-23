<script setup lang="ts">
import { ref, onUnmounted, nextTick } from "vue";
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
  if (scanning.value) {
    controller?.abort();
    scanning.value = false;
    return;
  }
  error.value = "";
  scanning.value = true;
  const current = new AbortController();
  controller = current;
  try {
    await nextTick();
    if (!video.value || current.signal.aborted) return;
    const value = await scanCode(video.value, current.signal);
    if (!current.signal.aborted) await enter(value);
  } catch {
    if (!current.signal.aborted)
      error.value = "未能读取二维码。也可以直接输入餐馆码或聚餐码。";
  } finally {
    if (controller === current) {
      scanning.value = false;
      controller = undefined;
    }
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
    </div>
    <div class="entry-card card">
      <button
        class="scan-entry"
        :aria-expanded="scanning"
        aria-controls="entry-scanner"
        @click="scan"
      >
        <span class="scan-icon"><AppIcon name="scan" :size="34" /></span>
        <span
          ><strong>{{ scanning ? "正在扫码" : "扫码进入" }}</strong
          ><small>{{
            scanning ? "再次点击收起" : "扫描餐馆或邀请二维码"
          }}</small></span
        >
        <AppIcon name="arrow" :size="20" />
      </button>
      <div v-if="scanning" id="entry-scanner" class="scanner">
        <video ref="video" autoplay playsinline />
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
    <p class="home-footnote">无需登录，也可以建局、邀请和点菜</p>
  </section>
</template>
