"""Add rental_hourly_rate to FareSetting

Revision ID: 9f241f06dd78
Revises: db8cbf683762
Create Date: 2026-07-04 11:05:05.866597

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '9f241f06dd78'
down_revision: Union[str, None] = 'db8cbf683762'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('fare_settings', sa.Column('rental_hourly_rate', sa.DECIMAL(10, 2), nullable=True))


def downgrade() -> None:
    op.drop_column('fare_settings', 'rental_hourly_rate')
