import { useEffect, useState, type DragEvent } from 'react';
import { cx } from '../lib/format';
import { moveInOrder } from '../lib/tasks';
import { useProjectMap } from '../store/hooks';
import { actions, useStore } from '../store/store';
import type { Task } from '../types';
import { Icon } from './Icon';
import { TaskRow, type RowAction } from './TaskRow';

interface TaskListProps {
  tasks: Task[];
  today: string;
  action?: RowAction;
  showDay?: boolean;
  showProject?: boolean;
  /** Lets the user drag rows into a new order. */
  reorderable?: boolean;
}

export function TaskList({ tasks, today, action, showDay, showProject, reorderable = false }: TaskListProps) {
  const projects = useProjectMap();
  const selectedId = useStore((state) => state.selectedTaskId);
  // Dragging starts from the grip only, so clicks on the row still select and complete.
  const [armedId, setArmedId] = useState<string | null>(null);
  const [draggingId, setDraggingId] = useState<string | null>(null);
  const [dropIndex, setDropIndex] = useState<number | null>(null);

  const reset = () => {
    setArmedId(null);
    setDraggingId(null);
    setDropIndex(null);
  };

  // A press on the grip that never turns into a drag must not leave the row draggable.
  useEffect(() => {
    if (!armedId) return;
    const disarm = () => setArmedId(null);
    window.addEventListener('pointerup', disarm);
    return () => window.removeEventListener('pointerup', disarm);
  }, [armedId]);

  const onDragOver = (event: DragEvent<HTMLLIElement>, index: number) => {
    if (!draggingId) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'move';
    const box = event.currentTarget.getBoundingClientRect();
    setDropIndex(event.clientY < box.top + box.height / 2 ? index : index + 1);
  };

  const onDrop = (event: DragEvent) => {
    event.preventDefault();
    if (draggingId && dropIndex !== null) {
      const ids = tasks.map((task) => task.id);
      const from = ids.indexOf(draggingId);
      const target = from < dropIndex ? dropIndex - 1 : dropIndex;
      const next = moveInOrder(ids, draggingId, target);
      if (next.some((id, index) => id !== ids[index])) void actions.reorder(next);
    }
    reset();
  };

  return (
    <ul className="task-list" onDrop={reorderable ? onDrop : undefined}>
      {tasks.map((task, index) => (
        <li
          key={task.id}
          className={cx(
            'task-list__item',
            draggingId === task.id && 'is-dragging',
            dropIndex === index && draggingId !== null && 'drop-before',
            dropIndex === index + 1 && index === tasks.length - 1 && draggingId !== null && 'drop-after',
          )}
          draggable={reorderable && armedId === task.id}
          onDragStart={(event) => {
            setDraggingId(task.id);
            event.dataTransfer.effectAllowed = 'move';
            event.dataTransfer.setData('text/plain', task.title);
          }}
          onDragOver={reorderable ? (event) => onDragOver(event, index) : undefined}
          onDragEnd={reset}
        >
          <TaskRow
            task={task}
            today={today}
            project={task.projectId ? projects.get(task.projectId) : undefined}
            selected={selectedId === task.id}
            action={action}
            showDay={showDay}
            showProject={showProject}
            grip={
              reorderable ? (
                <span
                  className="task-row__grip"
                  aria-hidden="true"
                  title="Drag to reorder"
                  onPointerDown={() => setArmedId(task.id)}
                >
                  <Icon name="grip" size={14} />
                </span>
              ) : undefined
            }
          />
        </li>
      ))}
    </ul>
  );
}

export function SectionTitle({ title, count }: { title: string; count?: string }) {
  return (
    <h2 className="section-title">
      {title}
      {count !== undefined && <span className="section-title__count">{count}</span>}
    </h2>
  );
}
