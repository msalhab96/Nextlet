import { useMemo } from 'react';
import { AddTask } from '../components/AddTask';
import { SectionTitle, TaskList } from '../components/TaskList';
import { plural } from '../lib/format';
import { inboxTasks } from '../lib/tasks';
import { useToday } from '../lib/today';
import { useTaskList } from '../store/hooks';

export function InboxView() {
  const today = useToday();
  const tasks = useTaskList();
  const inbox = useMemo(() => inboxTasks(tasks), [tasks]);

  return (
    <div className="view">
      <header className="view-header">
        <div className="view-header__titles">
          <span className="eyebrow">No day yet</span>
          <h1 className="view-title">Inbox</h1>
        </div>
      </header>
      <p className="view-intro">Everything you’ve captured without a day. Give a task a day when you’re ready for it.</p>

      {inbox.length > 0 ? (
        <section className="section">
          <SectionTitle title="Unscheduled" count={plural(inbox.length, 'task')} />
          <TaskList tasks={inbox} today={today} action="today" />
        </section>
      ) : (
        <div className="empty">
          <h2 className="empty__title">Inbox zero.</h2>
          <p className="empty__text">Press N anywhere to capture a task without picking a day.</p>
        </div>
      )}

      <AddTask defaultDay={null} label="Add a task to the Inbox" placeholder="Add to the Inbox — try “Plan a weekend trip #Personal”" />
    </div>
  );
}
