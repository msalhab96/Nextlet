import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { Database, Queryable } from '../db.js';
import { badRequest, notFound } from '../http.js';
import { addDays, isValidDay, laterDay } from '../lib/dates.js';
import { nextOccurrence, repeatRuleSchema, type RepeatRule } from '../lib/repeat.js';
import { MAX_TAG_LENGTH, MAX_TAGS, normalizeTag, normalizeTags, sameTag } from '../lib/tags.js';
import { findTask, findTasks } from '../lib/tasks.js';

const daySchema = z.string().refine(isValidDay, 'Expected a calendar date as YYYY-MM-DD');
const idParams = z.object({ id: z.uuid() });

const titleSchema = z.string().trim().min(1, 'Give the task a title').max(500);
const notesSchema = z.string().max(20_000);
const estimateSchema = z.number().int().min(1).max(1440).nullable();
const prioritySchema = z.number().int().min(0).max(3);
const subtaskInput = z.strictObject({ title: titleSchema, done: z.boolean().optional() });
const tagSchema = z
  .string()
  .transform(normalizeTag)
  .pipe(z.string().min(1, 'Tags can’t be empty').max(MAX_TAG_LENGTH, `Keep tags under ${MAX_TAG_LENGTH} characters`));
const tagsSchema = z
  .array(tagSchema)
  .transform(normalizeTags)
  .pipe(z.array(z.string()).max(MAX_TAGS, `A task can have up to ${MAX_TAGS} tags`));

const createTaskBody = z.strictObject({
  title: titleSchema,
  notes: notesSchema.optional(),
  projectId: z.uuid().nullable().optional(),
  day: daySchema.nullable().optional(),
  plannedDay: daySchema.nullable().optional(),
  estimateMinutes: estimateSchema.optional(),
  priority: prioritySchema.optional(),
  repeat: repeatRuleSchema.nullable().optional(),
  tags: tagsSchema.optional(),
  sortOrder: z.number().optional(),
  subtasks: z.array(subtaskInput).max(100).optional(),
});

