import asyncio
import httpx

async def main():
    # Login as driver phone 0755960594
    async with httpx.AsyncClient() as client:
        # Request OTP
        r1 = await client.post("http://localhost:8030/api/v1/auth/login", json={"phone_number": "0755960594"})
        print("Login:", r1.json())
        
        # Verify OTP (assumes test mode or 123456)
        r2 = await client.post("http://localhost:8030/api/v1/auth/verify", json={"phone_number": "0755960594", "otp": "123456"})
        print("Verify:", r2.json())
        
        token = r2.json().get("access_token")
        if not token:
            print("Failed to get token")
            return
            
        # Get bookings
        r3 = await client.get("http://localhost:8030/api/v1/bookings", headers={"Authorization": f"Bearer {token}"})
        print("Bookings status:", r3.status_code)
        
        data = r3.json()
        print("Bookings count:", len(data) if isinstance(data, list) else 0)
        
        if isinstance(data, list) and len(data) > 0:
            print("First booking:", data[0])

if __name__ == "__main__":
    asyncio.run(main())
