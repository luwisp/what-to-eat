<script setup lang="ts">
import { ref, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import type { AccountView, UserDefaultSettings } from "../../shared/contracts";
import { api, loadAccount, saveDefaults } from "../../shared/api";
import { applyDefaults, emptyPreferences } from "../menu/drafts";
import { safeReturnTo } from "../entry/entry";
import PreferencesForm from "../../shared/PreferencesForm.vue";
const route = useRoute(),
  router = useRouter(),
  account = ref<AccountView | null>(null),
  login = ref(""),
  password = ref(""),
  registering = ref(false),
  error = ref(""),
  notice = ref(""),
  prefs = ref(emptyPreferences());
async function refresh() {
  account.value = await loadAccount();
  if (account.value) {
    try {
      prefs.value = applyDefaults(
        await api<UserDefaultSettings>("/api/user/default-settings"),
        null,
      );
    } catch {
      error.value = "默认设置暂未读取，可稍后重试";
    }
  }
}
onMounted(() =>
  refresh().catch((e) => {
    error.value = (e as Error).message;
  }),
);
async function submit() {
  error.value = "";
  try {
    if (registering.value) {
      await api("/api/user/register", "POST", {
        login: login.value,
        password: password.value,
      });
      registering.value = false;
      notice.value = "注册成功，请登录";
      password.value = "";
      return;
    }
    await api("/api/user/login", "POST", {
      login: login.value,
      password: password.value,
    });
    password.value = "";
    await refresh();
  } catch (e) {
    error.value = (e as Error).message;
  }
}
async function save() {
  try {
    await saveDefaults({
      ...prefs.value,
      userId: account.value!.id,
      updatedAt: 0,
    });
    notice.value = "默认设置已保存；现有聚餐局不会被自动修改";
  } catch (e) {
    error.value = (e as Error).message;
  }
}
async function logout() {
  try {
    await api("/api/user/logout", "POST");
    account.value = null;
    notice.value = "已退出账号，本局访客身份保留";
  } catch (e) {
    error.value = (e as Error).message;
  }
}
</script>
<template>
  <section class="narrow">
    <button @click="router.push(safeReturnTo(route.query.returnTo))">
      ← 返回原页面
    </button>
    <h1>我的账号与默认设置</h1>
    <p class="hint">登录可复用常用要求，进入餐馆和聚餐局无需登录。</p>
    <p v-if="error" class="error" role="alert">{{ error }}</p>
    <p v-if="notice" class="notice" role="status">{{ notice }}</p>
    <form v-if="!account" class="card" @submit.prevent="submit">
      <h2>{{ registering ? "注册" : "登录" }}</h2>
      <label
        >账号<input
          v-model="login"
          autocomplete="username"
          required
          maxlength="128" /></label
      ><label
        >密码<input
          v-model="password"
          type="password"
          :autocomplete="registering ? 'new-password' : 'current-password'"
          required /></label
      ><button class="primary">{{ registering ? "注册账号" : "登录" }}</button
      ><button type="button" @click="registering = !registering">
        {{ registering ? "已有账号，去登录" : "还没有账号，去注册" }}
      </button>
    </form>
    <div v-else class="card">
      <div class="row between">
        <h2>{{ account.nickname || account.login }}</h2>
        <button @click="logout">退出账号</button>
      </div>
      <PreferencesForm v-model="prefs" defaults-only /><button
        class="primary"
        @click="save"
      >
        保存为我的默认设置
      </button>
    </div>
  </section>
</template>
