export type RepeatRule =
  | { type: 'daily' }
  | { type: 'weekdays' }
  | { type: 'weekly'; days: number[] }
  | { type: 'interval'; every: number }
  | { type: 'monthly' };

export interface Subtask {
  id: string;
  title: string;
  done: boolean;
  sortOrder: number;
}

export interface Task {
  id: string;
  title: string;
  notes: string;
  projectId: string | null;
  /** The day the task is planned for (YYYY-MM-DD). Null means it is in the Inbox. */
  day: string | null;
  /** The day it was last deliberately scheduled for; pushing a task leaves this alone. */
  plannedDay: string | null;
  estimateMinutes: number | null;
  priority: number;
  repeat: RepeatRule | null;
  sortOrder: number;
  completedAt: string | null;
  completedFromDay: string | null;
  postponedAt: string | null;
  nextOccurrenceId: string | null;
  createdAt: string;
  updatedAt: string;
  subtasks: Subtask[];
}

export interface Project {
  id: string;
  name: string;
  color: string;
  sortOrder: number;
  createdAt: string;
}

export interface TaskInput {
  title: string;
  notes?: string;
  projectId?: string | null;
  day?: string | null;
  plannedDay?: string | null;
  estimateMinutes?: number | null;
  priority?: number;
  repeat?: RepeatRule | null;
  sortOrder?: number;
  subtasks?: { title: string; done?: boolean }[];
}

export type TaskPatch = Partial<
  Pick<Task, 'title' | 'notes' | 'projectId' | 'day' | 'plannedDay' | 'estimateMinutes' | 'priority' | 'repeat' | 'sortOrder'>
>;
