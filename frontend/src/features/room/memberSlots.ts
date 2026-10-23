import type { ParticipantView } from "../../shared/contracts";

type NamedMember = Pick<ParticipantView, "nickname">;

function companionName(index: number): string {
  let letters = "";
  for (let n = index + 1; n > 0; n = Math.floor((n - 1) / 26))
    letters = String.fromCharCode(65 + ((n - 1) % 26)) + letters;
  return `同行人 ${letters}`;
}

export function nextCompanionName(members: NamedMember[]): string {
  const used = new Set(members.map((m) => m.nickname.replace(/\s/g, "")));
  for (let index = 0; ; index++) {
    const name = companionName(index);
    if (!used.has(name.replace(/\s/g, ""))) return name;
  }
}

// Empty seats are display-only until someone joins or confirms a companion's form.
export function memberPlaceholders(people: number, members: NamedMember[]) {
  const names = [...members];
  const slots: { nickname: string }[] = [];
  for (let i = members.length; i < people; i++) {
    const slot = { nickname: nextCompanionName(names) };
    names.push(slot);
    slots.push(slot);
  }
  return slots;
}

export function mealMemberName(
  memberId: string,
  members: Pick<ParticipantView, "id" | "nickname">[],
  placeholders: NamedMember[],
): string {
  const member = members.find((m) => m.id === memberId);
  if (member) return member.nickname;
  const pending = /^pending:(\d+)$/.exec(memberId);
  return (pending && placeholders[Number(pending[1])]?.nickname) || "同行人";
}
