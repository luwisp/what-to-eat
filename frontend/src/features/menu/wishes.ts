import type { Preferences } from "../../shared/contracts";

export function dishWishQuantity(prefs: Preferences, id: string): number {
  if (!prefs.wantedDishIds.includes(id)) return 0;
  return prefs.wantedExtras.find((wish) => wish.dishId === id)?.quantity ?? 1;
}

export function changeDishWish(
  prefs: Preferences,
  id: string,
  quantity: number,
): Preferences {
  if (!Number.isInteger(quantity) || quantity < 0 || quantity > 100)
    return prefs;
  const ids = prefs.wantedDishIds.filter((value) => value !== id);
  const extras = prefs.wantedExtras.filter((wish) => wish.dishId !== id);
  return {
    ...prefs,
    wantedDishIds: quantity ? [...ids, id] : ids,
    wantedExtras: quantity ? [...extras, { dishId: id, quantity }] : extras,
  };
}
