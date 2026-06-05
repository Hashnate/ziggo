from sqlalchemy import (
    Column,
    Integer,
    String,
    DECIMAL,
    DateTime,
    ForeignKey,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from ..database import Base


class CorporateAccount(Base):
    __tablename__ = "corporate_accounts"

    id = Column(Integer, primary_key=True, index=True)
    company_name = Column(String(100), nullable=False)
    billing_email = Column(String(120))
    balance = Column(DECIMAL(10, 2), default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    members = relationship("CorporateMember", back_populates="corporate", cascade="all, delete-orphan")


class CorporateMember(Base):
    __tablename__ = "corporate_members"

    id = Column(Integer, primary_key=True, index=True)
    corporate_id = Column(Integer, ForeignKey("corporate_accounts.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False)
    status = Column(String(20), default="active")  # active, suspended
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    corporate = relationship("CorporateAccount", back_populates="members")
    user = relationship("User")
