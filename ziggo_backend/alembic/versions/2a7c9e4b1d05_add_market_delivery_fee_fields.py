"""add_market_delivery_fee_fields

Adds the distance+weight delivery-fee fields:
- products.weight_kg
- market_orders.delivery_mode / delivery_distance_km / total_weight_kg

Revision ID: 2a7c9e4b1d05
Revises: 1f3155afef0d
Create Date: 2026-06-09 10:15:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '2a7c9e4b1d05'
down_revision: Union[str, None] = '1f3155afef0d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('products', sa.Column('weight_kg', sa.DECIMAL(precision=10, scale=3), nullable=True))
    op.add_column('market_orders', sa.Column('delivery_mode', sa.String(length=20), nullable=True))
    op.add_column('market_orders', sa.Column('delivery_distance_km', sa.DECIMAL(precision=10, scale=2), nullable=True))
    op.add_column('market_orders', sa.Column('total_weight_kg', sa.DECIMAL(precision=10, scale=3), nullable=True))


def downgrade() -> None:
    op.drop_column('market_orders', 'total_weight_kg')
    op.drop_column('market_orders', 'delivery_distance_km')
    op.drop_column('market_orders', 'delivery_mode')
    op.drop_column('products', 'weight_kg')
