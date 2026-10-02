import { useSyncExternalStore } from 'react';
import { api, ApiError } from '../api';
import { addDays, dayWithDate, formatShort, relativeDay } from '../lib/dates';
import { effectiveDay, reorderSlots } from '../lib/tasks';
import type { Project, Subtask, Task, TaskInput, TaskPatch } from '../types';

// One small store for the whole app. Every change is applied locally first and
// then confirmed by the API; if the API refuses, the change is rolled back and a
// toast explains what happened.

export type ToastIcon = 'push' | 'check' | 'info' | 'error';

export interface Toast {
  id: number;
  message: string;
  icon: ToastIcon;
  actionLabel?: string;
  onAction?: () => void;
}

export interface StoreState {
  /** "locked" means the server is password protected and we are not signed in. */
  status: 'loading' | 'ready' | 'error' | 'locked';
  loadError: string | null;
  authRequired: boolean;
  tasks: Record<string, Task>;
  projects: Project[];
  /** Done tasks are loaded from this day onwards (open tasks are always all loaded). */
  doneLoadedFrom: string | null;
  pending: number;
  syncError: string | null;
  selectedTaskId: string | null;
  toasts: Toast[];
}

const INITIAL_DONE_WINDOW_DAYS = 42;
const TOAST_MS = 6000;

let state: StoreState = {
  status: 'loading',
  loadError: null,
  authRequired: false,
  tasks: {},
  projects: [],
  doneLoadedFrom: null,
  pending: 0,
  syncError: null,
  selectedTaskId: null,
  toasts: [],
};

const listeners = new Set<() => void>();
// Bumped on every local change, so a slow background refresh never overwrites newer edits.
let localVersion = 0;
let tempCounter = 0;
let toastCounter = 0;

// Tasks and subtasks get a temporary id until the API answers with the real one.
const pendingCreates = new Map<string, Promise<string>>();
const resolvedIds = new Map<string, string>();

function emit() {
  for (const listener of listeners) listener();
}

function update(change: (current: StoreState) => Partial<StoreState>) {
  state = { ...state, ...change(state) };
  emit();
}

