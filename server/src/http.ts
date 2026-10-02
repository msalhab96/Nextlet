import type { FastifyError, FastifyReply, FastifyRequest } from 'fastify';
import { ZodError } from 'zod';

export class HttpError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export const notFound = (message: string) => new HttpError(404, 'not_found', message);
export const badRequest = (message: string) => new HttpError(400, 'invalid_request', message);

const POSTGRES_ERRORS: Record<string, [status: number, code: string, message: string]> = {
  '23505': [409, 'conflict', 'That already exists'],
  '23503': [400, 'invalid_reference', 'A referenced item does not exist'],
  '23514': [400, 'invalid_value', 'A value is out of range'],
  '22P02': [400, 'invalid_value', 'A value has the wrong format'],
  '22007': [400, 'invalid_value', 'That is not a valid date'],
  '22008': [400, 'invalid_value', 'That date is out of range'],
};

export function errorHandler(error: FastifyError | Error, request: FastifyRequest, reply: FastifyReply) {
  if (error instanceof ZodError) {
    const issues = error.issues.map((issue) => ({ path: issue.path.join('.'), message: issue.message }));
    const first = issues[0];
    return reply.status(400).send({
      error: 'invalid_request',
      message: first ? (first.path ? `${first.path}: ${first.message}` : first.message) : 'Invalid request',
      issues,
    });
  }

  if (error instanceof HttpError) {
    return reply.status(error.statusCode).send({ error: error.code, message: error.message });
  }

  const { code, constraint } = error as { code?: unknown; constraint?: unknown };
  if (typeof code === 'string' && POSTGRES_ERRORS[code]) {
    const [status, errorCode, message] = POSTGRES_ERRORS[code];
    const detail = constraint === 'projects_name_key' ? 'A project with that name already exists' : message;
    return reply.status(status).send({ error: errorCode, message: detail });
  }

  const statusCode = (error as FastifyError).statusCode;
  if (statusCode && statusCode >= 400 && statusCode < 500) {
    return reply.status(statusCode).send({ error: 'invalid_request', message: error.message });
  }

  request.log.error({ err: error }, 'unhandled error');
  return reply.status(500).send({ error: 'internal_error', message: 'Something went wrong on the server' });
}
