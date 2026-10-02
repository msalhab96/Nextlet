import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { createPgDatabase, type Database } from '../src/db.js';
import { migrate } from '../src/migrate.js';
import { seed } from '../src/seed.js';

// These tests need a real PostgreSQL. Point TEST_DATABASE_URL at any database you
// can create schemas in; each run works inside its own throwaway schema.
const url = process.env.TEST_DATABASE_URL;

const TODAY = '2026-10-01'; // a Thursday
const TOMORROW = '2026-10-02';

describe.skipIf(!url)('Nextlet API', () => {
  const schema = `nextlet_test_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
  let admin: Database;
  let db: Database;
  let app: ReturnType<typeof buildApp>;

  beforeAll(async () => {
    admin = createPgDatabase(url!);
    await admin.query(`CREATE SCHEMA ${schema}`);
    db = createPgDatabase(url!, { searchPath: schema });
    await migrate(db, () => undefined);
    await seed(db, { demo: false, log: () => undefined });
    app = buildApp({ db, logger: false });
    await app.ready();
  });

  afterAll(async () => {
    await app?.close();
    await db?.close();
    await admin?.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
    await admin?.close();
  });

  const call = async (method: 'GET' | 'POST' | 'PATCH' | 'DELETE', path: string, payload?: object) => {
    const response = await app.inject({ method, url: `/api${path}`, payload });
    return { status: response.statusCode, body: response.body ? response.json() : null };
  };

  const createTask = async (payload: Record<string, unknown>) => {
    const { status, body } = await call('POST', '/tasks', payload);
    expect(status).toBe(201);
    return body;
  };

  it('reports health', async () => {
    expect(await call('GET', '/health')).toEqual({ status: 200, body: { ok: true } });
  });

  it('seeds the default projects once', async () => {
    await seed(db, { demo: false, log: () => undefined });
    const { body } = await call('GET', '/projects');
    expect(body.map((project: { name: string }) => project.name)).toEqual(['Personal', 'Work', 'Health', 'Home']);
  });

  it('creates, renames and deletes projects', async () => {
    const created = await call('POST', '/projects', { name: 'Side project' });
    expect(created.status).toBe(201);
    expect(created.body.color).toMatch(/^#[0-9A-F]{6}$/i);

    const duplicate = await call('POST', '/projects', { name: '  side PROJECT ' });
    expect(duplicate.status).toBe(409);
    expect(duplicate.body.message).toBe('A project with that name already exists');

    const renamed = await call('PATCH', `/projects/${created.body.id}`, { name: 'Garden' });
    expect(renamed.body.name).toBe('Garden');

    const task = await createTask({ title: 'Plant tulips', projectId: created.body.id });
    expect((await call('DELETE', `/projects/${created.body.id}`)).status).toBe(204);
    const open = await call('GET', '/tasks?status=open');
    expect(open.body.find((t: { id: string }) => t.id === task.id).projectId).toBeNull();
  });

  it('creates tasks with subtasks and rejects bad input', async () => {
    const task = await createTask({
      title: '  Draft Q4 personal budget ',
      day: TODAY,
      estimateMinutes: 45,
      priority: 1,
      subtasks: [{ title: 'Export spending', done: true }, { title: 'Set savings target' }],
    });
    expect(task.title).toBe('Draft Q4 personal budget');
    expect(task.day).toBe(TODAY);
    expect(task.plannedDay).toBe(TODAY);
    expect(task.subtasks.map((s: { title: string; done: boolean }) => [s.title, s.done])).toEqual([
      ['Export spending', true],
      ['Set savings target', false],
    ]);

    expect((await call('POST', '/tasks', { title: '' })).status).toBe(400);
    expect((await call('POST', '/tasks', { title: 'Bad day', day: '2026-02-30' })).status).toBe(400);
    expect((await call('POST', '/tasks', { title: 'Hourly', day: '2026-10-01T11:44' })).status).toBe(400);
    expect((await call('POST', '/tasks', { title: 'Extra', dueAt: '11:44' })).status).toBe(400);
    expect((await call('PATCH', '/tasks/00000000-0000-4000-8000-000000000000', { title: 'x' })).status).toBe(404);
  });

  it('pushes a task to tomorrow without forgetting where it was planned', async () => {
    const task = await createTask({ title: 'Renew library books', day: '2026-09-29' });
    const { status, body } = await call('POST', '/tasks/move', { moves: [{ id: task.id, day: TOMORROW }], postponed: true });
    expect(status).toBe(200);
    expect(body[0].day).toBe(TOMORROW);
    expect(body[0].plannedDay).toBe('2026-09-29');
    expect(body[0].postponedAt).not.toBeNull();

    const back = await call('POST', '/tasks/move', { moves: [{ id: task.id, day: TODAY }], postponed: false });
    expect(back.body[0].day).toBe(TODAY);
    expect(back.body[0].postponedAt).toBeNull();

    // Choosing a day explicitly resets the plan.
    const rescheduled = await call('PATCH', `/tasks/${task.id}`, { day: '2026-10-05' });
    expect(rescheduled.body.plannedDay).toBe('2026-10-05');
  });

  it('completes a carried-over task on today and restores it on undo', async () => {
    const task = await createTask({ title: 'Reply to landlord', day: '2026-09-29' });
    const done = await call('POST', `/tasks/${task.id}/complete`, { today: TODAY });
    expect(done.body.task.completedAt).not.toBeNull();
    expect(done.body.task.day).toBe(TODAY);
    expect(done.body.nextOccurrence).toBeNull();

    const listed = await call('GET', `/tasks?status=done&from=${TODAY}&to=${TODAY}`);
    expect(listed.body.some((t: { id: string }) => t.id === task.id)).toBe(true);

    const undone = await call('POST', `/tasks/${task.id}/uncomplete`);
    expect(undone.body.task.completedAt).toBeNull();
    expect(undone.body.task.day).toBe('2026-09-29');
  });

  it('schedules the next occurrence of a repeating task', async () => {
    const task = await createTask({
      title: 'Read 20 pages',
      day: TODAY,
      repeat: { type: 'weekly', days: [1, 3, 5] },
      subtasks: [{ title: 'Pick a book', done: true }],
    });
    const done = await call('POST', `/tasks/${task.id}/complete`, { today: TODAY });
    const next = done.body.nextOccurrence;
    expect(next.day).toBe(TOMORROW);
    expect(next.repeat).toEqual({ type: 'weekly', days: [1, 3, 5] });
    expect(next.subtasks.map((s: { done: boolean }) => s.done)).toEqual([false]);

    const undone = await call('POST', `/tasks/${task.id}/uncomplete`);
    expect(undone.body.removedTaskId).toBe(next.id);
    const open = await call('GET', '/tasks?status=open');
    expect(open.body.some((t: { id: string }) => t.id === next.id)).toBe(false);

    expect((await call('PATCH', `/tasks/${task.id}`, { repeat: { type: 'hourly' } })).status).toBe(400);
  });

  it('reorders tasks within the slots they already hold', async () => {
    const a = await createTask({ title: 'A', day: TODAY });
    const b = await createTask({ title: 'B', day: TODAY });
    const c = await createTask({ title: 'C', day: TODAY });
    const { body } = await call('POST', '/tasks/reorder', { ids: [c.id, a.id, b.id] });
    expect(body.sortOrders[c.id]).toBe(a.sortOrder);
    expect(body.sortOrders[a.id]).toBe(b.sortOrder);
    expect(body.sortOrders[b.id]).toBe(c.sortOrder);
  });

  it('manages subtasks', async () => {
    const task = await createTask({ title: 'Review slides' });
    const added = await call('POST', `/tasks/${task.id}/subtasks`, { title: 'Check slide 4' });
    expect(added.status).toBe(201);
    const toggled = await call('PATCH', `/subtasks/${added.body.id}`, { done: true });
    expect(toggled.body.done).toBe(true);
    expect((await call('DELETE', `/subtasks/${added.body.id}`)).status).toBe(204);
    expect((await call('DELETE', `/subtasks/${added.body.id}`)).status).toBe(404);
  });

  it('searches titles and notes, treating wildcards literally', async () => {
    await createTask({ title: 'Buy 100% cotton sheets' });
    await createTask({ title: 'Something else', notes: 'mention of cotton here' });
    const percent = await call('GET', `/tasks?q=${encodeURIComponent('100%')}`);
    expect(percent.body.map((t: { title: string }) => t.title)).toEqual(['Buy 100% cotton sheets']);
    const cotton = await call('GET', '/tasks?q=cotton');
    expect(cotton.body).toHaveLength(2);
  });

  it('keeps optional tags, tidied up, and finds tasks by tag', async () => {
    const plain = await call('POST', '/tasks', { title: 'No tags here', day: TODAY });
    expect(plain.body.tags).toEqual([]);

    const tagged = await call('POST', '/tasks', { title: 'Call the bank', day: TODAY, tags: ['@Phone', ' phone ', 'deep   work', 'Errands'] });
    expect(tagged.status).toBe(201);
    expect(tagged.body.tags).toEqual(['Phone', 'deep work', 'Errands']);

    const updated = await call('PATCH', `/tasks/${tagged.body.id}`, { tags: ['errands', 'Bank'] });
    expect(updated.body.tags).toEqual(['errands', 'Bank']);
    expect((await call('PATCH', `/tasks/${tagged.body.id}`, { tags: ['  '] })).status).toBe(400);
    const tooMany = Array.from({ length: 21 }, (_, index) => `tag${index}`);
    expect((await call('PATCH', `/tasks/${tagged.body.id}`, { tags: tooMany })).status).toBe(400);

    const byTag = await call('GET', `/tasks?q=${encodeURIComponent('@ERRANDS')}`);
    expect(byTag.body.map((task: { id: string }) => task.id)).toEqual([tagged.body.id]);
    const byText = await call('GET', '/tasks?q=bank');
    expect(byText.body.map((task: { id: string }) => task.id)).toContain(tagged.body.id);

    const cleared = await call('PATCH', `/tasks/${tagged.body.id}`, { tags: [] });
    expect(cleared.body.tags).toEqual([]);
  });

  it('carries tags over to the next occurrence of a repeating task', async () => {
    const created = await call('POST', '/tasks', { title: 'Water the herbs', day: TODAY, repeat: { type: 'daily' }, tags: ['home'] });
    const completed = await call('POST', `/tasks/${created.body.id}/complete`, { today: TODAY });
    expect(completed.body.nextOccurrence.tags).toEqual(['home']);
    expect(completed.body.nextOccurrence.day).toBe(TOMORROW);
  });

  it('renames and removes a tag on every task that has it', async () => {
    const first = await call('POST', '/tasks', { title: 'Ring the plumber', day: TODAY, tags: ['Calls', 'home'] });
    const second = await call('POST', '/tasks', { title: 'Ring the bank', day: TODAY, tags: ['calls'] });
    await call('POST', `/tasks/${second.body.id}/complete`, { today: TODAY });

    const renamed = await call('PATCH', `/tags/${encodeURIComponent('CALLS')}`, { name: 'phone' });
    expect(renamed.body).toEqual({ name: 'phone', tasks: 2 });
    expect((await call('GET', '/tasks?q=%40phone')).body.map((task: { id: string }) => task.id).sort()).toEqual([first.body.id, second.body.id].sort());

    const removed = await call('DELETE', '/tags/phone');
    expect(removed.body).toEqual({ tasks: 2 });
    const open = await call('GET', '/tasks?status=open');
    expect(open.body.find((task: { id: string }) => task.id === first.body.id).tags).toEqual(['home']);
  });

  it('requires a range for done tasks', async () => {
    expect((await call('GET', '/tasks?status=done')).status).toBe(400);
    expect((await call('GET', `/tasks?status=done&from=${TOMORROW}&to=${TODAY}`)).status).toBe(400);
  });
});
