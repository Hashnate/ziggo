"""add_custom_fare_zones

Revision ID: 6f1a8c46b2a3
Revises: 5559a75b120f
Create Date: 2026-11-12 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '6f1a8c46b2a3'
down_revision: Union[str, None] = '5559a75b120f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'custom_fare_zones',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('name', sa.String(length=100), nullable=False),
        sa.Column('coordinates', sa.JSON(), nullable=False),
        sa.Column('color', sa.String(length=7), nullable=False, server_default='#2563eb'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('exempt_peak_surge', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('rates', sa.JSON(), nullable=False, server_default='{}'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.add_column('bookings', sa.Column('custom_fare_zone_id', sa.Integer(), sa.ForeignKey('custom_fare_zones.id', ondelete='SET NULL'), nullable=True))
    op.create_index('ix_bookings_custom_fare_zone_id', 'bookings', ['custom_fare_zone_id'])


def downgrade() -> None:
    op.drop_index('ix_bookings_custom_fare_zone_id', table_name='bookings')
    op.drop_column('bookings', 'custom_fare_zone_id')
    op.drop_table('custom_fare_zones')

