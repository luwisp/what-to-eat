<script setup lang="ts">
import { ref, computed, onMounted, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { getMenu, getRoom, money } from "../../shared/api";
import type { MenuSnapshot, Preferences } from "../../shared/contracts";
import { loadDraft, saveDraft, type DraftKey } from "./drafts";
const route = useRoute(),
  router = useRouter(),
  menu = ref<MenuSnapshot>(),
  error = ref(""),
  category = ref("all"),
  prefs = ref<Preferences>(
    loadDraft(`restaurant:${String(route.params.code)}`),
  );
let key: DraftKey = `restaurant:${String(route.params.code)}`;
const labels: Record<string, string> = {
  all: "全部",
  cold: "凉菜",
  hot: "热菜",
  soup: "汤",
  staple: "主食",
  drink: "饮品",
  setMeal: "套餐",
};
async function load() {
  try {
    let code = String(route.params.code);
    if (route.query.room) {
      const state = await getRoom(String(route.query.room));
      code = String(state.session.restaurantId);
      const restaurant = await getMenu(String(route.params.code));
      menu.value = restaurant;
      key = `room:${String(route.query.room)}:${state.self!.id}`;
      prefs.value = loadDraft(key);
    } else {
      menu.value = await getMenu(code);
      prefs.value = loadDraft(key);
    }
    error.value = "";
  } catch (e) {
    error.value = (e as Error).message;
  }
}
onMounted(load);
watch(prefs, (value) => saveDraft(key, value), { deep: true });
function toggle(id: string, meal = false) {
  const prop = meal ? "wantedSetMealIds" : "wantedDishIds";
  prefs.value = {
    ...prefs.value,
    [prop]: prefs.value[prop].includes(id)
      ? prefs.value[prop].filter((x) => x !== id)
      : [...prefs.value[prop], id],
  };
}
function ingredients(values: string[]) {
  return values.filter((v) => v.toLowerCase() !== "unknown").join("、");
}
const dishes = computed(
  () =>
    menu.value?.dishes.filter(
      (d) => category.value === "all" || d.category === category.value,
    ) ?? [],
);
</script>
<template>
  <section>
    <div class="row between">
      <div>
        <p class="eyebrow">先浏览，再决定</p>
        <h1>{{ menu?.restaurant.name ?? "餐馆菜单" }}</h1>
      </div>
      <button
        @click="
          router.push(
            route.query.room
              ? `/s/${route.query.room}/preferences`
              : `/r/${route.params.code}`,
          )
        "
      >
        完成选择
      </button>
    </div>
    <p class="hint">“想吃”是愿望，推荐时会结合每个人的要求。</p>
    <nav class="chips">
      <button
        v-for="(label, value) in labels"
        :key="value"
        :aria-pressed="category === value"
        @click="category = String(value)"
      >
        {{ label }}
      </button>
    </nav>
    <div class="grid" v-if="category !== 'setMeal'">
      <article v-for="dish in dishes" :key="dish.id" class="card dish">
        <img
          v-if="dish.imageUrl"
          :src="dish.imageUrl"
          :alt="dish.name"
          loading="lazy"
        />
        <div class="row between">
          <h2>{{ dish.name }} <small v-if="dish.isSignature">招牌</small></h2>
          <strong>{{ money(dish.priceFen) }}</strong>
        </div>
        <p>{{ dish.description }}</p>
        <p class="hint">
          {{ dish.taste }} · {{ dish.cookingMethod }} ·
          {{ ["不辣", "微辣", "中辣", "重辣"][dish.spiceLevel] }}
        </p>
        <p class="hint">
          食材：{{ ingredients(dish.ingredients)
          }}<span
            v-if="
              dish.ingredients.length === 0 ||
              dish.ingredients.some((v) => v.toLowerCase() === 'unknown')
            "
            >{{ ingredients(dish.ingredients) ? "；" : "" }}其余食材不详</span
          >
        </p>
        <button
          :disabled="!dish.available"
          :aria-pressed="prefs.wantedDishIds.includes(dish.id)"
          @click="toggle(dish.id)"
        >
          {{
            !dish.available
              ? "暂不可售"
              : prefs.wantedDishIds.includes(dish.id)
                ? "已标记想吃"
                : "想吃这道"
          }}
        </button>
      </article>
    </div>
    <div v-if="category === 'all' || category === 'setMeal'" class="grid">
      <article v-for="meal in menu?.setMeals" :key="meal.id" class="card">
        <img v-if="meal.imageUrl" :src="meal.imageUrl" :alt="meal.name" />
        <h2>{{ meal.name }}</h2>
        <strong>{{ money(meal.priceFen) }} / 套</strong>
        <details>
          <summary>查看套餐组分</summary>
          <p v-for="c in meal.components" :key="c.dishId">
            {{
              menu?.dishes.find((d) => d.id === c.dishId)?.name ?? "菜品已失效"
            }}
            × {{ c.quantity }}
          </p>
        </details>
        <button
          :aria-pressed="prefs.wantedSetMealIds.includes(meal.id)"
          @click="toggle(meal.id, true)"
        >
          {{
            prefs.wantedSetMealIds.includes(meal.id)
              ? "已标记想吃"
              : "想吃这个套餐"
          }}
        </button>
      </article>
    </div>
    <p v-if="error" class="error" role="alert">
      {{ error }} <button @click="load">重试</button>
    </p>
  </section>
</template>
