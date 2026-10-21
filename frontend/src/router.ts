import { createRouter, createWebHistory } from "vue-router";
import HomePage from "./features/entry/HomePage.vue";
import RestaurantPage from "./features/entry/RestaurantPage.vue";
import MenuPage from "./features/menu/MenuPage.vue";
import RoomPage from "./features/room/RoomPage.vue";
import AccountPage from "./features/account/AccountPage.vue";
export const router = createRouter({
  history: createWebHistory(),
  scrollBehavior(_to, _from, saved) {
    return saved ?? { top: 0 };
  },
  routes: [
    { path: "/", component: HomePage },
    { path: "/r/:code", component: RestaurantPage },
    { path: "/r/:code/menu", component: MenuPage },
    { path: "/s/:code", component: RoomPage },
    { path: "/s/:code/result", component: RoomPage },
    { path: "/s/:code/preferences", component: RoomPage },
    { path: "/account", component: AccountPage },
    { path: "/:pathMatch(.*)*", component: HomePage },
  ],
});
