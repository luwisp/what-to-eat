<script setup lang="ts">
import { ref, onMounted, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { getMenu, createRoom, priceFen } from "../../shared/api";
import type { MenuSnapshot } from "../../shared/contracts";
const route = useRoute(),
  router = useRouter(),
  menu = ref<MenuSnapshot>(),
  people = ref(4),
  budget = ref(""),
  error = ref(""),
  busy = ref(false);
let requestId = crypto.randomUUID();
watch([people, budget], () => {
  requestId = crypto.randomUUID();
});
async function load() {
  try {
    menu.value = await getMenu(String(route.params.code));
    error.value = "";
  } catch (e) {
    error.value = (e as Error).message;
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
    requestId = crypto.randomUUID();
    void router.push(`/s/${result.session.roomCode}`);
  } catch (e) {
    error.value = (e as Error).message;
  } finally {
    busy.value = false;
  }
}
</script>
<template>
  <section v-if="menu">
    <p class="eyebrow">餐馆 · {{ menu.restaurant.restaurantCode }}</p>
    <h1>{{ menu.restaurant.name }}</h1>
    <p>{{ menu.restaurant.description }}</p>
    <RouterLink class="button" :to="`/r/${route.params.code}/menu`"
      >先看菜单，标记今天想吃</RouterLink
    >
    <form class="card" @submit.prevent="create">
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
  <div v-if="error" class="error" role="alert">
    {{ error }} <button @click="load">重试</button>
  </div>
</template>
