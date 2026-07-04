"""Merge heads

Revision ID: db8cbf683762
Revises: f78bf9a8c39e, f857908b9499
Create Date: 2026-07-04 11:04:28.386188

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'db8cbf683762'
down_revision: Union[str, None] = ('f78bf9a8c39e', 'f857908b9499')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
