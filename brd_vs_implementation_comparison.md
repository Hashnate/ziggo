| Req ID | Feature Description | Nature | Status | Implementation Details / Scope |
| :--- | :--- | :---: | :---: | :--- |
| **CD-01** | User registration (phone number + OTP, email/password) | **BRD** | **Completed** | Mobile app auth module (`lib/modules/auth`), backend auth router (`app/api/v1/auth.py`) |
| **CD-02** | Profile management (name, photo, contact details, saved places) | **BRD** | **Completed** | Screen `edit_profile_screen.dart` and backend customer profile updates |
| **CD-03** | Switch Passenger / Driver Mode using in-app toggle button | **BRD** | **Completed** | Mode-toggle navigation state in `lib/modules/common` navigation logic |
| **CD-04** | Set pickup & drop-off via GPS or map pin (Google Maps API) | **BRD** | **Completed** | Managed via `choose_location_screen.dart` and `location_search_screen.dart` using Google Maps SDK |
| **CD-05** | Choose vehicle type (for passengers) and fare estimate | **BRD** | **Completed** | Implemented in `vehicle_selection_screen.dart` and `fare_estimate_screen.dart` |
| **CD-06** | View upfront fare estimate and confirm ride booking | **BRD** | **Completed** | Upfront pricing calculation loaded in `confirm_pickup_screen.dart` |
| **CD-07** | Request a ride and match with nearest available driver | **BRD** | **Completed** | Handled by match-making dispatch loops in the backend (`app/api/v1/bookings.py`) |
| **CD-08** | Turn on/off availability (for drivers) | **BRD** | **Completed** | Online availability toggle switch in `driver_home_screen.dart` |
| **CD-09** | Accept or reject incoming ride requests (for drivers) | **BRD** | **Completed** | Incoming ride request popups and accept/reject actions in `driver_home_screen.dart` |
| **CD-10** | GPS navigation for pickups and drop-offs using Google Maps API | **BRD** | **Completed** | GPS navigation rendering using Google Maps SDK in `ride_tracking_screen.dart` |
| **CD-11** | Collect payment (cash, card, or wallet) and confirm payment | **BRD** | **Completed** | Trip completion slide triggers checkout / receipt screen in `driver_home_screen.dart` |
| **CD-12** | Payment processing via PayHere (cash/card/wallet payments) | **BRD** | **Completed** | Payment processing via PayHere supporting cash/card/wallet payments in `payhere_checkout_screen.dart` |
| **CD-13** | View earnings and trip history (for drivers) | **BRD** | **Completed** | Earnings summaries and trip history in `driver_earnings_screen.dart` and `driver_history_screen.dart` |
| **CD-14** | In-app communication (call) with the other party | **BRD** | **Completed** | In-app voice call triggers integrated via `url_launcher` on ride tracking screens |
| **CD-15** | Rate and review the other party after the trip | **BRD** | **Completed** | Mutual ratings & feedback screens (`rating_screen.dart` and `driver_rating_screen.dart`) |
| **CD-16** | View trip history and receipts (both customers and drivers) | **BRD** | **Completed** | Ride history listing screens (`ride_history_screen.dart` and `driver_history_screen.dart`) |
| **CD-17** | Emergency SOS button and share trip with contacts | **BRD** | **Completed** | Emergency SOS triggers in active trip screens and backend `/trip_share` location sharing |
| **CD-18** | Receive push notifications via Firebase for booking status, alerts | **BRD** | **Completed** | Push notifications handler in `notifications_provider.dart` and Firebase subscription stubs |
| **AD-01** | Secure admin login with role-based access control | **BRD** | **Completed** | Admin login sessions via secure signed cookies in `routes.py` and RBAC logic checks |
| **AD-02** | Dashboard showing active trips, online users, revenue, etc. | **BRD** | **Completed** | Interactive dashboard in `dashboard.html` showing active counts, revenue, and Chart.js graphs |
| **AD-03** | Manage customer/driver accounts (approve, suspend, delete) | **BRD** | **Completed** | Accounts management in admin views (`drivers.html`, `customers.html`) and backend CRUD routers |
| **AD-04** | Configure fare rules, promo codes, and discounts | **BRD** | **Completed** | Fare settings configuration, promo manager in settings tabs (`routes.py` and settings models) |
| **AD-05** | View and monitor all trips, including customer and driver actions | **BRD** | **Completed** | Centralized trips monitor table (`trips.html`) and backend real-time monitoring |
| **AD-06** | Manage complaints, disputes, and refunds | **BRD** | **Completed** | Support ticket/dispute resolutions under complaints management views (`complaints.html`) |
| **AD-07** | Reports and analytics for trips, revenue, driver performance | **BRD** | **Completed** | Analytical suites and database metrics summary routing in admin pages |
| **AD-08** | Manage commissions and driver payouts | **BRD** | **Completed** | Commission setup, driver balance payouts interfaces in `/admin/payouts` |
| **BE-01** | Authentication and authorization for all user roles (token-based) | **BRD** | **Completed** | JWT token-based authentication and dependency checks in `app/api/v1/auth.py` |
| **BE-02** | Ride-matching engine — locate nearest available drivers and dispatch | **BRD** | **Completed** | Match-making and location routing algorithm in backend bookings service |
| **BE-03** | Real-time location tracking and updates using Google Maps API | **BRD** | **Completed** | Real-time updates and location telemetry streamed via WebSockets `/ws` endpoints |
| **BE-04** | Fare calculation engine — distance, time, vehicle type, surge | **BRD** | **Completed** | Multi-factor pricing engine calculating base + distance + time + surge rates |
| **BE-05** | Payment processing and wallet management through PayHere API | **BRD** | **Completed** | Transactional database operations for wallets and PayHere callbacks in `/payments` |
| **BE-06** | Trip lifecycle management (requested → accepted → ongoing → complete) | **BRD** | **Completed** | Trip state machine managing booking lifecycles (`app/models/misc.py`) |
| **BE-07** | Notifications service via Firebase for push alerts | **BRD** | **Completed** | Firebase push notification worker with local console fallback logger |
| **BE-08** | Ratings and reviews storage and aggregation | **BRD** | **Completed** | Ratings and reviews aggregation, aggregate rating updates on database schemas |
| **BE-09** | Commission and payout calculation | **BRD** | **Completed** | Commission shares calculated dynamically on trip completion database triggers |
| **BE-10** | Data storage for users, trips, vehicles, transactions | **BRD** | **Completed** | SQLAlchemy models mapping PostgreSQL database tables for all super app schemas |
| **BE-11** | APIs consumed by Customer/Driver App and Admin Panel | **BRD** | **Completed** | RESTful endpoints in `app/api/v1/` serving JSON payloads to app/admin clients |
| **BE-12** | Logging, audit trail, and error handling | **BRD** | **Completed** | Audit logs, file-appended traceback handling, and centralized API error responses |
| **Food Delivery** | Order meals from 10,000+ local restaurants | **Additional** | **Completed** | Customer food checkout (`food_home_screen.dart`) and backend restaurant manager (`restaurant.py`) |
| **Merchant Admin** | Restaurant Menu and Order manager | **Additional** | **Completed** | Menu & orders control screens (`restaurant_home_screen.dart`, `restaurant_menu_screen.dart`) |
| **Mart Grocery** | Local groceries, dark stores & pharmacy products | **Additional** | **Completed** | Market catalog and cart checkouts (`market_home_screen.dart`, `market_checkout_screen.dart`) |
| **Mart Vendor** | Store catalog stock and product manager | **Additional** | **Completed** | Store inventory and stock manager screens (`market_vendor_home_screen.dart`) |
| **Parcel Flash** | Same-day courier deliveries (Document/S/M/L) | **Additional** | **Completed** | Same-day courier booking flow screens (`flash_home_screen.dart`, `flash_checkout_screen.dart`) |
| **Truck Mover** | Moving Lorries with 1-3 helpers option + insurance | **Additional** | **Completed** | Lorry variants select UI and helpers configurations screen (`vehicle_selection_screen.dart`) |
| **Gold Pass** | Subscriptions offering free delivery (LKR 549/mo) | **Additional** | **Completed** | Gold subscription checkout (`subscription_screen.dart`) and backend models (`misc.py`) |
| **QR Scan & Go** | Pay local merchants/drivers via scan codes | **Additional** | **Completed** | QR payment camera scanner and confirmation screens (`qr_pay_scan_screen.dart`, `qr_pay_confirm_screen.dart`) |
| **Incentives** | Driver quest incentives milestones | **Additional** | **Completed** | Quests/incentives trackers widgets in `driver_earnings_screen.dart` and database milestones |
| **Corporate accounts** | Ziggo for Business billing & Cost Centers | **Additional** | **Completed** | Ziggo for Business billing profiles in `additional_settings_screen.dart` and backend `corporate.py` models |
| **Admin CRUD** | Central Superadmin user management controls | **Additional** | **Completed** | Central Superadmin controls over other admins lists (`admins.html`) and backend CRUD actions in `routes.py` |
