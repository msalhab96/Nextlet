import type { Database, Queryable } from './db.js';
import { addDays, isoWeekday, utcToday } from './lib/dates.js';
import type { RepeatRule } from './lib/repeat.js';

const SEED_LOCK = 727_002;

const DEFAULT_PROJECTS = [
  { name: 'Personal', color: '#3B3BD6' },
  { name: 'Work', color: '#0F766E' },
  { name: 'Health', color: '#C2410C' },
  { name: 'Home', color: '#A16207' },
];

interface DemoTask {
  title: string;
  project: string;
  /** Days from today; null puts the task in the Inbox. */
  offset: number | null;
  /** Where the task was first planned, for tasks carried over from an earlier day. */
  plannedOffset?: number;
  estimate?: number;
  priority?: number;
  notes?: string;
  repeat?: (today: string) => RepeatRule;
  done?: boolean;
  subtasks?: [title: string, done?: boolean][];
  tags?: string[];
}

const DEMO_TASKS: DemoTask[] = [
  {
    title: 'Draft Q4 personal budget',
    project: 'Personal',
    offset: 0,
    estimate: 45,
    priority: 1,
    notes: 'Compare against Q3. Keep fixed costs under the line we agreed on.',
    subtasks: [['Export last 3 months of spending', true], ['Set savings target'], ['Plan holiday spending']],
  },
  {
    title: 'Reply to landlord about lease renewal',
    tags: ['email'],
    project: 'Home',
    offset: 0,
    estimate: 10,
    priority: 2,
    notes: 'Ask about the renewal terms before confirming.',
  },
  { title: 'Renew library books', project: 'Personal', offset: -2, estimate: 5, notes: 'Two books, both due this week.' },
  {
    title: 'Review slides for Monday planning',
    tags: ['deep work'],
    project: 'Work',
    offset: 0,
    estimate: 30,
    priority: 2,
    subtasks: [['Check numbers on slide 4'], ['Tighten the summary']],
  },
  { title: 'Pick up dry cleaning', project: 'Home', offset: 0, estimate: 15, priority: 3, notes: 'Ticket is in the car.', tags: ['errands'] },
  { title: 'Read 20 pages', project: 'Personal', offset: 0, estimate: 20, repeat: () => ({ type: 'daily' }) },
  { title: 'Book dentist appointment', project: 'Health', offset: 0, estimate: 5, priority: 3, tags: ['phone'] },
  { title: '30-minute run', project: 'Health', offset: 0, estimate: 30, done: true },
  { title: 'Water the plants', project: 'Home', offset: 0, estimate: 5, done: true },
  { title: '1:1 with manager', project: 'Work', offset: 1, estimate: 30 },
  { title: 'Call mom', project: 'Personal', offset: 1, estimate: 20, tags: ['phone'] },
  {
    title: 'Yoga class',
    project: 'Health',
    offset: 1,
    estimate: 60,
    repeat: (today) => ({ type: 'weekly', days: [isoWeekday(addDays(today, 1))] }),
  },
  { title: 'Farmers market', project: 'Home', offset: 2, tags: ['errands'] },
  { title: 'Clean out the garage', project: 'Home', offset: 2, estimate: 90 },
  { title: 'Meal prep for the week', project: 'Health', offset: 3, estimate: 60 },
  {
    title: 'Weekly review',
    project: 'Personal',
    offset: 3,
    estimate: 30,
    repeat: (today) => ({ type: 'weekly', days: [isoWeekday(addDays(today, 3))] }),
  },
  { title: 'Pay electricity bill', project: 'Home', offset: -3, done: true },
  { title: 'Team sync', project: 'Work', offset: -3, done: true },
  { title: 'Gym — legs', project: 'Health', offset: -2, done: true },
  { title: 'Send invoice to client', project: 'Work', offset: -2, done: true },
  { title: 'Call grandma', project: 'Personal', offset: -1, done: true },
  { title: 'Grocery run', project: 'Home', offset: -1, done: true },
  { title: 'Plan a weekend trip', project: 'Personal', offset: null },
  { title: 'Research standing desks', project: 'Home', offset: null },
  { title: 'Sort out photo backups', project: 'Personal', offset: null },
];

async function insertDemoTasks(tx: Queryable, today: string) {
  const { rows } = await tx.query<{ id: string; name: string }>('SELECT id, name FROM projects');
  const projectIds = new Map(rows.map((row) => [row.name, row.id]));

  for (const [index, task] of DEMO_TASKS.entries()) {
    const day = task.offset === null ? null : addDays(today, task.offset);
    const plannedDay = task.plannedOffset !== undefined ? addDays(today, task.plannedOffset) : day;
    const inserted = await tx.query<{ id: string }>(
      `INSERT INTO tasks (title, notes, project_id, day, planned_day, estimate_minutes, priority, repeat, sort_order, completed_at, tags)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9,
               CASE WHEN $10::boolean
                 THEN LEAST(now(), ($4::date + time '09:00') AT TIME ZONE 'UTC' + make_interval(mins => $11::int))
               END, $12::text[])
       RETURNING id`,
      [
        task.title,
        task.notes ?? '',
        projectIds.get(task.project) ?? null,
        day,
        plannedDay,
        task.estimate ?? null,
        task.priority ?? 0,
        task.repeat ? JSON.stringify(task.repeat(today)) : null,
        index + 1,
        task.done ?? false,
        index * 7,
        task.tags ?? [],
      ],
    );
    const taskId = inserted.rows[0]!.id;
    for (const [position, [title, done]] of (task.subtasks ?? []).entries()) {
      await tx.query('INSERT INTO subtasks (task_id, title, done, sort_order) VALUES ($1, $2, $3, $4)', [
        taskId,
        title,
        done ?? false,
        position + 1,
      ]);
    }
  }
}

/**
 * Creates the starter projects the first time Nextlet runs, and optionally a week
 * of sample tasks so the app can be explored. Both happen once per database.
 */
export async function seed(db: Database, options: { demo: boolean; log: (message: string) => void; today?: string }) {
  await db.transaction(async (tx) => {
    await tx.query('SELECT pg_advisory_xact_lock($1)', [SEED_LOCK]);

    const defaults = await tx.query("SELECT 1 FROM app_meta WHERE key = 'default_projects_seeded'");
    if (!defaults.rowCount) {
      for (const [index, project] of DEFAULT_PROJECTS.entries()) {
        await tx.query('INSERT INTO projects (name, color, sort_order) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING', [
          project.name,
          project.color,
          index + 1,
        ]);
      }
      await tx.query("INSERT INTO app_meta (key, value) VALUES ('default_projects_seeded', 'true')");
      options.log('created the default projects');
    }

    if (!options.demo) return;
    const demo = await tx.query("SELECT 1 FROM app_meta WHERE key = 'demo_seeded'");
    const { rows } = await tx.query<{ count: number }>('SELECT count(*)::int AS count FROM tasks');
    if (demo.rowCount || (rows[0]?.count ?? 0) > 0) return;

    await insertDemoTasks(tx, options.today ?? utcToday());
    await tx.query("INSERT INTO app_meta (key, value) VALUES ('demo_seeded', 'true')");
    options.log('loaded the demo tasks');
  });
}
