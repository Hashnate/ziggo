"""add_menu_item_portions

Revision ID: 5559a75b120f
Revises: edeb844a1e65
Create Date: 2026-07-27 05:45:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '5559a75b120f'
down_revision: Union[str, None] = 'edeb844a1e65'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('menu_items', sa.Column('has_portions', sa.Boolean(), nullable=False, server_default='false'))
    op.add_column('menu_items', sa.Column('price_half', sa.Numeric(10, 2), nullable=True))
    op.add_column('food_order_items', sa.Column('portion', sa.String(length=20), nullable=True))


def downgrade() -> None:
    op.drop_column('food_order_items', 'portion')
    op.drop_column('menu_items', 'price_half')
    op.drop_column('menu_items', 'has_portions')
