"""Add product offer/category/popular fields

Revision ID: b2f1a9c4d7e3
Revises: e104da0c7531
Create Date: 2026-06-09 12:10:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b2f1a9c4d7e3'
down_revision: Union[str, None] = 'e104da0c7531'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table('products', schema=None) as batch_op:
        batch_op.add_column(sa.Column('original_price', sa.DECIMAL(precision=10, scale=2), nullable=True))
        batch_op.add_column(sa.Column('category', sa.String(length=100), nullable=True))
        batch_op.add_column(
            sa.Column('is_popular', sa.Boolean(), nullable=True, server_default=sa.false())
        )


def downgrade() -> None:
    with op.batch_alter_table('products', schema=None) as batch_op:
        batch_op.drop_column('is_popular')
        batch_op.drop_column('category')
        batch_op.drop_column('original_price')
