"""add_display_order_to_fare_settings

Revision ID: 5d812e5c8e3a
Revises: be8681e2640f
Create Date: 2026-06-22 14:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '5d812e5c8e3a'
down_revision: Union[str, None] = 'be8681e2640f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('fare_settings', sa.Column('display_order', sa.Integer(), nullable=False, server_default='0'))


def downgrade() -> None:
    op.drop_column('fare_settings', 'display_order')
