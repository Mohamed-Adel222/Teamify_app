"""add university fields and notification preferences to users

Revision ID: m3n4o5p6q7r8
Revises: l2m3n4o5p6q7
Create Date: 2026-08-08

"""
from alembic import op
import sqlalchemy as sa


revision = "m3n4o5p6q7r8"
down_revision = "l2m3n4o5p6q7"
branch_labels = None
depends_on = None


def _new_columns():
    # Built fresh on each call: a Column instance can only be bound to one table.
    return [
        sa.Column("university_id", sa.String(length=64), nullable=True),
        sa.Column("university_name", sa.String(length=200), nullable=True),
        sa.Column(
            "is_custom_university",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.Column("notification_prefs", sa.JSON(), nullable=True),
    ]


def _existing_columns():
    insp = sa.inspect(op.get_bind())
    return {c["name"] for c in insp.get_columns("users")}


def upgrade():
    # The app also patches these columns in at boot for deploys that never run
    # Alembic, so only add what is actually missing.
    existing = _existing_columns()
    missing = [c for c in _new_columns() if c.name not in existing]
    if not missing:
        return
    with op.batch_alter_table("users", schema=None) as batch_op:
        for column in missing:
            batch_op.add_column(column)


def downgrade():
    existing = _existing_columns()
    with op.batch_alter_table("users", schema=None) as batch_op:
        for column in reversed(_new_columns()):
            if column.name in existing:
                batch_op.drop_column(column.name)
