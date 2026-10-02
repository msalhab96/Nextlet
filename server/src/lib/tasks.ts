import type { Queryable } from '../db.js';
import type { RepeatRule } from './repeat.js';

export interface SubtaskDto {
  id: string;
  title: string;
  done: boolean;
  sortOrder: number;
}

export interface TaskDto {
  id: string;
  title: string;
  notes: string;
  projectId: string | null;
  day: string | null;
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
  subtasks: SubtaskDto[];
}

export interface TaskRow {
  id: string;
  title: string;
  notes: string;
  project_id: string | null;
  day: string | null;
  planned_day: string | null;
  estimate_minutes: number | null;
  priority: number;
  repeat: RepeatRule | null;
  sort_order: number;
  completed_at: Date | null;
  completed_from_day: string | null;
  postponed_at: Date | null;
  next_occurrence_id: string | null;
  created_at: Date;
  updated_at: Date;
}

const SELECT_TASKS = `
  SELECT t.*,
    COALESCE(
      (SELECT json_agg(
          json_build_object('id', s.id, 'title', s.title, 'done', s.done, 'sortOrder', s.sort_order)
          ORDER BY s.sort_order, s.created_at)
        FROM subtasks s
        WHERE s.task_id = t.id),
      '[]'::json
    ) AS subtasks
  FROM tasks t`;

export function toTaskDto(row: TaskRow & { subtasks: SubtaskDto[] }): TaskDto {
  return {
    id: row.id,
    title: row.title,
    notes: row.notes,
    projectId: row.project_id,
    day: row.day,
    plannedDay: row.planned_day,
    estimateMinutes: row.estimate_minutes,
    priority: row.priority,
    repeat: row.repeat,
    sortOrder: row.sort_order,
    completedAt: row.completed_at?.toISOString() ?? null,
    completedFromDay: row.completed_from_day,
    postponedAt: row.postponed_at?.toISOString() ?? null,
    nextOccurrenceId: row.next_occurrence_id,
    createdAt: row.created_at.toISOString(),
    updatedAt: row.updated_at.toISOString(),
    subtasks: row.subtasks,
  };
}

export async function findTasks(
  db: Queryable,
  where: string,
  params: unknown[] = [],
  tail = 'ORDER BY t.sort_order, t.created_at',
): Promise<TaskDto[]> {
  const { rows } = await db.query<TaskRow & { subtasks: SubtaskDto[] }>(`${SELECT_TASKS} WHERE ${where} ${tail}`, params);
  return rows.map(toTaskDto);
}

export async function findTask(db: Queryable, id: string): Promise<TaskDto | null> {
  const [task] = await findTasks(db, 't.id = $1', [id]);
  return task ?? null;
}
