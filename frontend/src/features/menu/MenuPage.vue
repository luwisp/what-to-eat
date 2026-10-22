<script setup lang="ts">
import AppIcon from "../../shared/AppIcon.vue";
import { ref, computed, onMounted, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { getMenu, getRoom, money } from "../../shared/api";
import type {
  MenuSnapshot,
  Preferences,
  RecommendationItem,
} from "../../shared/contracts";
import QuantityControl from "../../shared/QuantityControl.vue";
import {
  readPlan,
  writePlan,
  changePlanItem,
  type PlanDraft,
} from "./planDraft";
import {
  emptyPreferences,
  loadDraft,
  saveDraft,
  type DraftKey,
} from "./drafts";
const props = defineProps<{ embedded?: boolean; snapshot?: MenuSnapshot }>();
const emit = defineEmits<{ done: [] }>();
const prefs = defineModel<Preferences>({ default: emptyPreferences });
const route = useRoute(),
  router = useRouter(),
  menu = ref<MenuSnapshot>(),
  error = ref(""),
  category = ref("all");
const editPlan = computed(
  () => !props.embedded && route.query.edit === "1" && !!route.query.room,
);
const plan = ref<PlanDraft>({ version: 0, items: [] });
const planMember = ref("");
function planQuantity(id: string, meal = false) {
  return (
    plan.value.items.find(
      (i) => i.itemId === id && i.itemType === (meal ? "setMeal" : "dish"),
    )?.quantity ?? 0
  );
}
function changeQuantity(id: string, quantity: number, meal = false) {
  const item = meal
    ? menu.value?.setMeals.find((d) => d.id === id)
    : menu.value?.dishes.find((d) => d.id === id);
  if (!item || error.value || !planMember.value) return;
  plan.value = {
    ...plan.value,
    items: changePlanItem(
      plan.value.items,
      {
        itemType: meal ? "setMeal" : "dish",
        itemId: id,
        name: item.name,
        unitPriceFen: item.priceFen,
        quantity: 1,
      },
      quantity,
    ),
  };
  writePlan(String(route.query.room), planMember.value, plan.value);
}
const planTotal = computed(() =>
  plan.value.items.reduce((sum, i) => sum + i.quantity * i.unitPriceFen, 0),
);
let key: DraftKey = `restaurant:${String(route.params.code)}`;
const labels: Record<string, string> = {
  all: "全部",
  cold: "凉菜",
  hot: "热菜",
  soup: "汤",
  staple: "主食",
  side: "小吃",
  drink: "饮品",
  setMeal: "套餐",
};
const visibleCategories = computed(() =>
  Object.fromEntries(
    Object.entries(labels).filter(
      ([value]) =>
        value === "all" ||
        (value === "setMeal"
          ? !!menu.value?.setMeals.length
          : menu.value?.dishes.some((dish) => dish.category === value)),
    ),
  ),
);
watch(visibleCategories, (categories) => {
  if (!(category.value in categories)) category.value = "all";
});
async function load() {
  if (props.embedded) {
    menu.value = props.snapshot;
    return;
  }
  try {
    let code = String(route.params.code);
    if (route.query.room) {
      const state = await getRoom(String(route.query.room));
      code = String(state.session.restaurantId);
      const restaurant = await getMenu(String(route.params.code));
      menu.value = restaurant;
      if (!state.self) throw new Error("请先回到聚餐局加入这桌");
      key = `room:${String(route.query.room)}:${state.self.id}`;
      if (editPlan.value) {
        if (!state.self || !state.recommendation)
          throw new Error("先回到聚餐局生成方案，再添加菜品");
        planMember.value = state.self.id;
        plan.value = readPlan(String(route.query.room), state.self.id) ?? {
          version: state.stateVersion,
          items: state.recommendation.draft.items,
        };
        if (plan.value.version !== state.stateVersion)
          throw new Error("这桌方案已经更新，请返回后重新编辑");
      }
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
watch(
  prefs,
  (value) => {
    if (!props.embedded && !editPlan.value) saveDraft(key, value);
  },
  { deep: true },
);
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
const selectedCount = computed(() =>
  editPlan.value
    ? plan.value.items.length
    : prefs.value.wantedDishIds.length + prefs.value.wantedSetMealIds.length,
);
function done() {
  if (props.embedded) {
    emit("done");
    return;
  }
  void router.push(
    route.query.room
      ? `/s/${route.query.room}/${editPlan.value ? "result?edit=1" : "preferences"}`
      : `/r/${route.params.code}`,
  );
}
</script>
<template>
  <section class="menu-page" :class="{ 'embedded-menu': props.embedded }">
    <div v-if="!props.embedded" class="menu-heading">
      <span class="restaurant-avatar"><AppIcon name="store" :size="30" /></span>
      <div>
        <p class="eyebrow">餐馆菜单</p>
        <h1>{{ menu?.restaurant.name ?? "餐馆菜单" }}</h1>
      </div>
    </div>
    <p class="menu-tip">
      <AppIcon name="check" :size="16" />{{
        editPlan
          ? "选择要加入这桌的菜，返回后一起保存"
          : "先标记想吃的菜，再结合每个人的要求一起推荐"
      }}
    </p>
    <div class="menu-layout">
      <nav class="category-rail" aria-label="菜品分类">
        <button
          v-for="(label, value) in visibleCategories"
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
                <QuantityControl
                  v-if="editPlan"
                  :name="dish.name"
                  :quantity="planQuantity(dish.id)"
                  :increase-disabled="!dish.available || !!error"
                  @change="(n) => changeQuantity(dish.id, n)"
                />
                <button
                  v-else
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
                <QuantityControl
                  v-if="editPlan"
                  :name="meal.name"
                  :quantity="planQuantity(meal.id, true)"
                  @change="(n) => changeQuantity(meal.id, n, true)"
                />
                <button
                  v-else
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
          v-if="
            menu &&
            !dishes.length &&
            !menu.setMeals.length &&
            category === 'all'
          "
          class="empty-category"
        >
          这家餐馆还没有菜品
        </p>
        <p
          v-if="menu && category === 'setMeal' && !menu.setMeals.length"
          class="empty-category"
        >
          这家餐馆暂时没有套餐
        </p>
        <p v-if="error" class="error" role="alert">
          {{ error }} <button @click="load">重试</button
          ><RouterLink v-if="editPlan" :to="`/s/${route.query.room}/result`"
            >返回方案</RouterLink
          >
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
          editPlan
            ? `${selectedCount} 项 · ${money(planTotal)}`
            : selectedCount
              ? `已标记 ${selectedCount} 项想吃`
              : "看到喜欢的，就标记吧"
        }}</strong
        ><small>{{
          editPlan ? "返回方案后保存并校验" : "只记录愿望，稍后一起决定"
        }}</small>
      </div>
      <button class="primary" @click="done">
        {{ editPlan ? "返回方案" : "完成选择" }}
      </button>
    </div>
  </section>
</template>
