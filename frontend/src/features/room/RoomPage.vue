<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from "vue";
import { useRoute, useRouter } from "vue-router";
import QRCode from "qrcode";
import type {
  RoomSnapshot,
  Preferences,
  MenuSnapshot,
  RecommendationItem,
} from "../../shared/contracts";
import { api, getMenu, money, priceFen, copyJson } from "../../shared/api";
import { connectRoom, type RoomConnection } from "../../shared/socket";
import {
  loadDraft,
  saveDraft,
  hasDraft,
  emptyPreferences,
  type DraftKey,
} from "../menu/drafts";
import ModalSheet from "../../shared/ModalSheet.vue";
import AppIcon from "../../shared/AppIcon.vue";
import QuantityControl from "../../shared/QuantityControl.vue";
import {
  readPlan,
  writePlan,
  clearPlan,
  changePlanItem,
} from "../menu/planDraft";
import PreferencesForm from "../../shared/PreferencesForm.vue";
const aiEnabled = ref(false);
const route = useRoute(),
  router = useRouter(),
  state = ref<RoomSnapshot>(),
  status = ref("正在连接"),
  error = ref(""),
  notice = ref(""),
  prefs = ref(emptyPreferences()),
  menu = ref<MenuSnapshot>(),
  invite = ref(false),
  qr = ref(""),
  people = ref(4),
  budget = ref(""),
  busy = ref(false),
  companion = ref(false),
  companionId = ref(""),
  companionName = ref(""),
  companionPrefs = ref(emptyPreferences()),
  chatText = ref(""),
  chatOpen = ref(false),
  chatScroll = ref<HTMLElement>();
let connection: RoomConnection | undefined,
  key: DraftKey | undefined,
  initialized = "";
const resultView = computed(() => route.path.endsWith("/result"));
const pendingRecommendation = ref(false),
  copied = ref(false);
const working = computed(
  () => pendingRecommendation.value || !!state.value?.job,
);
const menuLink = computed(() =>
  state.value
    ? `/r/${state.value.restaurantCode}/menu?room=${route.params.code}`
    : "",
);
const editing = computed(() => route.path.endsWith("/preferences"));
const host = computed(
  () => state.value?.self?.id === state.value?.session.hostParticipantId,
);
const submitted = computed(
  () => state.value?.members.filter((p) => p.submitted).length ?? 0,
);
const result = computed(() => state.value?.recommendation);
const editingVersion = ref(0);
const editingResult = ref(false),
  editedItems = ref<RecommendationItem[]>([]);
