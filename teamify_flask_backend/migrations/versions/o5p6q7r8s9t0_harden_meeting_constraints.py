"""Harden live-meeting uniqueness and missing unique indexes.

Revision ID: o5p6q7r8s9t0
Revises: n4o5p6q7r8s9
Create Date: 2026-08-13
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect, text


revision = "o5p6q7r8s9t0"
down_revision = "n4o5p6q7r8s9"
branch_labels = None
depends_on = None


def _index_names(bind, table: str) -> set[str]:
    return {ix["name"] for ix in inspect(bind).get_indexes(table)}


def upgrade():
    bind = op.get_bind()
    tables = inspect(bind).get_table_names()
    dialect = bind.dialect.name

    if "meetings" in tables:
        if dialect == "postgresql":
            bind.execute(
                text(
                    """
                    UPDATE meetings
                    SET status = 'ended', ended_at = NOW()
                    WHERE status = 'live'
                      AND id NOT IN (
                        SELECT keep_id FROM (
                          SELECT MAX(id) AS keep_id FROM meetings
                          WHERE status = 'live'
                          GROUP BY chat_room_id
                        ) keepers
                      )
                    """
                )
            )
        else:
            bind.execute(
                text(
                    """
                    UPDATE meetings
                    SET status = 'ended', ended_at = CURRENT_TIMESTAMP
                    WHERE status = 'live'
                      AND id NOT IN (
                        SELECT keep_id FROM (
                          SELECT MAX(id) AS keep_id FROM meetings
                          WHERE status = 'live'
                          GROUP BY chat_room_id
                        ) keepers
                      )
                    """
                )
            )
        names = _index_names(bind, "meetings")
        if "uq_meetings_one_live_per_room" not in names:
            op.execute(
                sa.text(
                    "CREATE UNIQUE INDEX IF NOT EXISTS uq_meetings_one_live_per_room "
                    "ON meetings (chat_room_id) WHERE status = 'live'"
                )
            )

    if "messages" in tables:
        names = _index_names(bind, "messages")
        if "uq_msg_idempotency" not in names:
            op.execute(
                sa.text(
                    "CREATE UNIQUE INDEX IF NOT EXISTS uq_msg_idempotency "
                    "ON messages (room_id, sender_id, idempotency_key)"
                )
            )

    if "chat_rooms" in tables:
        names = _index_names(bind, "chat_rooms")
        if "uq_chat_rooms_direct_pair_key" not in names:
            op.execute(
                sa.text(
                    "CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_rooms_direct_pair_key "
                    "ON chat_rooms (direct_pair_key)"
                )
            )


def downgrade():
    bind = op.get_bind()
    tables = inspect(bind).get_table_names()
    if "meetings" in tables and "uq_meetings_one_live_per_room" in _index_names(bind, "meetings"):
        op.execute(sa.text("DROP INDEX IF EXISTS uq_meetings_one_live_per_room"))
    if "messages" in tables and "uq_msg_idempotency" in _index_names(bind, "messages"):
        op.execute(sa.text("DROP INDEX IF EXISTS uq_msg_idempotency"))
    if "chat_rooms" in tables and "uq_chat_rooms_direct_pair_key" in _index_names(bind, "chat_rooms"):
        op.execute(sa.text("DROP INDEX IF EXISTS uq_chat_rooms_direct_pair_key"))
