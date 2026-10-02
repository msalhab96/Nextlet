import { describe, expect, it } from 'vitest';
import { parseQuickAdd } from '../src/lib/parse';
import type { Project } from '../src/types';

const today = '2026-10-01'; // Thursday
const projects: Project[] = [
  { id: 'p1', name: 'Personal', color: '#3B3BD6', sortOrder: 1, createdAt: '' },
  { id: 'p2', name: 'Side project', color: '#0F766E', sortOrder: 2, createdAt: '' },
];
const parse = (text: string) => parseQuickAdd(text, { today, projects });

describe('parseQuickAdd', () => {
  it('pulls out the day, project and priority', () => {
    const result = parse('Call mom tomorrow #Personal !2');
    expect(result.title).toBe('Call mom');
    expect(result.day).toBe('2026-10-02');
    expect(result.priority).toBe(2);
    expect(result.project).toEqual({ kind: 'existing', project: projects[0] });
  });

  it('leaves plain titles alone', () => {
    expect(parse('Buy sun cream and sat nav cable')).toEqual({ title: 'Buy sun cream and sat nav cable' });
    expect(parse('Read 20 pages')).toEqual({ title: 'Read 20 pages' });
  });

  it('understands weekdays, always looking ahead', () => {
    expect(parse('Gym friday').day).toBe('2026-10-02');
    expect(parse('Gym fri').day).toBe('2026-10-02');
    expect(parse('Gym on sat with Sam').day).toBe('2026-10-03');
    expect(parse('Team review thursday').day).toBe('2026-10-08');
    expect(parse('Plan next mon').day).toBe('2026-10-12');
  });

  it('understands relative and explicit dates', () => {
    expect(parse('Weekly reset next week').day).toBe('2026-10-05');
    expect(parse('Renew passport in 3 days').day).toBe('2026-10-04');
    expect(parse('Renew passport in 2 weeks').day).toBe('2026-10-15');
    expect(parse('Pay rent on 5 oct').day).toBe('2026-10-05');
    expect(parse('Pay rent oct 5th').day).toBe('2026-10-05');
    expect(parse('Dentist 2026-11-20').day).toBe('2026-11-20');
    expect(parse('New year plans jan 2').day).toBe('2027-01-02');
  });

  it('sends "someday" tasks to the Inbox', () => {
    const result = parse('Learn the cello someday');
    expect(result.title).toBe('Learn the cello');
    expect(result.day).toBeNull();
  });

  it('does not invent dates from impossible ones', () => {
    expect(parse('Party 2026-02-30').day).toBeUndefined();
    expect(parse('Party 31 feb').day).toBeUndefined();
  });

  it('matches projects loosely and offers new ones', () => {
    expect(parse('Ship it #side-project').project).toEqual({ kind: 'existing', project: projects[1] });
    expect(parse('Plant tulips #Garden').project).toEqual({ kind: 'new', name: 'Garden' });
  });

  it('ignores times rather than scheduling by the hour', () => {
    const result = parse('Call mom tomorrow 6pm');
    expect(result.day).toBe('2026-10-02');
    expect(result.title).toBe('Call mom 6pm');
  });
});