const displayItems = computed(() =>
  editingResult.value ? editedItems.value : (result.value?.draft.items ?? []),
);
const displayTotal = computed(() =>
  displayItems.value.reduce((n, i) => n + i.unitPriceFen * i.quantity, 0),
);
const planMenuLink = computed(() => menuLink.value + "&edit=1");
function persistPlan() {
  if (state.value?.self && editingResult.value)
    writePlan(String(route.params.code), state.value.self.id, {
      version: editingVersion.value,
      items: editedItems.value,
    });
}
function cancelResultEdit() {
  editingResult.value = false;
  if (state.value?.self)
    clearPlan(String(route.params.code), state.value.self.id);
}
function changeItem(item: RecommendationItem, quantity: number) {
  editedItems.value = changePlanItem(editedItems.value, item, quantity);
  persistPlan();
}
function startResultEdit() {
  editingVersion.value = state.value?.stateVersion ?? 0;
  editedItems.value = copyJson(result.value?.draft.items ?? []);
  editingResult.value = true;
  persistPlan();
}
function itemDescription(item: RecommendationItem): string {
  if (item.itemType !== "dish") return "";
  return (
    menu.value?.dishes.find((d) => d.id === item.itemId)?.description.trim() ??
    ""
  );
}
async function saveResultEdit() {
  await send("edit_recommendation", {
    expectedVersion: editingVersion.value,
    items: editedItems.value.map((i) => ({
      itemType: i.itemType,
      itemId: i.itemId,
      quantity: Number(i.quantity),
    })),
  });
  if (!error.value) cancelResultEdit();
}
const inviteLink = computed(
  () => location.origin + "/s/" + String(route.params.code),
);
onMounted(() => {
  void api<{ aiEnabled: boolean }>("/api/capabilities")
    .then((c) => (aiEnabled.value = c.aiEnabled))
    .catch(() => {});
  connection = connectRoom(
    String(route.params.code),
    (s) => {
      const wasWorking = working.value;
      state.value = s;
      if (wasWorking && !s.job) {
        pendingRecommendation.value = false;
        if (
          s.recommendation &&
          !s.recommendationInvalid &&
          !editing.value &&
          !resultView.value
        )
          void router.push(`/s/${route.params.code}/result`);
        else if (!s.recommendation || s.recommendationInvalid)
          error.value = "这次没能完成搭配，请再试一次。";
      }
      people.value = s.session.people;
      budget.value =
        s.session.budgetPerPersonFen === null
          ? ""
          : String(s.session.budgetPerPersonFen / 100);
      if (s.self && initialized !== s.self.id) {
        initialized = s.self.id;
        key = `room:${s.session.roomCode}:${s.self.id}`;
        prefs.value = hasDraft(key) ? loadDraft(key) : copyJson(s.self.draft);
        if (resultView.value) {
          const draft = readPlan(String(route.params.code), s.self.id);
          if (draft && draft.version === s.stateVersion) {
            editingVersion.value = draft.version;
            editedItems.value = draft.items;
            editingResult.value = true;
          } else if (draft) {
            notice.value = "这桌的要求已经更新，请重新编辑最新方案。";
            clearPlan(String(route.params.code), s.self.id);
          }
        }
        if (!hasDraft(key) && hasDraft(`restaurant:${s.restaurantCode}`)) {
          const restaurant = loadDraft(`restaurant:${s.restaurantCode}`);
          prefs.value.wantedDishIds = restaurant.wantedDishIds;
          prefs.value.wantedSetMealIds = restaurant.wantedSetMealIds;
        }
        saveDraft(key, prefs.value);
        void getMenu(s.restaurantCode)
          .then((m) => {
            menu.value = m;
          })
          .catch(() => {});
      }
    },
    (s) => {
      status.value = s;
      if (
        ![
          "已连接",
          "正在连接",
          "正在重连",
          "连接断开，正在恢复",
          "服务不可用，正在重试",
        ].includes(s)
      ) {
        pendingRecommendation.value = false;
        error.value = s;
      }
    },
  );
  void QRCode.toDataURL(inviteLink.value, { width: 240, margin: 1 }).then(
    (v) => {
      qr.value = v;
    },
  );
});
onUnmounted(() => connection?.close());
watch(
  () => [chatOpen.value, state.value?.messages.length, working.value],
  async () => {
    if (!chatOpen.value) return;
    await nextTick();
    if (chatScroll.value)
      chatScroll.value.scrollTop = chatScroll.value.scrollHeight;
  },
);
watch(
  () => state.value?.menuVersion,
  () => {
    const s = state.value;
    if (!s) return;
    void getMenu(s.restaurantCode)
      .then((m) => {
        if (m.menuVersion === state.value?.menuVersion) menu.value = m;
      })
      .catch(() => {});
  },
);
watch(
  prefs,
  (v) => {
    if (key) saveDraft(key, v);
  },
  { deep: true },
);
async function send(type: string, payload: Record<string, unknown> = {}) {
  error.value = "";
  busy.value = true;
  try {
    await connection?.send(type, {
      ...payload,
      expectedVersion: payload.expectedVersion ?? state.value?.stateVersion,
    });
  } catch (e) {
    error.value = (e as Error).message;
  } finally {
    busy.value = false;
  }
}
async function save(submit: boolean) {
  notice.value = "";
  const wishes =
    prefs.value.wantedDishIds.length + prefs.value.wantedSetMealIds.length;
  await send("update_preferences", { prefs: copyJson(prefs.value), submit });
  if (!error.value && state.value?.self) {
    prefs.value = copyJson(state.value.self.draft);
    if (
      prefs.value.wantedDishIds.length + prefs.value.wantedSetMealIds.length <
      wishes
    )
      notice.value = "已取消与当前限制冲突或已不可售的愿望；其余要求已保留";
  }
  if (!error.value && submit) void router.push(`/s/${route.params.code}`);
}
async function updateSession() {
  try {
    await send("update_session", {
      people: people.value,
      budgetPerPersonFen: budget.value ? priceFen(budget.value) : null,
    });
  } catch (e) {
    error.value = (e as Error).message;
  }
}
function editCompanion(id = "") {
  const member = state.value?.members.find((m) => m.id === id);
  companionId.value = id;
  companionName.value = member?.nickname ?? "";
  companionPrefs.value = member?.preferences
    ? copyJson(member.preferences)
    : emptyPreferences();
  companion.value = true;
}
async function saveCompanion() {
  await send(companionId.value ? "update_companion" : "add_companion", {
    id: companionId.value,
    prefs: copyJson(companionPrefs.value),
    nickname: companionName.value,
  });
  if (!error.value) companion.value = false;
}
async function copyInvite() {
  try {
    await navigator.clipboard.writeText(inviteLink.value);
    copied.value = true;
  } catch {
    const input = document.querySelector<HTMLInputElement>(
      '[aria-label="邀请链接"]',
    );
    input?.focus();
    input?.select();
  }
}
async function requestRecommendation(adjustment?: string) {
  if (working.value || editingResult.value) return;
  pendingRecommendation.value = true;
  await send("request_recommendation", adjustment ? { adjustment } : {});
  if (error.value) pendingRecommendation.value = false;
}
async function reopen() {
  await send("reopen_recommendation");
  if (!error.value) void router.push(`/s/${route.params.code}`);
}
async function sendChat() {
  if (working.value || editingResult.value || !chatText.value.trim()) return;
  chatOpen.value = true;
  pendingRecommendation.value = true;
  await send("chat_message", { text: chatText.value.trim() });
  if (error.value) pendingRecommendation.value = false;
  else chatText.value = "";
}
function itemImage(item: RecommendationItem): string {
  return (
    (item.itemType === "dish"
      ? menu.value?.dishes.find((d) => d.id === item.itemId)
      : menu.value?.setMeals.find((d) => d.id === item.itemId)
    )?.imageUrl ?? ""
  );
}
function stapleFor(id: string | null) {
  return menu.value?.dishes.find((d) => d.id === id);
}
function suitableFor(memberId: string) {
  return (
    result.value?.draft.expandedDishes.filter(
      (d) =>
        d.dish.category !== "staple" &&
        result.value?.draft.fits.some(
          (f) =>
            f.dishId === d.dish.id &&
            f.memberId === memberId &&
            f.status === "fit",
        ),
    ) ?? []
  );
}
</script>
<template>
  <section class="room-page room-flow">
    <header class="room-heading">
      <div>
        <RouterLink
          v-if="editing || resultView"
          class="quiet-link"
          :to="`/s/${route.params.code}`"
          >← 返回这一桌</RouterLink
        >
        <h1>
          {{
            editing
              ? "我的用餐要求"
              : resultView
                ? "这桌这样点"
                : (menu?.restaurant.name ?? "聚小宝")
          }}
        </h1>
        <p class="room-caption">
          聚餐码 {{ route.params.code
          }}<span v-if="state"> · {{ state.session.people }} 人</span>
        </p>
      </div>
      <div v-if="!editing" class="room-tools">
        <RouterLink
          v-if="menuLink"
          :to="resultView && editingResult ? planMenuLink : menuLink"
          class="button"
          aria-label="看菜单"
          >看菜单</RouterLink
        ><button
          @click="
            invite = true;
            copied = false;
          "
          aria-haspopup="dialog"
        >
          邀请同行人
        </button>
      </div>
    </header>
    <p
      v-if="status !== '已连接' && state"
      class="connection-status"
      role="status"
    >
      {{ status }}
    </p>
    <p v-if="error" role="alert" class="error">
      {{ error }} <RouterLink v-if="!state" to="/">回首页重新输入</RouterLink>
    </p>
    <p v-if="notice" role="status" class="notice">{{ notice }}</p>
    <div
      v-if="working && !resultView"
      class="working-panel"
      role="status"
      aria-live="polite"
    >
      <span class="working-orbit"><AppIcon name="dish" :size="30" /></span>
      <div>
        <strong>{{
          aiEnabled ? "点菜员正在为这一桌搭配" : "正在搭配这一桌的菜"
        }}</strong>
        <p>
          结合大家的要求，核对菜品、份数和预算<span class="typing-dots"
            ><i></i><i></i><i></i
          ></span>
        </p>
      </div>
    </div>
    <div v-if="editing" class="card preferences-card">
      <PreferencesForm v-model="prefs" :menu="menu" :menu-link="menuLink" />
      <div class="row preferences-actions">
        <button
          :disabled="busy || state?.session.state === 'closed'"
          @click="save(false)"
        >
          只存草稿</button
        ><button
          class="primary"
          :disabled="busy || state?.session.state === 'closed'"
          @click="save(true)"
        >
          {{ busy ? "正在保存…" : "提交本局要求" }}
        </button>
      </div>
    </div>
    <template v-else-if="!resultView && state">
      <p v-if="state.session.state === 'closed'" class="notice">
        本桌已确认，可以查看已搭配的菜。
      </p>
      <section class="card member-card">
        <div class="section-heading">
          <h2>这一桌的人</h2>
          <span>{{ submitted }} / {{ state.session.people }} 人已填写</span>
        </div>
        <ul class="dining-members">
          <li v-for="m in state.members" :key="m.id">
            <span class="member-avatar"
              ><AppIcon
                :name="m.id === state.self?.id ? 'user' : 'group'"
                :size="20"
            /></span>
            <div class="member-copy">
              <strong
                >{{ m.id === state.self?.id ? "我" : m.nickname
                }}<small v-if="m.source === 'companion'">代填</small></strong
              ><span>{{ m.submitted ? "已填写" : "还没填写" }}</span>
            </div>
            <RouterLink
              v-if="m.id === state.self?.id"
              :to="`/s/${route.params.code}/preferences`"
              class="member-edit"
              :aria-label="m.submitted ? '编辑我的要求' : '填写我的要求'"
              >{{ m.submitted ? "编辑" : "填写" }}
              <AppIcon name="arrow" :size="14"
            /></RouterLink>
            <div
              v-else-if="m.filledByParticipantId === state.self?.id"
              class="member-controls"
            >
              <button
                :aria-label="'修改' + m.nickname + '的要求'"
                @click="editCompanion(m.id)"
              >
                编辑</button
              ><button
                :aria-label="'删除' + m.nickname"
                :disabled="busy || state.session.state === 'closed'"
                @click="send('remove_companion', { id: m.id })"
              >
                移除
              </button>
            </div>
          </li>
        </ul>
        <button
          class="add-member"
          @click="editCompanion()"
          :disabled="state.session.state === 'closed'"
        >
          ＋ 帮同行人填写
        </button>
      </section>
      <details v-if="host" class="table-settings card">
        <summary>
          <span
            >{{ state.session.people }} 人用餐 ·
            {{
              state.session.budgetPerPersonFen === null
                ? "预算不限"
                : "人均 " + money(state.session.budgetPerPersonFen)
            }}</span
          ><span class="quiet-link">设置 ⌄</span>
        </summary>
        <form @submit.prevent="updateSession">
          <div class="row">
            <label
              >人数<input
                v-model.number="people"
                type="number"
                :min="state.members.length"
                max="100" /></label
            ><label
              >人均预算（元，可不填）<input
                v-model="budget"
                inputmode="decimal"
            /></label>
          </div>
          <button :disabled="busy || state.session.state === 'closed'">
            保存人数和预算
          </button>
        </form>
      </details>
      <RouterLink
        v-if="result"
        class="existing-result card"
        :to="`/s/${route.params.code}/result`"
        ><AppIcon name="dish" /><span
          ><strong>{{
            state.recommendationInvalid ? "上次方案需要更新" : "看看已搭配的菜"
          }}</strong
          ><small
            >{{ displayItems.length }} 项 ·
            {{ money(result.draft.totalFen) }}</small
          ></span
        ><AppIcon name="arrow" :size="18"
      /></RouterLink>
      <div class="lobby-action">
        <button
          v-if="state.session.state !== 'closed'"
          class="primary"
          :disabled="busy || !submitted || working"
          @click="requestRecommendation()"
        >
          <span v-if="working" class="button-spinner"></span
          >{{
            working ? "正在搭配…" : result ? "重新搭配这一桌" : "看看怎么点"
          }}
        </button>
        <p v-if="!submitted">从成员列表填写要求，就可以开始搭配了</p>
      </div>
    </template>
    <article v-else-if="resultView && result" class="result result-page">
      <p v-if="state?.recommendationInvalid" class="notice">
        大家的要求或菜单变了，这份方案需要重新搭配。<button
          :disabled="working"
          @click="requestRecommendation()"
        >
          重新搭配
        </button>
      </p>
      <div class="result-total">
        <div>
          <span
            >{{ displayItems.length }} 项 · 人均约
            {{
              money(Math.ceil(displayTotal / (state?.session.people || 1)))
            }}</span
          ><strong>{{ money(displayTotal) }}</strong>
        </div>
        <span
          :class="[
            'result-badge',
            { partial: result.draft.mealStatus === 'partial' },
          ]"
          >{{
            editingResult
              ? "待保存校验"
              : result.draft.mealStatus === "partial"
                ? "还有需要补齐的地方"
                : "饭菜已配齐"
          }}</span
        >
      </div>
      <ul class="result-dishes">
        <li
          v-for="item in displayItems"
          :key="`${item.itemType}:${item.itemId}`"
          class="result-dish"
        >
          <img
            v-if="itemImage(item)"
            :src="itemImage(item)"
            :alt="item.name"
            loading="lazy"
          />
          <div v-else class="result-dish-placeholder">
            <AppIcon name="dish" :size="34" />
          </div>
          <div class="result-dish-copy">
            <div class="result-card-heading">
              <h2>{{ item.name }}</h2>
              <button
                v-if="editingResult"
                type="button"
                class="remove-dish"
                :aria-label="'移除 ' + item.name"
                @click="changeItem(item, 0)"
              >
                <AppIcon name="trash" :size="16" />
              </button>
            </div>
            <span v-if="itemDescription(item)" class="dish-description">{{
              itemDescription(item)
            }}</span
            ><span v-if="item.itemType === 'setMeal'" class="hint">套餐</span>
            <div class="result-dish-bottom">
              <strong>{{ money(item.unitPriceFen * item.quantity) }}</strong
              ><QuantityControl
                v-if="editingResult"
                :name="item.name"
                :quantity="item.quantity"
                @change="(n) => changeItem(item, n)"
              /><span v-else>× {{ item.quantity }}</span>
            </div>
          </div>
        </li>
      </ul>
      <p v-if="editingResult && !displayItems.length" class="card empty-plan">
        这份方案已清空，可以从菜单重新加菜。
      </p>
      <div v-if="!editingResult" class="result-edit-toolbar">
        <button
          v-if="state?.session.state !== 'closed'"
          :disabled="working || state?.recommendationInvalid"
          @click="startResultEdit"
        >
          修改这桌方案</button
        ><button
          :disabled="
            working ||
            state?.recommendationInvalid ||
            state?.session.state === 'closed'
          "
          @click="requestRecommendation('addSoup')"
        >
          再加一道汤
        </button>
      </div>
      <div v-if="editingResult" class="plan-edit-actions">
        <RouterLink :to="planMenuLink" class="button">＋ 从菜单加菜</RouterLink
        ><button @click="cancelResultEdit">取消修改</button
        ><button
          class="primary"
          :disabled="busy || working"
          @click="saveResultEdit"
        >
          保存并重新校验
        </button>
      </div>
      <details v-if="!editingResult" class="result-details">
        <summary>看看每个人怎么吃</summary>
        <div class="member-meals">
          <article
            v-for="m in result.draft.mealMembers"
            :key="m.memberId"
            class="member-meal-card"
          >
            <header>
              <span class="member-avatar"
                ><AppIcon name="user" :size="18" /></span
              ><strong>{{
                m.memberId === state?.self?.id
                  ? "我"
                  : state?.members.find((p) => p.id === m.memberId)?.nickname
              }}</strong
              ><span
                :class="[
                  'meal-coverage',
                  {
                    missing:
                      m.halfDishAllocated < m.halfDishNeed ||
                      (!m.stapleOptOut && !m.stapleDishId),
                  },
                ]"
                >{{
                  m.halfDishAllocated >= m.halfDishNeed &&
                  (m.stapleOptOut || m.stapleDishId)
                    ? "份量已配齐"
                    : "还需补充"
                }}</span
              >
            </header>
            <div class="meal-supply">
              <span
                >热菜 {{ m.halfDishAllocated / 2 }} /
                {{ m.halfDishNeed / 2 }} 份</span
              ><meter
                min="0"
                :max="Math.max(1, m.halfDishNeed)"
                :value="Math.min(m.halfDishAllocated, m.halfDishNeed)"
              />
            </div>
            <div class="member-staple">
              <img
                v-if="stapleFor(m.stapleDishId)?.imageUrl"
                :src="stapleFor(m.stapleDishId)?.imageUrl"
                alt=""
              /><AppIcon v-else name="dish" :size="20" /><span>{{
                m.stapleOptOut
                  ? "不要主食"
                  : (stapleFor(m.stapleDishId)?.name ?? "主食待补充")
              }}</span>
            </div>
            <div class="member-fit-dishes">
              <span v-for="d in suitableFor(m.memberId)" :key="d.dish.id"
                ><img v-if="d.dish.imageUrl" :src="d.dish.imageUrl" alt="" />{{
                  d.dish.name
                }}</span
              >
              <p v-if="!suitableFor(m.memberId).length">
                暂无确定适配的菜，需要继续搭配
              </p>
            </div>
          </article>
        </div>
        <p class="hint">
          热菜 {{ result.draft.estimatedHotSupply }} /
          {{ result.draft.estimatedHotNeed }} 份
        </p>
        <p
          v-if="result.draft.uncoveredIds.includes(state?.self?.id ?? '')"
          class="error"
        >
          还没有适合你的非汤、主食或饮品菜；食材不完整的菜暂不计入覆盖。
        </p>
        <p
          v-if="result.draft.undercoveredIds.includes(state?.self?.id ?? '')"
          class="notice"
        >
          目前只有 1 道适合的菜，选择较少。
        </p>
        <p v-for="notice in result.draft.notices" :key="notice" class="hint">
          {{ notice }}
        </p>
        <details v-if="result.draft.unmetWishes.length">
          <summary>没有满足的想吃愿望</summary>
          <p v-for="(wish, i) in result.draft.unmetWishes" :key="i">
            {{
              menu?.dishes.find((d) => d.id === wish.itemId)?.name ??
              menu?.setMeals.find((m) => m.id === wish.itemId)?.name ??
              wish.itemId
            }}：{{ wish.reason }}
          </p>
        </details>
        <p v-if="submitted < (state?.session.people ?? 0)" class="hint">
          成员尚未填齐，方案已保留；填写齐全后再确认整桌方案。
        </p>

        <p v-if="result.draft.budgetWarning" class="notice">
          {{ result.draft.budgetWarning }}
        </p>
      </details>
      <details
        v-if="
          !editingResult &&
          result.draft.items.some((i) => i.itemType === 'setMeal')
        "
        class="result-details"
      >
        <summary>套餐里有哪些菜</summary>
        <p v-for="d in result.draft.expandedDishes" :key="d.dish.id">
          {{ d.dish.name }} × {{ d.quantity
          }}<span v-if="d.dish.ingredients.includes('unknown')">
            · 其余食材不详</span
          >
        </p>
      </details>
      <div class="result-actions">
        <button
          v-if="
            !editingResult &&
            host &&
            result.canConfirm &&
            !state?.recommendationInvalid &&
            state?.session.state !== 'closed'
          "
          class="primary"
          :disabled="working"
          @click="
            send('confirm_recommendation', {
              id: result.id,
              version: state?.stateVersion,
            })
          "
        >
          确认这桌方案</button
        ><template v-if="state?.session.state === 'closed'"
          ><p>本桌已确认</p>
          <button v-if="host" @click="reopen">重开同一聚餐局</button></template
        >
      </div>
    </article>
    <div v-else-if="resultView && state" class="entry-empty card">
      <AppIcon name="dish" :size="40" />
      <h2>还没开始搭配</h2>
      <RouterLink :to="`/s/${route.params.code}`">返回这一桌</RouterLink>
    </div>
    <div v-if="resultView && result" class="dining-chat">
      <button
        type="button"
        class="chat-launcher"
        :aria-expanded="chatOpen"
        aria-controls="dining-chat"
        @click="chatOpen = !chatOpen"
      >
        <AppIcon name="chat" :size="22" /><span>{{
          working ? "点菜员正在回复…" : "找点菜员聊聊"
        }}</span>
      </button>
      <aside
        v-show="chatOpen"
        id="dining-chat"
        class="dining-chat-panel"
        role="dialog"
        aria-label="点菜员对话"
      >
        <div class="assistant-title">
          <span class="assistant-avatar"
            ><AppIcon name="dish" :size="22"
          /></span>
          <div>
            <strong>点菜员</strong
            ><small>{{
              aiEnabled ? "一起商量，点得更合口味" : "基础搭配 · 可手动调整"
            }}</small>
          </div>
          <button
            type="button"
            class="close-chat"
            aria-label="收起点菜员"
            @click="chatOpen = false"
          >
            ×
          </button>
        </div>
        <div ref="chatScroll" class="chat-scroll">
          <div
            class="chat-history"
            role="log"
            aria-live="polite"
            aria-relevant="additions"
          >
            <p
              v-for="m in state?.messages"
              :key="m.id"
              :class="
                m.role === 'agent' ? 'assistant-message' : 'guest-message'
              "
            >
              <span>{{ m.content }}</span>
            </p>
          </div>
          <div v-if="working" class="assistant-message" role="status">
            正在回复你<span class="typing-dots"><i></i><i></i><i></i></span>
          </div>
          <p v-if="error" class="error" role="alert">{{ error }}</p>
        </div>
        <form
          v-if="aiEnabled && state?.session.state !== 'closed'"
          class="assistant-input"
          @submit.prevent="sendChat"
        >
          <input
            v-model="chatText"
            aria-label="和点菜员说说"
            maxlength="200"
            :disabled="working || editingResult"
            :placeholder="
              editingResult
                ? '先保存修改，再和点菜员商量'
                : '想换哪道？或者再清淡一点…'
            "
          /><button
            type="submit"
            class="primary"
            :disabled="working || editingResult || !chatText.trim()"
          >
            发送
          </button>
        </form>
        <p v-if="!aiEnabled" class="chat-footnote">
          暂未启用AI，可直接在菜品卡片上修改方案。
        </p>
      </aside>
    </div>
    <ModalSheet v-model="invite" title="邀请同行人"
      ><div class="invitation-content">
        <p>扫码加入这一桌</p>
        <img v-if="qr" :src="qr" alt="聚餐局邀请二维码" class="qr" /><strong
          class="invite-code"
          >{{ route.params.code }}</strong
        ><small>也可以在首页输入聚餐码</small>
      </div>
      <div class="invite-copy">
        <input :value="inviteLink" readonly aria-label="邀请链接" /><button
          @click="copyInvite"
        >
          {{ copied ? "已复制" : "复制链接" }}
        </button>
      </div></ModalSheet
    >
    <ModalSheet
      v-model="companion"
      :title="companionId ? '编辑同行人的要求' : '帮同行人填写'"
      ><label class="companion-name"
        >称呼<input
          v-model="companionName"
          maxlength="40"
          placeholder="同行人" /></label
      ><PreferencesForm v-model="companionPrefs" :menu="menu" />
      <div class="modal-actions">
        <button @click="companion = false">取消</button
        ><button class="primary" :disabled="busy" @click="saveCompanion">
          保存同行人要求
        </button>
      </div></ModalSheet
    >
  </section>
</template>
