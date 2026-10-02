import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { Database } from '../db.js';
import { notFound } from '../http.js';

export const PROJECT_PALETTE = ['#3B3BD6', '#0F766E', '#C2410C', '#A16207', '#7C3AED', '#BE185D', '#0369A1', '#4D7C0F'];

const idParams = z.object({ id: z.uuid() });
const projectName = z.string().trim().min(1, 'Give the project a name').max(60);
const projectColor = z.string().regex(/^#[0-9A-Fa-f]{6}$/, 'Use a hex colour like #3B3BD6');

const createProjectBody = z.strictObject({
  name: projectName,
  color: projectColor.optional(),
});

const updateProjectBody = z
  .strictObject({
    name: projectName.optional(),
    color: projectColor.optional(),
    sortOrder: z.number().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, 'Nothing to update');

interface ProjectRow {
  id: string;
  name: string;
  color: string;
  sort_order: number;
  created_at: Date;
}

function toProjectDto(row: ProjectRow) {
  return {
    id: row.id,
    name: row.name,
    color: row.color,
    sortOrder: row.sort_order,
    createdAt: row.created_at.toISOString(),
  };
}

export function registerProjectRoutes(app: FastifyInstance, db: Database) {
  app.get('/projects', async () => {
    const { rows } = await db.query<ProjectRow>('SELECT * FROM projects ORDER BY sort_order, created_at');
    return rows.map(toProjectDto);
  });

  app.post('/projects', async (request, reply) => {
    const body = createProjectBody.parse(request.body);
    const project = await db.transaction(async (tx) => {
      let color = body.color;
      if (!color) {
        const { rows } = await tx.query<{ color: string }>('SELECT color FROM projects');
        const used = new Set(rows.map((row) => row.color.toUpperCase()));
        color = PROJECT_PALETTE.find((candidate) => !used.has(candidate)) ?? PROJECT_PALETTE[rows.length % PROJECT_PALETTE.length]!;
      }
      const { rows } = await tx.query<ProjectRow>(
        `INSERT INTO projects (name, color, sort_order)
         VALUES ($1, $2, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM projects))
         RETURNING *`,
        [body.name, color],
      );
      return toProjectDto(rows[0]!);
    });
    return reply.status(201).send(project);
  });

  app.patch('/projects/:id', async (request) => {
    const { id } = idParams.parse(request.params);
    const body = updateProjectBody.parse(request.body);
    const { rows } = await db.query<ProjectRow>(
      `UPDATE projects
       SET name = COALESCE($2, name),
           color = COALESCE($3, color),
           sort_order = COALESCE($4::double precision, sort_order),
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [id, body.name ?? null, body.color ?? null, body.sortOrder ?? null],
    );
    if (!rows[0]) throw notFound('Project not found');
    return toProjectDto(rows[0]);
  });

  // Deleting a project keeps its tasks; they simply lose the project.
  app.delete('/projects/:id', async (request, reply) => {
    const { id } = idParams.parse(request.params);
    const { rowCount } = await db.query('DELETE FROM projects WHERE id = $1', [id]);
    if (!rowCount) throw notFound('Project not found');
    return reply.status(204).send();
  });
}
