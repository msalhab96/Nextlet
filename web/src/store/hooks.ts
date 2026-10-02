import { useMemo } from 'react';
import type { Project, Task } from '../types';
import { useStore } from './store';

export function useTaskList(): Task[] {
  const tasks = useStore((state) => state.tasks);
  return useMemo(() => Object.values(tasks), [tasks]);
}

export function useProjectMap(): Map<string, Project> {
  const projects = useStore((state) => state.projects);
  return useMemo(() => new Map(projects.map((project) => [project.id, project])), [projects]);
}
