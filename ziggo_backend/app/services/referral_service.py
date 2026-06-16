from decimal import Decimal
from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from ..models import User, Customer, ReferralBonus, ReferralStatus, WalletTransaction, Notification, Booking

async def process_referral_on_first_trip(db: AsyncSession, booking: Booking) -> None:
    """Check if the customer who completed this booking was referred by someone.
    If they have a pending referral bonus and this is their first completed ride,
    mark the bonus completed and credit both the referrer and referred user wallets.
    """
    customer_profile = booking.customer
    if not customer_profile:
        return
        
    referred_user_id = customer_profile.user_id
    
    # Fetch pending referral bonus for this referred user
    q = await db.execute(
        select(ReferralBonus)
        .where(
            ReferralBonus.referred_user_id == referred_user_id,
            ReferralBonus.status == ReferralStatus.pending
        )
    )
    referral_bonus = q.scalars().first()
    if not referral_bonus:
        return
        
    # Check completed bookings for this customer
    booking_q = await db.execute(
        select(Booking)
        .where(
            Booking.customer_id == booking.customer_id,
            Booking.status == "COMPLETED"
        )
    )
    completed_bookings = booking_q.scalars().all()
    
    # Since the current booking has been transitioned to COMPLETED in the database,
    # if it's the first completed booking, the total completed count should be exactly 1.
    if len(completed_bookings) > 1:
        return
        
    # Resolve payout
    referral_bonus.status = ReferralStatus.completed
    referral_bonus.paid_at = datetime.now(timezone.utc)
    
    # Fetch referrer and referred users/profiles using explicit queries to avoid async lazy loading errors
    referrer_q = await db.execute(select(User).where(User.id == referral_bonus.referrer_user_id))
    referrer_user = referrer_q.scalars().first()
    referrer_name = referrer_user.full_name or referrer_user.phone_number if referrer_user else "Referrer"

    referred_user_q = await db.execute(select(User).where(User.id == referred_user_id))
    referred_user = referred_user_q.scalars().first()
    referred_name = referred_user.full_name or referred_user.phone_number if referred_user else "Referred User"

    # 1. Credit referred user
    ref_cust_q = await db.execute(select(Customer).where(Customer.user_id == referred_user_id))
    ref_cust = ref_cust_q.scalars().first()
    if not ref_cust:
        ref_cust = Customer(user_id=referred_user_id)
        db.add(ref_cust)
        await db.flush()
        
    ref_cust.wallet_balance = (ref_cust.wallet_balance or Decimal("0.00")) + referral_bonus.referred_amount
    
    referred_txn = WalletTransaction(
        user_id=referred_user_id,
        amount=referral_bonus.referred_amount,
        type="credit",
        description=f"Referral signup bonus — referred by {referrer_name}",
        reference_id=f"REF_SIGNUP_{referral_bonus.id}",
        balance_after=ref_cust.wallet_balance
    )
    db.add(referred_txn)
    
    referred_notif = Notification(
        user_id=referred_user_id,
        title="Referral Bonus Credited!",
        body=f"Congratulations! You've received Rs.{referral_bonus.referred_amount:.2f} wallet credit for completing your first ride.",
        type="payment",
        is_read=False
    )
    db.add(referred_notif)
    
    # 2. Credit referrer
    ref_referrer_cust_q = await db.execute(select(Customer).where(Customer.user_id == referral_bonus.referrer_user_id))
    ref_referrer_cust = ref_referrer_cust_q.scalars().first()
    if not ref_referrer_cust:
        ref_referrer_cust = Customer(user_id=referral_bonus.referrer_user_id)
        db.add(ref_referrer_cust)
        await db.flush()
        
    ref_referrer_cust.wallet_balance = (ref_referrer_cust.wallet_balance or Decimal("0.00")) + referral_bonus.referrer_amount
    
    referrer_txn = WalletTransaction(
        user_id=referral_bonus.referrer_user_id,
        amount=referral_bonus.referrer_amount,
        type="credit",
        description=f"Referral reward — friend {referred_name} completed first ride",
        reference_id=f"REF_REWARD_{referral_bonus.id}",
        balance_after=ref_referrer_cust.wallet_balance
    )
    db.add(referrer_txn)
    
    referrer_notif = Notification(
        user_id=referral_bonus.referrer_user_id,
        title="Referral Reward Credited!",
        body=f"Your friend {referred_name} completed their first ride. Rs.{referral_bonus.referrer_amount:.2f} credited to your wallet.",
        type="payment",
        is_read=False
    )
    db.add(referrer_notif)
    
    await db.commit()