const updateTaskBody = z
  .strictObject({
    title: titleSchema.optional(),
    notes: notesSchema.optional(),
    projectId: z.uuid().nullable().optional(),
    day: daySchema.nullable().optional(),
    plannedDay: daySchema.nullable().optional(),
    estimateMinutes: estimateSchema.optional(),
    priority: prioritySchema.optional(),
    repeat: repeatRuleSchema.nullable().optional(),
    tags: tagsSchema.optional(),
    sortOrder: z.number().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, 'Nothing to update');

const tagParams = z.object({ tag: tagSchema });
const renameTagBody = z.strictObject({ name: tagSchema });

const listQuery = z.object({
  status: z.enum(['open', 'done']).default('open'),
  from: daySchema.optional(),
  to: daySchema.optional(),
  q: z.string().trim().min(1).max(200).optional(),
});

const MAX_DONE_RANGE_DAYS = 1100;

const completeBody = z.strictObject({ today: daySchema });

const moveBody = z.strictObject({
  moves: z.array(z.strictObject({ id: z.uuid(), day: daySchema })).min(1).max(500),
  // true when the user pushed the task forward ("Move to tomorrow"), false when
  // they brought it back. Either way planned_day stays as it was.
  postponed: z.boolean(),
});

const reorderBody = z.strictObject({ ids: z.array(z.uuid()).min(1).max(1000) });

const subtaskCreateBody = z.strictObject({ title: titleSchema });
const subtaskUpdateBody = z
  .strictObject({ title: titleSchema.optional(), done: z.boolean().optional() })
  .refine((body) => Object.keys(body).length > 0, 'Nothing to update');

interface SubtaskRow {
  id: string;
  title: string;
  done: boolean;
  sort_order: number;
}

const toSubtaskDto = (row: SubtaskRow) => ({ id: row.id, title: row.title, done: row.done, sortOrder: row.sort_order });

const repeatParam = (rule: RepeatRule | null | undefined) => (rule ? JSON.stringify(rule) : null);

async function insertSubtasks(tx: Queryable, taskId: string, subtasks: { title: string; done?: boolean }[]) {
  for (const [index, subtask] of subtasks.entries()) {
    await tx.query('INSERT INTO subtasks (task_id, title, done, sort_order) VALUES ($1, $2, $3, $4)', [
      taskId,
      subtask.title,
      subtask.done ?? false,
      index + 1,
    ]);
  }
}

/** Changes the tags of every task that has `tag`, finished ones included. Returns how many changed. */
async function retag(db: Database, tag: string, change: (tags: string[]) => string[]): Promise<number> {
  return db.transaction(async (tx) => {
    const { rows } = await tx.query<{ id: string; tags: string[] }>(
      'SELECT id, tags FROM tasks WHERE EXISTS (SELECT 1 FROM unnest(tags) AS tag WHERE lower(tag) = lower($1)) FOR UPDATE',
      [tag],
    );
    for (const row of rows) {
      await tx.query('UPDATE tasks SET tags = $2::text[], updated_at = now() WHERE id = $1', [row.id, normalizeTags(change(row.tags))]);
    }
    return rows.length;
  });
}

export function registerTaskRoutes(app: FastifyInstance, db: Database) {
  // Renaming or removing a tag applies to every task that has it.
  app.patch('/tags/:tag', async (request) => {
    const { tag } = tagParams.parse(request.params);
    const { name } = renameTagBody.parse(request.body);
    const tasks = await retag(db, tag, (tags) => tags.map((existing) => (sameTag(existing, tag) ? name : existing)));
    return { name, tasks };
  });

  app.delete('/tags/:tag', async (request) => {
    const { tag } = tagParams.parse(request.params);
    const tasks = await retag(db, tag, (tags) => tags.filter((existing) => !sameTag(existing, tag)));
    return { tasks };
  });

  app.get('/tasks', async (request) => {
    const query = listQuery.parse(request.query);

    if (query.q) {
      const order = 'ORDER BY (t.completed_at IS NOT NULL), t.updated_at DESC LIMIT 30';
      const tag = query.q.startsWith('@') ? normalizeTag(query.q) : '';
      if (tag) {
        return findTasks(db, 'EXISTS (SELECT 1 FROM unnest(t.tags) AS tag WHERE lower(tag) = lower($1))', [tag], order);
      }
      const pattern = `%${query.q.replace(/[\\%_]/g, (char) => `\\${char}`)}%`;
      return findTasks(db, "(t.title ILIKE $1 OR t.notes ILIKE $1 OR array_to_string(t.tags, ' ') ILIKE $1)", [pattern], order);
    }

    if (query.status === 'open') {
      return findTasks(db, 't.completed_at IS NULL');
    }

    if (!query.from || !query.to) throw badRequest('from and to are required when listing done tasks');
    if (query.from > query.to) throw badRequest('from must not be after to');
    if (addDays(query.from, MAX_DONE_RANGE_DAYS) < query.to) throw badRequest(`Ask for at most ${MAX_DONE_RANGE_DAYS} days at a time`);
    return findTasks(
      db,
      't.completed_at IS NOT NULL AND t.day BETWEEN $1 AND $2',
      [query.from, query.to],
      'ORDER BY t.day, t.completed_at',
    );
  });

  app.post('/tasks', async (request, reply) => {
    const body = createTaskBody.parse(request.body);
    const task = await db.transaction(async (tx) => {
      const day = body.day ?? null;
      const { rows } = await tx.query<{ id: string }>(
        `INSERT INTO tasks (title, notes, project_id, day, planned_day, estimate_minutes, priority, repeat, sort_order, tags)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb,
                 COALESCE($9::double precision, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM tasks)), $10::text[])
         RETURNING id`,
        [
          body.title,
          body.notes ?? '',
          body.projectId ?? null,
          day,
          body.plannedDay !== undefined ? body.plannedDay : day,
          body.estimateMinutes ?? null,
          body.priority ?? 0,
          repeatParam(body.repeat),
          body.sortOrder ?? null,
          body.tags ?? [],
        ],
      );
      const id = rows[0]!.id;
      if (body.subtasks?.length) await insertSubtasks(tx, id, body.subtasks);
      return findTask(tx, id);
    });
    return reply.status(201).send(task);
  });

  app.patch('/tasks/:id', async (request) => {
    const { id } = idParams.parse(request.params);
    const body = updateTaskBody.parse(request.body);

    const assignments: string[] = [];
    const params: unknown[] = [];
    const assign = (column: string, value: unknown, cast = '') => {
      params.push(value);
      assignments.push(`${column} = $${params.length}${cast}`);
    };

    if (body.title !== undefined) assign('title', body.title);
    if (body.notes !== undefined) assign('notes', body.notes);
    if (body.projectId !== undefined) assign('project_id', body.projectId);
    if (body.estimateMinutes !== undefined) assign('estimate_minutes', body.estimateMinutes);
    if (body.priority !== undefined) assign('priority', body.priority);
    if (body.repeat !== undefined) assign('repeat', repeatParam(body.repeat), '::jsonb');
    if (body.tags !== undefined) assign('tags', body.tags, '::text[]');
    if (body.sortOrder !== undefined) assign('sort_order', body.sortOrder);
    if (body.day !== undefined) {
      // Picking a day is a deliberate plan, so the task stops counting as carried over.
      assign('day', body.day);
      assign('planned_day', body.plannedDay !== undefined ? body.plannedDay : body.day);
      assignments.push('postponed_at = NULL');
    } else if (body.plannedDay !== undefined) {
      assign('planned_day', body.plannedDay);
    }
    assignments.push('updated_at = now()');

    params.push(id);
    const { rowCount } = await db.query(`UPDATE tasks SET ${assignments.join(', ')} WHERE id = $${params.length}`, params);
    if (!rowCount) throw notFound('Task not found');
    return findTask(db, id);
  });

  app.delete('/tasks/:id', async (request, reply) => {
    const { id } = idParams.parse(request.params);
    const { rowCount } = await db.query('DELETE FROM tasks WHERE id = $1', [id]);
    if (!rowCount) throw notFound('Task not found');
    return reply.status(204).send();
  });

  app.post('/tasks/:id/complete', async (request) => {
    const { id } = idParams.parse(request.params);
    const { today } = completeBody.parse(request.body ?? {});

    return db.transaction(async (tx) => {
      const { rows } = await tx.query<{ day: string | null; repeat: RepeatRule | null; completed_at: Date | null }>(
        'SELECT day, repeat, completed_at FROM tasks WHERE id = $1 FOR UPDATE',
        [id],
      );
      const current = rows[0];
      if (!current) throw notFound('Task not found');
      if (current.completed_at) return { task: await findTask(tx, id), nextOccurrence: null };

      let nextId: string | null = null;
      if (current.repeat) {
        // Completing late never schedules the next one in the past, and completing
        // early never pulls it before the day it was meant for.
        const scheduled = current.day ?? today;
        const nextDay = nextOccurrence(current.repeat, laterDay(scheduled, today), scheduled);
        const inserted = await tx.query<{ id: string }>(
          `INSERT INTO tasks (title, notes, project_id, day, planned_day, estimate_minutes, priority, repeat, sort_order, tags)
           SELECT title, notes, project_id, $2, $2, estimate_minutes, priority, repeat, sort_order, tags
           FROM tasks WHERE id = $1
           RETURNING id`,
          [id, nextDay],
        );
        nextId = inserted.rows[0]!.id;
        await tx.query(
          `INSERT INTO subtasks (task_id, title, done, sort_order)
           SELECT $2, title, false, sort_order FROM subtasks WHERE task_id = $1`,
          [id, nextId],
        );
      }

      // A finished task lives on the day it was done; completed_from_day remembers where it was.
      await tx.query(
        `UPDATE tasks
         SET completed_at = now(), completed_from_day = day, day = $2,
             postponed_at = NULL, next_occurrence_id = $3, updated_at = now()
         WHERE id = $1`,
        [id, today, nextId],
      );

      return { task: await findTask(tx, id), nextOccurrence: nextId ? await findTask(tx, nextId) : null };
    });
  });

  app.post('/tasks/:id/uncomplete', async (request) => {
    const { id } = idParams.parse(request.params);

    return db.transaction(async (tx) => {
      const { rows } = await tx.query<{ completed_at: Date | null; next_occurrence_id: string | null }>(
        'SELECT completed_at, next_occurrence_id FROM tasks WHERE id = $1 FOR UPDATE',
        [id],
      );
      const current = rows[0];
      if (!current) throw notFound('Task not found');
      if (!current.completed_at) return { task: await findTask(tx, id), removedTaskId: null };

      let removedTaskId: string | null = null;
      if (current.next_occurrence_id) {
        // Only take back the follow-up occurrence if nobody has finished it yet.
        const removed = await tx.query<{ id: string }>('DELETE FROM tasks WHERE id = $1 AND completed_at IS NULL RETURNING id', [
          current.next_occurrence_id,
        ]);
        removedTaskId = removed.rows[0]?.id ?? null;
      }

      await tx.query(
        `UPDATE tasks
         SET completed_at = NULL, day = completed_from_day, completed_from_day = NULL,
             next_occurrence_id = NULL, updated_at = now()
         WHERE id = $1`,
        [id],
      );

      return { task: await findTask(tx, id), removedTaskId };
    });
  });

  app.post('/tasks/move', async (request) => {
    const { moves, postponed } = moveBody.parse(request.body);

    return db.transaction(async (tx) => {
      for (const move of moves) {
        await tx.query(
          `UPDATE tasks
           SET day = $2,
               postponed_at = CASE WHEN $3::boolean THEN now() ELSE NULL END,
               updated_at = now()
           WHERE id = $1 AND completed_at IS NULL`,
          [move.id, move.day, postponed],
        );
      }
      return findTasks(tx, 't.id = ANY($1::uuid[])', [moves.map((move) => move.id)]);
    });
  });

  // Reordering shuffles the given tasks between the sort positions they already
  // hold, so tasks that are not part of the list keep their place.
  app.post('/tasks/reorder', async (request) => {
    const { ids } = reorderBody.parse(request.body);
    const unique = [...new Set(ids)];

    return db.transaction(async (tx) => {
      const { rows } = await tx.query<{ id: string; sort_order: number }>(
        'SELECT id, sort_order FROM tasks WHERE id = ANY($1::uuid[]) FOR UPDATE',
        [unique],
      );
      const known = new Set(rows.map((row) => row.id));
      const ordered = unique.filter((id) => known.has(id));
      const slots = rows.map((row) => row.sort_order).sort((a, b) => a - b);
      for (let i = 1; i < slots.length; i++) {
        if (slots[i]! <= slots[i - 1]!) slots[i] = slots[i - 1]! + 1e-6;
      }

      const sortOrders: Record<string, number> = {};
      for (const [index, id] of ordered.entries()) {
        sortOrders[id] = slots[index]!;
        await tx.query('UPDATE tasks SET sort_order = $2, updated_at = now() WHERE id = $1', [id, slots[index]]);
      }
      return { sortOrders };
    });
  });

  app.post('/tasks/:id/subtasks', async (request, reply) => {
    const { id } = idParams.parse(request.params);
    const body = subtaskCreateBody.parse(request.body);
    const exists = await db.query('SELECT 1 FROM tasks WHERE id = $1', [id]);
    if (!exists.rowCount) throw notFound('Task not found');
    const { rows } = await db.query<SubtaskRow>(
      `INSERT INTO subtasks (task_id, title, sort_order)
       VALUES ($1, $2, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM subtasks WHERE task_id = $1))
       RETURNING id, title, done, sort_order`,
      [id, body.title],
    );
    return reply.status(201).send(toSubtaskDto(rows[0]!));
  });

  app.patch('/subtasks/:id', async (request) => {
    const { id } = idParams.parse(request.params);
    const body = subtaskUpdateBody.parse(request.body);
    const { rows } = await db.query<SubtaskRow>(
      `UPDATE subtasks
       SET title = COALESCE($2, title), done = COALESCE($3, done)
       WHERE id = $1
       RETURNING id, title, done, sort_order`,
      [id, body.title ?? null, body.done ?? null],
    );
    if (!rows[0]) throw notFound('Subtask not found');
    return toSubtaskDto(rows[0]);
  });

  app.delete('/subtasks/:id', async (request, reply) => {
    const { id } = idParams.parse(request.params);
    const { rowCount } = await db.query('DELETE FROM subtasks WHERE id = $1', [id]);
    if (!rowCount) throw notFound('Subtask not found');
    return reply.status(204).send();
  });
}
