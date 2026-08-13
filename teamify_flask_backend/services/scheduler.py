"""
Task reminders scheduler.

Uses APScheduler to periodically check for tasks approaching their deadline
and tasks that are overdue, generating reminder logs that can be consumed
by the frontend notifications system.
"""

from datetime import date, datetime, timezone, timedelta
from apscheduler.schedulers.background import BackgroundScheduler
from models import db
from models.task import Task
from models.log import Log
from models.user import User
from routes.notifications import create_notification, _merged_preferences


def _today_start(today: date) -> datetime:
    return datetime(today.year, today.month, today.day, tzinfo=timezone.utc)


def _already_logged(task_id: int, action: str, today: date) -> bool:
    return bool(
        Log.query.filter(
            Log.entity == "Reminder",
            Log.entity_id == task_id,
            Log.action == action,
            Log.created_at >= _today_start(today),
        ).first()
    )


def _reminder_timing(user: User | None) -> str:
    prefs = _merged_preferences(getattr(user, "notification_prefs", None) if user else None)
    return prefs.get("taskReminderTiming") or "24_hours"


def _should_email_deadline(action: str, timing: str) -> bool:
    if action == "OVERDUE":
        return True
    if action == "DUE_TODAY":
        return timing in ("3_hours", "12_hours")
    if action == "DUE_TOMORROW":
        return timing == "24_hours"
    if action == "DUE_IN_2_DAYS":
        return timing == "48_hours"
    return False


def _add_deadline_notification(
    task: Task,
    *,
    action: str,
    notif_type: str,
    title: str,
    body: str,
    today: date,
    pending_emails: list[tuple[int, str]],
) -> None:
    if not task.assigned_to:
        return
    if _already_logged(task.id, action, today):
        return

    log = Log(
        action=action,
        entity="Reminder",
        entity_id=task.id,
        details=body,
        user_id=task.assigned_to,
    )
    db.session.add(log)
    notif = create_notification(
        user_id=task.assigned_to,
        notif_type=notif_type,
        title=title,
        body=body,
        entity_type="Task",
        entity_id=task.id,
        queue_email=False,
    )
    assignee = db.session.get(User, task.assigned_to)
    timing = _reminder_timing(assignee)
    if getattr(notif, "id", None) and _should_email_deadline(action, timing):
        key = f"deadline:{task.assigned_to}:{task.id}:{action}:{today.isoformat()}"
        pending_emails.append((notif.id, key))


def check_reminders(app):
    """
    Check all active tasks and create reminder logs for:
      - Tasks due today
      - Tasks due tomorrow
      - Tasks due in two days (48h preference)
      - Tasks overdue (past due_date and not done)
    """
    with app.app_context():
        today = date.today()
        pending_emails: list[tuple[int, str]] = []

        due_today = Task.query.filter(
            Task.due_date == today,
            Task.status != "done",
        ).all()
        for task in due_today:
            _add_deadline_notification(
                task,
                action="DUE_TODAY",
                notif_type="deadline_approaching",
                title="Deadline approaching",
                body=f"Task '{task.title}' is due today",
                today=today,
                pending_emails=pending_emails,
            )

        tomorrow = today + timedelta(days=1)
        due_tomorrow = Task.query.filter(
            Task.due_date == tomorrow,
            Task.status != "done",
        ).all()
        for task in due_tomorrow:
            _add_deadline_notification(
                task,
                action="DUE_TOMORROW",
                notif_type="deadline_approaching",
                title="Deadline approaching",
                body=f"Task '{task.title}' is due tomorrow",
                today=today,
                pending_emails=pending_emails,
            )

        in_two_days = today + timedelta(days=2)
        due_in_two = Task.query.filter(
            Task.due_date == in_two_days,
            Task.status != "done",
        ).all()
        for task in due_in_two:
            assignee = db.session.get(User, task.assigned_to) if task.assigned_to else None
            if _reminder_timing(assignee) != "48_hours":
                continue
            _add_deadline_notification(
                task,
                action="DUE_IN_2_DAYS",
                notif_type="deadline_approaching",
                title="Deadline approaching",
                body=f"Task '{task.title}' is due in 2 days",
                today=today,
                pending_emails=pending_emails,
            )

        overdue_tasks = Task.query.filter(
            Task.due_date < today,
            Task.status != "done",
        ).all()
        for task in overdue_tasks:
            days_overdue = (today - task.due_date).days if task.due_date else 0
            _add_deadline_notification(
                task,
                action="OVERDUE",
                notif_type="delay_warning",
                title="AI Delay Warning",
                body=f"Task '{task.title}' is overdue by {days_overdue} day(s)",
                today=today,
                pending_emails=pending_emails,
            )

        db.session.commit()

        if pending_emails:
            from services.notification_email_service import deliver_notification_email_now

            for notif_id, key in pending_emails:
                try:
                    deliver_notification_email_now(notif_id, idempotency_key=key)
                except Exception:
                    pass


def init_scheduler(app):
    """
    Initialize and start the APScheduler background scheduler.
    Runs check_reminders every hour.
    """
    scheduler = BackgroundScheduler()
    scheduler.add_job(
        func=lambda: check_reminders(app),
        trigger="interval",
        hours=1,
        id="task_reminders",
        name="Check task deadlines and send reminders",
        replace_existing=True,
    )
    scheduler.add_job(
        func=lambda: _run_analytics_snapshot(app),
        trigger="cron",
        hour=2,
        minute=0,
        id="admin_analytics_snapshot",
        name="Daily admin analytics snapshot",
        replace_existing=True,
    )
    scheduler.start()
    # Run once immediately at startup
    check_reminders(app)
    _run_analytics_snapshot(app)
    return scheduler


def _run_analytics_snapshot(app):
    with app.app_context():
        from services.analytics_snapshot_service import create_daily_snapshot
        try:
            create_daily_snapshot()
        except Exception:
            pass
