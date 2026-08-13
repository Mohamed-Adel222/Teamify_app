"""add email_deliveries table and widen users.otp_code for hashed OTPs

Revision ID: n4o5p6q7r8s9
Revises: m3n4o5p6q7r8
Create Date: 2026-08-13

"""
from alembic import op
import sqlalchemy as sa


revision = "n4o5p6q7r8s9"
down_revision = "m3n4o5p6q7r8"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if "email_deliveries" not in tables:
        op.create_table(
            "email_deliveries",
            sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
            sa.Column("notification_id", sa.Integer(), nullable=True),
            sa.Column("user_id", sa.Integer(), nullable=True),
            sa.Column("recipient_email", sa.String(length=255), nullable=False),
            sa.Column("email_type", sa.String(length=50), nullable=False),
            sa.Column("status", sa.String(length=20), nullable=False),
            sa.Column("provider_message_id", sa.String(length=255), nullable=True),
            sa.Column("error_message", sa.Text(), nullable=True),
            sa.Column("skip_reason", sa.String(length=80), nullable=True),
            sa.Column("idempotency_key", sa.String(length=180), nullable=True),
            sa.Column("sent_at", sa.DateTime(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=True),
            sa.ForeignKeyConstraint(
                ["notification_id"],
                ["notifications.id"],
                ondelete="SET NULL",
            ),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("idempotency_key", name="uq_email_delivery_idempotency"),
        )
        op.create_index(
            "ix_email_delivery_notification",
            "email_deliveries",
            ["notification_id"],
        )
        op.create_index(
            "ix_email_delivery_user_created",
            "email_deliveries",
            ["user_id", "created_at"],
        )
        op.create_index(
            "ix_email_delivery_status",
            "email_deliveries",
            ["status"],
        )

    if "users" in tables:
        user_cols = {c["name"]: c for c in insp.get_columns("users")}
        otp_col = user_cols.get("otp_code")
        if otp_col is not None:
            dialect = bind.dialect.name
            if dialect == "postgresql":
                op.execute("ALTER TABLE users ALTER COLUMN otp_code TYPE VARCHAR(128)")
            elif dialect != "sqlite":
                with op.batch_alter_table("users", schema=None) as batch_op:
                    batch_op.alter_column(
                        "otp_code",
                        existing_type=sa.String(length=6),
                        type_=sa.String(length=128),
                        existing_nullable=True,
                    )


def downgrade():
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if "email_deliveries" in tables:
        op.drop_index("ix_email_delivery_status", table_name="email_deliveries")
        op.drop_index("ix_email_delivery_user_created", table_name="email_deliveries")
        op.drop_index("ix_email_delivery_notification", table_name="email_deliveries")
        op.drop_table("email_deliveries")

    if "users" in {t for t in tables}:
        dialect = bind.dialect.name
        if dialect == "postgresql":
            op.execute("ALTER TABLE users ALTER COLUMN otp_code TYPE VARCHAR(6)")
        elif dialect != "sqlite":
            with op.batch_alter_table("users", schema=None) as batch_op:
                batch_op.alter_column(
                    "otp_code",
                    existing_type=sa.String(length=128),
                    type_=sa.String(length=6),
                    existing_nullable=True,
                )
