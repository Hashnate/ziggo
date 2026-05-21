--
-- PostgreSQL database dump
--

\restrict eIxYYrYRKCKqu638opMLJpbnO05gJwicn4sjRE8nAIjB0sEhZeEuDYoTSTpishM

-- Dumped from database version 18.4
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

ALTER TABLE IF EXISTS ONLY public.wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.saved_addresses DROP CONSTRAINT IF EXISTS saved_addresses_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.restaurants DROP CONSTRAINT IF EXISTS restaurants_owner_id_fkey;
ALTER TABLE IF EXISTS ONLY public.referral_bonuses DROP CONSTRAINT IF EXISTS referral_bonuses_referrer_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.referral_bonuses DROP CONSTRAINT IF EXISTS referral_bonuses_referred_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.products DROP CONSTRAINT IF EXISTS products_vendor_id_fkey;
ALTER TABLE IF EXISTS ONLY public.payments DROP CONSTRAINT IF EXISTS payments_customer_id_fkey;
ALTER TABLE IF EXISTS ONLY public.payments DROP CONSTRAINT IF EXISTS payments_booking_id_fkey;
ALTER TABLE IF EXISTS ONLY public.notifications DROP CONSTRAINT IF EXISTS notifications_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.menu_items DROP CONSTRAINT IF EXISTS menu_items_restaurant_id_fkey;
ALTER TABLE IF EXISTS ONLY public.menu_items DROP CONSTRAINT IF EXISTS menu_items_category_id_fkey;
ALTER TABLE IF EXISTS ONLY public.menu_categories DROP CONSTRAINT IF EXISTS menu_categories_restaurant_id_fkey;
ALTER TABLE IF EXISTS ONLY public.market_vendors DROP CONSTRAINT IF EXISTS market_vendors_owner_id_fkey;
ALTER TABLE IF EXISTS ONLY public.market_orders DROP CONSTRAINT IF EXISTS market_orders_vendor_id_fkey;
ALTER TABLE IF EXISTS ONLY public.market_orders DROP CONSTRAINT IF EXISTS market_orders_driver_id_fkey;
ALTER TABLE IF EXISTS ONLY public.market_orders DROP CONSTRAINT IF EXISTS market_orders_customer_id_fkey;
ALTER TABLE IF EXISTS ONLY public.market_order_items DROP CONSTRAINT IF EXISTS market_order_items_product_id_fkey;
ALTER TABLE IF EXISTS ONLY public.market_order_items DROP CONSTRAINT IF EXISTS market_order_items_order_id_fkey;
ALTER TABLE IF EXISTS ONLY public.food_orders DROP CONSTRAINT IF EXISTS food_orders_restaurant_id_fkey;
ALTER TABLE IF EXISTS ONLY public.food_orders DROP CONSTRAINT IF EXISTS food_orders_driver_id_fkey;
ALTER TABLE IF EXISTS ONLY public.food_orders DROP CONSTRAINT IF EXISTS food_orders_customer_id_fkey;
ALTER TABLE IF EXISTS ONLY public.food_order_items DROP CONSTRAINT IF EXISTS food_order_items_order_id_fkey;
ALTER TABLE IF EXISTS ONLY public.food_order_items DROP CONSTRAINT IF EXISTS food_order_items_menu_item_id_fkey;
ALTER TABLE IF EXISTS ONLY public.event_ticket_tiers DROP CONSTRAINT IF EXISTS event_ticket_tiers_event_id_fkey;
ALTER TABLE IF EXISTS ONLY public.drivers DROP CONSTRAINT IF EXISTS drivers_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.driver_documents DROP CONSTRAINT IF EXISTS driver_documents_verified_by_fkey;
ALTER TABLE IF EXISTS ONLY public.driver_documents DROP CONSTRAINT IF EXISTS driver_documents_driver_id_fkey;
ALTER TABLE IF EXISTS ONLY public.customers DROP CONSTRAINT IF EXISTS customers_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.complaints DROP CONSTRAINT IF EXISTS complaints_user_id_fkey;
ALTER TABLE IF EXISTS ONLY public.complaints DROP CONSTRAINT IF EXISTS complaints_booking_id_fkey;
ALTER TABLE IF EXISTS ONLY public.complaints DROP CONSTRAINT IF EXISTS complaints_assigned_to_fkey;
ALTER TABLE IF EXISTS ONLY public.bookings DROP CONSTRAINT IF EXISTS bookings_driver_id_fkey;
ALTER TABLE IF EXISTS ONLY public.bookings DROP CONSTRAINT IF EXISTS bookings_customer_id_fkey;
DROP INDEX IF EXISTS public.ix_wallet_transactions_id;
DROP INDEX IF EXISTS public.ix_users_phone_number;
DROP INDEX IF EXISTS public.ix_users_id;
DROP INDEX IF EXISTS public.ix_saved_addresses_id;
DROP INDEX IF EXISTS public.ix_restaurants_id;
DROP INDEX IF EXISTS public.ix_referral_bonuses_status;
DROP INDEX IF EXISTS public.ix_referral_bonuses_referrer_user_id;
DROP INDEX IF EXISTS public.ix_referral_bonuses_id;
DROP INDEX IF EXISTS public.ix_promo_codes_id;
DROP INDEX IF EXISTS public.ix_promo_codes_code;
DROP INDEX IF EXISTS public.ix_products_id;
DROP INDEX IF EXISTS public.ix_payments_id;
DROP INDEX IF EXISTS public.ix_otp_codes_phone_number;
DROP INDEX IF EXISTS public.ix_otp_codes_id;
DROP INDEX IF EXISTS public.ix_notifications_id;
DROP INDEX IF EXISTS public.ix_menu_items_id;
DROP INDEX IF EXISTS public.ix_menu_categories_id;
DROP INDEX IF EXISTS public.ix_market_vendors_id;
DROP INDEX IF EXISTS public.ix_market_orders_status;
DROP INDEX IF EXISTS public.ix_market_orders_order_ref;
DROP INDEX IF EXISTS public.ix_market_orders_id;
DROP INDEX IF EXISTS public.ix_market_order_items_id;
DROP INDEX IF EXISTS public.ix_food_orders_status;
DROP INDEX IF EXISTS public.ix_food_orders_order_ref;
DROP INDEX IF EXISTS public.ix_food_orders_id;
DROP INDEX IF EXISTS public.ix_food_order_items_id;
DROP INDEX IF EXISTS public.ix_flash_weight_tiers_id;
DROP INDEX IF EXISTS public.ix_fare_settings_service_type;
DROP INDEX IF EXISTS public.ix_fare_settings_id;
DROP INDEX IF EXISTS public.ix_events_starts_at;
DROP INDEX IF EXISTS public.ix_events_is_published;
DROP INDEX IF EXISTS public.ix_events_id;
DROP INDEX IF EXISTS public.ix_event_ticket_tiers_id;
DROP INDEX IF EXISTS public.ix_drivers_id;
DROP INDEX IF EXISTS public.ix_driver_documents_id;
DROP INDEX IF EXISTS public.ix_customers_id;
DROP INDEX IF EXISTS public.ix_complaints_id;
DROP INDEX IF EXISTS public.ix_bookings_status;
DROP INDEX IF EXISTS public.ix_bookings_is_flash;
DROP INDEX IF EXISTS public.ix_bookings_id;
DROP INDEX IF EXISTS public.ix_bookings_booking_ref;
ALTER TABLE IF EXISTS ONLY public.wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_pkey;
ALTER TABLE IF EXISTS ONLY public.users DROP CONSTRAINT IF EXISTS users_pkey;
ALTER TABLE IF EXISTS ONLY public.referral_bonuses DROP CONSTRAINT IF EXISTS uq_referral_referred_user;
ALTER TABLE IF EXISTS ONLY public.saved_addresses DROP CONSTRAINT IF EXISTS saved_addresses_pkey;
ALTER TABLE IF EXISTS ONLY public.restaurants DROP CONSTRAINT IF EXISTS restaurants_pkey;
ALTER TABLE IF EXISTS ONLY public.referral_bonuses DROP CONSTRAINT IF EXISTS referral_bonuses_pkey;
ALTER TABLE IF EXISTS ONLY public.promo_codes DROP CONSTRAINT IF EXISTS promo_codes_pkey;
ALTER TABLE IF EXISTS ONLY public.products DROP CONSTRAINT IF EXISTS products_pkey;
ALTER TABLE IF EXISTS ONLY public.payments DROP CONSTRAINT IF EXISTS payments_pkey;
ALTER TABLE IF EXISTS ONLY public.otp_codes DROP CONSTRAINT IF EXISTS otp_codes_pkey;
ALTER TABLE IF EXISTS ONLY public.notifications DROP CONSTRAINT IF EXISTS notifications_pkey;
ALTER TABLE IF EXISTS ONLY public.menu_items DROP CONSTRAINT IF EXISTS menu_items_pkey;
ALTER TABLE IF EXISTS ONLY public.menu_categories DROP CONSTRAINT IF EXISTS menu_categories_pkey;
ALTER TABLE IF EXISTS ONLY public.market_vendors DROP CONSTRAINT IF EXISTS market_vendors_pkey;
ALTER TABLE IF EXISTS ONLY public.market_orders DROP CONSTRAINT IF EXISTS market_orders_pkey;
ALTER TABLE IF EXISTS ONLY public.market_order_items DROP CONSTRAINT IF EXISTS market_order_items_pkey;
ALTER TABLE IF EXISTS ONLY public.food_orders DROP CONSTRAINT IF EXISTS food_orders_pkey;
ALTER TABLE IF EXISTS ONLY public.food_order_items DROP CONSTRAINT IF EXISTS food_order_items_pkey;
ALTER TABLE IF EXISTS ONLY public.flash_weight_tiers DROP CONSTRAINT IF EXISTS flash_weight_tiers_pkey;
ALTER TABLE IF EXISTS ONLY public.fare_settings DROP CONSTRAINT IF EXISTS fare_settings_pkey;
ALTER TABLE IF EXISTS ONLY public.events DROP CONSTRAINT IF EXISTS events_pkey;
ALTER TABLE IF EXISTS ONLY public.event_ticket_tiers DROP CONSTRAINT IF EXISTS event_ticket_tiers_pkey;
ALTER TABLE IF EXISTS ONLY public.drivers DROP CONSTRAINT IF EXISTS drivers_vehicle_number_key;
ALTER TABLE IF EXISTS ONLY public.drivers DROP CONSTRAINT IF EXISTS drivers_user_id_key;
ALTER TABLE IF EXISTS ONLY public.drivers DROP CONSTRAINT IF EXISTS drivers_pkey;
ALTER TABLE IF EXISTS ONLY public.drivers DROP CONSTRAINT IF EXISTS drivers_nic_number_key;
ALTER TABLE IF EXISTS ONLY public.drivers DROP CONSTRAINT IF EXISTS drivers_license_number_key;
ALTER TABLE IF EXISTS ONLY public.driver_documents DROP CONSTRAINT IF EXISTS driver_documents_pkey;
ALTER TABLE IF EXISTS ONLY public.customers DROP CONSTRAINT IF EXISTS customers_user_id_key;
ALTER TABLE IF EXISTS ONLY public.customers DROP CONSTRAINT IF EXISTS customers_pkey;
ALTER TABLE IF EXISTS ONLY public.complaints DROP CONSTRAINT IF EXISTS complaints_pkey;
ALTER TABLE IF EXISTS ONLY public.bookings DROP CONSTRAINT IF EXISTS bookings_pkey;
ALTER TABLE IF EXISTS public.wallet_transactions ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.users ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.saved_addresses ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.restaurants ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.referral_bonuses ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.promo_codes ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.products ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.payments ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.otp_codes ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.notifications ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.menu_items ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.menu_categories ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.market_vendors ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.market_orders ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.market_order_items ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.food_orders ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.food_order_items ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.flash_weight_tiers ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.fare_settings ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.events ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.event_ticket_tiers ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.drivers ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.driver_documents ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.customers ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.complaints ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.bookings ALTER COLUMN id DROP DEFAULT;
DROP SEQUENCE IF EXISTS public.wallet_transactions_id_seq;
DROP TABLE IF EXISTS public.wallet_transactions;
DROP SEQUENCE IF EXISTS public.users_id_seq;
DROP TABLE IF EXISTS public.users;
DROP SEQUENCE IF EXISTS public.saved_addresses_id_seq;
DROP TABLE IF EXISTS public.saved_addresses;
DROP SEQUENCE IF EXISTS public.restaurants_id_seq;
DROP TABLE IF EXISTS public.restaurants;
DROP SEQUENCE IF EXISTS public.referral_bonuses_id_seq;
DROP TABLE IF EXISTS public.referral_bonuses;
DROP SEQUENCE IF EXISTS public.promo_codes_id_seq;
DROP TABLE IF EXISTS public.promo_codes;
DROP SEQUENCE IF EXISTS public.products_id_seq;
DROP TABLE IF EXISTS public.products;
DROP SEQUENCE IF EXISTS public.payments_id_seq;
DROP TABLE IF EXISTS public.payments;
DROP SEQUENCE IF EXISTS public.otp_codes_id_seq;
DROP TABLE IF EXISTS public.otp_codes;
DROP SEQUENCE IF EXISTS public.notifications_id_seq;
DROP TABLE IF EXISTS public.notifications;
DROP SEQUENCE IF EXISTS public.menu_items_id_seq;
DROP TABLE IF EXISTS public.menu_items;
DROP SEQUENCE IF EXISTS public.menu_categories_id_seq;
DROP TABLE IF EXISTS public.menu_categories;
DROP SEQUENCE IF EXISTS public.market_vendors_id_seq;
DROP TABLE IF EXISTS public.market_vendors;
DROP SEQUENCE IF EXISTS public.market_orders_id_seq;
DROP TABLE IF EXISTS public.market_orders;
DROP SEQUENCE IF EXISTS public.market_order_items_id_seq;
DROP TABLE IF EXISTS public.market_order_items;
DROP SEQUENCE IF EXISTS public.food_orders_id_seq;
DROP TABLE IF EXISTS public.food_orders;
DROP SEQUENCE IF EXISTS public.food_order_items_id_seq;
DROP TABLE IF EXISTS public.food_order_items;
DROP SEQUENCE IF EXISTS public.flash_weight_tiers_id_seq;
DROP TABLE IF EXISTS public.flash_weight_tiers;
DROP SEQUENCE IF EXISTS public.fare_settings_id_seq;
DROP TABLE IF EXISTS public.fare_settings;
DROP SEQUENCE IF EXISTS public.events_id_seq;
DROP TABLE IF EXISTS public.events;
DROP SEQUENCE IF EXISTS public.event_ticket_tiers_id_seq;
DROP TABLE IF EXISTS public.event_ticket_tiers;
DROP SEQUENCE IF EXISTS public.drivers_id_seq;
DROP TABLE IF EXISTS public.drivers;
DROP SEQUENCE IF EXISTS public.driver_documents_id_seq;
DROP TABLE IF EXISTS public.driver_documents;
DROP SEQUENCE IF EXISTS public.customers_id_seq;
DROP TABLE IF EXISTS public.customers;
DROP SEQUENCE IF EXISTS public.complaints_id_seq;
DROP TABLE IF EXISTS public.complaints;
DROP SEQUENCE IF EXISTS public.bookings_id_seq;
DROP TABLE IF EXISTS public.bookings;
DROP TYPE IF EXISTS public.user_role;
DROP TYPE IF EXISTS public.referral_status;
DROP TYPE IF EXISTS public.referral_kind;
DROP TYPE IF EXISTS public.market_order_status;
DROP TYPE IF EXISTS public.food_order_status;
DROP TYPE IF EXISTS public.driver_status;
DROP TYPE IF EXISTS public.booking_status;
--
-- Name: booking_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.booking_status AS ENUM (
    'SEARCHING',
    'ACCEPTED',
    'ARRIVED',
    'STARTED',
    'COMPLETED',
    'CANCELLED',
    'PAYMENT_PENDING'
);


--
-- Name: driver_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.driver_status AS ENUM (
    'PENDING',
    'APPROVED',
    'REJECTED',
    'SUSPENDED'
);


--
-- Name: food_order_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.food_order_status AS ENUM (
    'PENDING',
    'CONFIRMED',
    'PREPARING',
    'READY_FOR_PICKUP',
    'OUT_FOR_DELIVERY',
    'DELIVERED',
    'CANCELLED'
);


--
-- Name: market_order_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.market_order_status AS ENUM (
    'PENDING',
    'CONFIRMED',
    'PROCESSING',
    'READY_FOR_PICKUP',
    'OUT_FOR_DELIVERY',
    'SHIPPED',
    'DELIVERED',
    'CANCELLED'
);


--
-- Name: referral_kind; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.referral_kind AS ENUM (
    'CUSTOMER',
    'DRIVER'
);


--
-- Name: referral_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.referral_status AS ENUM (
    'PENDING',
    'PAID',
    'VOIDED'
);


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'CUSTOMER',
    'DRIVER',
    'ADMIN',
    'RESTAURANT_OWNER',
    'MARKET_OWNER'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: bookings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bookings (
    id integer NOT NULL,
    booking_ref character varying(20),
    customer_id integer,
    driver_id integer,
    pickup_lat numeric(10,7),
    pickup_lng numeric(10,7),
    pickup_address text,
    drop_lat numeric(10,7),
    drop_lng numeric(10,7),
    drop_address text,
    service_type character varying(20),
    trip_type character varying(20) NOT NULL,
    status public.booking_status,
    fare_amount numeric(10,2),
    distance_km numeric(8,2),
    duration_min integer,
    payment_method character varying(20),
    payment_status character varying(20),
    promo_code character varying(50),
    discount_amount numeric(10,2),
    final_amount numeric(10,2),
    platform_fee numeric(10,2),
    driver_earnings numeric(10,2),
    booked_at timestamp with time zone DEFAULT now(),
    accepted_at timestamp with time zone,
    arrived_at timestamp with time zone,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    cancelled_at timestamp with time zone,
    cancelled_by character varying(20),
    cancellation_reason text,
    customer_rating integer,
    driver_rating integer,
    customer_feedback text,
    driver_feedback text,
    is_flash boolean,
    parcel_type character varying(50),
    parcel_weight_kg numeric(6,2),
    receiver_name character varying(100),
    receiver_phone character varying(20),
    parcel_instructions text,
    is_rental boolean DEFAULT false NOT NULL,
    rental_hours integer,
    is_event boolean DEFAULT false NOT NULL,
    scheduled_at timestamp with time zone,
    event_note text
);


--
-- Name: bookings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bookings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bookings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bookings_id_seq OWNED BY public.bookings.id;


--
-- Name: complaints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.complaints (
    id integer NOT NULL,
    user_id integer,
    booking_id integer,
    category character varying(50),
    subject character varying(200),
    description text,
    attachment_url character varying(255),
    status character varying(20),
    assigned_to integer,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: complaints_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.complaints_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: complaints_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.complaints_id_seq OWNED BY public.complaints.id;


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id integer NOT NULL,
    user_id integer,
    default_payment_method character varying(20),
    wallet_balance numeric(10,2),
    notification_token character varying(255),
    gold_member boolean,
    gold_expires_at timestamp with time zone
);


--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customers_id_seq OWNED BY public.customers.id;


--
-- Name: driver_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.driver_documents (
    id integer NOT NULL,
    driver_id integer,
    document_type character varying(50),
    document_url character varying(255),
    is_verified boolean,
    verified_by integer,
    verified_at timestamp with time zone,
    uploaded_at timestamp with time zone DEFAULT now()
);


--
-- Name: driver_documents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.driver_documents_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: driver_documents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.driver_documents_id_seq OWNED BY public.driver_documents.id;


--
-- Name: drivers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drivers (
    id integer NOT NULL,
    user_id integer,
    nic_number character varying(20),
    license_number character varying(50),
    vehicle_type character varying(20),
    vehicle_number character varying(20),
    vehicle_model character varying(100),
    vehicle_color character varying(50),
    is_approved boolean,
    is_online boolean,
    current_lat numeric(10,7),
    current_lng numeric(10,7),
    last_location_update timestamp with time zone,
    total_earnings numeric(12,2),
    today_earnings numeric(10,2),
    today_rides integer,
    acceptance_rate numeric(5,2),
    status public.driver_status,
    approved_at timestamp with time zone
);


--
-- Name: drivers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.drivers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: drivers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.drivers_id_seq OWNED BY public.drivers.id;


--
-- Name: event_ticket_tiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_ticket_tiers (
    id integer NOT NULL,
    event_id integer,
    name character varying(50) NOT NULL,
    price numeric(10,2) NOT NULL,
    capacity integer,
    description text
);


--
-- Name: event_ticket_tiers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.event_ticket_tiers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: event_ticket_tiers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.event_ticket_tiers_id_seq OWNED BY public.event_ticket_tiers.id;


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id integer NOT NULL,
    name character varying(200) NOT NULL,
    description text,
    venue character varying(200),
    city character varying(80),
    image_url character varying(500),
    organizer_name character varying(100),
    organizer_phone character varying(20),
    starts_at timestamp with time zone NOT NULL,
    ends_at timestamp with time zone,
    is_published boolean,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.events_id_seq OWNED BY public.events.id;


