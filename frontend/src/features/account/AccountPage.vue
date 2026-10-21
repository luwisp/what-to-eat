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
  nickname = ref(""),
  savingProfile = ref(false),
  registering = ref(false),
  error = ref(""),
  notice = ref(""),
  prefs = ref(emptyPreferences());
async function refresh() {
  account.value = await loadAccount();
  if (account.value) {
    nickname.value = account.value.nickname ?? "";
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
  notice.value = "";
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
  error.value = "";
  notice.value = "";
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
async function saveProfile() {
  error.value = "";
  notice.value = "";
  savingProfile.value = true;
  try {
    account.value = await api<AccountView>("/api/user/profile", "PATCH", {
      nickname: nickname.value,
    });
    nickname.value = account.value.nickname ?? "";
    notice.value = "用户名已保存";
  } catch (e) {
    error.value = (e as Error).message;
  } finally {
    savingProfile.value = false;
  }
}
async function logout() {
  error.value = "";
  notice.value = "";
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
  <section class="narrow account-page">
    <button @click="router.push(safeReturnTo(route.query.returnTo))">
      ← 返回原页面
    </button>
    <h1>我的账号与默认设置</h1>
    <p class="hint">登录可复用常用要求，进入餐馆和聚餐局无需登录。</p>
    <p v-if="error" class="error" role="alert">{{ error }}</p>
    <p v-if="notice" class="notice" role="status">{{ notice }}</p>
    <form v-if="!account" class="card" @submit.prevent="submit">
      <h2>{{ registering ? "注册" : "登录" }}</h2>
      <p v-if="registering" class="hint">
        账号不能含空格；密码至少8字节，建议使用8位以上英文或数字。
      </p>
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
          :placeholder="registering ? '建议至少8位英文或数字' : '请输入密码'"
          required /></label
      ><button class="primary">{{ registering ? "注册账号" : "登录" }}</button
      ><button type="button" @click="registering = !registering">
        {{ registering ? "已有账号，去登录" : "还没有账号，去注册" }}
      </button>
      <a class="merchant-login-link" href="/admin/"
        >我是商家，进入餐馆工作台 →</a
      >
    </form>
    <template v-else>
      <section class="card profile-card">
        <div class="profile-summary">
          <span class="profile-avatar">{{
            (account.nickname || account.login).slice(0, 1)
          }}</span>
          <div>
            <h2>{{ account.nickname || account.login }}</h2>
            <p>登录账号：{{ account.login }}</p>
          </div>
        </div>
        <form class="profile-editor" @submit.prevent="saveProfile">
          <label
            >用户名<input
              v-model="nickname"
              maxlength="40"
              placeholder="设置大家看到的名字" /></label
          ><button :disabled="savingProfile">
            {{ savingProfile ? "正在保存…" : "保存用户名" }}
          </button>
        </form>
      </section>
      <section class="card defaults-card">
        <h2>我的饮食偏好</h2>
        <PreferencesForm v-model="prefs" defaults-only /><button
          class="primary save-defaults"
          @click="save"
        >
          保存为我的默认设置
        </button>
      </section>
      <div class="account-signout">
        <button @click="logout">退出账号</button>
      </div>
    </template>
  </section>
</template>
