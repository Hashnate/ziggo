"""add additional fields to event

Revision ID: f78bf9a8c39e
Revises: e72bf7a9c39d
Create Date: 2026-07-03 06:46:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'f78bf9a8c39e'
down_revision: Union[str, None] = 'e72bf7a9c39d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('events', sa.Column('additional_fields', sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column('events', 'additional_fields')
