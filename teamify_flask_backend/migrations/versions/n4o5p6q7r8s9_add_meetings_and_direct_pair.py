"""meetings, meeting_participants, direct DM pair key, session.meeting_id

Revision ID: n4o5p6q7r8s9
Revises: m3n4o5p6q7r8
Create Date: 2026-08-13
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


revision = "n4o5p6q7r8s9"
down_revision = "m3n4o5p6q7r8"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    tables = inspect(bind).get_table_names()

    if "chat_rooms" in tables:
        cols = {c["name"] for c in inspect(bind).get_columns("chat_rooms")}
        if "direct_pair_key" not in cols:
            with op.batch_alter_table("chat_rooms") as batch:
                batch.add_column(sa.Column("direct_pair_key", sa.String(length=64), nullable=True))
                batch.create_unique_constraint("uq_chat_rooms_direct_pair_key", ["direct_pair_key"])

    if "meetings" not in tables:
        op.create_table(
            "meetings",
            sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
            sa.Column("public_id", sa.String(length=36), nullable=False),
            sa.Column("title", sa.String(length=200), nullable=False),
            sa.Column("status", sa.String(length=20), nullable=False),
            sa.Column("starts_at", sa.DateTime(), nullable=True),
            sa.Column("host_user_id", sa.Integer(), nullable=False),
            sa.Column("project_id", sa.Integer(), nullable=True),
            sa.Column("chat_room_id", sa.Integer(), nullable=False),
            sa.Column("provider", sa.String(length=40), nullable=False),
            sa.Column("provider_room", sa.String(length=120), nullable=False),
            sa.Column("ended_at", sa.DateTime(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(["host_user_id"], ["users.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["project_id"], ["projects.id"], ondelete="SET NULL"),
            sa.ForeignKeyConstraint(["chat_room_id"], ["chat_rooms.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("public_id"),
        )
        op.create_index("ix_meetings_public_id", "meetings", ["public_id"])
        op.create_index("ix_meetings_host_user_id", "meetings", ["host_user_id"])
        op.create_index("ix_meetings_project_id", "meetings", ["project_id"])
        op.create_index("ix_meetings_chat_room_id", "meetings", ["chat_room_id"])

    if "meeting_participants" not in tables:
        op.create_table(
            "meeting_participants",
            sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
            sa.Column("meeting_id", sa.Integer(), nullable=False),
            sa.Column("user_id", sa.Integer(), nullable=False),
            sa.Column("role", sa.String(length=20), nullable=False),
            sa.Column("invite_status", sa.String(length=20), nullable=False),
            sa.Column("joined_at", sa.DateTime(), nullable=True),
            sa.Column("left_at", sa.DateTime(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(["meeting_id"], ["meetings.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("meeting_id", "user_id", name="uq_meeting_participant"),
        )
        op.create_index("ix_meeting_participants_meeting_id", "meeting_participants", ["meeting_id"])
        op.create_index("ix_meeting_participants_user_id", "meeting_participants", ["user_id"])
        op.create_index("ix_mp_user_status", "meeting_participants", ["user_id", "invite_status"])

    if "meeting_sessions" in tables:
        cols = {c["name"] for c in inspect(bind).get_columns("meeting_sessions")}
        if "meeting_id" not in cols:
            with op.batch_alter_table("meeting_sessions") as batch:
                batch.add_column(sa.Column("meeting_id", sa.Integer(), nullable=True))
                batch.create_foreign_key(
                    "fk_meeting_sessions_meeting_id",
                    "meetings",
                    ["meeting_id"],
                    ["id"],
                    ondelete="SET NULL",
                )
                batch.create_index("ix_meeting_sessions_meeting_id", ["meeting_id"])

    if "messages" in tables:
        cols = {c["name"] for c in inspect(bind).get_columns("messages")}
        if "idempotency_key" not in cols:
            with op.batch_alter_table("messages") as batch:
                batch.add_column(sa.Column("idempotency_key", sa.String(length=64), nullable=True))
                batch.create_index(
                    "uq_msg_idempotency",
                    ["room_id", "sender_id", "idempotency_key"],
                    unique=True,
                )


def downgrade():
    bind = op.get_bind()
    tables = inspect(bind).get_table_names()
    if "meeting_sessions" in tables:
        cols = {c["name"] for c in inspect(bind).get_columns("meeting_sessions")}
        if "meeting_id" in cols:
            with op.batch_alter_table("meeting_sessions") as batch:
                batch.drop_constraint("fk_meeting_sessions_meeting_id", type_="foreignkey")
                batch.drop_index("ix_meeting_sessions_meeting_id")
                batch.drop_column("meeting_id")
    if "meeting_participants" in tables:
        op.drop_table("meeting_participants")
    if "meetings" in tables:
        op.drop_table("meetings")
    if "chat_rooms" in tables:
        cols = {c["name"] for c in inspect(bind).get_columns("chat_rooms")}
        if "direct_pair_key" in cols:
            with op.batch_alter_table("chat_rooms") as batch:
                batch.drop_constraint("uq_chat_rooms_direct_pair_key", type_="unique")
                batch.drop_column("direct_pair_key")
