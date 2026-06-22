"""add_color_to_surge_zones

Revision ID: be8681e2640f
Revises: 942b4acbfae6
Create Date: 2026-06-22 13:08:49.270208

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = 'be8681e2640f'
down_revision: Union[str, None] = '942b4acbfae6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('surge_zones', sa.Column('color', sa.String(length=7), nullable=False, server_default='#dc3545'))


def downgrade() -> None:
    op.drop_column('surge_zones', 'color')