--
-- Name: fare_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fare_settings (
    id integer NOT NULL,
    service_type character varying(20),
    base_fare numeric(10,2),
    per_km_rate numeric(10,2),
    per_minute_rate numeric(10,2),
    min_fare numeric(10,2),
    platform_fee_percent numeric(5,2),
    surge_multiplier numeric(3,2),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: fare_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fare_settings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fare_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fare_settings_id_seq OWNED BY public.fare_settings.id;


--
-- Name: flash_weight_tiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flash_weight_tiers (
    id integer NOT NULL,
    label character varying(40) NOT NULL,
    min_weight_kg numeric(6,2) NOT NULL,
    max_weight_kg numeric(6,2),
    representative_weight_kg numeric(6,2) NOT NULL,
    surcharge numeric(10,2) NOT NULL,
    icon character varying(40) NOT NULL,
    display_order integer NOT NULL,
    is_active boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: flash_weight_tiers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flash_weight_tiers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flash_weight_tiers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flash_weight_tiers_id_seq OWNED BY public.flash_weight_tiers.id;


--
-- Name: food_order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.food_order_items (
    id integer NOT NULL,
    order_id integer,
    menu_item_id integer,
    quantity integer NOT NULL,
    price_at_order numeric(10,2) NOT NULL,
    notes character varying(255)
);


--
-- Name: food_order_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.food_order_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: food_order_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.food_order_items_id_seq OWNED BY public.food_order_items.id;


--
-- Name: food_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.food_orders (
    id integer NOT NULL,
    order_ref character varying(20),
    customer_id integer,
    restaurant_id integer,
    driver_id integer,
    status public.food_order_status,
    total_amount numeric(10,2),
    delivery_fee numeric(10,2),
    tax_amount numeric(10,2),
    discount_amount numeric(10,2),
    final_amount numeric(10,2),
    delivery_address text,
    delivery_lat numeric(10,7),
    delivery_lng numeric(10,7),
    payment_method character varying(20),
    payment_status character varying(20),
    instructions text,
    cancellation_reason text,
    created_at timestamp with time zone DEFAULT now(),
    confirmed_at timestamp with time zone,
    ready_at timestamp with time zone,
    picked_up_at timestamp with time zone,
    delivered_at timestamp with time zone
);


--
-- Name: food_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.food_orders_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: food_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.food_orders_id_seq OWNED BY public.food_orders.id;


--
-- Name: market_order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.market_order_items (
    id integer NOT NULL,
    order_id integer,
    product_id integer,
    quantity integer NOT NULL,
    price_at_order numeric(10,2) NOT NULL
);


--
-- Name: market_order_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.market_order_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: market_order_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.market_order_items_id_seq OWNED BY public.market_order_items.id;


--
-- Name: market_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.market_orders (
    id integer NOT NULL,
    order_ref character varying(20),
    customer_id integer,
    vendor_id integer,
    driver_id integer,
    status public.market_order_status,
    total_amount numeric(10,2),
    delivery_fee numeric(10,2),
    final_amount numeric(10,2),
    delivery_address text,
    delivery_lat numeric(10,7),
    delivery_lng numeric(10,7),
    payment_method character varying(20),
    payment_status character varying(20),
    instructions text,
    cancellation_reason text,
    created_at timestamp with time zone DEFAULT now(),
    confirmed_at timestamp with time zone,
    ready_at timestamp with time zone,
    picked_up_at timestamp with time zone,
    delivered_at timestamp with time zone
);


--
-- Name: market_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.market_orders_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: market_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.market_orders_id_seq OWNED BY public.market_orders.id;


--
-- Name: market_vendors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.market_vendors (
    id integer NOT NULL,
    name character varying(200) NOT NULL,
    description text,
    category character varying(100),
    address character varying(500),
    lat numeric(10,7),
    lng numeric(10,7),
    phone_number character varying(20),
    image_url character varying(255),
    rating numeric(3,2),
    is_active boolean,
    is_open boolean,
    opening_time character varying(10),
    closing_time character varying(10),
    delivery_fee numeric(10,2),
    eta_minutes integer,
    owner_id integer,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: market_vendors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.market_vendors_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: market_vendors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.market_vendors_id_seq OWNED BY public.market_vendors.id;


--
-- Name: menu_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menu_categories (
    id integer NOT NULL,
    restaurant_id integer,
    name character varying(100) NOT NULL,
    description character varying(500),
    display_order integer,
    is_active boolean
);


--
-- Name: menu_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.menu_categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: menu_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.menu_categories_id_seq OWNED BY public.menu_categories.id;


--
-- Name: menu_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menu_items (
    id integer NOT NULL,
    restaurant_id integer,
    category_id integer,
    name character varying(200) NOT NULL,
    description text,
    price numeric(10,2) NOT NULL,
    image_url character varying(255),
    is_available boolean,
    is_veg boolean,
    calories integer,
    prep_time_min integer
);


--
-- Name: menu_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.menu_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: menu_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.menu_items_id_seq OWNED BY public.menu_items.id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id integer NOT NULL,
    user_id integer,
    title character varying(200),
    body text,
    type character varying(50),
    data text,
    is_read boolean,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notifications_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notifications_id_seq OWNED BY public.notifications.id;


--
-- Name: otp_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.otp_codes (
    id integer NOT NULL,
    phone_number character varying(20) NOT NULL,
    code character varying(10) NOT NULL,
    is_used boolean,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: otp_codes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.otp_codes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: otp_codes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.otp_codes_id_seq OWNED BY public.otp_codes.id;


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id integer NOT NULL,
    booking_id integer,
    customer_id integer,
    amount numeric(10,2),
    payment_method character varying(20),
    transaction_id character varying(100),
    payment_gateway_response text,
    status character varying(20),
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: payments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payments_id_seq OWNED BY public.payments.id;


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id integer NOT NULL,
    vendor_id integer,
    name character varying(200) NOT NULL,
    description text,
    price numeric(10,2) NOT NULL,
    stock_quantity integer,
    image_url character varying(255),
    unit character varying(20),
    is_available boolean,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.products_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- Name: promo_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promo_codes (
    id integer NOT NULL,
    code character varying(50),
    description text,
    discount_type character varying(20),
    discount_value numeric(10,2),
    min_order_amount numeric(10,2),
    max_discount numeric(10,2),
    usage_limit integer,
    used_count integer,
    valid_from timestamp with time zone,
    valid_to timestamp with time zone,
    is_active boolean
);


--
-- Name: promo_codes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.promo_codes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: promo_codes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.promo_codes_id_seq OWNED BY public.promo_codes.id;


--
-- Name: referral_bonuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.referral_bonuses (
    id integer NOT NULL,
    referrer_user_id integer NOT NULL,
    referred_user_id integer NOT NULL,
    kind public.referral_kind NOT NULL,
    referrer_amount numeric(10,2) NOT NULL,
    referred_amount numeric(10,2) NOT NULL,
    status public.referral_status NOT NULL,
    trigger_description character varying(255),
    created_at timestamp with time zone DEFAULT now(),
    paid_at timestamp with time zone
);


--
-- Name: referral_bonuses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.referral_bonuses_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: referral_bonuses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.referral_bonuses_id_seq OWNED BY public.referral_bonuses.id;


--
-- Name: restaurants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.restaurants (
    id integer NOT NULL,
    name character varying(200) NOT NULL,
    description text,
    address character varying(500),
    lat numeric(10,7),
    lng numeric(10,7),
    phone_number character varying(20),
    email character varying(120),
    image_url character varying(255),
    rating numeric(3,2),
    is_active boolean,
    is_open boolean,
    opening_time character varying(10),
    closing_time character varying(10),
    delivery_fee numeric(10,2),
    cuisine character varying(100),
    eta_minutes integer,
    owner_id integer,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: restaurants_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.restaurants_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: restaurants_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.restaurants_id_seq OWNED BY public.restaurants.id;


--
-- Name: saved_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saved_addresses (
    id integer NOT NULL,
    user_id integer,
    label character varying(50),
    address character varying(255),
    lat numeric(10,7),
    lng numeric(10,7),
    is_default boolean,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: saved_addresses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.saved_addresses_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: saved_addresses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.saved_addresses_id_seq OWNED BY public.saved_addresses.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer NOT NULL,
    phone_number character varying(20) NOT NULL,
    role public.user_role NOT NULL,
    full_name character varying(100),
    email character varying(120),
    profile_photo character varying(255),
    rating numeric(3,2),
    total_rides integer,
    is_active boolean,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    referral_code character varying(16),
    referred_by_user_id integer
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: wallet_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallet_transactions (
    id integer NOT NULL,
    user_id integer,
    amount numeric(10,2),
    type character varying(20),
    description text,
    reference_id character varying(100),
    balance_after numeric(10,2),
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: wallet_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wallet_transactions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wallet_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wallet_transactions_id_seq OWNED BY public.wallet_transactions.id;


--
-- Name: bookings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings ALTER COLUMN id SET DEFAULT nextval('public.bookings_id_seq'::regclass);


--
-- Name: complaints id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints ALTER COLUMN id SET DEFAULT nextval('public.complaints_id_seq'::regclass);


--
-- Name: customers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers ALTER COLUMN id SET DEFAULT nextval('public.customers_id_seq'::regclass);


--
-- Name: driver_documents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_documents ALTER COLUMN id SET DEFAULT nextval('public.driver_documents_id_seq'::regclass);


--
-- Name: drivers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers ALTER COLUMN id SET DEFAULT nextval('public.drivers_id_seq'::regclass);


--
-- Name: event_ticket_tiers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_ticket_tiers ALTER COLUMN id SET DEFAULT nextval('public.event_ticket_tiers_id_seq'::regclass);


--
-- Name: events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events ALTER COLUMN id SET DEFAULT nextval('public.events_id_seq'::regclass);


--
-- Name: fare_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fare_settings ALTER COLUMN id SET DEFAULT nextval('public.fare_settings_id_seq'::regclass);


--
-- Name: flash_weight_tiers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flash_weight_tiers ALTER COLUMN id SET DEFAULT nextval('public.flash_weight_tiers_id_seq'::regclass);


--
-- Name: food_order_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_order_items ALTER COLUMN id SET DEFAULT nextval('public.food_order_items_id_seq'::regclass);


--
-- Name: food_orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_orders ALTER COLUMN id SET DEFAULT nextval('public.food_orders_id_seq'::regclass);


--
-- Name: market_order_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_order_items ALTER COLUMN id SET DEFAULT nextval('public.market_order_items_id_seq'::regclass);


--
-- Name: market_orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_orders ALTER COLUMN id SET DEFAULT nextval('public.market_orders_id_seq'::regclass);


--
-- Name: market_vendors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_vendors ALTER COLUMN id SET DEFAULT nextval('public.market_vendors_id_seq'::regclass);


--
-- Name: menu_categories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_categories ALTER COLUMN id SET DEFAULT nextval('public.menu_categories_id_seq'::regclass);


--
-- Name: menu_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items ALTER COLUMN id SET DEFAULT nextval('public.menu_items_id_seq'::regclass);


--
-- Name: notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications ALTER COLUMN id SET DEFAULT nextval('public.notifications_id_seq'::regclass);


--
-- Name: otp_codes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.otp_codes ALTER COLUMN id SET DEFAULT nextval('public.otp_codes_id_seq'::regclass);


--
-- Name: payments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments ALTER COLUMN id SET DEFAULT nextval('public.payments_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: promo_codes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_codes ALTER COLUMN id SET DEFAULT nextval('public.promo_codes_id_seq'::regclass);


--
-- Name: referral_bonuses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referral_bonuses ALTER COLUMN id SET DEFAULT nextval('public.referral_bonuses_id_seq'::regclass);


--
-- Name: restaurants id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurants ALTER COLUMN id SET DEFAULT nextval('public.restaurants_id_seq'::regclass);


--
-- Name: saved_addresses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_addresses ALTER COLUMN id SET DEFAULT nextval('public.saved_addresses_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: wallet_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions ALTER COLUMN id SET DEFAULT nextval('public.wallet_transactions_id_seq'::regclass);


--
-- Data for Name: bookings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.bookings (id, booking_ref, customer_id, driver_id, pickup_lat, pickup_lng, pickup_address, drop_lat, drop_lng, drop_address, service_type, trip_type, status, fare_amount, distance_km, duration_min, payment_method, payment_status, promo_code, discount_amount, final_amount, platform_fee, driver_earnings, booked_at, accepted_at, arrived_at, started_at, completed_at, cancelled_at, cancelled_by, cancellation_reason, customer_rating, driver_rating, customer_feedback, driver_feedback, is_flash, parcel_type, parcel_weight_kg, receiver_name, receiver_phone, parcel_instructions, is_rental, rental_hours, is_event, scheduled_at, event_note) FROM stdin;
1	ZG11A1AA76	4	6	6.9271000	79.8612000	Galle Face	6.9043000	79.8682000	Independence Sq	car	one_way	ACCEPTED	386.03	2.65	6	cash	pending	\N	0.00	386.03	57.90	328.13	2026-05-13 09:49:48+05:30	2026-05-13 09:49:48.973359+05:30	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
2	ZG1DE8EB37	4	\N	6.9271000	79.8612000	Pickup 2	6.9043000	79.8682000	Drop 2	car	one_way	SEARCHING	386.03	2.65	6	cash	pending	\N	0.00	386.03	57.90	328.13	2026-05-13 09:49:49+05:30	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
3	ZGC0F5B23C	3	\N	6.9271000	79.8420000	Galle Face Green, Colombo 3	6.9089000	79.8946000	Rajagiriya, Rajagiriya	truck	one_way	CANCELLED	1819.77	6.15	15	cash	pending	\N	0.00	1819.77	272.97	1546.80	2026-05-13 09:54:57+05:30	\N	\N	\N	\N	2026-05-13 09:57:10.617453+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
4	FLBC78542B	5	6	6.9271000	79.8612000	Galle Face	6.9043000	79.8682000	Independence Sq	bike	one_way	ACCEPTED	164.76	2.65	6	cash	pending	\N	0.00	164.76	24.71	140.05	2026-05-13 11:03:32+05:30	2026-05-13 11:03:32.140117+05:30	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	t	document	0.50	Mr Perera	0771234567	Hand to receptionist	f	\N	f	\N	\N
5	ZG070FCE40	3	\N	6.9271000	79.8420000	Galle Face Green, Colombo 3	6.9043000	79.8682000	Independence Square, Colombo 7	bike	one_way	CANCELLED	212.61	3.85	9	cash	pending	\N	0.00	212.61	31.89	180.72	2026-05-13 11:24:56+05:30	\N	\N	\N	\N	2026-05-13 11:25:01.115228+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
6	ZGE8AAA7E4	3	\N	6.9165000	79.8625000	Viharamahadevi Park, Colombo 7	6.9043000	79.8682000	Independence Square, Colombo 7	car	one_way	CANCELLED	289.63	1.50	5	cash	pending	\N	0.00	289.63	43.44	246.19	2026-05-13 11:25:08+05:30	\N	\N	\N	\N	2026-05-13 11:25:09.539661+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
7	ZGDADEC53F	3	\N	6.9271000	79.8420000	Galle Face Green, Colombo 3	6.9043000	79.8682000	Independence Square, Colombo 7	bike	one_way	CANCELLED	212.61	3.85	9	cash	pending	\N	0.00	212.61	31.89	180.72	2026-05-13 11:25:47+05:30	\N	\N	\N	\N	2026-05-13 11:25:51.862041+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
8	ZG17C677C3	3	\N	6.9271000	79.8420000	Galle Face Green, Colombo 3	6.9043000	79.8682000	Independence Square, Colombo 7	car	one_way	CANCELLED	493.68	3.85	9	cash	pending	\N	0.00	493.68	74.05	419.63	2026-05-13 11:49:40+05:30	\N	\N	\N	\N	2026-05-13 11:49:46.281754+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
9	ZG241B7331	3	\N	6.9271000	79.8420000	Galle Face Green, Colombo 3	6.9043000	79.8682000	Independence Square, Colombo 7	bike	one_way	CANCELLED	212.61	3.85	9	cash	pending	\N	0.00	212.61	31.89	180.72	2026-05-13 11:50:28+05:30	\N	\N	\N	\N	2026-05-13 12:28:23.097897+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
10	ZG63E30B25	3	\N	8.5025625	81.1804375	Buhary Junction | புஹாரி சந்தி | බුහාරි හන්දිය, Kinniya, Sri Lanka	8.4827294	81.1692255	Faiza tyre house, Tampalakamam-Kinniyai Road, Kinniya, Sri Lanka	bike	one_way	CANCELLED	160.43	2.53	6	cash	pending	\N	0.00	160.43	24.06	136.37	2026-05-14 07:59:20+05:30	\N	\N	\N	\N	2026-05-14 07:59:50.629476+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
11	ZG87FEDB3E	3	\N	8.4871950	81.1932245	Kinniya Beach, Kinniya, Sri Lanka	8.4827294	81.1692255	Faiza tyre house, Tampalakamam-Kinniyai Road, Kinniya, Sri Lanka	bike	one_way	CANCELLED	166.00	2.69	6	cash	pending	\N	0.00	166.00	24.90	141.10	2026-05-14 10:08:14+05:30	\N	\N	\N	\N	2026-05-14 12:10:23.832398+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
12	ZGB171622D	3	\N	8.4871950	81.1932245	Kinniya Beach, Kinniya, Sri Lanka	8.5025625	81.1804375	Buhary Junction | புஹாரி சந்தி | බුහාරි හන්දිය, Kinniya, Sri Lanka	bike	one_way	CANCELLED	147.46	2.21	5	cash	pending	\N	0.00	147.46	22.12	125.34	2026-05-15 04:34:06+05:30	\N	\N	\N	\N	2026-05-15 04:36:41.662298+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
13	ZG92B2303B	3	\N	8.5025069	81.1812034	G52J+XF5, B541	8.5333333	81.2500000	Trincomalee Harbour, Sri Lanka	bike	one_way	CANCELLED	390.70	8.31	20	cash	pending	\N	0.00	390.70	58.61	332.10	2026-05-15 05:05:49+05:30	\N	\N	\N	\N	2026-05-15 05:25:57.79846+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
14	ZG65608064	3	\N	8.5024384	81.1812279	B541, Kinniya 31100	8.5333333	81.2500000	Trincomalee Harbour, Sri Lanka	bike	one_way	CANCELLED	390.73	8.31	20	cash	pending	\N	0.00	390.73	58.61	332.12	2026-05-15 06:10:22+05:30	\N	\N	\N	\N	2026-05-15 06:10:30.096238+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
15	ZGA6956EE3	3	\N	8.5024404	81.1812248	B541, Kinniya 31100	8.5873638	81.2152121	Trincomalee, Sri Lanka	bike	one_way	CANCELLED	463.45	10.16	24	cash	pending	\N	0.00	463.45	69.52	393.93	2026-05-15 06:10:53+05:30	\N	\N	\N	\N	2026-05-15 06:11:05.549525+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
16	ZGAFF4D092	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	8.5873638	81.2152121	Trincomalee, Sri Lanka	bike	one_way	CANCELLED	456.41	9.95	24	cash	pending	\N	0.00	456.41	68.46	387.95	2026-05-15 10:28:24+05:30	\N	\N	\N	\N	2026-05-15 10:28:38.138368+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
17	ZGB9E1A517	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	8.5873638	81.2152121	Trincomalee, Sri Lanka	bike	return	CANCELLED	821.55	19.91	48	cash	pending	\N	0.00	821.55	123.23	698.31	2026-05-15 10:32:18+05:30	\N	\N	\N	\N	2026-05-15 11:24:38.856107+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
18	ZGF8FFE61D	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	8.5333333	81.2500000	Trincomalee Harbour, Sri Lanka	bike	return	CANCELLED	699.36	16.49	40	cash	pending	\N	0.00	699.36	104.90	594.46	2026-05-15 10:33:15+05:30	\N	\N	\N	\N	2026-05-15 10:33:19.30236+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
19	ZG9C5BC263	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	8.5873638	81.2152121	Trincomalee, Sri Lanka	bike	return	CANCELLED	821.55	19.91	48	cash	pending	\N	0.00	821.55	123.23	698.31	2026-05-15 10:33:58+05:30	\N	\N	\N	\N	2026-05-15 10:34:01.451062+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
20	FLA077F6DA	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	bike	one_way	CANCELLED	5943.94	147.83	355	cash	pending	\N	0.00	5943.94	891.59	5052.35	2026-05-15 10:45:52+05:30	\N	\N	\N	\N	2026-05-15 10:46:13.307008+05:30	customer	Cancelled by user	\N	\N	\N	\N	t	document	0.50	sinthujan	0759368810	sinthu	f	\N	f	\N	\N
21	ZGD6CA328A	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	8.5873638	81.2152121	Trincomalee, Sri Lanka	bike	one_way	CANCELLED	456.41	9.95	24	cash	pending	\N	0.00	456.41	68.46	387.95	2026-05-15 12:01:07+05:30	\N	\N	\N	\N	2026-05-15 12:16:01.28049+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
22	ZG117AC10A	3	9	8.5045045	81.1809344	78 UC Rd, Kinniya	8.5873638	81.2152121	Trincomalee, Sri Lanka	car	one_way	COMPLETED	1042.38	9.95	24	cash	paid	\N	0.00	1042.38	156.36	886.02	2026-05-15 12:16:10+05:30	2026-05-15 12:16:23.977948+05:30	2026-05-15 12:16:41.379547+05:30	2026-05-15 12:16:42.74229+05:30	2026-05-15 12:16:45.660854+05:30	\N	\N	\N	5	\N	super	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
23	ZG1DD6A743	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	8.4871950	81.1932245	Kinniya Beach, Kinniya, Sri Lanka	car	return	CANCELLED	651.87	4.70	12	cash	pending	\N	0.00	651.87	97.78	554.09	2026-05-15 12:17:40+05:30	\N	\N	\N	\N	2026-05-15 12:18:04.265299+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
24	ZGEBBE4D86	3	9	8.5045045	81.1809344	78 UC Rd, Kinniya	8.5073239	81.1914141	Kinniya Bridge, Trincomalee Highway, Sri Lanka	car	return	COMPLETED	477.99	2.39	10	cash	paid	\N	0.00	477.99	71.70	406.29	2026-05-15 12:18:30+05:30	2026-05-15 12:18:39.441253+05:30	2026-05-15 12:18:56.888768+05:30	2026-05-15 12:18:57.256523+05:30	2026-05-15 12:19:05.136578+05:30	\N	\N	\N	5	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
25	ZG4C140564	3	10	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	truck	return	CANCELLED	57951.63	295.65	710	cash	pending	\N	0.00	57951.63	8692.74	49258.89	2026-05-15 12:24:43+05:30	2026-05-15 12:24:48.086262+05:30	\N	\N	\N	2026-05-15 12:27:15.664811+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
26	ZGE3B7C386	3	10	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	truck	one_way	COMPLETED	32195.35	147.83	355	cash	paid	\N	0.00	32195.35	4829.30	27366.05	2026-05-15 12:27:43+05:30	2026-05-15 12:28:00.065464+05:30	2026-05-15 12:28:27.208593+05:30	2026-05-15 12:29:07.241359+05:30	2026-05-15 12:29:08.556725+05:30	\N	\N	\N	5	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
27	ZG078A0CD1	3	10	8.5045045	81.1809344	78 UC Rd, Kinniya	6.9270786	79.8612430	Colombo, Sri Lanka	truck	return	COMPLETED	88828.92	455.67	1094	cash	paid	\N	0.00	88828.92	13324.34	75504.58	2026-05-15 12:32:36+05:30	2026-05-15 12:32:38.361175+05:30	2026-05-15 12:32:50.078932+05:30	2026-05-15 12:32:53.874873+05:30	2026-05-15 12:32:55.792117+05:30	\N	\N	\N	5	\N	good	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
28	ZGFF1E9D79	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	8.5873638	81.2152121	Trincomalee, Sri Lanka	bike	return	CANCELLED	821.55	19.91	48	cash	pending	\N	0.00	821.55	123.23	698.31	2026-05-18 03:33:40+05:30	\N	\N	\N	\N	2026-05-18 03:33:47.911204+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
29	ZGCAA335AF	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	8.5873638	81.2152121	Trincomalee, Sri Lanka	bike	one_way	CANCELLED	456.41	9.95	24	cash	pending	\N	0.00	456.41	68.46	387.95	2026-05-18 04:21:22+05:30	\N	\N	\N	\N	2026-05-18 04:23:29.666634+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
61	ZG73BE7EE5	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	tuk	one_way	CANCELLED	9275.47	147.83	355	cash	pending	\N	0.00	9275.47	1391.32	7884.15	2026-05-18 08:29:54+05:30	\N	\N	\N	\N	2026-05-18 08:30:49.421648+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
30	ZG708EFB0B	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	8.4871950	81.1932245	Kinniya Beach, Kinniya, Sri Lanka	car	one_way	CANCELLED	362.15	2.35	6	cash	pending	\N	0.00	362.15	54.32	307.83	2026-05-18 04:23:53+05:30	\N	\N	\N	\N	2026-05-18 04:24:56.896449+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
31	ZG1E109287	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	8.4871950	81.1932245	Kinniya Beach, Kinniya, Sri Lanka	car	one_way	CANCELLED	362.15	2.35	6	cash	pending	\N	0.00	362.15	54.32	307.83	2026-05-18 04:25:18+05:30	\N	\N	\N	\N	2026-05-18 04:25:29.454838+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
32	ZG30BEB225	3	9	8.5045045	81.1809344	78 UC Rd, Kinniya	8.4871950	81.1932245	Kinniya Beach, Kinniya, Sri Lanka	car	one_way	COMPLETED	362.15	2.35	6	cash	paid	\N	0.00	362.15	54.32	307.83	2026-05-18 04:26:12+05:30	2026-05-18 04:26:18.318145+05:30	2026-05-18 04:26:26.09619+05:30	2026-05-18 04:26:35.846306+05:30	2026-05-18 04:26:38.944673+05:30	\N	\N	\N	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
33	ZG99A13F3D	3	9	8.5045045	81.1809344	78 UC Rd, Kinniya	8.4871950	81.1932245	Kinniya Beach, Kinniya, Sri Lanka	car	one_way	COMPLETED	362.15	2.35	6	cash	paid	\N	0.00	362.15	54.32	307.83	2026-05-18 04:27:18+05:30	2026-05-18 04:27:22.751344+05:30	2026-05-18 04:27:36.943803+05:30	2026-05-18 04:27:41.740801+05:30	2026-05-18 04:27:46.739997+05:30	\N	\N	\N	5	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
34	ZG76A0D7E5	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	bike	one_way	CANCELLED	5943.94	147.83	355	cash	pending	\N	0.00	5943.94	891.59	5052.35	2026-05-18 04:57:02+05:30	\N	\N	\N	\N	2026-05-18 04:57:05.294733+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
35	ZG375C9D2F	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	one_way	CANCELLED	13396.14	147.83	355	cash	pending	\N	0.00	13396.14	2009.42	11386.72	2026-05-18 04:57:18+05:30	\N	\N	\N	\N	2026-05-18 06:06:22.368535+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
36	ZGB92057A9	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	return	CANCELLED	24113.05	295.65	710	cash	pending	\N	0.00	24113.05	3616.96	20496.10	2026-05-18 05:09:56+05:30	\N	\N	\N	\N	2026-05-18 05:11:10.162326+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
37	ZG6B67B1F2	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	return	CANCELLED	24113.05	295.65	710	cash	pending	\N	0.00	24113.05	3616.96	20496.10	2026-05-18 05:11:42+05:30	\N	\N	\N	\N	2026-05-18 05:16:16.631982+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
38	ZG9B87E75D	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	return	CANCELLED	24113.05	295.65	710	cash	pending	\N	0.00	24113.05	3616.96	20496.10	2026-05-18 05:16:43+05:30	\N	\N	\N	\N	2026-05-18 05:58:28.207911+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
39	ZGB93C9771	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	return	CANCELLED	24113.05	295.65	710	cash	pending	\N	0.00	24113.05	3616.96	20496.10	2026-05-18 05:17:27+05:30	\N	\N	\N	\N	2026-05-18 05:27:02.877776+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
40	ZGD6744B6D	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	return	CANCELLED	24113.05	295.65	710	cash	pending	\N	0.00	24113.05	3616.96	20496.10	2026-05-18 05:27:29+05:30	\N	\N	\N	\N	2026-05-18 05:28:31.645773+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
41	ZGEEC2605A	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	one_way	CANCELLED	13396.14	147.83	355	cash	pending	\N	0.00	13396.14	2009.42	11386.72	2026-05-18 05:28:38+05:30	\N	\N	\N	\N	2026-05-18 05:29:36.047514+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
42	ZG08F5269B	3	9	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	one_way	COMPLETED	13396.14	147.83	355	cash	paid	\N	0.00	13396.14	2009.42	11386.72	2026-05-18 05:29:43+05:30	2026-05-18 05:29:49.327564+05:30	2026-05-18 05:29:58.695941+05:30	2026-05-18 05:30:00.322242+05:30	2026-05-18 05:30:01.458419+05:30	\N	\N	\N	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
43	ZG91FA0149	3	9	8.5045045	81.1809344	78 UC Rd, Kinniya	8.2165366	79.7156610	KSL Reception, Kalpitiya, Sri Lanka	car	one_way	COMPLETED	14873.90	164.35	394	cash	paid	\N	0.00	14873.90	2231.08	12642.81	2026-05-18 05:58:38+05:30	2026-05-18 05:58:56.89068+05:30	2026-05-18 05:59:41.767162+05:30	2026-05-18 05:59:44.093281+05:30	2026-05-18 05:59:49.461487+05:30	\N	\N	\N	5	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
44	ZGD92817F4	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	return	CANCELLED	24113.05	295.65	710	cash	pending	\N	0.00	24113.05	3616.96	20496.10	2026-05-18 06:06:40+05:30	\N	\N	\N	\N	2026-05-18 07:12:12.210902+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
45	ZGA786513E	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	return	CANCELLED	24113.05	295.65	710	cash	pending	\N	0.00	24113.05	3616.96	20496.10	2026-05-18 06:08:27+05:30	\N	\N	\N	\N	2026-05-18 06:09:07.720071+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
46	ZGF0D82524	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	one_way	CANCELLED	13396.14	147.83	355	cash	pending	\N	0.00	13396.14	2009.42	11386.72	2026-05-18 06:09:20+05:30	\N	\N	\N	\N	2026-05-18 07:04:13.316865+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
47	ZG5937EFBC	3	7	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	return	COMPLETED	24113.05	295.65	710	cash	paid	\N	0.00	24113.05	3616.96	20496.10	2026-05-18 06:16:52+05:30	2026-05-18 06:17:03.018173+05:30	2026-05-18 06:17:06.061028+05:30	2026-05-18 06:17:09.159356+05:30	2026-05-18 06:17:10.923179+05:30	\N	\N	\N	5	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
48	ZGD0C5A4C7	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	tuk	one_way	CANCELLED	9275.47	147.83	355	cash	pending	\N	0.00	9275.47	1391.32	7884.15	2026-05-18 06:48:45+05:30	\N	\N	\N	\N	2026-05-18 06:48:56.649909+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
49	ZG04369525	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	one_way	CANCELLED	13396.14	147.83	355	cash	pending	\N	0.00	13396.14	2009.42	11386.72	2026-05-18 06:59:53+05:30	\N	\N	\N	\N	2026-05-18 07:01:39.079294+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
50	ZG1097CCFF	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	one_way	CANCELLED	13396.14	147.83	355	cash	pending	\N	0.00	13396.14	2009.42	11386.72	2026-05-18 07:01:46+05:30	\N	\N	\N	\N	2026-05-18 07:02:27.864274+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
51	ZG13520D56	3	9	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	one_way	COMPLETED	13396.14	147.83	355	cash	paid	\N	0.00	13396.14	2009.42	11386.72	2026-05-18 07:02:35+05:30	2026-05-18 07:02:41.608194+05:30	2026-05-18 07:02:52.978279+05:30	2026-05-18 07:02:57.532967+05:30	2026-05-18 07:02:59.851759+05:30	\N	\N	\N	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
52	ZG203F2F31	3	9	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	return	COMPLETED	24113.05	295.65	710	cash	paid	\N	0.00	24113.05	3616.96	20496.10	2026-05-18 07:07:31+05:30	2026-05-18 07:07:35.669858+05:30	2026-05-18 07:07:46.874529+05:30	2026-05-18 07:07:50.293292+05:30	2026-05-18 07:07:52.655936+05:30	\N	\N	\N	5	\N	supsr	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
53	ZGC84CBA08	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	tuk	return	CANCELLED	16695.85	295.65	710	cash	pending	\N	0.00	16695.85	2504.38	14191.47	2026-05-18 07:09:13+05:30	\N	\N	\N	\N	2026-05-18 07:09:28.207903+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
54	ZG59550792	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	tuk	return	CANCELLED	16695.85	295.65	710	cash	pending	\N	0.00	16695.85	2504.38	14191.47	2026-05-18 07:09:36+05:30	\N	\N	\N	\N	2026-05-18 07:09:56.980654+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
55	ZG5D00F9BF	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.0046324	79.9541550	Kadawatha, Sri Lanka	tuk	return	CANCELLED	24177.33	429.34	1030	cash	pending	\N	0.00	24177.33	3626.60	20550.73	2026-05-18 07:10:10+05:30	\N	\N	\N	\N	2026-05-18 07:10:26.684404+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
56	ZG1E741695	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	tuk	one_way	CANCELLED	9275.47	147.83	355	cash	pending	\N	0.00	9275.47	1391.32	7884.15	2026-05-18 07:10:34+05:30	\N	\N	\N	\N	2026-05-18 07:10:44.848134+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
57	ZG73DEB025	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	tuk	one_way	CANCELLED	9275.47	147.83	355	cash	pending	\N	0.00	9275.47	1391.32	7884.15	2026-05-18 07:11:02+05:30	\N	\N	\N	\N	2026-05-18 07:11:06.302709+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
58	ZGE4FC350D	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	car	return	CANCELLED	24113.05	295.65	710	cash	pending	\N	0.00	24113.05	3616.96	20496.10	2026-05-18 07:11:20+05:30	\N	\N	\N	\N	2026-05-18 07:12:10.144143+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
59	ZG612D5D18	3	10	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2905715	80.6337262	Kandy, Sri Lanka	tuk	one_way	COMPLETED	9275.47	147.83	355	cash	paid	\N	0.00	9275.47	1391.32	7884.15	2026-05-18 07:12:41+05:30	2026-05-18 07:12:45.044226+05:30	2026-05-18 07:12:50.245333+05:30	2026-05-18 07:12:51.416385+05:30	2026-05-18 07:12:53.048078+05:30	\N	\N	\N	5	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
60	ZG6446BBDB	3	9	8.5045045	81.1809344	78 UC Rd, Kinniya	6.9205009	79.8658211	Asiri Central Hospital - Central Hospital Limited, Norris Canal Road, Colombo, Sri Lanka	car	return	COMPLETED	37051.98	456.16	1094	cash	paid	\N	0.00	37051.98	5557.80	31494.19	2026-05-18 07:13:32+05:30	2026-05-18 07:13:34.782632+05:30	2026-05-18 07:13:36.050681+05:30	2026-05-18 07:13:36.9384+05:30	2026-05-18 07:13:37.734238+05:30	\N	\N	\N	5	\N	dsw	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
62	ZGD4983182	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	9.6605990	80.0117023	Jaffna, Sri Lanka	tuk	return	CANCELLED	20484.56	363.36	872	cash	pending	\N	0.00	20484.56	3072.68	17411.88	2026-05-18 08:31:39+05:30	\N	\N	\N	\N	2026-05-18 08:31:45.234223+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
63	ZGC65A5736	3	10	8.5045045	81.1809344	78 UC Rd, Kinniya	6.9778284	79.9271523	Kiribathgoda, Sri Lanka	tuk	return	COMPLETED	24646.31	437.72	1050	cash	paid	\N	0.00	24646.31	3696.95	20949.37	2026-05-18 11:53:20+05:30	2026-05-18 11:53:22.486152+05:30	2026-05-18 11:53:29.568827+05:30	2026-05-18 11:53:30.605946+05:30	2026-05-18 11:53:32.624802+05:30	\N	\N	\N	5	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
64	ZG0830E45E	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	6.9897845	80.4270885	Kitulgala, Sri Lanka	tuk	return	CANCELLED	21171.04	375.59	902	cash	pending	\N	0.00	21171.04	3175.66	17995.38	2026-05-18 12:05:35+05:30	\N	\N	\N	\N	2026-05-18 12:07:11.281651+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
65	FL68FB0645	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	7.2898141	80.6310986	Kandy Bus Stand, Kandy, Sri Lanka	bike	one_way	CANCELLED	5950.76	148.02	355	cash	pending	\N	0.00	5950.76	892.61	5058.15	2026-05-18 12:08:50+05:30	\N	\N	\N	\N	2026-05-18 12:08:54.46441+05:30	customer	Cancelled by user	\N	\N	\N	\N	t	document	0.50	farus	07596464640	good	f	\N	f	\N	\N
66	FL459D7F31	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	8.4871950	81.1932245	Kinniya Beach, Kinniya, Sri Lanka	bike	one_way	CANCELLED	154.32	2.35	6	cash	pending	\N	0.00	154.32	23.15	131.17	2026-05-18 12:27:02+05:30	\N	\N	\N	\N	2026-05-18 12:27:23.04895+05:30	customer	Cancelled by user	\N	\N	\N	\N	t	document	0.50	faris	0759137506	papers	f	\N	f	\N	\N
67	ZG513D0BA5	3	\N	8.5045045	81.1809344	78 UC Rd, Kinniya	8.0343167	80.7520489	Habarana, Sri Lanka	car	one_way	CANCELLED	6460.59	70.43	169	cash	pending	\N	0.00	6460.59	969.09	5491.50	2026-05-19 11:31:36+05:30	\N	\N	\N	\N	2026-05-19 11:31:57.985523+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
68	ZGFB97C669	3	9	8.5045045	81.1809344	78 UC Rd, Kinniya	8.0343167	80.7520489	Habarana, Sri Lanka	car	one_way	COMPLETED	6460.59	70.43	169	cash	paid	\N	0.00	6460.59	969.09	5491.50	2026-05-19 11:32:09+05:30	2026-05-19 11:32:11.873673+05:30	2026-05-19 11:32:15.152741+05:30	2026-05-19 11:32:16.597693+05:30	2026-05-19 11:32:17.156397+05:30	\N	\N	\N	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
69	FLF084D13D	3	\N	8.5045045	81.1627160	Kinniya, Sri Lanka	7.2905715	80.6337262	Kandy, Sri Lanka	bike	one_way	CANCELLED	6511.70	147.02	353	cash	pending	\N	0.00	6511.70	976.76	5534.95	2026-05-20 11:55:11.293949+05:30	\N	\N	\N	\N	2026-05-20 11:55:24.136053+05:30	customer	Cancelled by user	\N	\N	\N	\N	t	other	20.00	faris	0771234567	\N	f	\N	f	\N	\N
70	ZG21056715	3	11	8.5045045	81.1627160	Kinniya, Sri Lanka	8.5873638	81.2152121	Trincomalee, Sri Lanka	bike	one_way	COMPLETED	492.54	10.87	26	cash	paid	\N	0.00	492.54	73.88	418.66	2026-05-20 11:55:45.968673+05:30	2026-05-20 11:55:56.992532+05:30	2026-05-20 11:56:25.935481+05:30	2026-05-20 11:56:29.850872+05:30	2026-05-20 11:56:33.679149+05:30	\N	\N	\N	5	\N	good	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
71	FL89872701	3	\N	8.5045045	81.1627160	Kinniya, Sri Lanka	7.2905715	80.6337262	Kandy, Sri Lanka	bike	one_way	CANCELLED	5991.70	147.02	353	cash	pending	\N	0.00	5991.70	898.76	5092.95	2026-05-20 12:10:36.925895+05:30	\N	\N	\N	\N	2026-05-20 12:13:59.323405+05:30	customer	Cancelled by user	\N	\N	\N	\N	t	document	3.00	fatmris	0759137509	\N	f	\N	f	\N	\N
72	FL95331048	3	10	8.5045045	81.1627160	Kinniya, Sri Lanka	7.2905715	80.6337262	Kandy, Sri Lanka	bike	one_way	COMPLETED	5991.70	147.02	353	cash	paid	\N	0.00	5991.70	898.76	5092.95	2026-05-20 12:14:16.37499+05:30	2026-05-20 12:14:24.05837+05:30	2026-05-20 12:14:36.397376+05:30	2026-05-20 12:14:41.012432+05:30	2026-05-20 12:14:43.794097+05:30	\N	\N	\N	\N	\N	\N	\N	t	document	3.00	faris	0759238552	\N	f	\N	f	\N	\N
73	FLBE869150	3	10	8.5045045	81.1627160	Kinniya, Sri Lanka	8.3665178	81.0032203	Kanthale, Sri Lanka	bike	one_way	COMPLETED	1237.72	23.31	56	cash	paid	\N	0.00	1237.72	185.66	1052.06	2026-05-20 12:18:15.680549+05:30	2026-05-20 12:18:19.770747+05:30	2026-05-20 12:18:22.919648+05:30	2026-05-20 12:18:28.702991+05:30	2026-05-20 12:18:30.966829+05:30	\N	\N	\N	5	\N	\N	\N	t	clothes	10.00	sakeena	0859164510	\N	f	\N	f	\N	\N
74	ZG2E3FB148	3	\N	8.5045045	81.1627160	Kinniya, Sri Lanka	8.5873638	81.2152121	Trincomalee, Sri Lanka	car	return	CANCELLED	2022.84	21.74	52	cash	pending	\N	0.00	2022.84	303.43	1719.41	2026-05-20 12:41:53.631777+05:30	\N	\N	\N	\N	2026-05-20 12:42:02.588153+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
75	RT2237AFD2	3	\N	8.5045045	81.1627160	Kinniya, Sri Lanka	8.5045045	81.1627160	Kinniya, Sri Lanka	bike	one_way	CANCELLED	1600.00	0.00	240	cash	pending	\N	0.00	1600.00	240.00	1360.00	2026-05-20 12:53:53.634144+05:30	\N	\N	\N	\N	2026-05-20 12:54:00.153278+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	t	4	f	\N	\N
76	RT7B716D4E	3	\N	8.5045045	81.1627160	Kinniya, Sri Lanka	8.5045045	81.1627160	Kinniya, Sri Lanka	bike	one_way	CANCELLED	1600.00	0.00	240	cash	pending	\N	0.00	1600.00	240.00	1360.00	2026-05-20 12:56:41.632738+05:30	\N	\N	\N	\N	2026-05-20 12:56:50.260939+05:30	customer	Cancelled by user	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	t	4	f	\N	\N
77	ZG2203733C	3	9	8.5045045	81.1809344	78 UC Rd, Kinniya	8.5873638	81.2152121	Trincomalee, Sri Lanka	car	one_way	COMPLETED	1042.38	9.95	24	cash	paid	\N	0.00	1042.38	156.36	886.02	2026-05-20 18:45:45.770382+05:30	2026-05-20 18:46:15.426828+05:30	2026-05-20 18:48:08.204486+05:30	2026-05-20 18:48:14.415782+05:30	2026-05-20 18:48:41.491423+05:30	\N	\N	\N	\N	\N	\N	\N	f	\N	\N	\N	\N	\N	f	\N	f	\N	\N
\.


--
-- Data for Name: complaints; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.complaints (id, user_id, booking_id, category, subject, description, attachment_url, status, assigned_to, resolved_at, created_at) FROM stdin;
\.


--
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.customers (id, user_id, default_payment_method, wallet_balance, notification_token, gold_member, gold_expires_at) FROM stdin;
3	9	cash	1000.00	\N	t	2026-06-17 04:41:44.662269+05:30
4	10	cash	0.00	\N	f	\N
5	14	cash	0.00	\N	f	\N
6	18	cash	5000.00	\N	f	\N
1	5	cash	300.00	\N	f	\N
2	7	cash	300.00	\N	f	\N
7	26	cash	0.00	\N	f	\N
8	27	cash	0.00	\N	f	\N
\.


--
-- Data for Name: driver_documents; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.driver_documents (id, driver_id, document_type, document_url, is_verified, verified_by, verified_at, uploaded_at) FROM stdin;
\.


--
-- Data for Name: drivers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.drivers (id, user_id, nic_number, license_number, vehicle_type, vehicle_number, vehicle_model, vehicle_color, is_approved, is_online, current_lat, current_lng, last_location_update, total_earnings, today_earnings, today_rides, acceptance_rate, status, approved_at) FROM stdin;
1	2	991234567V	L-TEST-001	car	WP-TEST-1	Toyota Aqua	White	t	f	6.9271000	79.8612000	\N	0.00	0.00	0	100.00	APPROVED	2026-05-19 12:13:23.783597+05:30
2	3	ADM-NIC-1	ADM-L-1	tuk	WP-ADM-1	Bajaj	Yellow	t	f	6.9271000	79.8612000	\N	0.00	0.00	0	100.00	APPROVED	2026-05-19 12:13:21.505073+05:30
3	4	200114102373	qwertyui	bike	HL-1746	bajaj boxer	white	t	f	6.9271000	79.8612000	\N	0.00	0.00	0	100.00	APPROVED	2026-05-19 12:13:19.665414+05:30
4	6	200233404129	b1539237	car	KN-5949	premio	silver	t	f	6.9271000	79.8612000	2026-05-13 07:00:31.633358+05:30	0.00	0.00	0	100.00	APPROVED	2026-05-19 12:13:17.9174+05:30
5	8	200003803916	B443	car	HK-56I9	prius	blue	t	f	6.9271000	79.8612000	2026-05-13 09:40:48.151113+05:30	0.00	0.00	0	100.00	APPROVED	2026-05-19 12:13:15.767427+05:30
6	11	NIC-N1	L-N1	car	WP-N1	Honda	Red	t	f	6.9271000	79.8612000	2026-05-13 09:49:19.523231+05:30	0.00	0.00	0	100.00	APPROVED	2026-05-19 12:13:12.951779+05:30
7	12	246990272662627373	h62738	car	KM-6877	car	light	t	f	8.5024174	81.1811321	2026-05-18 07:07:24.751176+05:30	20496.10	20496.10	1	100.00	APPROVED	2026-05-18 05:08:59.196369+05:30
8	15	35688900087	hf5790	truck	vh_*&₹	hkkkk	ujff	t	f	8.5025103	81.1812489	2026-05-13 11:11:58.581653+05:30	0.00	0.00	0	100.00	APPROVED	2026-05-18 11:16:51.719773+05:30
10	17	200367841520	b78632	tuk	KL-5698	toyota	black	t	t	8.5024785	81.1810761	2026-05-20 15:09:04.946962+05:30	137849.16	137849.16	6	100.00	APPROVED	2026-05-15 12:23:17.070069+05:30
9	16	200233656878	b15789585	car	CBB-5898	ALLION	whine red	t	t	8.5024770	81.1810089	2026-05-20 19:02:18.389136+05:30	95692.03	95692.03	11	100.00	APPROVED	2026-05-15 05:47:00.114282+05:30
12	28	3588998532368	v3699	bike	nh-6796	dio	white	t	f	8.5045045	81.1627160	2026-05-20 11:37:51.96375+05:30	0.00	0.00	0	100.00	APPROVED	2026-05-20 11:02:51.460103+05:30
11	19	20034893949	B34kks	bike	BAD-5456	hornet	red	t	f	8.5024752	81.1810760	2026-05-20 11:56:21.446793+05:30	418.66	418.66	1	100.00	APPROVED	2026-05-18 11:16:56.203395+05:30
\.


--
-- Data for Name: event_ticket_tiers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.event_ticket_tiers (id, event_id, name, price, capacity, description) FROM stdin;
1	1	Regular	1500.00	300	\N
2	1	Premium	3500.00	100	\N
3	1	VIP	7500.00	40	\N
4	2	Day Pass	800.00	500	\N
5	2	Weekend Pass	1800.00	250	\N
\.


--
-- Data for Name: events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.events (id, name, description, venue, city, image_url, organizer_name, organizer_phone, starts_at, ends_at, is_published, created_at) FROM stdin;
1	Colombo Music Night 2026	An open-air evening of local indie + reggae acts at the Galle Face Green. Food trucks, late-night DJ set.	Galle Face Green	Colombo	https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?w=1200&q=80	Ziggo Live	0771234567	2026-06-03 14:42:40.816654+05:30	2026-06-03 19:42:40.816654+05:30	t	2026-05-20 14:42:40.678167+05:30
2	Kandy Cultural Festival	A weekend of traditional dance, drumming and craft stalls in the heart of the hill country. Family-friendly.	Bogambara Stadium	Kandy	https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=1200&q=80	Hill Country Arts Council	0812223344	2026-06-19 14:42:40.816654+05:30	2026-06-21 14:42:40.816654+05:30	t	2026-05-20 14:42:40.678167+05:30
\.


--
-- Data for Name: fare_settings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.fare_settings (id, service_type, base_fare, per_km_rate, per_minute_rate, min_fare, platform_fee_percent, surge_multiplier, updated_at) FROM stdin;
1	bike	60.00	35.00	2.00	100.00	15.00	1.00	2026-05-13 06:25:16+05:30
2	tuk	80.00	55.00	3.00	150.00	15.00	1.00	2026-05-13 06:25:16+05:30
3	car	150.00	80.00	4.00	250.00	15.00	1.00	2026-05-13 06:25:16+05:30
4	van	250.00	120.00	5.00	400.00	15.00	1.00	2026-05-13 06:25:16+05:30
5	truck	500.00	200.00	6.00	750.00	15.00	1.00	2026-05-13 06:25:16+05:30
\.


--
-- Data for Name: flash_weight_tiers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.flash_weight_tiers (id, label, min_weight_kg, max_weight_kg, representative_weight_kg, surcharge, icon, display_order, is_active, updated_at) FROM stdin;
1	Light	0.00	1.00	0.50	0.00	feed	1	t	2026-05-15 10:50:32+05:30
2	Medium	1.00	5.00	3.00	80.00	shopping_bag	2	t	2026-05-15 10:50:32+05:30
3	Heavy	5.00	15.00	10.00	250.00	inventory_2	3	t	2026-05-15 10:50:32+05:30
4	X-Large	15.00	\N	20.00	600.00	local_shipping	4	t	2026-05-15 10:50:32+05:30
\.


--
-- Data for Name: food_order_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.food_order_items (id, order_id, menu_item_id, quantity, price_at_order, notes) FROM stdin;
1	1	2	1	1500.00	\N
2	2	1	1	950.00	\N
3	3	1	1	950.00	\N
4	4	1	1	950.00	\N
5	5	1	1	950.00	\N
6	6	3	1	500.00	\N
7	7	3	2	500.00	\N
8	8	3	1	500.00	\N
9	9	3	1	500.00	\N
10	10	3	1	500.00	\N
11	11	3	1	500.00	\N
12	12	3	1	500.00	\N
13	13	3	1	500.00	\N
14	14	3	1	500.00	\N
15	15	3	1	500.00	\N
16	16	3	1	500.00	\N
17	17	3	1	500.00	\N
18	18	3	1	500.00	\N
19	19	4	2	350.00	\N
20	20	4	2	350.00	\N
21	21	4	2	350.00	\N
22	22	4	2	350.00	\N
23	23	4	2	350.00	\N
24	24	4	2	350.00	\N
25	25	4	2	350.00	\N
26	26	4	2	350.00	\N
27	27	4	1	350.00	\N
28	28	4	1	350.00	\N
29	29	1	1	950.00	\N
30	30	4	1	350.00	\N
31	31	4	1	350.00	\N
\.


--
-- Data for Name: food_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.food_orders (id, order_ref, customer_id, restaurant_id, driver_id, status, total_amount, delivery_fee, tax_amount, discount_amount, final_amount, delivery_address, delivery_lat, delivery_lng, payment_method, payment_status, instructions, cancellation_reason, created_at, confirmed_at, ready_at, picked_up_at, delivered_at) FROM stdin;
1	FO1040B665	3	2	\N	CANCELLED	1500.00	150.00	0.00	0.00	1650.00	Viharamahadevi Park, Colombo 7	6.9165000	79.8625000	cash	pending	\N	Restaurant did not respond in 5 minutes	2026-05-13 10:29:31+05:30	\N	\N	\N	\N
2	FO642B188E	3	1	\N	CANCELLED	950.00	200.00	0.00	0.00	1150.00	Kinniya Beach, Kinniya, Sri Lanka	8.4871950	81.1932245	cash	pending	\N	Restaurant did not respond in 5 minutes	2026-05-15 09:52:13+05:30	\N	\N	\N	\N
3	FO823F54A9	3	1	\N	CANCELLED	950.00	200.00	0.00	0.00	1150.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Restaurant did not respond in 5 minutes	2026-05-18 04:33:35+05:30	\N	\N	\N	\N
4	FO1719BF00	3	1	\N	CANCELLED	950.00	200.00	0.00	0.00	1150.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Restaurant did not respond in 5 minutes	2026-05-18 10:08:20+05:30	\N	\N	\N	\N
5	FOBEDB1C23	3	1	\N	CANCELLED	950.00	200.00	0.00	0.00	1150.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Restaurant did not respond in 5 minutes	2026-05-18 10:14:59+05:30	\N	\N	\N	\N
6	FOAF6646C3	3	3	\N	CANCELLED	500.00	150.00	0.00	0.00	650.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Restaurant did not respond in 5 minutes	2026-05-18 10:18:43+05:30	\N	\N	\N	\N
7	FOF080C5E9	6	3	9	DELIVERED	1000.00	150.00	0.00	0.00	1150.00	Kinniya UC Rd test address	8.5024000	81.1810000	cash	paid	Extra napkins please	\N	2026-05-18 10:26:43+05:30	\N	\N	\N	2026-05-18 10:26:43.984451+05:30
8	FO099AE714	3	3	\N	CANCELLED	500.00	150.00	0.00	0.00	650.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Restaurant did not respond in 5 minutes	2026-05-18 11:20:29+05:30	\N	\N	\N	\N
9	FOA69EACFE	3	3	9	DELIVERED	500.00	150.00	0.00	0.00	650.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	paid	\N	\N	2026-05-18 11:24:17+05:30	\N	\N	\N	2026-05-18 12:27:11.955826+05:30
10	FO1F6BBC84	3	3	\N	CANCELLED	500.00	150.00	0.00	0.00	650.00	Kandy, Sri Lanka	7.2905715	80.6337262	cash	pending	\N	Restaurant did not respond in 5 minutes	2026-05-18 11:25:00+05:30	\N	\N	\N	\N
11	FOE2277E0A	3	3	9	DELIVERED	500.00	150.00	0.00	0.00	650.00	Kandy, Sri Lanka	7.2905715	80.6337262	cash	paid	\N	\N	2026-05-18 11:27:28+05:30	\N	\N	\N	2026-05-18 11:38:07.669723+05:30
12	FO3067B1F3	3	3	\N	CANCELLED	500.00	150.00	0.00	0.00	650.00	Jaffna, Sri Lanka	9.6605990	80.0117023	cash	pending	\N	Restaurant did not respond in 5 minutes	2026-05-18 11:37:22+05:30	\N	\N	\N	\N
13	FOCC11749D	3	3	9	DELIVERED	500.00	150.00	0.00	0.00	650.00	Jaffna, Sri Lanka	9.6605990	80.0117023	cash	paid	\N	\N	2026-05-18 11:38:19+05:30	\N	\N	\N	2026-05-18 11:38:40.586908+05:30
14	FO7C9EBD5F	3	3	9	DELIVERED	500.00	150.00	0.00	0.00	650.00	Kitulgala, Sri Lanka	6.9897845	80.4270885	cash	paid	\N	\N	2026-05-18 11:54:20+05:30	\N	\N	\N	2026-05-18 11:54:37.44835+05:30
15	FO5E7A397F	3	3	9	DELIVERED	500.00	150.00	0.00	0.00	650.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	paid	\N	\N	2026-05-18 11:54:56+05:30	\N	\N	\N	2026-05-18 11:55:22.963612+05:30
16	FOFDDA82FA	3	3	9	DELIVERED	500.00	150.00	0.00	0.00	650.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	paid	\N	\N	2026-05-18 12:17:30+05:30	\N	\N	\N	2026-05-18 12:17:44.469669+05:30
17	FO24447C92	3	3	9	DELIVERED	500.00	150.00	0.00	0.00	650.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	paid	\N	\N	2026-05-18 12:27:29+05:30	\N	\N	\N	2026-05-18 12:27:43.191467+05:30
18	FOD15F6C98	3	3	\N	CANCELLED	500.00	150.00	0.00	0.00	650.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Restaurant did not respond in 5 minutes	2026-05-18 12:52:56+05:30	\N	\N	\N	\N
19	FOB4E26A35	6	4	\N	CANCELLED	700.00	180.00	0.00	0.00	880.00	Kinniya UC Rd	8.5024000	81.1810000	wallet	refunded	Extra spicy	Restaurant did not respond in 5 minutes	2026-05-19 04:19:49+05:30	\N	\N	\N	\N
20	FO17F2C2DF	6	4	\N	READY_FOR_PICKUP	700.00	180.00	0.00	0.00	880.00	Kinniya UC Rd	8.5024000	81.1810000	wallet	paid	Extra spicy	\N	2026-05-19 04:20:25+05:30	2026-05-19 04:20:25.997325+05:30	2026-05-19 04:20:26.014935+05:30	\N	\N
21	FOA2271D0E	6	4	9	DELIVERED	700.00	180.00	0.00	0.00	880.00	Kinniya UC Rd	8.5024000	81.1810000	wallet	paid	Extra spicy	\N	2026-05-19 04:21:38+05:30	2026-05-19 04:21:39.030468+05:30	2026-05-19 04:21:39.047614+05:30	2026-05-19 04:21:39.08893+05:30	2026-05-19 04:21:39.105401+05:30
22	FO7E075992	6	4	\N	CANCELLED	700.00	180.00	0.00	0.00	880.00	Kinniya UC Rd	8.5024000	81.1810000	wallet	refunded	Extra spicy	Out of ingredients	2026-05-19 04:21:39+05:30	\N	\N	\N	\N
23	FO0AE7B9BD	6	4	\N	CANCELLED	700.00	180.00	0.00	0.00	880.00	Kinniya UC Rd	8.5024000	81.1810000	wallet	refunded	Extra spicy	Restaurant did not respond in 5 minutes	2026-05-19 04:11:39+05:30	\N	\N	\N	\N
24	FO6A325428	6	4	9	DELIVERED	700.00	180.00	0.00	0.00	880.00	Kinniya UC Rd	8.5024000	81.1810000	wallet	paid	Extra spicy	\N	2026-05-19 04:22:06+05:30	2026-05-19 04:22:06.683409+05:30	2026-05-19 04:22:06.700746+05:30	2026-05-19 04:22:06.751033+05:30	2026-05-19 04:22:06.76975+05:30
25	FOD0159B56	6	4	\N	CANCELLED	700.00	180.00	0.00	0.00	880.00	Kinniya UC Rd	8.5024000	81.1810000	wallet	refunded	Extra spicy	Out of ingredients	2026-05-19 04:22:06+05:30	\N	\N	\N	\N
26	FO3B09F1D3	6	4	\N	CANCELLED	700.00	180.00	0.00	0.00	880.00	Kinniya UC Rd	8.5024000	81.1810000	wallet	refunded	Extra spicy	Restaurant did not respond in 5 minutes	2026-05-19 04:12:06+05:30	\N	\N	\N	\N
27	FO6414CCDD	3	4	9	DELIVERED	350.00	180.00	0.00	0.00	530.00	Kandy, Sri Lanka	7.2905715	80.6337262	cash	paid	\N	\N	2026-05-19 05:33:38+05:30	2026-05-19 05:33:44.747759+05:30	2026-05-19 05:34:03.801267+05:30	2026-05-19 05:34:13.041037+05:30	2026-05-19 05:34:21.621431+05:30
28	FO4D532010	3	4	9	DELIVERED	350.00	180.00	0.00	0.00	530.00	Kandy, Sri Lanka	7.2905715	80.6337262	cash	paid	\N	\N	2026-05-19 05:36:47+05:30	2026-05-19 05:36:55.054033+05:30	2026-05-19 05:37:04.516302+05:30	2026-05-19 05:37:28.912997+05:30	2026-05-19 05:37:35.776297+05:30
29	FOFB39E230	3	1	\N	READY_FOR_PICKUP	950.00	200.00	0.00	0.00	1150.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	\N	2026-05-19 05:55:08+05:30	2026-05-19 05:55:08.68392+05:30	2026-05-19 05:55:08.68392+05:30	\N	\N
30	FOCBAA78D4	3	4	9	DELIVERED	350.00	180.00	0.00	0.00	530.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	paid	\N	\N	2026-05-19 10:23:45+05:30	2026-05-19 10:23:55.6046+05:30	2026-05-19 10:25:03.608205+05:30	2026-05-19 10:25:09.656697+05:30	2026-05-19 10:25:13.120035+05:30
31	FOC4701FC7	3	4	10	DELIVERED	350.00	180.00	0.00	0.00	530.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	paid	\N	\N	2026-05-20 11:58:01.505888+05:30	2026-05-20 11:58:09.181349+05:30	2026-05-20 11:58:18.10113+05:30	2026-05-20 11:58:31.125801+05:30	2026-05-20 11:58:34.108924+05:30
\.


--
-- Data for Name: market_order_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.market_order_items (id, order_id, product_id, quantity, price_at_order) FROM stdin;
1	1	1	1	1200.00
2	2	1	1	1200.00
3	3	1	1	1200.00
4	4	1	1	1200.00
5	5	2	1	3500.00
6	6	3	1	50.00
7	7	3	1	50.00
8	8	3	1	50.00
9	9	4	1	3499.98
10	10	4	1	3499.98
11	11	4	1	3499.98
12	12	4	1	3499.98
13	13	4	1	3499.98
14	14	4	1	3499.98
15	15	4	1	3499.98
16	16	4	1	3499.98
17	17	4	1	3499.98
18	18	4	1	3499.98
19	19	3	1	50.00
20	20	3	1	50.00
21	21	3	1	50.00
22	22	4	1	3500.00
\.


--
-- Data for Name: market_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.market_orders (id, order_ref, customer_id, vendor_id, driver_id, status, total_amount, delivery_fee, final_amount, delivery_address, delivery_lat, delivery_lng, payment_method, payment_status, instructions, cancellation_reason, created_at, confirmed_at, ready_at, picked_up_at, delivered_at) FROM stdin;
1	MK619C556D	3	1	\N	PENDING	1200.00	150.00	1350.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	\N	2026-05-18 04:46:56+05:30	\N	\N	\N	\N
2	MKB7F7D987	3	1	\N	PENDING	1200.00	150.00	1350.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	\N	2026-05-18 12:28:53+05:30	\N	\N	\N	\N
3	MKF4F90FC6	3	1	\N	PENDING	1200.00	150.00	1350.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	\N	2026-05-19 05:40:46+05:30	\N	\N	\N	\N
4	MKFB7C73D7	3	1	\N	PENDING	1200.00	150.00	1350.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	\N	2026-05-19 05:55:27+05:30	\N	\N	\N	\N
5	MK4D3DB267	3	2	\N	PENDING	3500.00	150.00	3650.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	\N	2026-05-19 06:32:11+05:30	\N	\N	\N	\N
6	MKD8D0C080	3	3	\N	READY_FOR_PICKUP	50.00	150.00	200.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	\N	2026-05-19 10:23:06+05:30	2026-05-19 10:26:34.110908+05:30	2026-05-19 10:26:49.193238+05:30	\N	\N
7	MK8472B6C7	3	3	\N	CANCELLED	50.00	150.00	200.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Out of stock	2026-05-19 10:26:27+05:30	\N	\N	\N	\N
8	MK5C45BB18	3	3	\N	CANCELLED	50.00	150.00	200.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Cannot reach customer	2026-05-19 10:43:45+05:30	\N	\N	\N	\N
9	MKC6432A12	3	4	\N	CANCELLED	3499.98	350.00	3849.98	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Closing early today	2026-05-19 10:46:37+05:30	\N	\N	\N	\N
10	MK94061561	3	4	\N	CANCELLED	3499.98	350.00	3849.98	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Store too busy right now	2026-05-19 10:52:32+05:30	\N	\N	\N	\N
11	MKE2F7031B	3	4	\N	CANCELLED	3499.98	350.00	3849.98	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Cannot reach customer	2026-05-19 10:52:57+05:30	\N	\N	\N	\N
12	MK3BEAED17	3	4	\N	CANCELLED	3499.98	350.00	3849.98	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Store is closed	2026-05-19 10:56:40+05:30	\N	\N	\N	\N
13	MKB9481AE4	3	4	\N	READY_FOR_PICKUP	3499.98	350.00	3849.98	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	\N	2026-05-19 11:01:56+05:30	2026-05-19 11:02:08.829459+05:30	2026-05-19 11:02:20.831726+05:30	\N	\N
14	MK9A7B4021	3	4	\N	READY_FOR_PICKUP	3499.98	350.00	3849.98	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	\N	2026-05-19 11:03:16+05:30	2026-05-19 11:03:22.431252+05:30	2026-05-19 11:03:33.944159+05:30	\N	\N
15	MK145D8E0F	3	4	\N	READY_FOR_PICKUP	3499.98	350.00	3849.98	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	\N	2026-05-19 11:03:53+05:30	2026-05-19 11:03:59.029377+05:30	2026-05-19 11:04:06.669133+05:30	\N	\N
16	MKF5FBA66F	3	4	\N	READY_FOR_PICKUP	3499.98	350.00	3849.98	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	\N	2026-05-19 11:10:13+05:30	2026-05-19 11:10:23.07573+05:30	2026-05-19 11:10:30.869119+05:30	\N	\N
17	MK1A9E3C29	3	4	9	DELIVERED	3499.98	350.00	3849.98	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	paid	\N	\N	2026-05-19 11:18:30+05:30	2026-05-19 11:18:36.871938+05:30	2026-05-19 11:19:02.700431+05:30	2026-05-19 11:19:09.597798+05:30	2026-05-19 11:19:14.544417+05:30
18	MK90990CFF	3	4	\N	CANCELLED	3499.98	350.00	3849.98	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Cannot reach customer	2026-05-19 11:26:33+05:30	\N	\N	\N	\N
19	MK664F2776	3	3	9	DELIVERED	50.00	150.00	200.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	paid	\N	\N	2026-05-19 11:34:30+05:30	2026-05-19 11:34:35.06702+05:30	2026-05-19 11:34:43.370437+05:30	2026-05-19 11:34:56.882429+05:30	2026-05-19 11:35:02.958932+05:30
20	MK6ABA4525	3	3	\N	CANCELLED	50.00	150.00	200.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Closing early today	2026-05-19 11:36:17+05:30	\N	\N	\N	\N
21	MK8A7E45EE	3	3	\N	CANCELLED	50.00	150.00	200.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	pending	\N	Out of stock	2026-05-19 12:21:41+05:30	\N	\N	\N	\N
22	MK38947461	3	4	10	DELIVERED	3500.00	350.00	3850.00	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	cash	paid	\N	\N	2026-05-20 12:09:15.517225+05:30	2026-05-20 12:09:20.530669+05:30	2026-05-20 12:09:27.384057+05:30	2026-05-20 12:09:34.452238+05:30	2026-05-20 12:09:37.990352+05:30
\.


--
-- Data for Name: market_vendors; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.market_vendors (id, name, description, category, address, lat, lng, phone_number, image_url, rating, is_active, is_open, opening_time, closing_time, delivery_fee, eta_minutes, owner_id, created_at) FROM stdin;
1	Test Mart	Test vendor	Grocery	12 Test Rd	6.9100000	79.8500000	+94115555555	\N	4.30	t	t	\N	\N	0.00	40	\N	2026-05-13 10:20:17+05:30
2	HRM HOLDINGS	\N	Electronics	\N	8.4872000	81.1932000	\N	\N	4.30	t	t	\N	\N	0.00	40	\N	2026-05-19 06:31:04+05:30
3	FRS BAKERS	\N	Bakery	kanthala	8.5024000	81.1810000	\N	\N	4.30	t	f	\N	\N	0.00	40	24	2026-05-19 09:21:15+05:30
4	qwerty pvt ltd	\N	Grocery	colombo	8.5024000	81.1810000	0779137509	\N	4.30	t	t	08:00	22:00	350.00	40	25	2026-05-19 10:45:53+05:30
\.


--
-- Data for Name: menu_categories; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.menu_categories (id, restaurant_id, name, description, display_order, is_active) FROM stdin;
1	1	Mains	\N	1	t
2	1	Drinks	\N	2	t
3	2	koththu	\N	100	t
4	3	koththu	\N	50	t
5	4	chinese koththu	\N	25	t
6	4	Mains	\N	1	t
\.


--
-- Data for Name: menu_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.menu_items (id, restaurant_id, category_id, name, description, price, image_url, is_available, is_veg, calories, prep_time_min) FROM stdin;
1	1	1	Burger	Beef burger with fries	950.00	\N	t	f	\N	12
2	2	3	beef	\N	1500.00	\N	t	f	\N	15
3	3	4	KOTHTHU	\N	500.00	\N	t	f	\N	15
4	4	5	Hashnate Special Rice		350.00	\N	t	f	\N	\N
5	4	6	koththu	\N	1500.00	\N	t	f	\N	20
\.


--
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notifications (id, user_id, title, body, type, data, is_read, created_at) FROM stdin;
1	5	Ride Cancelled	Booking ZGAC5F73F1 is now cancelled	ride_update	\N	f	2026-05-13 06:51:48+05:30
2	5	Ride Cancelled	Booking ZGB5166397 is now cancelled	ride_update	\N	f	2026-05-13 06:53:09+05:30
3	7	Ride Cancelled	Booking ZG1BBA17AD is now cancelled	ride_update	\N	t	2026-05-13 07:04:28+05:30
4	7	Ride Cancelled	Booking ZG1E381D1E is now cancelled	ride_update	\N	t	2026-05-13 07:07:09+05:30
5	7	Ride Cancelled	Booking ZGD6A6CCEB is now cancelled	ride_update	\N	t	2026-05-13 07:17:20+05:30
6	7	Ride Cancelled	Booking ZG70C923C6 is now cancelled	ride_update	\N	t	2026-05-13 09:05:46+05:30
7	9	Ride Cancelled	Booking ZG029E5DDF is now cancelled	ride_update	\N	t	2026-05-13 09:43:22+05:30
8	9	Ride Cancelled	Booking ZG8870526C is now cancelled	ride_update	\N	t	2026-05-13 09:48:29+05:30
9	2	New ride request	Galle Face → Independence Sq • Rs.386	ride_request	{"booking_id":1}	f	2026-05-13 09:49:48+05:30
10	10	Driver on the way	Notify Test Driver accepted your ride ZG11A1AA76	ride_update	\N	f	2026-05-13 09:49:48+05:30
11	2	New ride request	Pickup 2 → Drop 2 • Rs.386	ride_request	{"booking_id":2}	f	2026-05-13 09:49:49+05:30
12	2	New ride request	Pickup 2 → Drop 2 • Rs.386	ride_request	{"booking_id":2}	f	2026-05-13 09:49:49+05:30
13	9	Ride Cancelled	Booking ZGC0F5B23C is now cancelled	ride_update	\N	t	2026-05-13 09:57:10+05:30
14	4	New parcel delivery	document • Galle Face → Independence Sq • Rs.164	flash_request	{"booking_id":4}	f	2026-05-13 11:03:32+05:30
15	14	Driver on the way	Notify Test Driver accepted your ride FLBC78542B	ride_update	\N	f	2026-05-13 11:03:32+05:30
16	4	New ride request	Galle Face Green, Colombo 3 → Independence Square, Colombo 7 • Rs.212	ride_request	{"booking_id":5}	f	2026-05-13 11:24:56+05:30
17	9	Ride Cancelled	Booking ZG070FCE40 is now cancelled	ride_update	\N	t	2026-05-13 11:25:01+05:30
18	2	New ride request	Viharamahadevi Park, Colombo 7 → Independence Square, Colombo 7 • Rs.289	ride_request	{"booking_id":6}	f	2026-05-13 11:25:08+05:30
19	9	Ride Cancelled	Booking ZGE8AAA7E4 is now cancelled	ride_update	\N	t	2026-05-13 11:25:09+05:30
20	4	New ride request	Galle Face Green, Colombo 3 → Independence Square, Colombo 7 • Rs.212	ride_request	{"booking_id":7}	f	2026-05-13 11:25:47+05:30
21	9	Ride Cancelled	Booking ZGDADEC53F is now cancelled	ride_update	\N	t	2026-05-13 11:25:51+05:30
22	2	New ride request	Galle Face Green, Colombo 3 → Independence Square, Colombo 7 • Rs.493	ride_request	{"booking_id":8}	f	2026-05-13 11:49:40+05:30
23	9	Ride Cancelled	Booking ZG17C677C3 is now cancelled	ride_update	\N	t	2026-05-13 11:49:46+05:30
24	4	New ride request	Galle Face Green, Colombo 3 → Independence Square, Colombo 7 • Rs.212	ride_request	{"booking_id":9}	f	2026-05-13 11:50:28+05:30
25	9	Ride Cancelled	Booking ZG241B7331 is now cancelled	ride_update	\N	t	2026-05-13 12:28:23+05:30
26	9	Ride Cancelled	Booking ZG63E30B25 is now cancelled	ride_update	\N	t	2026-05-14 07:59:50+05:30
27	9	Ride Cancelled	Booking ZG87FEDB3E is now cancelled	ride_update	\N	t	2026-05-14 12:10:23+05:30
28	9	Ride Cancelled	Booking ZGB171622D is now cancelled	ride_update	\N	t	2026-05-15 04:36:41+05:30
29	9	Ride Cancelled	Booking ZG92B2303B is now cancelled	ride_update	\N	t	2026-05-15 05:25:57+05:30
30	9	Ride Cancelled	Booking ZG65608064 is now cancelled	ride_update	\N	t	2026-05-15 06:10:30+05:30
31	9	Ride Cancelled	Booking ZGA6956EE3 is now cancelled	ride_update	\N	t	2026-05-15 06:11:05+05:30
32	9	Ride Cancelled	Booking ZGAFF4D092 is now cancelled	ride_update	\N	t	2026-05-15 10:28:38+05:30
33	9	Ride Cancelled	Booking ZGF8FFE61D is now cancelled	ride_update	\N	t	2026-05-15 10:33:19+05:30
34	9	Ride Cancelled	Booking ZG9C5BC263 is now cancelled	ride_update	\N	t	2026-05-15 10:34:01+05:30
35	9	Ride Cancelled	Booking FLA077F6DA is now cancelled	ride_update	\N	t	2026-05-15 10:46:13+05:30
36	9	Ride Cancelled	Booking ZGB9E1A517 is now cancelled	ride_update	\N	t	2026-05-15 11:24:38+05:30
37	9	Ride Cancelled	Booking ZGD6CA328A is now cancelled	ride_update	\N	t	2026-05-15 12:16:01+05:30
38	16	New ride request	78 UC Rd, Kinniya → Trincomalee, Sri Lanka • Rs.1042	ride_request	{"booking_id":22}	f	2026-05-15 12:16:10+05:30
39	9	Driver on the way	aashik accepted your ride ZG117AC10A	ride_update	\N	t	2026-05-15 12:16:23+05:30
40	9	Ride Arrived	Booking ZG117AC10A is now arrived	ride_update	\N	t	2026-05-15 12:16:41+05:30
41	9	Ride Started	Booking ZG117AC10A is now started	ride_update	\N	t	2026-05-15 12:16:42+05:30
42	9	Ride Completed	Booking ZG117AC10A is now completed	ride_update	\N	t	2026-05-15 12:16:45+05:30
43	9	Ride Cancelled	Booking ZG1DD6A743 is now cancelled	ride_update	\N	t	2026-05-15 12:18:04+05:30
44	16	New ride request	78 UC Rd, Kinniya → Kinniya Bridge, Trincomalee Highway, Sri Lanka • Rs.477	ride_request	{"booking_id":24}	f	2026-05-15 12:18:31+05:30
45	9	Driver on the way	aashik accepted your ride ZGEBBE4D86	ride_update	\N	t	2026-05-15 12:18:39+05:30
46	9	Ride Arrived	Booking ZGEBBE4D86 is now arrived	ride_update	\N	t	2026-05-15 12:18:56+05:30
47	9	Ride Started	Booking ZGEBBE4D86 is now started	ride_update	\N	t	2026-05-15 12:18:57+05:30
48	9	Ride Completed	Booking ZGEBBE4D86 is now completed	ride_update	\N	t	2026-05-15 12:19:05+05:30
49	17	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.57951	ride_request	{"booking_id":25}	f	2026-05-15 12:24:43+05:30
50	9	Driver on the way	faris accepted your ride ZG4C140564	ride_update	\N	t	2026-05-15 12:24:48+05:30
51	9	Ride Cancelled	Booking ZG4C140564 is now cancelled	ride_update	\N	t	2026-05-15 12:27:15+05:30
52	17	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.32195	ride_request	{"booking_id":26}	f	2026-05-15 12:27:43+05:30
53	9	Driver on the way	faris accepted your ride ZGE3B7C386	ride_update	\N	t	2026-05-15 12:28:00+05:30
54	9	Ride Arrived	Booking ZGE3B7C386 is now arrived	ride_update	\N	t	2026-05-15 12:28:27+05:30
55	9	Ride Started	Booking ZGE3B7C386 is now started	ride_update	\N	t	2026-05-15 12:29:07+05:30
56	9	Ride Completed	Booking ZGE3B7C386 is now completed	ride_update	\N	t	2026-05-15 12:29:08+05:30
57	17	New ride request	78 UC Rd, Kinniya → Colombo, Sri Lanka • Rs.88828	ride_request	{"booking_id":27}	f	2026-05-15 12:32:36+05:30
58	9	Driver on the way	faris accepted your ride ZG078A0CD1	ride_update	\N	t	2026-05-15 12:32:38+05:30
59	9	Ride Arrived	Booking ZG078A0CD1 is now arrived	ride_update	\N	t	2026-05-15 12:32:50+05:30
60	9	Ride Started	Booking ZG078A0CD1 is now started	ride_update	\N	t	2026-05-15 12:32:53+05:30
61	9	Ride Completed	Booking ZG078A0CD1 is now completed	ride_update	\N	t	2026-05-15 12:32:55+05:30
62	9	Ride Cancelled	Booking ZGFF1E9D79 is now cancelled	ride_update	\N	t	2026-05-18 03:33:47+05:30
63	9	Ride Cancelled	Booking ZGCAA335AF is now cancelled	ride_update	\N	t	2026-05-18 04:23:29+05:30
64	9	Ride Cancelled	Booking ZG708EFB0B is now cancelled	ride_update	\N	t	2026-05-18 04:24:56+05:30
65	16	New ride request	78 UC Rd, Kinniya → Kinniya Beach, Kinniya, Sri Lanka • Rs.362	ride_request	{"booking_id":31}	f	2026-05-18 04:25:18+05:30
66	9	Ride Cancelled	Booking ZG1E109287 is now cancelled	ride_update	\N	t	2026-05-18 04:25:29+05:30
67	16	New ride request	78 UC Rd, Kinniya → Kinniya Beach, Kinniya, Sri Lanka • Rs.362	ride_request	{"booking_id":32}	f	2026-05-18 04:26:12+05:30
68	9	Driver on the way	aashik accepted your ride ZG30BEB225	ride_update	\N	t	2026-05-18 04:26:18+05:30
69	9	Ride Arrived	Booking ZG30BEB225 is now arrived	ride_update	\N	t	2026-05-18 04:26:26+05:30
70	9	Ride Started	Booking ZG30BEB225 is now started	ride_update	\N	t	2026-05-18 04:26:35+05:30
71	9	Ride Completed	Booking ZG30BEB225 is now completed	ride_update	\N	t	2026-05-18 04:26:38+05:30
72	16	New ride request	78 UC Rd, Kinniya → Kinniya Beach, Kinniya, Sri Lanka • Rs.362	ride_request	{"booking_id":33}	f	2026-05-18 04:27:18+05:30
73	9	Driver on the way	aashik accepted your ride ZG99A13F3D	ride_update	\N	t	2026-05-18 04:27:22+05:30
74	9	Ride Arrived	Booking ZG99A13F3D is now arrived	ride_update	\N	t	2026-05-18 04:27:36+05:30
75	9	Ride Started	Booking ZG99A13F3D is now started	ride_update	\N	t	2026-05-18 04:27:41+05:30
76	9	Ride Completed	Booking ZG99A13F3D is now completed	ride_update	\N	t	2026-05-18 04:27:46+05:30
77	9	Ride Cancelled	Booking ZG76A0D7E5 is now cancelled	ride_update	\N	f	2026-05-18 04:57:05+05:30
78	16	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.13396	ride_request	{"booking_id":35}	f	2026-05-18 04:57:18+05:30
79	9	Ride Cancelled	Booking ZGB92057A9 is now cancelled	ride_update	\N	f	2026-05-18 05:11:10+05:30
80	12	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.24113	ride_request	{"booking_id":37}	f	2026-05-18 05:11:42+05:30
81	16	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.24113	ride_request	{"booking_id":37}	f	2026-05-18 05:12:12+05:30
82	9	Ride Cancelled	Booking ZG6B67B1F2 is now cancelled	ride_update	\N	f	2026-05-18 05:16:16+05:30
83	12	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.24113	ride_request	{"booking_id":38}	f	2026-05-18 05:16:43+05:30
84	12	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.24113	ride_request	{"booking_id":39}	f	2026-05-18 05:17:27+05:30
85	16	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.24113	ride_request	{"booking_id":39}	f	2026-05-18 05:17:57+05:30
86	12	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.24113	ride_request	{"booking_id":39}	f	2026-05-18 05:18:27+05:30
87	16	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.24113	ride_request	{"booking_id":39}	f	2026-05-18 05:18:57+05:30
88	9	Ride Cancelled	Booking ZGB93C9771 is now cancelled	ride_update	\N	f	2026-05-18 05:27:02+05:30
89	9	Ride Cancelled	Booking ZGD6744B6D is now cancelled	ride_update	\N	f	2026-05-18 05:28:31+05:30
90	12	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.13396	ride_request	{"booking_id":41}	f	2026-05-18 05:28:38+05:30
91	9	Ride Cancelled	Booking ZGEEC2605A is now cancelled	ride_update	\N	f	2026-05-18 05:29:36+05:30
92	12	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.13396	ride_request	{"booking_id":42}	f	2026-05-18 05:29:43+05:30
93	16	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.13396	ride_request	{"booking_id":42}	f	2026-05-18 05:29:43+05:30
94	9	Driver on the way	aashik accepted your ride ZG08F5269B	ride_update	\N	f	2026-05-18 05:29:49+05:30
95	9	Ride Arrived	Booking ZG08F5269B is now arrived	ride_update	\N	f	2026-05-18 05:29:58+05:30
96	9	Ride Started	Booking ZG08F5269B is now started	ride_update	\N	f	2026-05-18 05:30:00+05:30
97	9	Ride Completed	Booking ZG08F5269B is now completed	ride_update	\N	f	2026-05-18 05:30:01+05:30
98	9	Ride Cancelled	Booking ZG9B87E75D is now cancelled	ride_update	\N	f	2026-05-18 05:58:28+05:30
99	12	New ride request	78 UC Rd, Kinniya → KSL Reception, Kalpitiya, Sri Lanka • Rs.14873	ride_request	{"booking_id":43}	f	2026-05-18 05:58:38+05:30
100	16	New ride request	78 UC Rd, Kinniya → KSL Reception, Kalpitiya, Sri Lanka • Rs.14873	ride_request	{"booking_id":43}	f	2026-05-18 05:58:38+05:30
101	9	Driver on the way	aashik accepted your ride ZG91FA0149	ride_update	\N	f	2026-05-18 05:58:56+05:30
102	9	Ride Arrived	Booking ZG91FA0149 is now arrived	ride_update	\N	f	2026-05-18 05:59:41+05:30
103	9	Ride Started	Booking ZG91FA0149 is now started	ride_update	\N	f	2026-05-18 05:59:44+05:30
104	9	Ride Completed	Booking ZG91FA0149 is now completed	ride_update	\N	f	2026-05-18 05:59:49+05:30
105	9	Ride Cancelled	Booking ZG375C9D2F is now cancelled	ride_update	\N	f	2026-05-18 06:06:22+05:30
106	12	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.24113	ride_request	{"booking_id":44}	f	2026-05-18 06:06:40+05:30
107	16	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.24113	ride_request	{"booking_id":44}	f	2026-05-18 06:06:40+05:30
108	9	Ride Cancelled	Booking ZGA786513E is now cancelled	ride_update	\N	f	2026-05-18 06:09:07+05:30
109	12	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.13396	ride_request	{"booking_id":46}	f	2026-05-18 06:09:20+05:30
110	16	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.13396	ride_request	{"booking_id":46}	f	2026-05-18 06:09:20+05:30
111	12	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.24113	ride_request	{"booking_id":47}	f	2026-05-18 06:16:52+05:30
112	16	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.24113	ride_request	{"booking_id":47}	f	2026-05-18 06:16:52+05:30
113	9	Driver on the way	driver test accepted your ride ZG5937EFBC	ride_update	\N	f	2026-05-18 06:17:03+05:30
114	9	Ride Arrived	Booking ZG5937EFBC is now arrived	ride_update	\N	f	2026-05-18 06:17:06+05:30
115	9	Ride Started	Booking ZG5937EFBC is now started	ride_update	\N	f	2026-05-18 06:17:09+05:30
116	9	Ride Completed	Booking ZG5937EFBC is now completed	ride_update	\N	f	2026-05-18 06:17:10+05:30
117	9	Ride Cancelled	Booking ZGD0C5A4C7 is now cancelled	ride_update	\N	f	2026-05-18 06:48:56+05:30
118	12	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.13396	ride_request	{"booking_id":49}	f	2026-05-18 06:59:53+05:30
119	9	Ride Cancelled	Booking ZG04369525 is now cancelled	ride_update	\N	f	2026-05-18 07:01:39+05:30
120	9	Ride Cancelled	Booking ZG1097CCFF is now cancelled	ride_update	\N	f	2026-05-18 07:02:27+05:30
121	12	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.13396	ride_request	{"booking_id":51}	f	2026-05-18 07:02:35+05:30
122	16	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.13396	ride_request	{"booking_id":51}	f	2026-05-18 07:02:35+05:30
123	9	Driver on the way	aashik accepted your ride ZG13520D56	ride_update	\N	f	2026-05-18 07:02:41+05:30
124	9	Ride Arrived	Booking ZG13520D56 is now arrived	ride_update	\N	f	2026-05-18 07:02:53+05:30
125	9	Ride Started	Booking ZG13520D56 is now started	ride_update	\N	f	2026-05-18 07:02:57+05:30
126	9	Ride Completed	Booking ZG13520D56 is now completed	ride_update	\N	f	2026-05-18 07:02:59+05:30
127	9	Ride Cancelled	Booking ZGF0D82524 is now cancelled	ride_update	\N	f	2026-05-18 07:04:13+05:30
128	12	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.24113	ride_request	{"booking_id":52}	f	2026-05-18 07:07:31+05:30
129	16	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.24113	ride_request	{"booking_id":52}	f	2026-05-18 07:07:31+05:30
130	9	Driver on the way	aashik accepted your ride ZG203F2F31	ride_update	\N	f	2026-05-18 07:07:35+05:30
131	9	Ride Arrived	Booking ZG203F2F31 is now arrived	ride_update	\N	f	2026-05-18 07:07:46+05:30
132	9	Ride Started	Booking ZG203F2F31 is now started	ride_update	\N	f	2026-05-18 07:07:50+05:30
133	9	Ride Completed	Booking ZG203F2F31 is now completed	ride_update	\N	f	2026-05-18 07:07:52+05:30
134	9	Ride Cancelled	Booking ZGC84CBA08 is now cancelled	ride_update	\N	f	2026-05-18 07:09:28+05:30
135	17	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.16695	ride_request	{"booking_id":54}	f	2026-05-18 07:09:36+05:30
136	9	Ride Cancelled	Booking ZG59550792 is now cancelled	ride_update	\N	f	2026-05-18 07:09:57+05:30
137	17	New ride request	78 UC Rd, Kinniya → Kadawatha, Sri Lanka • Rs.24177	ride_request	{"booking_id":55}	f	2026-05-18 07:10:10+05:30
138	9	Ride Cancelled	Booking ZG5D00F9BF is now cancelled	ride_update	\N	f	2026-05-18 07:10:26+05:30
139	9	Ride Cancelled	Booking ZG1E741695 is now cancelled	ride_update	\N	f	2026-05-18 07:10:44+05:30
140	17	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.9275	ride_request	{"booking_id":57}	f	2026-05-18 07:11:02+05:30
141	9	Ride Cancelled	Booking ZG73DEB025 is now cancelled	ride_update	\N	f	2026-05-18 07:11:06+05:30
142	9	Ride Cancelled	Booking ZGE4FC350D is now cancelled	ride_update	\N	f	2026-05-18 07:12:10+05:30
143	9	Ride Cancelled	Booking ZGD92817F4 is now cancelled	ride_update	\N	f	2026-05-18 07:12:12+05:30
144	17	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.9275	ride_request	{"booking_id":59}	f	2026-05-18 07:12:41+05:30
145	9	Driver on the way	faris accepted your ride ZG612D5D18	ride_update	\N	f	2026-05-18 07:12:45+05:30
146	9	Ride Arrived	Booking ZG612D5D18 is now arrived	ride_update	\N	f	2026-05-18 07:12:50+05:30
147	9	Ride Started	Booking ZG612D5D18 is now started	ride_update	\N	f	2026-05-18 07:12:51+05:30
148	9	Ride Completed	Booking ZG612D5D18 is now completed	ride_update	\N	f	2026-05-18 07:12:53+05:30
149	16	New ride request	78 UC Rd, Kinniya → Asiri Central Hospital - Central Hospital Limited, Norris Canal Road, Colombo, Sri Lanka • Rs.37051	ride_request	{"booking_id":60}	f	2026-05-18 07:13:32+05:30
150	9	Driver on the way	aashik accepted your ride ZG6446BBDB	ride_update	\N	f	2026-05-18 07:13:34+05:30
151	9	Ride Arrived	Booking ZG6446BBDB is now arrived	ride_update	\N	f	2026-05-18 07:13:36+05:30
152	9	Ride Started	Booking ZG6446BBDB is now started	ride_update	\N	f	2026-05-18 07:13:36+05:30
153	9	Ride Completed	Booking ZG6446BBDB is now completed	ride_update	\N	f	2026-05-18 07:13:37+05:30
154	17	New ride request	78 UC Rd, Kinniya → Kandy, Sri Lanka • Rs.9275	ride_request	{"booking_id":61}	f	2026-05-18 08:29:54+05:30
155	9	Ride Cancelled	Booking ZG73BE7EE5 is now cancelled	ride_update	\N	t	2026-05-18 08:30:49+05:30
156	17	New ride request	78 UC Rd, Kinniya → Jaffna, Sri Lanka • Rs.20484	ride_request	{"booking_id":62}	f	2026-05-18 08:31:39+05:30
157	9	Ride Cancelled	Booking ZGD4983182 is now cancelled	ride_update	\N	t	2026-05-18 08:31:45+05:30
158	16	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":6}	f	2026-05-18 10:18:44+05:30
159	17	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":6}	f	2026-05-18 10:18:44+05:30
160	16	New food delivery	sinthujan Hotel → Kinniya UC Rd test address • Rs.1150	food_request	{"food_order_id":7}	f	2026-05-18 10:26:43+05:30
161	17	New food delivery	sinthujan Hotel → Kinniya UC Rd test address • Rs.1150	food_request	{"food_order_id":7}	f	2026-05-18 10:26:43+05:30
162	18	Rider on the way	aashik accepted your order FOF080C5E9	order_update	\N	f	2026-05-18 10:26:43+05:30
163	18	Order Out For Delivery	Order FOF080C5E9 is now out for delivery	order_update	\N	f	2026-05-18 10:26:43+05:30
164	18	Order Delivered	Order FOF080C5E9 is now delivered	order_update	\N	f	2026-05-18 10:26:43+05:30
165	16	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":8}	f	2026-05-18 11:20:29+05:30
166	17	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":8}	f	2026-05-18 11:20:29+05:30
167	16	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":9}	f	2026-05-18 11:24:17+05:30
168	17	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":9}	f	2026-05-18 11:24:17+05:30
169	9	Rider on the way	aashik accepted your order FOA69EACFE	order_update	\N	t	2026-05-18 11:24:20+05:30
170	16	New food delivery	sinthujan Hotel → Kandy, Sri Lanka • Rs.650	food_request	{"food_order_id":10}	f	2026-05-18 11:25:00+05:30
171	17	New food delivery	sinthujan Hotel → Kandy, Sri Lanka • Rs.650	food_request	{"food_order_id":10}	f	2026-05-18 11:25:00+05:30
172	16	New food delivery	sinthujan Hotel → Kandy, Sri Lanka • Rs.650	food_request	{"food_order_id":11}	f	2026-05-18 11:27:28+05:30
173	17	New food delivery	sinthujan Hotel → Kandy, Sri Lanka • Rs.650	food_request	{"food_order_id":11}	f	2026-05-18 11:27:28+05:30
174	9	Rider on the way	aashik accepted your order FOE2277E0A	order_update	\N	t	2026-05-18 11:27:33+05:30
175	16	New food delivery	sinthujan Hotel → Jaffna, Sri Lanka • Rs.650	food_request	{"food_order_id":12}	f	2026-05-18 11:37:22+05:30
176	17	New food delivery	sinthujan Hotel → Jaffna, Sri Lanka • Rs.650	food_request	{"food_order_id":12}	f	2026-05-18 11:37:22+05:30
177	9	Order Out For Delivery	Order FOE2277E0A is now out for delivery	order_update	\N	t	2026-05-18 11:38:01+05:30
178	9	Order Delivered	Order FOE2277E0A is now delivered	order_update	\N	t	2026-05-18 11:38:07+05:30
179	16	New food delivery	sinthujan Hotel → Jaffna, Sri Lanka • Rs.650	food_request	{"food_order_id":13}	f	2026-05-18 11:38:19+05:30
180	17	New food delivery	sinthujan Hotel → Jaffna, Sri Lanka • Rs.650	food_request	{"food_order_id":13}	f	2026-05-18 11:38:19+05:30
181	9	Rider on the way	aashik accepted your order FOCC11749D	order_update	\N	t	2026-05-18 11:38:23+05:30
182	9	Order Out For Delivery	Order FOCC11749D is now out for delivery	order_update	\N	t	2026-05-18 11:38:33+05:30
183	9	Order Delivered	Order FOCC11749D is now delivered	order_update	\N	t	2026-05-18 11:38:40+05:30
184	17	New ride request	78 UC Rd, Kinniya → Kiribathgoda, Sri Lanka • Rs.24646	ride_request	{"booking_id":63}	f	2026-05-18 11:53:20+05:30
185	9	Driver on the way	faris accepted your ride ZGC65A5736	ride_update	\N	t	2026-05-18 11:53:22+05:30
186	9	Ride Arrived	Booking ZGC65A5736 is now arrived	ride_update	\N	t	2026-05-18 11:53:29+05:30
187	9	Ride Started	Booking ZGC65A5736 is now started	ride_update	\N	t	2026-05-18 11:53:30+05:30
188	9	Ride Completed	Booking ZGC65A5736 is now completed	ride_update	\N	t	2026-05-18 11:53:32+05:30
189	16	New food delivery	sinthujan Hotel → Kitulgala, Sri Lanka • Rs.650	food_request	{"food_order_id":14}	f	2026-05-18 11:54:20+05:30
190	17	New food delivery	sinthujan Hotel → Kitulgala, Sri Lanka • Rs.650	food_request	{"food_order_id":14}	f	2026-05-18 11:54:20+05:30
191	9	Rider on the way	aashik accepted your order FO7C9EBD5F	order_update	\N	t	2026-05-18 11:54:27+05:30
192	9	Order Out For Delivery	Order FO7C9EBD5F is now out for delivery	order_update	\N	t	2026-05-18 11:54:34+05:30
193	9	Order Delivered	Order FO7C9EBD5F is now delivered	order_update	\N	t	2026-05-18 11:54:37+05:30
194	16	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":15}	f	2026-05-18 11:54:56+05:30
195	17	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":15}	f	2026-05-18 11:54:56+05:30
196	9	Rider on the way	aashik accepted your order FO5E7A397F	order_update	\N	t	2026-05-18 11:54:59+05:30
197	9	Order Out For Delivery	Order FO5E7A397F is now out for delivery	order_update	\N	t	2026-05-18 11:55:13+05:30
198	9	Order Delivered	Order FO5E7A397F is now delivered	order_update	\N	t	2026-05-18 11:55:22+05:30
199	17	New ride request	78 UC Rd, Kinniya → Kitulgala, Sri Lanka • Rs.21171	ride_request	{"booking_id":64}	f	2026-05-18 12:05:35+05:30
200	9	Ride Cancelled	Booking ZG0830E45E is now cancelled	ride_update	\N	t	2026-05-18 12:07:11+05:30
201	9	Ride Cancelled	Booking FL68FB0645 is now cancelled	ride_update	\N	t	2026-05-18 12:08:54+05:30
202	16	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":16}	f	2026-05-18 12:17:30+05:30
203	17	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":16}	f	2026-05-18 12:17:30+05:30
204	9	Rider on the way	aashik accepted your order FOFDDA82FA	order_update	\N	t	2026-05-18 12:17:33+05:30
205	9	Order Out For Delivery	Order FOFDDA82FA is now out for delivery	order_update	\N	t	2026-05-18 12:17:39+05:30
206	9	Order Delivered	Order FOFDDA82FA is now delivered	order_update	\N	t	2026-05-18 12:17:44+05:30
207	9	Order Out For Delivery	Order FOA69EACFE is now out for delivery	order_update	\N	t	2026-05-18 12:27:10+05:30
208	9	Order Delivered	Order FOA69EACFE is now delivered	order_update	\N	t	2026-05-18 12:27:11+05:30
209	9	Ride Cancelled	Booking FL459D7F31 is now cancelled	ride_update	\N	t	2026-05-18 12:27:23+05:30
210	16	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":17}	f	2026-05-18 12:27:29+05:30
211	17	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":17}	f	2026-05-18 12:27:29+05:30
212	9	Rider on the way	aashik accepted your order FO24447C92	order_update	\N	t	2026-05-18 12:27:32+05:30
213	9	Order Out For Delivery	Order FO24447C92 is now out for delivery	order_update	\N	t	2026-05-18 12:27:36+05:30
214	9	Order Delivered	Order FO24447C92 is now delivered	order_update	\N	t	2026-05-18 12:27:43+05:30
215	16	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":18}	f	2026-05-18 12:52:56+05:30
216	17	New food delivery	sinthujan Hotel → Hashnate, Kinniya, Sri Lanka • Rs.650	food_request	{"food_order_id":18}	f	2026-05-18 12:52:56+05:30
217	9	Order auto-cancelled	Order FO1040B665 was cancelled because the restaurant didn't respond. Wallet payments have been refunded.	order_update	\N	t	2026-05-19 04:17:33+05:30
218	9	Order auto-cancelled	Order FO642B188E was cancelled because the restaurant didn't respond. Wallet payments have been refunded.	order_update	\N	t	2026-05-19 04:17:33+05:30
219	9	Order auto-cancelled	Order FO823F54A9 was cancelled because the restaurant didn't respond. Wallet payments have been refunded.	order_update	\N	t	2026-05-19 04:17:33+05:30
220	9	Order auto-cancelled	Order FO1719BF00 was cancelled because the restaurant didn't respond. Wallet payments have been refunded.	order_update	\N	t	2026-05-19 04:17:33+05:30
221	9	Order auto-cancelled	Order FOBEDB1C23 was cancelled because the restaurant didn't respond. Wallet payments have been refunded.	order_update	\N	t	2026-05-19 04:17:33+05:30
222	9	Order auto-cancelled	Order FOAF6646C3 was cancelled because the restaurant didn't respond. Wallet payments have been refunded.	order_update	\N	t	2026-05-19 04:17:33+05:30
223	9	Order auto-cancelled	Order FO099AE714 was cancelled because the restaurant didn't respond. Wallet payments have been refunded.	order_update	\N	t	2026-05-19 04:17:33+05:30
224	9	Order auto-cancelled	Order FO1F6BBC84 was cancelled because the restaurant didn't respond. Wallet payments have been refunded.	order_update	\N	t	2026-05-19 04:17:33+05:30
225	9	Order auto-cancelled	Order FO3067B1F3 was cancelled because the restaurant didn't respond. Wallet payments have been refunded.	order_update	\N	t	2026-05-19 04:17:33+05:30
226	9	Order auto-cancelled	Order FOD15F6C98 was cancelled because the restaurant didn't respond. Wallet payments have been refunded.	order_update	\N	t	2026-05-19 04:17:33+05:30
227	20	New food order	2 item(s) • Rs.880 • FOB4E26A35	new_food_order	{"food_order_id":19}	f	2026-05-19 04:19:49+05:30
228	20	New food order	2 item(s) • Rs.880 • FO17F2C2DF	new_food_order	{"food_order_id":20}	f	2026-05-19 04:20:25+05:30
229	18	Order confirmed	The restaurant is preparing your order FO17F2C2DF	order_update	\N	f	2026-05-19 04:20:26+05:30
230	20	New food order	2 item(s) • Rs.880 • FOA2271D0E	new_food_order	{"food_order_id":21}	f	2026-05-19 04:21:39+05:30
231	18	Order confirmed	The restaurant is preparing your order FOA2271D0E	order_update	\N	f	2026-05-19 04:21:39+05:30
232	16	New food delivery	Hashnate Bistro → Kinniya UC Rd • Rs.880	food_request	{"food_order_id":21}	f	2026-05-19 04:21:39+05:30
233	18	Rider on the way	aashik accepted your order FOA2271D0E	order_update	\N	f	2026-05-19 04:21:39+05:30
234	18	Order Out For Delivery	Order FOA2271D0E is now out for delivery	order_update	\N	f	2026-05-19 04:21:39+05:30
235	18	Order Delivered	Order FOA2271D0E is now delivered	order_update	\N	f	2026-05-19 04:21:39+05:30
236	20	New food order	2 item(s) • Rs.880 • FO7E075992	new_food_order	{"food_order_id":22}	f	2026-05-19 04:21:39+05:30
237	18	Order rejected	Order FO7E075992: Out of ingredients	order_update	\N	f	2026-05-19 04:21:39+05:30
238	20	New food order	2 item(s) • Rs.880 • FO0AE7B9BD	new_food_order	{"food_order_id":23}	f	2026-05-19 04:21:39+05:30
239	18	Order auto-cancelled	Order FO0AE7B9BD was cancelled because the restaurant didn't respond. Wallet payments have been refunded.	order_update	\N	f	2026-05-19 04:21:58+05:30
240	20	New food order	2 item(s) • Rs.880 • FO6A325428	new_food_order	{"food_order_id":24}	f	2026-05-19 04:22:06+05:30
241	18	Order confirmed	The restaurant is preparing your order FO6A325428	order_update	\N	f	2026-05-19 04:22:06+05:30
242	16	New food delivery	Hashnate Bistro → Kinniya UC Rd • Rs.880	food_request	{"food_order_id":24}	f	2026-05-19 04:22:06+05:30
243	18	Rider on the way	aashik accepted your order FO6A325428	order_update	\N	f	2026-05-19 04:22:06+05:30
244	18	Order Out For Delivery	Order FO6A325428 is now out for delivery	order_update	\N	f	2026-05-19 04:22:06+05:30
245	18	Order Delivered	Order FO6A325428 is now delivered	order_update	\N	f	2026-05-19 04:22:06+05:30
246	20	New food order	2 item(s) • Rs.880 • FOD0159B56	new_food_order	{"food_order_id":25}	f	2026-05-19 04:22:06+05:30
247	18	Order rejected	Order FOD0159B56: Out of ingredients	order_update	\N	f	2026-05-19 04:22:06+05:30
248	20	New food order	2 item(s) • Rs.880 • FO3B09F1D3	new_food_order	{"food_order_id":26}	f	2026-05-19 04:22:06+05:30
249	18	Order auto-cancelled	Order FO3B09F1D3 was cancelled because the restaurant didn't respond. Wallet payments have been refunded.	order_update	\N	f	2026-05-19 04:22:07+05:30
250	18	Order auto-cancelled	Order FOB4E26A35 was cancelled because the restaurant didn't respond. Wallet payments have been refunded.	order_update	\N	f	2026-05-19 04:25:01+05:30
251	20	New food order	1 item(s) • Rs.530 • FO6414CCDD	new_food_order	{"food_order_id":27}	f	2026-05-19 05:33:38+05:30
252	9	Order confirmed	The restaurant is preparing your order FO6414CCDD	order_update	\N	t	2026-05-19 05:33:44+05:30
253	9	Your food is being prepared	The chef has started cooking your order FO6414CCDD	order_update	\N	t	2026-05-19 05:33:57+05:30
254	16	New food delivery	Hashnate Bistro → Kandy, Sri Lanka • Rs.530	food_request	{"food_order_id":27}	f	2026-05-19 05:34:03+05:30
255	9	Rider on the way	aashik accepted your order FO6414CCDD	order_update	\N	t	2026-05-19 05:34:08+05:30
256	9	Order Out For Delivery	Order FO6414CCDD is now out for delivery	order_update	\N	t	2026-05-19 05:34:13+05:30
257	9	Order Delivered	Order FO6414CCDD is now delivered	order_update	\N	t	2026-05-19 05:34:21+05:30
258	20	New food order	1 item(s) • Rs.530 • FO4D532010	new_food_order	{"food_order_id":28}	f	2026-05-19 05:36:47+05:30
259	9	Order confirmed	The restaurant is preparing your order FO4D532010	order_update	\N	t	2026-05-19 05:36:55+05:30
260	9	Your food is being prepared	The chef has started cooking your order FO4D532010	order_update	\N	t	2026-05-19 05:37:01+05:30
261	16	New food delivery	Hashnate Bistro → Kandy, Sri Lanka • Rs.530	food_request	{"food_order_id":28}	f	2026-05-19 05:37:04+05:30
262	9	Rider on the way	aashik accepted your order FO4D532010	order_update	\N	t	2026-05-19 05:37:13+05:30
263	9	Order Out For Delivery	Order FO4D532010 is now out for delivery	order_update	\N	t	2026-05-19 05:37:28+05:30
264	9	Order Delivered	Order FO4D532010 is now delivered	order_update	\N	t	2026-05-19 05:37:35+05:30
265	24	New market order	1 item(s) • Rs.200 • MKD8D0C080	new_market_order	{"market_order_id":6}	f	2026-05-19 10:23:06+05:30
266	20	New food order	1 item(s) • Rs.530 • FOCBAA78D4	new_food_order	{"food_order_id":30}	f	2026-05-19 10:23:45+05:30
267	9	Order confirmed	The restaurant is preparing your order FOCBAA78D4	order_update	\N	t	2026-05-19 10:23:55+05:30
268	9	Your food is being prepared	The chef has started cooking your order FOCBAA78D4	order_update	\N	t	2026-05-19 10:24:02+05:30
269	16	New food delivery	Hashnate Bistro → Hashnate, Kinniya, Sri Lanka • Rs.530	food_request	{"food_order_id":30}	f	2026-05-19 10:25:03+05:30
270	9	Rider on the way	aashik accepted your order FOCBAA78D4	order_update	\N	t	2026-05-19 10:25:06+05:30
271	9	Order Out For Delivery	Order FOCBAA78D4 is now out for delivery	order_update	\N	t	2026-05-19 10:25:09+05:30
272	9	Order Delivered	Order FOCBAA78D4 is now delivered	order_update	\N	t	2026-05-19 10:25:13+05:30
273	24	New market order	1 item(s) • Rs.200 • MK8472B6C7	new_market_order	{"market_order_id":7}	f	2026-05-19 10:26:27+05:30
274	9	Order confirmed	The store is packing your order MKD8D0C080	market_order_update	\N	t	2026-05-19 10:26:34+05:30
275	24	New market order	1 item(s) • Rs.200 • MK5C45BB18	new_market_order	{"market_order_id":8}	f	2026-05-19 10:43:45+05:30
276	9	Order rejected	Order MK8472B6C7: Out of stock	market_order_update	\N	t	2026-05-19 10:43:56+05:30
277	25	New market order	1 item(s) • Rs.3849 • MKC6432A12	new_market_order	{"market_order_id":9}	f	2026-05-19 10:46:37+05:30
278	25	New market order	1 item(s) • Rs.3849 • MK94061561	new_market_order	{"market_order_id":10}	f	2026-05-19 10:52:32+05:30
279	25	New market order	1 item(s) • Rs.3849 • MKE2F7031B	new_market_order	{"market_order_id":11}	f	2026-05-19 10:52:57+05:30
280	25	New market order	1 item(s) • Rs.3849 • MK3BEAED17	new_market_order	{"market_order_id":12}	f	2026-05-19 10:56:40+05:30
281	25	New market order	1 item(s) • Rs.3849 • MKB9481AE4	new_market_order	{"market_order_id":13}	f	2026-05-19 11:01:56+05:30
282	9	Order confirmed	The store is packing your order MKB9481AE4	market_order_update	\N	t	2026-05-19 11:02:08+05:30
283	9	Order rejected	Order MKC6432A12: Closing early today	market_order_update	\N	t	2026-05-19 11:02:42+05:30
284	9	Order rejected	Order MK3BEAED17: Store is closed	market_order_update	\N	t	2026-05-19 11:02:48+05:30
285	9	Order rejected	Order MKE2F7031B: Cannot reach customer	market_order_update	\N	t	2026-05-19 11:03:03+05:30
286	9	Order rejected	Order MK94061561: Store too busy right now	market_order_update	\N	t	2026-05-19 11:03:09+05:30
287	25	New market order	1 item(s) • Rs.3849 • MK9A7B4021	new_market_order	{"market_order_id":14}	f	2026-05-19 11:03:17+05:30
288	9	Order confirmed	The store is packing your order MK9A7B4021	market_order_update	\N	t	2026-05-19 11:03:22+05:30
289	25	New market order	1 item(s) • Rs.3849 • MK145D8E0F	new_market_order	{"market_order_id":15}	f	2026-05-19 11:03:53+05:30
290	9	Order confirmed	The store is packing your order MK145D8E0F	market_order_update	\N	t	2026-05-19 11:03:59+05:30
291	25	New market order	1 item(s) • Rs.3849 • MKF5FBA66F	new_market_order	{"market_order_id":16}	f	2026-05-19 11:10:13+05:30
292	9	Order confirmed	The store is packing your order MKF5FBA66F	market_order_update	\N	t	2026-05-19 11:10:23+05:30
293	25	No riders available	Order MKF5FBA66F: No riders are online within 10km of your stall. Try again in a few minutes.	no_riders_for_market_order	{"market_order_id":16}	f	2026-05-19 11:10:30+05:30
294	25	New market order	1 item(s) • Rs.3849 • MK1A9E3C29	new_market_order	{"market_order_id":17}	f	2026-05-19 11:18:30+05:30
295	9	Order confirmed	The store is packing your order MK1A9E3C29	market_order_update	\N	t	2026-05-19 11:18:36+05:30
296	16	New market delivery	qwerty pvt ltd → Hashnate, Kinniya, Sri Lanka • Rs.3849	market_request	{"market_order_id":17}	f	2026-05-19 11:19:02+05:30
297	9	Rider on the way	aashik accepted your order MK1A9E3C29	market_order_update	\N	t	2026-05-19 11:19:05+05:30
298	9	Order Out For Delivery	Order MK1A9E3C29 is now out for delivery	market_order_update	\N	t	2026-05-19 11:19:09+05:30
299	9	Order Delivered	Order MK1A9E3C29 is now delivered	market_order_update	\N	t	2026-05-19 11:19:14+05:30
300	25	New market order	1 item(s) • Rs.3849 • MK90990CFF	new_market_order	{"market_order_id":18}	f	2026-05-19 11:26:33+05:30
301	9	Order rejected	Order MK90990CFF: Cannot reach customer	market_order_update	\N	t	2026-05-19 11:26:40+05:30
302	16	New ride request	78 UC Rd, Kinniya → Habarana, Sri Lanka • Rs.6460	ride_request	{"booking_id":67}	f	2026-05-19 11:31:36+05:30
303	9	Ride Cancelled	Booking ZG513D0BA5 is now cancelled	ride_update	\N	t	2026-05-19 11:31:58+05:30
304	16	New ride request	78 UC Rd, Kinniya → Habarana, Sri Lanka • Rs.6460	ride_request	{"booking_id":68}	f	2026-05-19 11:32:09+05:30
305	9	Driver on the way	aashik accepted your ride ZGFB97C669	ride_update	\N	t	2026-05-19 11:32:11+05:30
306	9	Ride Arrived	Booking ZGFB97C669 is now arrived	ride_update	\N	t	2026-05-19 11:32:15+05:30
307	9	Ride Started	Booking ZGFB97C669 is now started	ride_update	\N	t	2026-05-19 11:32:16+05:30
308	9	Ride Completed	Booking ZGFB97C669 is now completed	ride_update	\N	t	2026-05-19 11:32:17+05:30
309	9	Order rejected	Order MK5C45BB18: Cannot reach customer	market_order_update	\N	t	2026-05-19 11:34:05+05:30
310	24	New market order	1 item(s) • Rs.200 • MK664F2776	new_market_order	{"market_order_id":19}	f	2026-05-19 11:34:31+05:30
311	9	Order confirmed	The store is packing your order MK664F2776	market_order_update	\N	t	2026-05-19 11:34:35+05:30
312	16	New market delivery	FRS BAKERS → Hashnate, Kinniya, Sri Lanka • Rs.200	market_request	{"market_order_id":19}	f	2026-05-19 11:34:43+05:30
313	16	New market delivery	FRS BAKERS → Hashnate, Kinniya, Sri Lanka • Rs.200	market_request	{"market_order_id":19}	f	2026-05-19 11:34:48+05:30
314	9	Rider on the way	aashik accepted your order MK664F2776	market_order_update	\N	t	2026-05-19 11:34:50+05:30
315	9	Order Out For Delivery	Order MK664F2776 is now out for delivery	market_order_update	\N	t	2026-05-19 11:34:56+05:30
316	9	Order Delivered	Order MK664F2776 is now delivered	market_order_update	\N	t	2026-05-19 11:35:02+05:30
317	24	New market order	1 item(s) • Rs.200 • MK6ABA4525	new_market_order	{"market_order_id":20}	f	2026-05-19 11:36:17+05:30
318	9	Order rejected	Order MK6ABA4525: Closing early today	market_order_update	\N	t	2026-05-19 11:36:26+05:30
319	24	New market order	1 item(s) • Rs.200 • MK8A7E45EE	new_market_order	{"market_order_id":21}	f	2026-05-19 12:21:41+05:30
322	19	New ride request	Kinniya, Sri Lanka → Trincomalee, Sri Lanka • Rs.492	ride_request	{"booking_id":70}	f	2026-05-20 11:55:45.968673+05:30
321	9	Ride Cancelled	Booking FLF084D13D is now cancelled	ride_update	\N	t	2026-05-20 11:55:24.141258+05:30
320	9	Order rejected	Order MK8A7E45EE: Out of stock	market_order_update	\N	t	2026-05-19 12:29:02+05:30
323	9	Driver on the way	muzakkir accepted your ride ZG21056715	ride_update	\N	t	2026-05-20 11:55:56.998474+05:30
327	20	New food order	1 item(s) • Rs.530 • FOC4701FC7	new_food_order	{"food_order_id":31}	f	2026-05-20 11:58:01.536424+05:30
330	17	New food delivery	Hashnate Bistro → Hashnate, Kinniya, Sri Lanka • Rs.530	food_request	{"food_order_id":31}	f	2026-05-20 11:58:18.109284+05:30
334	25	Stall suspended	qwerty pvt ltd has been suspended by admin. Contact support for details.	vendor_suspended	\N	f	2026-05-20 12:08:07.605336+05:30
335	25	Stall reactivated	qwerty pvt ltd is live again on Ziggo Mart. You can accept orders now.	vendor_approved	\N	f	2026-05-20 12:08:13.885813+05:30
336	25	New market order	1 item(s) • Rs.3850 • MK38947461	new_market_order	{"market_order_id":22}	f	2026-05-20 12:09:15.537229+05:30
338	17	New market delivery	qwerty pvt ltd → Hashnate, Kinniya, Sri Lanka • Rs.3850	market_request	{"market_order_id":22}	f	2026-05-20 12:09:27.390994+05:30
341	9	Order Delivered	Order MK38947461 is now delivered	market_order_update	\N	t	2026-05-20 12:09:38.009637+05:30
340	9	Order Out For Delivery	Order MK38947461 is now out for delivery	market_order_update	\N	t	2026-05-20 12:09:34.458759+05:30
339	9	Rider on the way	faris accepted your order MK38947461	market_order_update	\N	t	2026-05-20 12:09:30.387591+05:30
337	9	Order confirmed	The store is packing your order MK38947461	market_order_update	\N	t	2026-05-20 12:09:20.536688+05:30
333	9	Order Delivered	Order FOC4701FC7 is now delivered	order_update	\N	t	2026-05-20 11:58:34.122913+05:30
332	9	Order Out For Delivery	Order FOC4701FC7 is now out for delivery	order_update	\N	t	2026-05-20 11:58:31.129388+05:30
331	9	Rider on the way	faris accepted your order FOC4701FC7	order_update	\N	t	2026-05-20 11:58:24.408968+05:30
329	9	Your food is being prepared	The chef has started cooking your order FOC4701FC7	order_update	\N	t	2026-05-20 11:58:13.880833+05:30
328	9	Order confirmed	The restaurant is preparing your order FOC4701FC7	order_update	\N	t	2026-05-20 11:58:09.185727+05:30
326	9	Ride Completed	Booking ZG21056715 is now completed	ride_update	\N	t	2026-05-20 11:56:33.728699+05:30
325	9	Ride Started	Booking ZG21056715 is now started	ride_update	\N	t	2026-05-20 11:56:29.856788+05:30
324	9	Ride Arrived	Booking ZG21056715 is now arrived	ride_update	\N	t	2026-05-20 11:56:25.940001+05:30
342	9	Ride Cancelled	Booking FL89872701 is now cancelled	ride_update	\N	f	2026-05-20 12:13:59.330056+05:30
343	17	New parcel delivery	document • Kinniya, Sri Lanka → Kandy, Sri Lanka • Rs.5991	flash_request	{"booking_id":72}	f	2026-05-20 12:14:16.37499+05:30
344	9	Driver on the way	faris accepted your ride FL95331048	ride_update	\N	f	2026-05-20 12:14:24.06238+05:30
345	9	Ride Arrived	Booking FL95331048 is now arrived	ride_update	\N	f	2026-05-20 12:14:36.400756+05:30
346	9	Ride Started	Booking FL95331048 is now started	ride_update	\N	f	2026-05-20 12:14:41.016436+05:30
347	9	Ride Completed	Booking FL95331048 is now completed	ride_update	\N	f	2026-05-20 12:14:43.826425+05:30
348	17	New parcel delivery	clothes • Kinniya, Sri Lanka → Kanthale, Sri Lanka • Rs.1237	flash_request	{"booking_id":73}	f	2026-05-20 12:18:15.680549+05:30
349	9	Driver on the way	faris accepted your ride FLBE869150	ride_update	\N	f	2026-05-20 12:18:19.776223+05:30
350	9	Ride Arrived	Booking FLBE869150 is now arrived	ride_update	\N	f	2026-05-20 12:18:22.923076+05:30
351	9	Ride Started	Booking FLBE869150 is now started	ride_update	\N	f	2026-05-20 12:18:28.706316+05:30
352	9	Ride Completed	Booking FLBE869150 is now completed	ride_update	\N	f	2026-05-20 12:18:30.977181+05:30
353	9	Ride Cancelled	Booking ZG2E3FB148 is now cancelled	ride_update	\N	f	2026-05-20 12:42:02.597293+05:30
354	9	Ride Cancelled	Booking RT2237AFD2 is now cancelled	ride_update	\N	f	2026-05-20 12:54:00.157656+05:30
355	9	Ride Cancelled	Booking RT7B716D4E is now cancelled	ride_update	\N	f	2026-05-20 12:56:50.265089+05:30
356	16	New ride request	78 UC Rd, Kinniya → Trincomalee, Sri Lanka • Rs.1042	ride_request	{"booking_id":77}	f	2026-05-20 18:45:45.770382+05:30
357	9	Driver on the way	aashik accepted your ride ZG2203733C	ride_update	\N	f	2026-05-20 18:46:15.438809+05:30
358	9	Ride Arrived	Booking ZG2203733C is now arrived	ride_update	\N	f	2026-05-20 18:48:08.217855+05:30
359	9	Ride Started	Booking ZG2203733C is now started	ride_update	\N	f	2026-05-20 18:48:14.426635+05:30
360	9	Ride Completed	Booking ZG2203733C is now completed	ride_update	\N	f	2026-05-20 18:48:41.508968+05:30
\.


--
-- Data for Name: otp_codes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.otp_codes (id, phone_number, code, is_used, expires_at, created_at) FROM stdin;
1	+94771234599	762701	t	2026-05-13 06:37:01.064109+05:30	2026-05-13 06:32:01+05:30
2	+94759137509	594693	t	2026-05-13 06:56:25.294051+05:30	2026-05-13 06:51:25+05:30
3	+947859137809	353095	t	2026-05-13 07:00:01.725809+05:30	2026-05-13 06:55:01+05:30
4	+94759137509	493572	t	2026-05-13 07:04:18.306203+05:30	2026-05-13 06:59:18+05:30
5	+947859137809	134777	t	2026-05-13 07:04:57.19476+05:30	2026-05-13 06:59:57+05:30
6	+94759137509	895779	f	2026-05-13 07:08:27.075971+05:30	2026-05-13 07:03:27+05:30
7	+947859137509	761649	t	2026-05-13 07:09:03.023491+05:30	2026-05-13 07:04:03+05:30
8	0759137509	596260	t	2026-05-13 09:13:38.69595+05:30	2026-05-13 09:08:38+05:30
9	0759137509	471642	t	2026-05-13 09:45:25.718038+05:30	2026-05-13 09:40:25+05:30
10	0785913750	773766	t	2026-05-13 09:46:16.461449+05:30	2026-05-13 09:41:16+05:30
11	0785913750	809922	t	2026-05-13 09:52:26.735547+05:30	2026-05-13 09:47:26+05:30
12	0770000111	153540	t	2026-05-13 09:53:35.711514+05:30	2026-05-13 09:48:35+05:30
13	0770000111	362105	t	2026-05-13 09:54:19.397804+05:30	2026-05-13 09:49:19+05:30
14	0770000222	567267	t	2026-05-13 09:54:19.436289+05:30	2026-05-13 09:49:19+05:30
15	0770000111	216829	t	2026-05-13 09:54:48.875812+05:30	2026-05-13 09:49:48+05:30
16	0770000222	732973	t	2026-05-13 09:54:48.905666+05:30	2026-05-13 09:49:48+05:30
17	0770000333	487916	t	2026-05-13 09:54:49.024347+05:30	2026-05-13 09:49:49+05:30
18	0770000111	874745	t	2026-05-13 09:55:41.502657+05:30	2026-05-13 09:50:41+05:30
19	0770000333	789389	t	2026-05-13 09:57:12.93634+05:30	2026-05-13 09:52:12+05:30
20	0785913750	346529	t	2026-05-13 09:59:48.298643+05:30	2026-05-13 09:54:48+05:30
21	0770000333	131223	t	2026-05-13 10:00:11.743653+05:30	2026-05-13 09:55:11+05:30
22	0785913750	762601	t	2026-05-13 10:02:06.005778+05:30	2026-05-13 09:57:06+05:30
23	0785913750	142166	t	2026-05-13 10:15:14.907626+05:30	2026-05-13 10:10:14+05:30
24	0700000000	752308	t	2026-05-13 10:21:16.262359+05:30	2026-05-13 10:16:16+05:30
25	0785913750	271133	t	2026-05-13 10:21:27.437744+05:30	2026-05-13 10:16:27+05:30
26	0785913750	849535	t	2026-05-13 10:57:31.419563+05:30	2026-05-13 10:52:31+05:30
27	0779990001	834155	t	2026-05-13 11:08:31.966506+05:30	2026-05-13 11:03:32+05:30
28	0779990001	926530	t	2026-05-13 11:08:32.019975+05:30	2026-05-13 11:03:32+05:30
29	0770000222	519883	t	2026-05-13 11:08:32.059726+05:30	2026-05-13 11:03:32+05:30
30	0770000222	152183	t	2026-05-13 11:08:32.069541+05:30	2026-05-13 11:03:32+05:30
31	0785913750	127824	t	2026-05-13 11:11:17.927348+05:30	2026-05-13 11:06:17+05:30
32	0785913750	018346	t	2026-05-13 11:12:27.895052+05:30	2026-05-13 11:07:27+05:30
33	0785937509	590100	t	2026-05-13 11:16:02.695261+05:30	2026-05-13 11:11:02+05:30
34	0785913750	389665	t	2026-05-13 11:17:20.874762+05:30	2026-05-13 11:12:20+05:30
35	0785913750	736400	t	2026-05-13 11:29:36.823226+05:30	2026-05-13 11:24:36+05:30
36	0785913750	874397	t	2026-05-13 11:42:29.18278+05:30	2026-05-13 11:37:29+05:30
37	0785913750	060186	t	2026-05-13 11:46:11.4918+05:30	2026-05-13 11:41:11+05:30
38	0785913750	129478	t	2026-05-13 11:47:14.640541+05:30	2026-05-13 11:42:14+05:30
39	0785913750	296065	t	2026-05-13 11:54:26.471065+05:30	2026-05-13 11:49:26+05:30
40	0785913750	421027	t	2026-05-13 11:55:10.95443+05:30	2026-05-13 11:50:10+05:30
41	0785913750	738032	t	2026-05-14 05:07:57.589046+05:30	2026-05-14 05:02:57+05:30
42	0785913750	465058	t	2026-05-14 10:11:59.48222+05:30	2026-05-14 10:06:59+05:30
43	0785913750	956491	t	2026-05-14 10:27:48.567528+05:30	2026-05-14 10:22:48+05:30
44	0785913750	153289	t	2026-05-14 10:29:12.950701+05:30	2026-05-14 10:24:12+05:30
45	0785913750	375997	t	2026-05-14 10:31:22.276151+05:30	2026-05-14 10:26:22+05:30
46	0785913750	172358	t	2026-05-14 12:02:03.320826+05:30	2026-05-14 11:57:03+05:30
47	0770000333	038052	t	2026-05-14 12:08:42.30442+05:30	2026-05-14 12:03:42+05:30
48	0785913750	775242	t	2026-05-14 12:09:17.189555+05:30	2026-05-14 12:04:17+05:30
49	0785913750	934579	t	2026-05-15 03:45:55.042986+05:30	2026-05-15 03:40:55+05:30
50	0785913750	001077	t	2026-05-15 03:50:40.486931+05:30	2026-05-15 03:45:40+05:30
51	0785913750	056367	t	2026-05-15 03:52:37.435707+05:30	2026-05-15 03:47:37+05:30
52	0785913750	999388	t	2026-05-15 03:59:06.866736+05:30	2026-05-15 03:54:06+05:30
53	0785913750	211486	t	2026-05-15 04:11:24.071863+05:30	2026-05-15 04:06:24+05:30
54	0785913750	196200	t	2026-05-15 04:14:42.959694+05:30	2026-05-15 04:09:42+05:30
55	0785913750	140706	t	2026-05-15 04:17:20.598979+05:30	2026-05-15 04:12:20+05:30
56	0785913750	985365	t	2026-05-15 04:19:19.865321+05:30	2026-05-15 04:14:19+05:30
57	0770000333	405862	t	2026-05-15 04:21:29.769331+05:30	2026-05-15 04:16:29+05:30
58	0785913750	542148	t	2026-05-15 04:23:12.083229+05:30	2026-05-15 04:18:12+05:30
59	0785913750	160124	t	2026-05-15 04:25:45.455439+05:30	2026-05-15 04:20:45+05:30
60	0785913750	831795	t	2026-05-15 04:36:48.800221+05:30	2026-05-15 04:31:48+05:30
61	0770000333	237727	t	2026-05-15 04:52:36.582846+05:30	2026-05-15 04:47:36+05:30
62	0785913750	092817	t	2026-05-15 04:54:50.339651+05:30	2026-05-15 04:49:50+05:30
63	0785913750	168864	t	2026-05-15 05:30:52.041936+05:30	2026-05-15 05:25:52+05:30
64	0785913750	732788	t	2026-05-15 06:00:32.2294+05:30	2026-05-15 05:55:32+05:30
65	0770000333	688501	t	2026-05-15 06:13:31.020007+05:30	2026-05-15 06:08:31+05:30
66	0785913750	878896	t	2026-05-15 06:14:03.468211+05:30	2026-05-15 06:09:03+05:30
67	0785913750	409737	t	2026-05-15 09:56:32.81036+05:30	2026-05-15 09:51:32+05:30
68	0785913750	326104	t	2026-05-15 09:58:30.130101+05:30	2026-05-15 09:53:30+05:30
69	0785913750	003447	t	2026-05-15 09:59:52.956919+05:30	2026-05-15 09:54:52+05:30
70	0785913750	132134	t	2026-05-15 10:08:35.459294+05:30	2026-05-15 10:03:35+05:30
71	0770000333	485523	t	2026-05-15 11:33:02.387975+05:30	2026-05-15 11:28:02+05:30
72	0785913750	407967	t	2026-05-15 11:36:56.315922+05:30	2026-05-15 11:31:56+05:30
73	0770000333	527947	t	2026-05-15 11:38:40.263509+05:30	2026-05-15 11:33:40+05:30
74	0770000333	754862	t	2026-05-15 11:41:31.327903+05:30	2026-05-15 11:36:31+05:30
75	0757048001	619267	t	2026-05-15 11:57:30.268769+05:30	2026-05-15 11:52:30+05:30
76	0785913750	956231	t	2026-05-15 11:58:02.654753+05:30	2026-05-15 11:53:02+05:30
77	0757048001	524709	t	2026-05-15 12:05:35.642498+05:30	2026-05-15 12:00:35+05:30
78	0755960594	443567	t	2026-05-15 12:26:39.171526+05:30	2026-05-15 12:21:39+05:30
79	0785913750	406257	t	2026-05-18 04:22:08.961362+05:30	2026-05-18 04:17:08+05:30
80	0757048001	183305	t	2026-05-18 04:28:38.888058+05:30	2026-05-18 04:23:38+05:30
81	0785913750	732565	t	2026-05-18 04:35:23.569222+05:30	2026-05-18 04:30:23+05:30
82	0785913750	101874	t	2026-05-18 04:49:17.274161+05:30	2026-05-18 04:44:17+05:30
83	0785913750	878545	t	2026-05-18 04:51:21.13808+05:30	2026-05-18 04:46:21+05:30
84	0770000111	591684	t	2026-05-18 05:00:27.869005+05:30	2026-05-18 04:55:27+05:30
85	0757048001	193223	t	2026-05-18 05:08:41.243493+05:30	2026-05-18 05:03:41+05:30
86	0785913750	165289	t	2026-05-18 05:08:59.447389+05:30	2026-05-18 05:03:59+05:30
87	0757048001	576199	t	2026-05-18 05:12:39.894697+05:30	2026-05-18 05:07:39+05:30
88	0755960594	444308	t	2026-05-18 05:13:10.351929+05:30	2026-05-18 05:08:10+05:30
89	0770000333	757381	t	2026-05-18 05:13:50.207434+05:30	2026-05-18 05:08:50+05:30
90	0785913750	241162	t	2026-05-18 05:14:43.327152+05:30	2026-05-18 05:09:43+05:30
91	0755960594	770242	t	2026-05-18 06:53:40.009774+05:30	2026-05-18 06:48:40+05:30
92	0770000333	936572	t	2026-05-18 07:04:23.934827+05:30	2026-05-18 06:59:23+05:30
93	0755960594	858369	t	2026-05-18 07:13:49.454342+05:30	2026-05-18 07:08:49+05:30
94	0785913750	902410	t	2026-05-18 08:35:45.926271+05:30	2026-05-18 08:30:45+05:30
95	0771234567	227164	t	2026-05-18 10:29:17.188432+05:30	2026-05-18 10:24:17+05:30
96	0771234567	911341	t	2026-05-18 10:29:36.126246+05:30	2026-05-18 10:24:36+05:30
97	0771000001	352665	t	2026-05-18 10:29:36.165231+05:30	2026-05-18 10:24:36+05:30
98	0700000000	326633	t	2026-05-18 10:30:06.599177+05:30	2026-05-18 10:25:06+05:30
99	0771234567	477159	t	2026-05-18 10:31:43.744969+05:30	2026-05-18 10:26:43+05:30
100	0757048001	318546	t	2026-05-18 10:31:43.795556+05:30	2026-05-18 10:26:43+05:30
101	0755960594	513655	t	2026-05-18 10:31:43.999224+05:30	2026-05-18 10:26:44+05:30
102	0757048001	326444	t	2026-05-18 11:22:45.096898+05:30	2026-05-18 11:17:45+05:30
103	0755960594	594412	t	2026-05-18 11:22:59.277131+05:30	2026-05-18 11:17:59+05:30
104	0755960594	451094	t	2026-05-18 12:56:45.737243+05:30	2026-05-18 12:51:45+05:30
105	0757048001	057064	t	2026-05-18 12:57:09.18339+05:30	2026-05-18 12:52:09+05:30
106	0757048001	688652	t	2026-05-19 03:39:39.556976+05:30	2026-05-19 03:34:39+05:30
107	0755960594	896170	t	2026-05-19 03:40:29.994744+05:30	2026-05-19 03:35:29+05:30
108	0785913750	398312	t	2026-05-19 03:41:49.456246+05:30	2026-05-19 03:36:49+05:30
109	0779900001	055911	t	2026-05-19 04:08:13.723599+05:30	2026-05-19 04:03:13+05:30
110	0771234567	806698	t	2026-05-19 04:08:13.875176+05:30	2026-05-19 04:03:13+05:30
111	0771234567	382269	t	2026-05-19 04:08:47.233152+05:30	2026-05-19 04:03:47+05:30
112	0771234567	844292	t	2026-05-19 04:14:31.010426+05:30	2026-05-19 04:09:31+05:30
113	0779900001	035509	t	2026-05-19 04:24:28.549858+05:30	2026-05-19 04:19:28+05:30
114	0771234567	261309	t	2026-05-19 04:24:28.581963+05:30	2026-05-19 04:19:28+05:30
115	0757048001	862912	t	2026-05-19 04:24:28.60032+05:30	2026-05-19 04:19:28+05:30
116	0779900001	122961	t	2026-05-19 04:24:49.235861+05:30	2026-05-19 04:19:49+05:30
117	0771234567	261564	t	2026-05-19 04:24:49.266616+05:30	2026-05-19 04:19:49+05:30
118	0757048001	177107	t	2026-05-19 04:24:49.282763+05:30	2026-05-19 04:19:49+05:30
119	0779900001	871746	t	2026-05-19 04:25:25.865334+05:30	2026-05-19 04:20:25+05:30
120	0771234567	679135	t	2026-05-19 04:25:25.899893+05:30	2026-05-19 04:20:25+05:30
121	0757048001	418197	t	2026-05-19 04:25:25.916641+05:30	2026-05-19 04:20:25+05:30
122	0779900001	294058	t	2026-05-19 04:26:38.883211+05:30	2026-05-19 04:21:38+05:30
123	0771234567	762182	t	2026-05-19 04:26:38.914595+05:30	2026-05-19 04:21:38+05:30
124	0757048001	111851	t	2026-05-19 04:26:38.93383+05:30	2026-05-19 04:21:38+05:30
125	0779900001	895628	t	2026-05-19 04:27:06.54589+05:30	2026-05-19 04:22:06+05:30
126	0771234567	734179	t	2026-05-19 04:27:06.573457+05:30	2026-05-19 04:22:06+05:30
127	0757048001	020920	t	2026-05-19 04:27:06.592775+05:30	2026-05-19 04:22:06+05:30
128	0755960594	509508	t	2026-05-19 04:51:58.430516+05:30	2026-05-19 04:46:58+05:30
129	0779900001	611627	t	2026-05-19 05:13:41.024388+05:30	2026-05-19 05:08:41+05:30
130	0779900001	573484	t	2026-05-19 05:15:10.038823+05:30	2026-05-19 05:10:10+05:30
131	0785913750	466396	t	2026-05-19 05:31:21.31531+05:30	2026-05-19 05:26:21+05:30
132	0785913750	742114	t	2026-05-19 05:36:16.591843+05:30	2026-05-19 05:31:16+05:30
133	0757048001	929323	t	2026-05-19 05:36:37.355759+05:30	2026-05-19 05:31:37+05:30
134	0779900001	586967	t	2026-05-19 05:38:14.533814+05:30	2026-05-19 05:33:14+05:30
135	0785913750	954320	t	2026-05-19 05:55:05.009772+05:30	2026-05-19 05:50:05+05:30
136	0700000000	017024	t	2026-05-19 06:13:55.940337+05:30	2026-05-19 06:08:55+05:30
137	0779900003	151420	t	2026-05-19 06:14:22.934866+05:30	2026-05-19 06:09:22+05:30
138	0779900001	799057	t	2026-05-19 06:15:33.651546+05:30	2026-05-19 06:10:33+05:30
139	0757048001	205387	t	2026-05-19 06:17:18.62897+05:30	2026-05-19 06:12:18+05:30
140	0779900001	777408	t	2026-05-19 06:17:28.127897+05:30	2026-05-19 06:12:28+05:30
141	0757048002	521998	t	2026-05-19 06:36:51.326059+05:30	2026-05-19 06:31:51+05:30
142	0779900001	363678	t	2026-05-19 06:46:15.430957+05:30	2026-05-19 06:41:15+05:30
143	0757048001	278341	t	2026-05-19 08:50:00.99492+05:30	2026-05-19 08:45:01+05:30
144	0779900001	830885	t	2026-05-19 08:50:41.967316+05:30	2026-05-19 08:45:41+05:30
145	0772000002	970031	t	2026-05-19 09:01:01.852749+05:30	2026-05-19 08:56:01+05:30
146	0785913750	527957	t	2026-05-19 09:03:21.056794+05:30	2026-05-19 08:58:21+05:30
147	0789137509	034738	t	2026-05-19 09:29:19.696738+05:30	2026-05-19 09:24:19+05:30
148	0789137509	386676	t	2026-05-19 09:48:43.082183+05:30	2026-05-19 09:43:43+05:30
149	0789137509	501598	t	2026-05-19 10:04:05.010927+05:30	2026-05-19 09:59:05+05:30
150	0789137509	656145	t	2026-05-19 10:07:54.101065+05:30	2026-05-19 10:02:54+05:30
151	0779900001	775382	t	2026-05-19 10:08:26.315864+05:30	2026-05-19 10:03:26+05:30
152	0789137509	329028	t	2026-05-19 10:18:13.325866+05:30	2026-05-19 10:13:13+05:30
153	0779900001	534903	t	2026-05-19 10:28:27.645142+05:30	2026-05-19 10:23:27+05:30
154	0757048001	187441	t	2026-05-19 10:29:51.012036+05:30	2026-05-19 10:24:51+05:30
155	0789137509	286482	t	2026-05-19 10:31:04.841388+05:30	2026-05-19 10:26:04+05:30
156	0779137509	573028	t	2026-05-19 10:51:29.24466+05:30	2026-05-19 10:46:29+05:30
157	0779137509	323281	t	2026-05-19 11:31:19.896709+05:30	2026-05-19 11:26:19+05:30
158	0789137509	946261	t	2026-05-19 11:34:28.480517+05:30	2026-05-19 11:29:28+05:30
159	0779900001	210865	t	2026-05-19 12:21:23.340239+05:30	2026-05-19 12:16:23+05:30
160	0789137509	539033	t	2026-05-19 12:26:19.272146+05:30	2026-05-19 12:21:19+05:30
161	0785913750	367060	t	2026-05-19 13:18:19.266232+05:30	2026-05-19 13:13:19+05:30
162	0757048001	346574	t	2026-05-19 13:46:48.840083+05:30	2026-05-19 13:41:48+05:30
163	0779900001	511800	t	2026-05-19 13:47:17.319413+05:30	2026-05-19 13:42:17+05:30
164	0789137509	813672	t	2026-05-19 13:48:01.701747+05:30	2026-05-19 13:43:01+05:30
165	0785913750	361208	t	2026-05-20 03:41:02.258066+05:30	2026-05-20 03:36:02+05:30
166	0789137509	574378	t	2026-05-20 10:05:05.676899+05:30	2026-05-20 10:00:05.679507+05:30
167	0757048001	692896	t	2026-05-20 10:05:34.489464+05:30	2026-05-20 10:00:34.491932+05:30
168	0755960594	224811	t	2026-05-20 10:07:46.725345+05:30	2026-05-20 10:02:46.726614+05:30
169	0757048001	052732	t	2026-05-20 10:32:14.588462+05:30	2026-05-20 10:27:14.597826+05:30
170	0757048001	344214	t	2026-05-20 10:32:59.372394+05:30	2026-05-20 10:27:59.375493+05:30
171	0785913750	463977	t	2026-05-20 10:35:08.245052+05:30	2026-05-20 10:30:08.247795+05:30
172	0776087233	378162	t	2026-05-20 10:35:32.428797+05:30	2026-05-20 10:30:32.431583+05:30
173	0785913750	343338	t	2026-05-20 10:36:38.206478+05:30	2026-05-20 10:31:38.209509+05:30
174	0785913750	831476	t	2026-05-20 10:36:52.9505+05:30	2026-05-20 10:31:52.952856+05:30
175	0785913750	324515	t	2026-05-20 10:41:01.061713+05:30	2026-05-20 10:36:01.06266+05:30
176	0761032568	552830	t	2026-05-20 10:50:10.192361+05:30	2026-05-20 10:45:10.200187+05:30
177	0771234567	294711	t	2026-05-20 10:51:31.650875+05:30	2026-05-20 10:46:31.653582+05:30
178	0771000001	007255	t	2026-05-20 10:52:49.059483+05:30	2026-05-20 10:47:49.062706+05:30
179	0771000001	369893	t	2026-05-20 10:58:19.546283+05:30	2026-05-20 10:53:19.548519+05:30
180	0771000001	262263	t	2026-05-20 11:04:00.393622+05:30	2026-05-20 10:59:00.395878+05:30
181	0771234567	543694	t	2026-05-20 11:06:43.111064+05:30	2026-05-20 11:01:43.117011+05:30
182	0771234568	040545	t	2026-05-20 11:06:53.353444+05:30	2026-05-20 11:01:53.355359+05:30
183	0785913750	060107	t	2026-05-20 11:43:17.173796+05:30	2026-05-20 11:38:17.174569+05:30
184	0779900001	302265	t	2026-05-20 12:02:39.754848+05:30	2026-05-20 11:57:39.757095+05:30
185	0789137509	200878	t	2026-05-20 12:04:54.238375+05:30	2026-05-20 11:59:54.240048+05:30
186	0789137509	886589	t	2026-05-20 12:05:04.675853+05:30	2026-05-20 12:00:04.677556+05:30
187	0779137509	316321	t	2026-05-20 12:08:51.81735+05:30	2026-05-20 12:03:51.821868+05:30
188	0779137509	529350	t	2026-05-20 12:12:33.380391+05:30	2026-05-20 12:07:33.382613+05:30
189	0785913750	308347	t	2026-05-20 12:32:24.997841+05:30	2026-05-20 12:27:25.001123+05:30
190	0785913750	129760	t	2026-05-20 14:29:22.464552+05:30	2026-05-20 14:24:22.472522+05:30
191	0785913750	860073	t	2026-05-20 14:29:43.031445+05:30	2026-05-20 14:24:43.034289+05:30
192	0757048001	436398	t	2026-05-20 18:50:19.153256+05:30	2026-05-20 18:45:19.195261+05:30
193	0757048001	557337	t	2026-05-20 18:52:53.496778+05:30	2026-05-20 18:47:53.502965+05:30
\.


--
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payments (id, booking_id, customer_id, amount, payment_method, transaction_id, payment_gateway_response, status, created_at) FROM stdin;
\.


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.products (id, vendor_id, name, description, price, stock_quantity, image_url, unit, is_available, created_at) FROM stdin;
1	1	Rice 5kg	\N	1200.00	50	\N	pack	t	2026-05-13 10:20:17+05:30
2	2	light	LED	3500.00	9	\N	50	t	2026-05-19 06:31:25+05:30
3	3	BUN	\N	50.00	143	\N	100	t	2026-05-19 09:22:03+05:30
4	4	pipe		3500.00	24	\N	35m	t	2026-05-19 10:46:09+05:30
\.


--
-- Data for Name: promo_codes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.promo_codes (id, code, description, discount_type, discount_value, min_order_amount, max_discount, usage_limit, used_count, valid_from, valid_to, is_active) FROM stdin;
\.


--
-- Data for Name: referral_bonuses; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.referral_bonuses (id, referrer_user_id, referred_user_id, kind, referrer_amount, referred_amount, status, trigger_description, created_at, paid_at) FROM stdin;
1	5	7	CUSTOMER	300.00	300.00	PAID	market:MKTEST	2026-05-20 10:22:36.482927+05:30	2026-05-20 10:22:36.520926+05:30
\.


--
-- Data for Name: restaurants; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.restaurants (id, name, description, address, lat, lng, phone_number, email, image_url, rating, is_active, is_open, opening_time, closing_time, delivery_fee, cuisine, eta_minutes, owner_id, created_at) FROM stdin;
1	Test Bistro Admin	Created from admin test	99 Test Lane, Colombo	6.9300000	79.8500000	+94112345678	\N	\N	4.50	t	t	08:00	23:00	200.00	Continental	25	\N	2026-05-13 10:20:17+05:30
2	faris restuarent	hotel	\N	6.9271000	79.8612000	0759137509	\N	\N	4.50	t	t	09:00	22:00	150.00	kinniyan	30	\N	2026-05-13 10:22:25+05:30
3	sinthujan Hotel	hotel	kinniya	8.4833000	81.2000000	\N	\N	\N	4.50	t	t	09:00	22:00	150.00	\N	30	\N	2026-05-18 10:16:52+05:30
4	Hashnate Bistro	Test sign-up via API	UC Rd, Kinniya	8.5024000	81.1810000	0779900001	\N	\N	0.00	t	t			180.00	Sri Lankan	25	20	2026-05-19 04:03:13+05:30
\.


--
-- Data for Name: saved_addresses; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.saved_addresses (id, user_id, label, address, lat, lng, is_default, created_at) FROM stdin;
1	9	office	Hashnate, Kinniya, Sri Lanka	8.5024163	81.1811984	f	2026-05-15 10:07:59+05:30
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users (id, phone_number, role, full_name, email, profile_photo, rating, total_rides, is_active, created_at, updated_at, referral_code, referred_by_user_id) FROM stdin;
1	+94700000000	ADMIN	Ziggo Admin	admin@ziggo.com	\N	0.00	0	t	2026-05-13 06:25:16+05:30	2026-05-20 10:15:27.496879+05:30	ZIGG5E5A	\N
2	+94771234599	DRIVER	Test Driver	test@ziggo.com	\N	0.00	0	t	2026-05-13 06:32:01+05:30	2026-05-20 10:15:27.496879+05:30	TESTNAJE	\N
3	+94771234588	DRIVER	Admin-Added Driver	\N	\N	0.00	0	t	2026-05-13 06:32:01+05:30	2026-05-20 10:15:27.496879+05:30	ADMISPGO	\N
4	+94 755960594	DRIVER	faris	faris@hashnate.com	/static/uploads/drivers/40764ec729c4a701.jpg	0.00	0	t	2026-05-13 06:34:37+05:30	2026-05-20 10:15:27.496879+05:30	FARI8O4T	\N
5	+94759137509	CUSTOMER	\N	\N	\N	0.00	0	t	2026-05-13 06:51:26+05:30	2026-05-20 10:15:27.496879+05:30	94751JHH	\N
6	+947859137809	DRIVER	sinthujan	sinthujan@hashnate.com	/static/uploads/drivers/4bc40d04cb051f81.jpg	0.00	0	t	2026-05-13 06:55:02+05:30	2026-05-20 10:15:27.496879+05:30	SINTV7Y2	\N
8	0759137509	DRIVER	muzzakir	muzakkir@hashnate.com	\N	0.00	0	t	2026-05-13 09:08:40+05:30	2026-05-20 10:15:27.496879+05:30	MUZZ1IM9	\N
9	0785913750	CUSTOMER	saud	\N	\N	0.00	0	t	2026-05-13 09:41:17+05:30	2026-05-20 10:15:27.496879+05:30	SAUDGNTU	\N
10	0770000111	CUSTOMER	\N	\N	\N	0.00	0	t	2026-05-13 09:49:19+05:30	2026-05-20 10:15:27.496879+05:30	077086B0	\N
11	0770000222	DRIVER	Notify Test Driver	\N	\N	0.00	0	t	2026-05-13 09:49:19+05:30	2026-05-20 10:15:27.496879+05:30	NOTIG0ZL	\N
12	0770000333	DRIVER	driver test	test@gmail.com	\N	5.00	1	t	2026-05-13 09:49:49+05:30	2026-05-20 10:15:27.496879+05:30	DRIVG1E7	\N
13	0700000000	ADMIN	\N	\N	\N	0.00	0	t	2026-05-13 10:16:17+05:30	2026-05-20 10:15:27.496879+05:30	0700BTHR	\N
14	0779990001	CUSTOMER	\N	\N	\N	0.00	0	t	2026-05-13 11:03:32+05:30	2026-05-20 10:15:27.496879+05:30	0779XONH	\N
15	0785937509	DRIVER	testi	gm@gmail.com	\N	0.00	0	t	2026-05-13 11:11:03+05:30	2026-05-20 10:15:27.496879+05:30	TESTKYYV	\N
16	0757048001	DRIVER	aashik	aashik@gmail.com	/static/uploads/drivers/b11a616fe594e4f8.jpg	5.00	13	t	2026-05-15 05:47:00+05:30	2026-05-20 10:15:27.496879+05:30	AASH6SFP	\N
18	0771234567	CUSTOMER	\N	\N	\N	0.00	0	t	2026-05-18 10:24:36+05:30	2026-05-20 10:15:27.496879+05:30	0771CM9X	\N
20	0779900001	RESTAURANT_OWNER	\N	\N	\N	0.00	0	t	2026-05-19 04:03:13+05:30	2026-05-20 10:15:27.496879+05:30	07793G6B	\N
21	0779900003	RESTAURANT_OWNER	\N	\N	\N	0.00	0	t	2026-05-19 06:09:24+05:30	2026-05-20 10:15:27.496879+05:30	07794TNT	\N
22	0757048002	RESTAURANT_OWNER	\N	\N	\N	0.00	0	t	2026-05-19 06:31:52+05:30	2026-05-20 10:15:27.496879+05:30	07570OLO	\N
23	0772000002	RESTAURANT_OWNER	\N	\N	\N	0.00	0	t	2026-05-19 08:56:02+05:30	2026-05-20 10:15:27.496879+05:30	0772WTOC	\N
24	0789137509	MARKET_OWNER	\N	\N	\N	0.00	0	t	2026-05-19 09:24:21+05:30	2026-05-20 10:15:27.496879+05:30	0789KA8X	\N
25	0779137509	MARKET_OWNER	\N	\N	\N	0.00	0	t	2026-05-19 10:45:53+05:30	2026-05-20 10:15:27.496879+05:30	0779WUNR	\N
7	+947859137509	CUSTOMER	saud	\N	\N	0.00	0	t	2026-05-13 07:04:05+05:30	2026-05-20 10:22:36.482927+05:30	SAUD2KBJ	5
26	0776087233	CUSTOMER	haha	\N	\N	0.00	0	t	2026-05-20 10:30:33.773384+05:30	2026-05-20 10:30:51.927522+05:30	0776LLSC	\N
27	0761032568	CUSTOMER	Sinthuma	\N	\N	0.00	0	t	2026-05-20 10:45:12.817197+05:30	2026-05-20 10:45:12.817197+05:30	SINT33FG	\N
28	0771234568	DRIVER	koylan	\N	\N	0.00	0	t	2026-05-20 11:01:54.583396+05:30	2026-05-20 11:02:24.280368+05:30	KOYL741Q	\N
19	0771000001	DRIVER	muzakkir	\N	\N	5.00	1	t	2026-05-18 10:24:36+05:30	2026-05-20 11:56:39.61509+05:30	0771JD8A	\N
17	0755960594	DRIVER	faris	faris@gmail.com	\N	5.00	10	t	2026-05-15 12:21:40+05:30	2026-05-20 12:18:33.03003+05:30	FARIHNQD	\N
\.


--
-- Data for Name: wallet_transactions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wallet_transactions (id, user_id, amount, type, description, reference_id, balance_after, created_at) FROM stdin;
1	9	500.00	credit	Wallet top-up	TOPUP	500.00	2026-05-13 11:28:33+05:30
2	9	500.00	debit	Ziggo Gold - 1 month(s)	GOLD	0.00	2026-05-18 04:41:44+05:30
3	9	500.00	credit	Wallet top-up	TOPUP	500.00	2026-05-18 08:32:25+05:30
4	9	500.00	credit	Wallet top-up	TOPUP	1000.00	2026-05-18 09:09:31+05:30
5	18	880.00	debit	Food order FOB4E26A35	FOB4E26A35	4120.00	2026-05-19 04:19:49+05:30
6	18	880.00	debit	Food order FO17F2C2DF	FO17F2C2DF	4120.00	2026-05-19 04:20:25+05:30
7	18	880.00	debit	Food order FOA2271D0E	FOA2271D0E	4120.00	2026-05-19 04:21:38+05:30
8	18	880.00	debit	Food order FO7E075992	FO7E075992	3240.00	2026-05-19 04:21:39+05:30
9	18	880.00	credit	Refund for restaurant rejected: order FO7E075992	FO7E075992	4120.00	2026-05-19 04:21:39+05:30
10	18	880.00	debit	Food order FO0AE7B9BD	FO0AE7B9BD	3240.00	2026-05-19 04:21:39+05:30
11	18	880.00	credit	Refund for auto-cancelled food order FO0AE7B9BD	FO0AE7B9BD	4120.00	2026-05-19 04:21:57+05:30
12	18	880.00	debit	Food order FO6A325428	FO6A325428	4120.00	2026-05-19 04:22:06+05:30
13	18	880.00	debit	Food order FOD0159B56	FOD0159B56	3240.00	2026-05-19 04:22:06+05:30
14	18	880.00	credit	Refund for restaurant rejected: order FOD0159B56	FOD0159B56	4120.00	2026-05-19 04:22:06+05:30
15	18	880.00	debit	Food order FO3B09F1D3	FO3B09F1D3	3240.00	2026-05-19 04:22:06+05:30
16	18	880.00	credit	Refund for auto-cancelled food order FO3B09F1D3	FO3B09F1D3	4120.00	2026-05-19 04:22:07+05:30
17	18	880.00	credit	Refund for auto-cancelled food order FOB4E26A35	FOB4E26A35	5000.00	2026-05-19 04:25:01+05:30
18	5	300.00	credit	Referral bonus — friend completed first order	REFC1	300.00	2026-05-20 10:22:36.506915+05:30
19	7	300.00	credit	Welcome bonus — first order completed	REFC1	300.00	2026-05-20 10:22:36.506915+05:30
\.


--
-- Name: bookings_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.bookings_id_seq', 77, true);


--
-- Name: complaints_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.complaints_id_seq', 1, false);


--
-- Name: customers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.customers_id_seq', 8, true);


--
-- Name: driver_documents_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.driver_documents_id_seq', 1, false);


--
-- Name: drivers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.drivers_id_seq', 12, true);


--
-- Name: event_ticket_tiers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.event_ticket_tiers_id_seq', 5, true);


--
-- Name: events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.events_id_seq', 2, true);


--
-- Name: fare_settings_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.fare_settings_id_seq', 5, true);


--
-- Name: flash_weight_tiers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.flash_weight_tiers_id_seq', 4, true);


--
-- Name: food_order_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.food_order_items_id_seq', 31, true);


--
-- Name: food_orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.food_orders_id_seq', 31, true);


--
-- Name: market_order_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.market_order_items_id_seq', 22, true);


--
-- Name: market_orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.market_orders_id_seq', 22, true);


--
-- Name: market_vendors_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.market_vendors_id_seq', 4, true);


--
-- Name: menu_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.menu_categories_id_seq', 6, true);


--
-- Name: menu_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.menu_items_id_seq', 5, true);


--
-- Name: notifications_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.notifications_id_seq', 360, true);


--
-- Name: otp_codes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.otp_codes_id_seq', 193, true);


--
-- Name: payments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.payments_id_seq', 1, false);


--
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.products_id_seq', 4, true);


--
-- Name: promo_codes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.promo_codes_id_seq', 1, false);


--
-- Name: referral_bonuses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.referral_bonuses_id_seq', 1, true);


--
-- Name: restaurants_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.restaurants_id_seq', 4, true);


--
-- Name: saved_addresses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.saved_addresses_id_seq', 1, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.users_id_seq', 28, true);


--
-- Name: wallet_transactions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wallet_transactions_id_seq', 19, true);


--
-- Name: bookings bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pkey PRIMARY KEY (id);


--
-- Name: complaints complaints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: customers customers_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_user_id_key UNIQUE (user_id);


--
-- Name: driver_documents driver_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_documents
    ADD CONSTRAINT driver_documents_pkey PRIMARY KEY (id);


--
-- Name: drivers drivers_license_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_license_number_key UNIQUE (license_number);


--
-- Name: drivers drivers_nic_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_nic_number_key UNIQUE (nic_number);


--
-- Name: drivers drivers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_pkey PRIMARY KEY (id);


--
-- Name: drivers drivers_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_user_id_key UNIQUE (user_id);


--
-- Name: drivers drivers_vehicle_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_vehicle_number_key UNIQUE (vehicle_number);


--
-- Name: event_ticket_tiers event_ticket_tiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_ticket_tiers
    ADD CONSTRAINT event_ticket_tiers_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: fare_settings fare_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fare_settings
    ADD CONSTRAINT fare_settings_pkey PRIMARY KEY (id);


--
-- Name: flash_weight_tiers flash_weight_tiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flash_weight_tiers
    ADD CONSTRAINT flash_weight_tiers_pkey PRIMARY KEY (id);


--
-- Name: food_order_items food_order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_order_items
    ADD CONSTRAINT food_order_items_pkey PRIMARY KEY (id);


--
-- Name: food_orders food_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_orders
    ADD CONSTRAINT food_orders_pkey PRIMARY KEY (id);


--
-- Name: market_order_items market_order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_order_items
    ADD CONSTRAINT market_order_items_pkey PRIMARY KEY (id);


--
-- Name: market_orders market_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_orders
    ADD CONSTRAINT market_orders_pkey PRIMARY KEY (id);


--
-- Name: market_vendors market_vendors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_vendors
    ADD CONSTRAINT market_vendors_pkey PRIMARY KEY (id);


--
-- Name: menu_categories menu_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_categories
    ADD CONSTRAINT menu_categories_pkey PRIMARY KEY (id);


--
-- Name: menu_items menu_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: otp_codes otp_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.otp_codes
    ADD CONSTRAINT otp_codes_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: promo_codes promo_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_codes
    ADD CONSTRAINT promo_codes_pkey PRIMARY KEY (id);


--
-- Name: referral_bonuses referral_bonuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referral_bonuses
    ADD CONSTRAINT referral_bonuses_pkey PRIMARY KEY (id);


--
-- Name: restaurants restaurants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurants
    ADD CONSTRAINT restaurants_pkey PRIMARY KEY (id);


--
-- Name: saved_addresses saved_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_addresses
    ADD CONSTRAINT saved_addresses_pkey PRIMARY KEY (id);


--
-- Name: referral_bonuses uq_referral_referred_user; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referral_bonuses
    ADD CONSTRAINT uq_referral_referred_user UNIQUE (referred_user_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: wallet_transactions wallet_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_pkey PRIMARY KEY (id);


--
-- Name: ix_bookings_booking_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_bookings_booking_ref ON public.bookings USING btree (booking_ref);


--
-- Name: ix_bookings_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bookings_id ON public.bookings USING btree (id);


--
-- Name: ix_bookings_is_flash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bookings_is_flash ON public.bookings USING btree (is_flash);


--
-- Name: ix_bookings_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bookings_status ON public.bookings USING btree (status);


--
-- Name: ix_complaints_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_complaints_id ON public.complaints USING btree (id);


--
-- Name: ix_customers_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_customers_id ON public.customers USING btree (id);


--
-- Name: ix_driver_documents_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_driver_documents_id ON public.driver_documents USING btree (id);


--
-- Name: ix_drivers_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_drivers_id ON public.drivers USING btree (id);


--
-- Name: ix_event_ticket_tiers_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_event_ticket_tiers_id ON public.event_ticket_tiers USING btree (id);


--
-- Name: ix_events_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_events_id ON public.events USING btree (id);


--
-- Name: ix_events_is_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_events_is_published ON public.events USING btree (is_published);


--
-- Name: ix_events_starts_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_events_starts_at ON public.events USING btree (starts_at);


--
-- Name: ix_fare_settings_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_fare_settings_id ON public.fare_settings USING btree (id);


--
-- Name: ix_fare_settings_service_type; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_fare_settings_service_type ON public.fare_settings USING btree (service_type);


--
-- Name: ix_flash_weight_tiers_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_flash_weight_tiers_id ON public.flash_weight_tiers USING btree (id);


--
-- Name: ix_food_order_items_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_food_order_items_id ON public.food_order_items USING btree (id);


--
-- Name: ix_food_orders_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_food_orders_id ON public.food_orders USING btree (id);


--
-- Name: ix_food_orders_order_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_food_orders_order_ref ON public.food_orders USING btree (order_ref);


--
-- Name: ix_food_orders_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_food_orders_status ON public.food_orders USING btree (status);


--
-- Name: ix_market_order_items_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_market_order_items_id ON public.market_order_items USING btree (id);


--
-- Name: ix_market_orders_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_market_orders_id ON public.market_orders USING btree (id);


--
-- Name: ix_market_orders_order_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_market_orders_order_ref ON public.market_orders USING btree (order_ref);


--
-- Name: ix_market_orders_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_market_orders_status ON public.market_orders USING btree (status);


--
-- Name: ix_market_vendors_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_market_vendors_id ON public.market_vendors USING btree (id);


--
-- Name: ix_menu_categories_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_menu_categories_id ON public.menu_categories USING btree (id);


--
-- Name: ix_menu_items_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_menu_items_id ON public.menu_items USING btree (id);


--
-- Name: ix_notifications_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_notifications_id ON public.notifications USING btree (id);


--
-- Name: ix_otp_codes_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_otp_codes_id ON public.otp_codes USING btree (id);


--
-- Name: ix_otp_codes_phone_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_otp_codes_phone_number ON public.otp_codes USING btree (phone_number);


--
-- Name: ix_payments_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_payments_id ON public.payments USING btree (id);


--
-- Name: ix_products_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_products_id ON public.products USING btree (id);


--
-- Name: ix_promo_codes_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_promo_codes_code ON public.promo_codes USING btree (code);


--
-- Name: ix_promo_codes_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_promo_codes_id ON public.promo_codes USING btree (id);


--
-- Name: ix_referral_bonuses_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_referral_bonuses_id ON public.referral_bonuses USING btree (id);


--
-- Name: ix_referral_bonuses_referrer_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_referral_bonuses_referrer_user_id ON public.referral_bonuses USING btree (referrer_user_id);


--
-- Name: ix_referral_bonuses_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_referral_bonuses_status ON public.referral_bonuses USING btree (status);


--
-- Name: ix_restaurants_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_restaurants_id ON public.restaurants USING btree (id);


--
-- Name: ix_saved_addresses_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_saved_addresses_id ON public.saved_addresses USING btree (id);


--
-- Name: ix_users_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_users_id ON public.users USING btree (id);


--
-- Name: ix_users_phone_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_users_phone_number ON public.users USING btree (phone_number);


--
-- Name: ix_wallet_transactions_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_wallet_transactions_id ON public.wallet_transactions USING btree (id);


--
-- Name: bookings bookings_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: bookings bookings_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id);


--
-- Name: complaints complaints_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.users(id);


--
-- Name: complaints complaints_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id);


--
-- Name: complaints complaints_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: customers customers_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: driver_documents driver_documents_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_documents
    ADD CONSTRAINT driver_documents_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id) ON DELETE CASCADE;


--
-- Name: driver_documents driver_documents_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver_documents
    ADD CONSTRAINT driver_documents_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES public.users(id);


--
-- Name: drivers drivers_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: event_ticket_tiers event_ticket_tiers_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_ticket_tiers
    ADD CONSTRAINT event_ticket_tiers_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: food_order_items food_order_items_menu_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_order_items
    ADD CONSTRAINT food_order_items_menu_item_id_fkey FOREIGN KEY (menu_item_id) REFERENCES public.menu_items(id);


--
-- Name: food_order_items food_order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_order_items
    ADD CONSTRAINT food_order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.food_orders(id) ON DELETE CASCADE;


--
-- Name: food_orders food_orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_orders
    ADD CONSTRAINT food_orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: food_orders food_orders_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_orders
    ADD CONSTRAINT food_orders_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id);


--
-- Name: food_orders food_orders_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_orders
    ADD CONSTRAINT food_orders_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id);


--
-- Name: market_order_items market_order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_order_items
    ADD CONSTRAINT market_order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.market_orders(id) ON DELETE CASCADE;


--
-- Name: market_order_items market_order_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_order_items
    ADD CONSTRAINT market_order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: market_orders market_orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_orders
    ADD CONSTRAINT market_orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: market_orders market_orders_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_orders
    ADD CONSTRAINT market_orders_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id);


--
-- Name: market_orders market_orders_vendor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_orders
    ADD CONSTRAINT market_orders_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES public.market_vendors(id);


--
-- Name: market_vendors market_vendors_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_vendors
    ADD CONSTRAINT market_vendors_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- Name: menu_categories menu_categories_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_categories
    ADD CONSTRAINT menu_categories_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: menu_items menu_items_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.menu_categories(id);


--
-- Name: menu_items menu_items_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: payments payments_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id);


--
-- Name: payments payments_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: products products_vendor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES public.market_vendors(id) ON DELETE CASCADE;


--
-- Name: referral_bonuses referral_bonuses_referred_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referral_bonuses
    ADD CONSTRAINT referral_bonuses_referred_user_id_fkey FOREIGN KEY (referred_user_id) REFERENCES public.users(id);


--
-- Name: referral_bonuses referral_bonuses_referrer_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referral_bonuses
    ADD CONSTRAINT referral_bonuses_referrer_user_id_fkey FOREIGN KEY (referrer_user_id) REFERENCES public.users(id);


--
-- Name: restaurants restaurants_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurants
    ADD CONSTRAINT restaurants_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- Name: saved_addresses saved_addresses_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_addresses
    ADD CONSTRAINT saved_addresses_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: wallet_transactions wallet_transactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

\unrestrict eIxYYrYRKCKqu638opMLJpbnO05gJwicn4sjRE8nAIjB0sEhZeEuDYoTSTpishM

