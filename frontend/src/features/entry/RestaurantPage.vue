<script setup lang="ts">
import { ref, onMounted, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { ApiError, getMenu, createRoom, priceFen } from "../../shared/api";
import AppIcon from "../../shared/AppIcon.vue";
import type { MenuSnapshot } from "../../shared/contracts";
import { createRequestId } from "../../shared/requestId";
const route = useRoute(),
  router = useRouter(),
  menu = ref<MenuSnapshot>(),
  people = ref(4),
  budget = ref(""),
  error = ref(""),
  busy = ref(false),
  missing = ref(false),
  loading = ref(true);
let requestId = createRequestId();
watch([people, budget], () => {
  requestId = createRequestId();
});
async function load() {
  loading.value = true;
  try {
    menu.value = await getMenu(String(route.params.code));
    error.value = "";
    missing.value = false;
  } catch (e) {
    error.value = (e as Error).message;
    missing.value = e instanceof ApiError && e.status === 404;
  } finally {
    loading.value = false;
  }
}
onMounted(load);
async function create() {
  busy.value = true;
  error.value = "";
  try {
    const result = await createRoom(
      {
        restaurantCode: String(route.params.code),
        people: people.value,
        budgetPerPersonFen: budget.value ? priceFen(budget.value) : null,
      },
      requestId,
    );
    requestId = createRequestId();
    void router.push(`/s/${result.session.roomCode}`);
  } catch (e) {
    error.value = (e as Error).message;
  } finally {
    busy.value = false;
  }
}
</script>
<template>
  <section v-if="menu" class="restaurant-page">
    <div class="restaurant-heading card">
      <span class="restaurant-avatar"><AppIcon name="store" :size="38" /></span>
      <div>
        <p class="eyebrow">餐馆 · {{ menu.restaurant.restaurantCode }}</p>
        <h1>{{ menu.restaurant.name }}</h1>
        <p class="hint">{{ menu.restaurant.description }}</p>
      </div>
    </div>
    <RouterLink class="button browse-entry" :to="`/r/${route.params.code}/menu`"
      ><span class="step-icon"><AppIcon name="dish" /></span
      ><span
        ><strong>先看菜单，标记今天想吃</strong
        ><small>单点、套餐，都可以先看看</small></span
      ><AppIcon name="arrow" :size="20"
    /></RouterLink>
    <form class="card create-room-card" @submit.prevent="create">
      <p class="eyebrow">一起点菜</p>
      <h2>开一桌，一起决定</h2>
      <div class="row">
        <label
          >用餐人数<input
            v-model.number="people"
            type="number"
            min="1"
            max="100"
            required /></label
        ><label
          >人均预算（可不填）<input
            v-model="budget"
            inputmode="decimal"
            placeholder="元"
        /></label>
      </div>
      <p class="hint">建局后可立即邀请；每个人什么时候填写都可以。</p>
      <button class="primary" :disabled="busy">
        {{ busy ? "正在创建…" : "创建聚餐局" }}
      </button>
    </form>
  </section>
  <section v-if="error" class="entry-empty card" role="alert">
    <AppIcon name="store" :size="44" />
    <h1>{{ missing ? "没有找到这家餐馆" : "暂时无法加载餐馆" }}</h1>
    <p>{{ missing ? "可能是餐馆码写错了，回首页重新输入吧。" : error }}</p>
    <RouterLink to="/" class="button primary">回首页重新输入</RouterLink>
    <button v-if="!missing" :disabled="loading" @click="load">重新加载</button>
  </section>
  <p v-else-if="loading" role="status">正在打开餐馆…</p>
</template>
