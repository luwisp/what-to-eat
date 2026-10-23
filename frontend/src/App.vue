<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import AppIcon from "./shared/AppIcon.vue";
import logo from "./assets/juxiaobao-logo.png";
const route = useRoute();
const accountLink = computed(() =>
  route.path === "/" || route.path === "/account"
    ? "/account"
    : `/account?returnTo=${encodeURIComponent(route.fullPath)}`,
);
const showTabs = computed(
  () => route.path === "/" || route.path === "/account",
);
</script>
<template>
  <div class="consumer-app" :class="{ 'has-tabs': showTabs }">
    <header class="app-header">
      <RouterLink to="/" class="brand">
        <img
          :src="logo"
          class="brand-logo"
          alt="聚小宝"
          width="144"
          height="48"
        />
      </RouterLink>
      <RouterLink v-if="!showTabs" :to="accountLink" class="header-account"
        ><AppIcon name="user" :size="19" />我的</RouterLink
      >
    </header>
    <main><RouterView /></main>
    <nav v-if="showTabs" class="bottom-tabs" aria-label="主导航">
      <RouterLink to="/" exact-active-class="tab-active"
        ><AppIcon name="home" />首页</RouterLink
      >
      <RouterLink to="/account" active-class="tab-active"
        ><AppIcon name="user" />我的</RouterLink
      >
    </nav>
  </div>
</template>
