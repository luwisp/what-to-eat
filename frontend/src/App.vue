<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import AppIcon from "./shared/AppIcon.vue";
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
      <RouterLink to="/" class="brand"
        ><span class="brand-symbol"><AppIcon name="dish" :size="22" /></span
        >聚小宝</RouterLink
      >
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
