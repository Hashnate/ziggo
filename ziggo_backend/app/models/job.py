"""Job roles / careers management models.

Supports publishing open roles from the Ziggo Admin Panel to the website careers
page, viewing role descriptions, and tracking candidate applications.
"""
from sqlalchemy import (
    Column,
    Integer,
    String,
    Boolean,
    DateTime,
    ForeignKey,
    Text,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from ..database import Base


class JobOpening(Base):
    __tablename__ = "job_openings"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(200), nullable=False)
    slug = Column(String(220), unique=True, index=True, nullable=False)
    department = Column(String(100), nullable=False, index=True)  # e.g. "Product Engineering", "Engineering", "Operations"
    location = Column(String(100), default="Colombo", nullable=False)
    employment_type = Column(String(50), default="Full Time", nullable=False)  # Full Time, Part Time, Contract, Remote, Internship
    overview = Column(Text, nullable=True)  # Short summary/intro paragraph for hero banner
    responsibilities = Column(Text, nullable=True)  # Formatted text / bullet points
    requirements = Column(Text, nullable=True)  # "You might be a fit if you have" items
    preferred_qualifications = Column(Text, nullable=True)  # "Preferred Qualifications" list
    apply_email = Column(String(200), default="careers@ziggo.lk", nullable=False)
    apply_url = Column(String(500), nullable=True)
    is_active = Column(Boolean, default=True, index=True, nullable=False)
    display_order = Column(Integer, default=0, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    applications = relationship(
        "JobApplication",
        back_populates="job",
        cascade="all, delete-orphan",
        order_by="JobApplication.created_at.desc()",
    )


class JobApplication(Base):
    __tablename__ = "job_applications"

    id = Column(Integer, primary_key=True, index=True)
    job_id = Column(Integer, ForeignKey("job_openings.id", ondelete="CASCADE"), nullable=True, index=True)
    job_title = Column(String(200), nullable=False)
    full_name = Column(String(120), nullable=False)
    email = Column(String(200), nullable=False)
    phone = Column(String(40), nullable=False)
    resume_url = Column(String(500), nullable=True)
    linkedin_url = Column(String(300), nullable=True)
    cover_note = Column(Text, nullable=True)
    status = Column(String(30), default="new", nullable=False)  # new, reviewed, shortlisted, rejected
    is_read = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    job = relationship("JobOpening", back_populates="applications")
