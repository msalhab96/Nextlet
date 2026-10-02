import type { Task } from '../types';
import { addDays, localDay } from './dates';

export const isOpen = (task: Task) => task.completedAt === null;

/** The day a task shows up on. Unfinished tasks from earlier days roll forward to today. */
export function effectiveDay(task: Task, today: string): string | null {
  if (!task.day) return null;
  return isOpen(task) && task.day < today ? today : task.day;
}

/** The earlier day an open task was planned for, when it was carried over or pushed. */
export function carriedFrom(task: Task, today: string): string | null {
  if (!isOpen(task) || !task.day) return null;
  const shown = effectiveDay(task, today)!;
  const origin = task.plannedDay && task.plannedDay < task.day ? task.plannedDay : task.day;
  return origin < shown ? origin : null;
}

export function bySortOrder(a: Task, b: Task): number {
  return a.sortOrder - b.sortOrder || a.createdAt.localeCompare(b.createdAt);
}

function byCompletion(a: Task, b: Task): number {
  return (a.completedAt ?? '').localeCompare(b.completedAt ?? '');
}

/** Open tasks that show up on `day`, in the user's order. */
export function openOn(tasks: Task[], day: string, today: string): Task[] {
  return tasks.filter((task) => isOpen(task) && effectiveDay(task, today) === day).sort(bySortOrder);
}

/** Tasks finished on `day`, oldest first. */
export function doneOn(tasks: Task[], day: string): Task[] {
  return tasks.filter((task) => !isOpen(task) && task.day === day).sort(byCompletion);
}

export function inboxTasks(tasks: Task[]): Task[] {
  return tasks.filter((task) => isOpen(task) && !task.day).sort(bySortOrder);
}

/** Tasks pushed from today to tomorrow, so Today can offer to bring them back. */
export function pushedToTomorrow(tasks: Task[], today: string): Task[] {
  const tomorrow = addDays(today, 1);
  return tasks
    .filter((task) => isOpen(task) && task.day === tomorrow && task.postponedAt && localDay(new Date(task.postponedAt)) === today)
    .sort(bySortOrder);
}

export interface TaskCounts {
  inbox: number;
  today: number;
  upcoming: number;
  byProject: Record<string, number>;
}

export function countTasks(tasks: Task[], today: string): TaskCounts {
  const counts: TaskCounts = { inbox: 0, today: 0, upcoming: 0, byProject: {} };
  for (const task of tasks) {
    if (!isOpen(task)) continue;
    const day = effectiveDay(task, today);
    if (day === null) counts.inbox += 1;
    else if (day === today) counts.today += 1;
    else counts.upcoming += 1;
    if (task.projectId) counts.byProject[task.projectId] = (counts.byProject[task.projectId] ?? 0) + 1;
  }
  return counts;
}

/** The order to keep tasks in after moving `id` to position `index` among `ids`. */
export function moveInOrder(ids: string[], id: string, index: number): string[] {
  const without = ids.filter((other) => other !== id);
  const target = Math.max(0, Math.min(index, without.length));
  return [...without.slice(0, target), id, ...without.slice(target)];
}

/** Assigns `ordered` the sort positions those tasks already hold, mirroring the API. */
export function reorderSlots(tasks: Task[], ordered: string[]): Record<string, number> {
  const known = ordered.map((id) => tasks.find((task) => task.id === id)).filter((task): task is Task => !!task);
  const slots = known.map((task) => task.sortOrder).sort((a, b) => a - b);
  for (let i = 1; i < slots.length; i++) {
    if (slots[i]! <= slots[i - 1]!) slots[i] = slots[i - 1]! + 1e-6;
  }
  return Object.fromEntries(known.map((task, index) => [task.id, slots[index]!]));
}
