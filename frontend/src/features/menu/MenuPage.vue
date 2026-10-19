<script setup lang="ts">
import AppIcon from "../../shared/AppIcon.vue";
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
const selectedCount = computed(
  () => prefs.value.wantedDishIds.length + prefs.value.wantedSetMealIds.length,
);
function done() {
  void router.push(
    route.query.room
      ? `/s/${route.query.room}/preferences`
      : `/r/${route.params.code}`,
  );
}
</script>
<template>
  <section class="menu-page">
    <div class="menu-heading">
      <span class="restaurant-avatar"><AppIcon name="store" :size="30" /></span>
      <div>
        <p class="eyebrow">餐馆菜单</p>
        <h1>{{ menu?.restaurant.name ?? "餐馆菜单" }}</h1>
      </div>
    </div>
    <p class="menu-tip">
      <AppIcon
        name="check"
        :size="16"
      />先标记想吃的菜，再结合每个人的要求一起推荐
    </p>
    <div class="menu-layout">
      <nav class="category-rail" aria-label="菜品分类">
        <button
          v-for="(label, value) in labels"
          :key="value"
          :aria-pressed="category === value"
          @click="category = String(value)"
        >
          {{ label }}
        </button>
      </nav>
      <div class="menu-items">
        <div class="menu-list-heading">
          <h2>{{ labels[category] }}</h2>
          <span>按口味，慢慢选</span>
        </div>
        <div v-if="category !== 'setMeal'" class="dish-list">
          <article
            v-for="dish in dishes"
            :key="dish.id"
            class="menu-dish"
            :class="{ unavailable: !dish.available }"
          >
            <img
              v-if="dish.imageUrl"
              :src="dish.imageUrl"
              :alt="dish.name"
              loading="lazy"
              class="dish-thumb"
            />
            <div v-else class="dish-thumb dish-placeholder" aria-hidden="true">
              <AppIcon name="dish" :size="36" /><span>好菜待上桌</span>
            </div>
            <div class="dish-info">
              <h2>{{ dish.name }}</h2>
              <p v-if="dish.description" class="dish-description">
                {{ dish.description }}
              </p>
              <div class="dish-tags">
                <span v-if="dish.isSignature" class="signature">招牌</span
                ><span>{{
                  ["不辣", "微辣", "中辣", "重辣"][dish.spiceLevel]
                }}</span
                ><span v-if="dish.taste">{{ dish.taste }}</span
                ><span v-if="dish.cookingMethod">{{ dish.cookingMethod }}</span>
              </div>
              <p class="ingredient-note">
                食材：{{ ingredients(dish.ingredients)
                }}<span
                  v-if="
                    dish.ingredients.length === 0 ||
                    dish.ingredients.some((v) => v.toLowerCase() === 'unknown')
                  "
                  >{{
                    ingredients(dish.ingredients) ? "；" : ""
                  }}其余食材不详</span
                >
              </p>
              <div class="dish-bottom">
                <strong class="price">{{ money(dish.priceFen) }}</strong>
                <button
                  class="wish-button"
                  :disabled="!dish.available"
                  :aria-pressed="prefs.wantedDishIds.includes(dish.id)"
                  @click="toggle(dish.id)"
                >
                  <AppIcon
                    :name="
                      prefs.wantedDishIds.includes(dish.id) ? 'check' : 'plus'
                    "
                    :size="15"
                  />
                  {{
                    !dish.available
                      ? "暂不可售"
                      : prefs.wantedDishIds.includes(dish.id)
                        ? "已标记想吃"
                        : "想吃这道"
                  }}
                </button>
              </div>
            </div>
          </article>
        </div>
        <div
          v-if="category === 'all' || category === 'setMeal'"
          class="dish-list"
        >
          <h3
            v-if="category === 'all' && menu?.setMeals.length"
            class="meal-heading"
          >
            搭配套餐
          </h3>
          <article
            v-for="meal in menu?.setMeals"
            :key="meal.id"
            class="menu-dish"
          >
            <img
              v-if="meal.imageUrl"
              :src="meal.imageUrl"
              :alt="meal.name"
              loading="lazy"
              class="dish-thumb"
            />
            <div v-else class="dish-thumb dish-placeholder" aria-hidden="true">
              <AppIcon name="dish" :size="36" /><span>一起分享</span>
            </div>
            <div class="dish-info">
              <h2>{{ meal.name }}</h2>
              <span class="meal-tag">套餐</span>
              <details class="meal-components">
                <summary>查看套餐组分</summary>
                <p v-for="c in meal.components" :key="c.dishId">
                  {{
                    menu?.dishes.find((d) => d.id === c.dishId)?.name ??
                    "菜品已失效"
                  }}
                  × {{ c.quantity }}
                </p>
              </details>
              <div class="dish-bottom">
                <strong class="price"
                  >{{ money(meal.priceFen) }}<small> / 套</small></strong
                >
                <button
                  class="wish-button"
                  :aria-pressed="prefs.wantedSetMealIds.includes(meal.id)"
                  @click="toggle(meal.id, true)"
                >
                  <AppIcon
                    :name="
                      prefs.wantedSetMealIds.includes(meal.id)
                        ? 'check'
                        : 'plus'
                    "
                    :size="15"
                  />{{
                    prefs.wantedSetMealIds.includes(meal.id)
                      ? "已标记想吃"
                      : "想吃这个套餐"
                  }}
                </button>
              </div>
            </div>
          </article>
        </div>
        <p
          v-if="menu && !dishes.length && category !== 'setMeal'"
          class="empty-category"
        >
          这个分类还没有菜品，看看其他分类吧
        </p>
        <p
          v-if="menu && category === 'setMeal' && !menu.setMeals.length"
          class="empty-category"
        >
          这家餐馆暂时没有套餐
        </p>
        <p v-if="error" class="error" role="alert">
          {{ error }} <button @click="load">重试</button>
        </p>
      </div>
    </div>
    <div class="selection-bar">
      <span class="selection-icon"
        ><AppIcon name="dish" :size="26" /><b v-if="selectedCount">{{
          selectedCount
        }}</b></span
      >
      <div>
        <strong>{{
          selectedCount
            ? `已标记 ${selectedCount} 项想吃`
            : "看到喜欢的，就标记吧"
        }}</strong
        ><small>只记录愿望，稍后一起决定</small>
      </div>
      <button class="primary" @click="done">完成选择</button>
    </div>
  </section>
</template>
