import type { Project, Subtask, Task, TaskInput, TaskPatch } from './types';

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`/api${path}`, {
      method,
      headers: body === undefined ? undefined : { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, 'network', 'Can’t reach the Nextlet server');
  }
  if (response.status === 204) return undefined as T;
  const data = (await response.json().catch(() => null)) as { error?: string; message?: string } | null;
  if (!response.ok) {
    throw new ApiError(response.status, data?.error ?? 'error', data?.message ?? `Request failed (${response.status})`);
  }
  return data as T;
}

export const api = {
  authStatus: () => request<{ required: boolean; authenticated: boolean }>('GET', '/auth/status'),
  login: (password: string) => request<{ ok: boolean }>('POST', '/auth/login', { password }),
  logout: () => request<void>('POST', '/auth/logout'),

  listProjects: () => request<Project[]>('GET', '/projects'),
  createProject: (body: { name: string; color?: string }) => request<Project>('POST', '/projects', body),
  updateProject: (id: string, body: { name?: string; color?: string }) => request<Project>('PATCH', `/projects/${id}`, body),
  deleteProject: (id: string) => request<void>('DELETE', `/projects/${id}`),

  listOpenTasks: () => request<Task[]>('GET', '/tasks?status=open'),
  listDoneTasks: (from: string, to: string) => request<Task[]>('GET', `/tasks?status=done&from=${from}&to=${to}`),
  searchTasks: (query: string) => request<Task[]>('GET', `/tasks?q=${encodeURIComponent(query)}`),
  createTask: (body: TaskInput) => request<Task>('POST', '/tasks', body),
  updateTask: (id: string, body: TaskPatch) => request<Task>('PATCH', `/tasks/${id}`, body),
  deleteTask: (id: string) => request<void>('DELETE', `/tasks/${id}`),
  completeTask: (id: string, today: string) =>
    request<{ task: Task; nextOccurrence: Task | null }>('POST', `/tasks/${id}/complete`, { today }),
  uncompleteTask: (id: string) => request<{ task: Task; removedTaskId: string | null }>('POST', `/tasks/${id}/uncomplete`),
  moveTasks: (moves: { id: string; day: string }[], postponed: boolean) =>
    request<Task[]>('POST', '/tasks/move', { moves, postponed }),
  reorderTasks: (ids: string[]) => request<{ sortOrders: Record<string, number> }>('POST', '/tasks/reorder', { ids }),

  addSubtask: (taskId: string, title: string) => request<Subtask>('POST', `/tasks/${taskId}/subtasks`, { title }),
  updateSubtask: (id: string, body: { title?: string; done?: boolean }) => request<Subtask>('PATCH', `/subtasks/${id}`, body),
  deleteSubtask: (id: string) => request<void>('DELETE', `/subtasks/${id}`),
};