export function getState(): StoreState {
  return state;
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** Select a slice of the store. Return stored values, not freshly built objects. */
export function useStore<T>(selector: (current: StoreState) => T): T {
  return useSyncExternalStore(
    subscribe,
    () => selector(state),
    () => selector(state),
  );
}

const currentId = (id: string) => resolvedIds.get(id) ?? id;

async function resolveId(id: string): Promise<string> {
  const known = resolvedIds.get(id);
  if (known) return known;
  return pendingCreates.get(id) ?? id;
}

function messageOf(error: unknown): string {
  if (error instanceof ApiError) return error.message;
  if (error instanceof Error) return error.message;
  return 'Something went wrong';
}

const isUnauthorized = (error: unknown) => error instanceof ApiError && error.status === 401;

/** The session ran out or the password changed: go back to the sign-in screen. */
function lock() {
  update(() => ({ status: 'locked', authRequired: true, tasks: {}, projects: [], selectedTaskId: null, doneLoadedFrom: null, toasts: [] }));
}

async function track<T>(request: Promise<T>): Promise<T> {
  update((s) => ({ pending: s.pending + 1 }));
  try {
    const result = await request;
    update((s) => ({ pending: s.pending - 1, syncError: null }));
    return result;
  } catch (error) {
    update((s) => ({ pending: s.pending - 1, syncError: messageOf(error) }));
    if (isUnauthorized(error)) lock();
    throw error;
  }
}

function putTasks(list: Task[]) {
  if (!list.length) return;
  update((s) => {
    const tasks = { ...s.tasks };
    for (const task of list) tasks[task.id] = task;
    return { tasks };
  });
}

function patchTask(id: string, patch: Partial<Task>) {
  update((s) => {
    const task = s.tasks[id];
    return task ? { tasks: { ...s.tasks, [id]: { ...task, ...patch } } } : {};
  });
}

function removeTask(id: string) {
  update((s) => {
    if (!s.tasks[id]) return {};
    const tasks = { ...s.tasks };
    delete tasks[id];
    return { tasks, selectedTaskId: s.selectedTaskId === id ? null : s.selectedTaskId };
  });
}

function changed() {
  localVersion += 1;
}

function failed(error: unknown, fallback: string) {
  if (isUnauthorized(error)) return; // the sign-in screen explains this one
  const detail = messageOf(error);
  actions.toast(error instanceof ApiError && error.status === 0 ? detail : `${fallback}: ${detail}`, { icon: 'error' });
}

function quoted(title: string) {
  return `“${title.length > 48 ? `${title.slice(0, 47)}…` : title}”`;
}

/** "moved to tomorrow" / "moved to Sat 3 Oct" */
function movedPhrase(day: string, today: string) {
  const relative = relativeDay(day, today);
  return relative === 'Today' || relative === 'Tomorrow' ? `moved to ${relative.toLowerCase()}` : `moved to ${formatShort(day, today)}`;
}

function snapshot(task: Task): Task {
  return { ...task, subtasks: task.subtasks.map((subtask) => ({ ...subtask })) };
}

async function fetchEverything(today: string, doneFrom: string) {
  const [projects, open, done] = await Promise.all([api.listProjects(), api.listOpenTasks(), api.listDoneTasks(doneFrom, today)]);
  const tasks: Record<string, Task> = {};
  for (const task of [...open, ...done]) tasks[task.id] = task;
  return { projects, tasks };
}

export const actions = {
  async load(today: string) {
    update(() => ({ status: 'loading', loadError: null }));
    try {
      const auth = await api.authStatus();
      if (auth.required && !auth.authenticated) {
        update(() => ({ status: 'locked', authRequired: true }));
        return;
      }
      const doneFrom = addDays(today, -INITIAL_DONE_WINDOW_DAYS);
      const { projects, tasks } = await fetchEverything(today, doneFrom);
      update(() => ({ status: 'ready', authRequired: auth.required, projects, tasks, doneLoadedFrom: doneFrom }));
    } catch (error) {
      if (isUnauthorized(error)) lock();
      else update(() => ({ status: 'error', loadError: messageOf(error) }));
    }
  },

  /** Returns an error message, or null once signed in and loaded. */
  async signIn(password: string, today: string): Promise<string | null> {
    try {
      await api.login(password);
    } catch (error) {
      return messageOf(error);
    }
    await actions.load(today);
    return state.status === 'ready' ? null : (state.loadError ?? 'Signed in, but Nextlet could not load your tasks');
  },

  async signOut() {
    try {
      await api.logout();
    } finally {
      lock();
    }
  },

  /** Picks up changes made elsewhere (another tab or device). Quietly skips while edits are in flight. */
  async refresh(today: string) {
    if (state.status !== 'ready' || state.pending > 0) return;
    const version = localVersion;
    try {
      const doneFrom = state.doneLoadedFrom ?? addDays(today, -INITIAL_DONE_WINDOW_DAYS);
      const { projects, tasks } = await fetchEverything(today, doneFrom);
      if (version !== localVersion || state.pending > 0) return;
      // A done task opened from search can be older than the loaded window; keep it.
      const selected = state.selectedTaskId ? state.tasks[state.selectedTaskId] : undefined;
      if (selected?.completedAt && !tasks[selected.id]) tasks[selected.id] = selected;
      update((s) => ({
        projects,
        tasks,
        syncError: null,
        selectedTaskId: s.selectedTaskId && tasks[s.selectedTaskId] ? s.selectedTaskId : null,
      }));
    } catch (error) {
      // Offline or the server is restarting; the next refresh will try again.
      if (isUnauthorized(error)) lock();
    }
  },

  /** Makes sure done tasks are loaded back to `from`, for browsing past weeks and months. */
  async ensureDoneFrom(from: string) {
    const loadedFrom = state.doneLoadedFrom;
    if (!loadedFrom || from >= loadedFrom) return;
    update(() => ({ doneLoadedFrom: from }));
    try {
      putTasks(await api.listDoneTasks(from, addDays(loadedFrom, -1)));
    } catch (error) {
      update(() => ({ doneLoadedFrom: loadedFrom }));
      failed(error, 'Couldn’t load older tasks');
    }
  },

  /** Adds tasks fetched outside the normal lists, such as search results. */
  rememberTasks(list: Task[]) {
    putTasks(list.filter((task) => !state.tasks[task.id]));
  },

  select(id: string | null) {
    update(() => ({ selectedTaskId: id === null ? null : currentId(id) }));
  },

  toast(message: string, options: { icon?: ToastIcon; actionLabel?: string; onAction?: () => void } = {}) {
    const id = ++toastCounter;
    const toast: Toast = { id, message, icon: options.icon ?? 'info', actionLabel: options.actionLabel, onAction: options.onAction };
    update((s) => ({ toasts: [...s.toasts.slice(-2), toast] }));
    window.setTimeout(() => actions.dismissToast(id), TOAST_MS);
    return id;
  },

  dismissToast(id: number) {
    update((s) => (s.toasts.some((toast) => toast.id === id) ? { toasts: s.toasts.filter((toast) => toast.id !== id) } : {}));
  },

  /** Runs the undo of the most recent toast that offers one. Used by ⌘Z. */
  undoLatest(): boolean {
    const toast = [...state.toasts].reverse().find((candidate) => candidate.onAction);
    if (!toast?.onAction) return false;
    toast.onAction();
    actions.dismissToast(toast.id);
    return true;
  },

  async createTask(input: TaskInput, options: { select?: boolean } = {}): Promise<string | null> {
    const tempId = `tmp-${++tempCounter}`;
    const now = new Date().toISOString();
    const nextSort = Math.max(0, ...Object.values(state.tasks).map((task) => task.sortOrder)) + 1;
    const optimistic: Task = {
      id: tempId,
      title: input.title,
      notes: input.notes ?? '',
      projectId: input.projectId ?? null,
      day: input.day ?? null,
      plannedDay: input.plannedDay !== undefined ? input.plannedDay : (input.day ?? null),
      estimateMinutes: input.estimateMinutes ?? null,
      priority: input.priority ?? 0,
      repeat: input.repeat ?? null,
      sortOrder: input.sortOrder ?? nextSort,
      completedAt: null,
      completedFromDay: null,
      postponedAt: null,
      nextOccurrenceId: null,
      createdAt: now,
      updatedAt: now,
      subtasks: (input.subtasks ?? []).map((subtask, index) => ({
        id: `${tempId}-${index}`,
        title: subtask.title,
        done: subtask.done ?? false,
        sortOrder: index + 1,
      })),
    };
    changed();
    putTasks([optimistic]);
    if (options.select) update(() => ({ selectedTaskId: tempId }));

    const creation = track(api.createTask(input)).then((task) => {
      resolvedIds.set(tempId, task.id);
      update((s) => {
        const tasks = { ...s.tasks };
        delete tasks[tempId];
        tasks[task.id] = task;
        return { tasks, selectedTaskId: s.selectedTaskId === tempId ? task.id : s.selectedTaskId };
      });
      return task.id;
    });
    pendingCreates.set(tempId, creation);
    try {
      return await creation;
    } catch (error) {
      removeTask(tempId);
      failed(error, 'Couldn’t add the task');
      return null;
    } finally {
      pendingCreates.delete(tempId);
    }
  },

  async updateTask(id: string, patch: TaskPatch) {
    const key = currentId(id);
    const before = state.tasks[key];
    if (!before) return;
    changed();
    const optimistic: Partial<Task> = { ...patch };
    if (patch.day !== undefined) {
      optimistic.plannedDay = patch.plannedDay !== undefined ? patch.plannedDay : patch.day;
      optimistic.postponedAt = null;
    }
    patchTask(key, optimistic);
    try {
      const task = await track(api.updateTask(await resolveId(key), patch));
      putTasks([task]);
    } catch (error) {
      if (state.tasks[key]) putTasks([before]);
      failed(error, 'Couldn’t save that change');
    }
  },

  /** Schedules a task for a chosen day (drag and drop, the date picker), with undo. */
  rescheduleTask(id: string, day: string | null, today: string) {
    const before = state.tasks[currentId(id)];
    if (!before || before.day === day) return;
    void actions.updateTask(id, { day });
    actions.toast(`${quoted(before.title)} ${day ? movedPhrase(day, today) : 'moved to the Inbox'}`, {
      icon: 'push',
      actionLabel: 'Undo',
      onAction: () => void actions.updateTask(before.id, { day: before.day, plannedDay: before.plannedDay }),
    });
  },

  async deleteTask(id: string) {
    const key = currentId(id);
    const before = state.tasks[key];
    if (!before) return;
    changed();
    removeTask(key);
    try {
      await track(api.deleteTask(await resolveId(key)));
      actions.toast(`Deleted ${quoted(before.title)}`, {
        icon: 'info',
        actionLabel: 'Undo',
        onAction: () => void actions.restoreDeleted(before),
      });
    } catch (error) {
      putTasks([before]);
      failed(error, 'Couldn’t delete the task');
    }
  },

  async restoreDeleted(task: Task) {
    const id = await actions.createTask({
      title: task.title,
      notes: task.notes,
      projectId: task.projectId && state.projects.some((p) => p.id === task.projectId) ? task.projectId : null,
      day: task.completedAt ? (task.completedFromDay ?? null) : task.day,
      plannedDay: task.plannedDay,
      estimateMinutes: task.estimateMinutes,
      priority: task.priority,
      repeat: task.repeat,
      sortOrder: task.sortOrder,
      subtasks: task.subtasks.map((subtask) => ({ title: subtask.title, done: subtask.done })),
    });
    if (id && task.completedAt && task.day) {
      try {
        const { task: completed } = await track(api.completeTask(id, task.day));
        putTasks([completed]);
      } catch (error) {
        failed(error, 'Couldn’t restore the task as done');
      }
    }
  },

  async toggleComplete(id: string, today: string) {
    const key = currentId(id);
    const before = state.tasks[key];
    if (!before) return;
    changed();

    if (before.completedAt) {
      const follower = before.nextOccurrenceId ? state.tasks[before.nextOccurrenceId] : undefined;
      patchTask(key, { completedAt: null, day: before.completedFromDay, completedFromDay: null, nextOccurrenceId: null });
      if (follower && !follower.completedAt) removeTask(follower.id);
      try {
        const { task, removedTaskId } = await track(api.uncompleteTask(await resolveId(key)));
        putTasks([task]);
        if (removedTaskId) removeTask(removedTaskId);
      } catch (error) {
        putTasks(follower ? [before, follower] : [before]);
        failed(error, 'Couldn’t reopen the task');
      }
      return;
    }

    patchTask(key, { completedAt: new Date().toISOString(), completedFromDay: before.day, day: today, postponedAt: null });
    actions.toast(`Done: ${quoted(before.title)}`, {
      icon: 'check',
      actionLabel: 'Undo',
      onAction: () => void actions.toggleComplete(key, today),
    });
    try {
      const { task, nextOccurrence } = await track(api.completeTask(await resolveId(key), today));
      putTasks(nextOccurrence ? [task, nextOccurrence] : [task]);
      if (nextOccurrence?.day) actions.toast(`Repeats: next one is ${dayWithDate(nextOccurrence.day, today)}`, { icon: 'info' });
    } catch (error) {
      putTasks([before]);
      failed(error, 'Couldn’t complete the task');
    }
  },

  /**
   * Moves tasks to other days while remembering where they were planned.
   * `postponed` marks a push forward; bringing a task back clears it.
   */
  async moveTasks(moves: { id: string; day: string }[], options: { postponed: boolean; message?: string; undoable?: boolean }) {
    const befores = moves.map((move) => state.tasks[currentId(move.id)]).filter((task): task is Task => !!task && !task.completedAt);
    if (!befores.length) return;
    changed();
    const now = new Date().toISOString();
    update((s) => {
      const tasks = { ...s.tasks };
      for (const move of moves) {
        const key = currentId(move.id);
        const task = tasks[key];
        if (task && !task.completedAt) tasks[key] = { ...task, day: move.day, postponedAt: options.postponed ? now : null };
      }
      return { tasks };
    });

    if (options.message) {
      actions.toast(options.message, {
        icon: 'push',
        ...(options.undoable === false
          ? {}
          : { actionLabel: 'Undo', onAction: () => void actions.restorePlacement(befores.map(snapshot)) }),
      });
    }

    try {
      const ids = await Promise.all(moves.map((move) => resolveId(move.id)));
      const tasks = await track(
        api.moveTasks(
          moves.map((move, index) => ({ id: ids[index]!, day: move.day })),
          options.postponed,
        ),
      );
      putTasks(tasks);
    } catch (error) {
      putTasks(befores);
      failed(error, 'Couldn’t move that');
    }
  },

  /** Puts tasks back on the days they were on before a move. */
  async restorePlacement(befores: Task[]) {
    const withDay = befores.filter((task) => task.day !== null);
    const pushed = withDay.filter((task) => task.postponedAt !== null);
    const placed = withDay.filter((task) => task.postponedAt === null);
    if (pushed.length) await actions.moveTasks(pushed.map((task) => ({ id: task.id, day: task.day! })), { postponed: true });
    if (placed.length) await actions.moveTasks(placed.map((task) => ({ id: task.id, day: task.day! })), { postponed: false });
    for (const task of befores.filter((candidate) => candidate.day === null)) {
      await actions.updateTask(task.id, { day: null, plannedDay: task.plannedDay });
    }
  },

  /** "Move to tomorrow": each task goes to the day after the one it shows up on. */
  pushToNextDay(ids: string[], today: string) {
    const tasks = ids.map((id) => state.tasks[currentId(id)]).filter((task): task is Task => !!task && !task.completedAt);
    if (!tasks.length) return;
    const moves = tasks.map((task) => ({ id: task.id, day: addDays(effectiveDay(task, today) ?? today, 1) }));
    const first = moves[0]!;
    const sameDay = moves.every((move) => move.day === first.day);
    const message =
      tasks.length === 1
        ? `${quoted(tasks[0]!.title)} ${movedPhrase(first.day, today)}`
        : `${tasks.length} tasks ${sameDay ? movedPhrase(first.day, today) : 'moved to their next day'}`;
    void actions.moveTasks(moves, { postponed: true, message });
  },

  bringBackToToday(id: string, today: string) {
    const task = state.tasks[currentId(id)];
    if (!task) return;
    void actions.moveTasks([{ id: task.id, day: today }], { postponed: false, message: `${quoted(task.title)} is back on today` });
  },

  async reorder(ids: string[]) {
    const tasks = Object.values(state.tasks);
    const local = reorderSlots(tasks, ids.map(currentId));
    const befores = Object.keys(local).map((id) => state.tasks[id]!);
    changed();
    update((s) => {
      const next = { ...s.tasks };
      for (const [id, sortOrder] of Object.entries(local)) next[id] = { ...next[id]!, sortOrder };
      return { tasks: next };
    });
    try {
      const realIds = await Promise.all(ids.map(resolveId));
      const { sortOrders } = await track(api.reorderTasks(realIds));
      update((s) => {
        const next = { ...s.tasks };
        for (const [id, sortOrder] of Object.entries(sortOrders)) if (next[id]) next[id] = { ...next[id]!, sortOrder };
        return { tasks: next };
      });
    } catch (error) {
      putTasks(befores);
      failed(error, 'Couldn’t reorder');
    }
  },

  async addSubtask(taskId: string, title: string) {
    const key = currentId(taskId);
    const task = state.tasks[key];
    if (!task) return;
    const tempId = `tmp-sub-${++tempCounter}`;
    const sortOrder = Math.max(0, ...task.subtasks.map((subtask) => subtask.sortOrder)) + 1;
    changed();
    patchTask(key, { subtasks: [...task.subtasks, { id: tempId, title, done: false, sortOrder }] });
    const creation = (async () => {
      const subtask = await track(api.addSubtask(await resolveId(key), title));
      resolvedIds.set(tempId, subtask.id);
      const latest = state.tasks[currentId(key)];
      if (latest) patchTask(latest.id, { subtasks: latest.subtasks.map((item) => (item.id === tempId ? subtask : item)) });
      return subtask.id;
    })();
    pendingCreates.set(tempId, creation);
    try {
      await creation;
    } catch (error) {
      const latest = state.tasks[currentId(key)];
      if (latest) patchTask(latest.id, { subtasks: latest.subtasks.filter((item) => item.id !== tempId) });
      failed(error, 'Couldn’t add the subtask');
    } finally {
      pendingCreates.delete(tempId);
    }
  },

  async updateSubtask(taskId: string, subtaskId: string, patch: Partial<Pick<Subtask, 'title' | 'done'>>) {
    const key = currentId(taskId);
    const task = state.tasks[key];
    const subId = currentId(subtaskId);
    const before = task?.subtasks.find((subtask) => subtask.id === subId);
    if (!task || !before) return;
    changed();
    patchTask(key, { subtasks: task.subtasks.map((subtask) => (subtask.id === subId ? { ...subtask, ...patch } : subtask)) });
    try {
      const saved = await track(api.updateSubtask(await resolveId(subId), patch));
      const latest = state.tasks[currentId(key)];
      if (latest) patchTask(latest.id, { subtasks: latest.subtasks.map((subtask) => (subtask.id === subId ? saved : subtask)) });
    } catch (error) {
      const latest = state.tasks[currentId(key)];
      if (latest) patchTask(latest.id, { subtasks: latest.subtasks.map((subtask) => (subtask.id === subId ? before : subtask)) });
      failed(error, 'Couldn’t update the subtask');
    }
  },

  async deleteSubtask(taskId: string, subtaskId: string) {
    const key = currentId(taskId);
    const task = state.tasks[key];
    const subId = currentId(subtaskId);
    if (!task) return;
    changed();
    const before = task.subtasks;
    patchTask(key, { subtasks: before.filter((subtask) => subtask.id !== subId) });
    try {
      await track(api.deleteSubtask(await resolveId(subId)));
    } catch (error) {
      const latest = state.tasks[currentId(key)];
      if (latest) patchTask(latest.id, { subtasks: before });
      failed(error, 'Couldn’t delete the subtask');
    }
  },

  async createProject(name: string): Promise<Project | null> {
    try {
      const project = await track(api.createProject({ name }));
      changed();
      update((s) => ({ projects: [...s.projects, project] }));
      return project;
    } catch (error) {
      failed(error, 'Couldn’t create the project');
      return null;
    }
  },

  async updateProject(id: string, patch: { name?: string; color?: string }) {
    const before = state.projects.find((project) => project.id === id);
    if (!before) return;
    changed();
    update((s) => ({ projects: s.projects.map((project) => (project.id === id ? { ...project, ...patch } : project)) }));
    try {
      const saved = await track(api.updateProject(id, patch));
      update((s) => ({ projects: s.projects.map((project) => (project.id === id ? saved : project)) }));
    } catch (error) {
      update((s) => ({ projects: s.projects.map((project) => (project.id === id ? before : project)) }));
      failed(error, 'Couldn’t update the project');
    }
  },

  async deleteProject(id: string): Promise<boolean> {
    const before = state.projects;
    const affected = Object.values(state.tasks).filter((task) => task.projectId === id);
    changed();
    update((s) => {
      const tasks = { ...s.tasks };
      for (const task of affected) tasks[task.id] = { ...task, projectId: null };
      return { projects: s.projects.filter((project) => project.id !== id), tasks };
    });
    try {
      await track(api.deleteProject(id));
      return true;
    } catch (error) {
      update(() => ({ projects: before }));
      putTasks(affected);
      failed(error, 'Couldn’t delete the project');
      return false;
    }
  },
};
