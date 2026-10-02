--
-- PostgreSQL database dump
--

\restrict DjdRh6tdoipdGXaXDJR0maxkmoShmBS9rOMhrLAxEYY12qR3eqRvpi6rCyoYD67

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

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

--
-- Data for Name: amenities; Type: TABLE DATA; Schema: public; Owner: -
--

-- V001's migration itself inserts these 7 rows with freshly-generated uuidv7() ids, which won't
-- match the ids this dump's room_type_amenities rows reference below. Replace them with the
-- original, stable ids from the source database instead of relying on the migration's own copy.
DELETE FROM public.amenities;

INSERT INTO public.amenities (id, code, name, sort_order) VALUES ('01a0e22b-c08a-7f80-a9a3-a06da32ae06a', 'WIFI', 'Wi-Fi', 10);
INSERT INTO public.amenities (id, code, name, sort_order) VALUES ('01a0e22b-c08b-79a4-b7d1-2f2e4902b7f9', 'AIR_CONDITIONING', 'Air conditioning / climate control', 20);
INSERT INTO public.amenities (id, code, name, sort_order) VALUES ('01a0e22b-c08b-7a07-b349-ff6a40accc4e', 'REFRIGERATOR', 'Refrigerator', 30);
INSERT INTO public.amenities (id, code, name, sort_order) VALUES ('01a0e22b-c08b-7a1c-bdab-15dcfd424159', 'TELEVISION', 'Television', 40);
INSERT INTO public.amenities (id, code, name, sort_order) VALUES ('01a0e22b-c08b-7a32-b1df-8a713927fe94', 'MICROWAVE', 'Microwave', 50);
INSERT INTO public.amenities (id, code, name, sort_order) VALUES ('01a0e22b-c08b-7a46-9bcf-70b45e88a88a', 'WET_BAR', 'Wet bar', 60);
INSERT INTO public.amenities (id, code, name, sort_order) VALUES ('01a0e22b-c08b-7a5a-9a55-6eee49a56b19', 'SAFE', 'Safe for valuables', 70);


--
-- Data for Name: properties; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.properties (id, name, slug, description, photo_url, address_line1, address_line2, city, state_province, postal_code, country_code, phone, timezone, is_active, created_at, updated_at) VALUES ('01a0e22c-ac6d-7a75-89f2-030097892f4f', 'Harborview Grand', 'harborview-grand', 'A waterfront hotel steps from the ferry terminal.', 'https://thumbs.dreamstime.com/b/san-diego-bay-18586760.jpg?w=768', '18 Wharf Street', NULL, 'Portland', 'ME', '04101', 'US', '+1-207-555-0100', 'America/New_York', true, '2026-09-27 05:22:53.639775-04', '2026-09-27 05:22:53.639775-04');
INSERT INTO public.properties (id, name, slug, description, photo_url, address_line1, address_line2, city, state_province, postal_code, country_code, phone, timezone, is_active, created_at, updated_at) VALUES ('01a0e22c-ac77-7412-96e5-3f2c6ca2c40c', 'Lakeside Inn', 'lakeside-inn', 'Twenty-four rooms on the north shore.', 'https://thumbs.dreamstime.com/b/hotel-regency-porto-montenegro-tivat-montenegro-64446287.jpg?w=992', '7 North Shore Road', NULL, 'Burlington', 'VT', '05401', 'US', '+1-802-555-0177', 'America/New_York', true, '2026-09-27 05:22:53.639775-04', '2026-09-27 05:22:53.639775-04');


--
-- Data for Name: room_types; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.room_types (id, property_id, code, name, description, base_rate, max_occupancy, bed_configuration, is_accessible, is_active, created_at, updated_at) VALUES ('01a0e55e-4703-7643-953f-6a43f080563d', '01a0e22c-ac6d-7a75-89f2-030097892f4f', 'KING', 'Deluxe King, Harbor View', 'Corner room with a king bed and harbor-facing windows.', 249.00, 2, 'one king bed', false, true, '2026-09-27 20:15:56.16121-04', '2026-09-27 20:15:56.16121-04');
INSERT INTO public.room_types (id, property_id, code, name, description, base_rate, max_occupancy, bed_configuration, is_accessible, is_active, created_at, updated_at) VALUES ('01a0e55e-4705-70d3-998c-71c21a833f87', '01a0e22c-ac6d-7a75-89f2-030097892f4f', 'SUITE', 'Accessible Suite, Harbor View', 'Ground-floor suite with a roll-in shower and wide doorways.', 329.00, 4, 'one king bed, one sofa bed', true, true, '2026-09-27 20:15:56.16121-04', '2026-09-27 20:15:56.16121-04');
INSERT INTO public.room_types (id, property_id, code, name, description, base_rate, max_occupancy, bed_configuration, is_accessible, is_active, created_at, updated_at) VALUES ('01a0e89f-859d-78c2-8dee-0214cb0e4b1a', '01a0e22c-ac6d-7a75-89f2-030097892f4f', 'DOUBLE', 'Double Queen, Harbor View', 'Bright room with two queen beds and harbor views, ideal for families or friends traveling together.', 279.00, 4, 'two queen beds', false, true, '2026-09-28 11:26:03.676607-04', '2026-09-28 11:26:03.676607-04');
INSERT INTO public.room_types (id, property_id, code, name, description, base_rate, max_occupancy, bed_configuration, is_accessible, is_active, created_at, updated_at) VALUES ('01a0e89f-859e-7e44-b568-3af16f49e1fc', '01a0e22c-ac77-7412-96e5-3f2c6ca2c40c', 'KING', 'Classic King, Lakeside Inn', 'Comfortable room with a king bed and lake views.', 229.00, 2, 'one king bed', false, true, '2026-09-28 11:26:03.676607-04', '2026-09-28 11:26:03.676607-04');
INSERT INTO public.room_types (id, property_id, code, name, description, base_rate, max_occupancy, bed_configuration, is_accessible, is_active, created_at, updated_at) VALUES ('01a0e89f-859f-7412-94c2-8bf8925ddc44', '01a0e22c-ac77-7412-96e5-3f2c6ca2c40c', 'DOUBLE', 'Double Queen, Lakeside Inn', 'Spacious room with two queen beds, perfect for groups or families visiting the lake.', 259.00, 4, 'two queen beds', false, true, '2026-09-28 11:26:03.676607-04', '2026-09-28 11:26:03.676607-04');
INSERT INTO public.room_types (id, property_id, code, name, description, base_rate, max_occupancy, bed_configuration, is_accessible, is_active, created_at, updated_at) VALUES ('01a0e8a4-8c4c-7826-ad3d-be75aa424036', '01a0e22c-ac6d-7a75-89f2-030097892f4f', 'CONFERENCE_ROOM', 'Meeting Room, Harbor View', 'A versatile meeting space with harbor views, booked by the full day for business gatherings and events.', 349.00, 20, NULL, true, true, '2026-09-28 11:31:33.067277-04', '2026-09-28 11:31:33.067277-04');


--
-- Data for Name: rooms; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e583-f9f4-7233-adfb-21d854415a3d', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e55e-4703-7643-953f-6a43f080563d', '201', 2, false, '2026-09-27 20:57:06.803603-04', '2026-09-27 20:57:06.803603-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e583-f9f5-713a-8b8f-52f7c759fc1b', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e55e-4703-7643-953f-6a43f080563d', '202', 2, false, '2026-09-27 20:57:06.803603-04', '2026-09-27 20:57:06.803603-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e583-f9f5-7187-9b76-73ab8e652c49', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e55e-4703-7643-953f-6a43f080563d', '203', 2, false, '2026-09-27 20:57:06.803603-04', '2026-09-27 20:57:06.803603-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e583-f9f5-719e-b5d6-bf78952326c2', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e55e-4703-7643-953f-6a43f080563d', '204', 2, false, '2026-09-27 20:57:06.803603-04', '2026-09-27 20:57:06.803603-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e583-f9f5-71b8-98b5-addf23a8685e', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e55e-4705-70d3-998c-71c21a833f87', '301', 3, false, '2026-09-27 20:57:06.803603-04', '2026-09-27 20:57:06.803603-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e583-f9f5-71ce-b5ce-97c04abfc27f', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e55e-4705-70d3-998c-71c21a833f87', '302', 3, false, '2026-09-27 20:57:06.803603-04', '2026-09-27 20:57:06.803603-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e89f-85a3-7fa5-8df7-973b83214225', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e89f-859d-78c2-8dee-0214cb0e4b1a', '401', 4, false, '2026-09-28 11:26:03.676607-04', '2026-09-28 11:26:03.676607-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e89f-85a4-72eb-ad0c-7b35f36fb84b', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e89f-859d-78c2-8dee-0214cb0e4b1a', '402', 4, false, '2026-09-28 11:26:03.676607-04', '2026-09-28 11:26:03.676607-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e89f-85a4-7312-b81b-26cef2ff85fd', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e89f-859d-78c2-8dee-0214cb0e4b1a', '403', 4, false, '2026-09-28 11:26:03.676607-04', '2026-09-28 11:26:03.676607-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e89f-85a4-7c12-afa3-423e4b565057', '01a0e22c-ac77-7412-96e5-3f2c6ca2c40c', '01a0e89f-859e-7e44-b568-3af16f49e1fc', '201', 2, false, '2026-09-28 11:26:03.676607-04', '2026-09-28 11:26:03.676607-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e89f-85a4-7c52-8212-b831887197c9', '01a0e22c-ac77-7412-96e5-3f2c6ca2c40c', '01a0e89f-859e-7e44-b568-3af16f49e1fc', '202', 2, false, '2026-09-28 11:26:03.676607-04', '2026-09-28 11:26:03.676607-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e89f-85a4-7c70-807e-4eb458aa863e', '01a0e22c-ac77-7412-96e5-3f2c6ca2c40c', '01a0e89f-859e-7e44-b568-3af16f49e1fc', '203', 2, false, '2026-09-28 11:26:03.676607-04', '2026-09-28 11:26:03.676607-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e89f-85a5-750a-9fbb-cc0b1cb43b31', '01a0e22c-ac77-7412-96e5-3f2c6ca2c40c', '01a0e89f-859f-7412-94c2-8bf8925ddc44', '301', 3, false, '2026-09-28 11:26:03.676607-04', '2026-09-28 11:26:03.676607-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e89f-85a5-757c-84fe-545a0fc62fa6', '01a0e22c-ac77-7412-96e5-3f2c6ca2c40c', '01a0e89f-859f-7412-94c2-8bf8925ddc44', '302', 3, false, '2026-09-28 11:26:03.676607-04', '2026-09-28 11:26:03.676607-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e89f-85a5-75b1-8ef2-9836930d496f', '01a0e22c-ac77-7412-96e5-3f2c6ca2c40c', '01a0e89f-859f-7412-94c2-8bf8925ddc44', '303', 3, false, '2026-09-28 11:26:03.676607-04', '2026-09-28 11:26:03.676607-04');
INSERT INTO public.rooms (id, property_id, room_type_id, room_number, floor, is_out_of_service, created_at, updated_at) VALUES ('01a0e8a4-8c50-7fe2-9f2c-e994d7b44a6f', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e8a4-8c4c-7826-ad3d-be75aa424036', '101', 1, false, '2026-09-28 11:31:33.067277-04', '2026-09-28 11:31:33.067277-04');


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.users (id, email, password_hash, first_name, last_name, phone, address_line1, address_line2, city, state_province, postal_code, country_code, role, home_property_id, is_active, created_at, updated_at) VALUES ('01a0e5b2-09d2-7bb6-aa8c-dadf9dc803da', 'dana.step5@example.com', '$2a$12$QOXTUUAvVcqfUS0yGP..S.VIY/6UWEDZPrOFOOV9cRrsXIXoJofgG', 'Danielle', 'Reyes', NULL, '', NULL, 'Portland', '', '', '  ', 'GUEST', NULL, true, '2026-09-27 21:47:25.174191-04', '2026-09-27 21:47:25.174191-04');
INSERT INTO public.users (id, email, password_hash, first_name, last_name, phone, address_line1, address_line2, city, state_province, postal_code, country_code, role, home_property_id, is_active, created_at, updated_at) VALUES ('01a0e5d9-f8e0-7a88-a009-f34a87322d3a', 'pat.step7@example.com', '$2a$12$NJ4Rx/bwo1OyiCuojhcOuOOLOYnGzmjHDFNmcBUKQDtVXX9ZiG2Me', 'Pat', 'Tester', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'GUEST', NULL, true, '2026-09-27 22:31:02.338461-04', '2026-09-27 22:31:02.338461-04');
INSERT INTO public.users (id, email, password_hash, first_name, last_name, phone, address_line1, address_line2, city, state_province, postal_code, country_code, role, home_property_id, is_active, created_at, updated_at) VALUES ('01a0e87f-75e9-7eed-b414-16f263b7a3c1', 'mikejones@example.com', '$2a$12$csFNbY8RGVEs9u00LGFdu.blEr3sSUmWK42kuIzav0thqv1d8OX7K', 'Mike', 'Jones', '3135551212', NULL, NULL, NULL, NULL, NULL, NULL, 'GUEST', NULL, true, '2026-09-28 10:51:02.237833-04', '2026-09-28 10:51:02.237833-04');
INSERT INTO public.users (id, email, password_hash, first_name, last_name, phone, address_line1, address_line2, city, state_province, postal_code, country_code, role, home_property_id, is_active, created_at, updated_at) VALUES ('01a0ef04-88ab-776d-a9e5-ed0312edbcda', 'booking-test-1790716445998@example.com', '$2b$12$A//xnaxmQUGO6gHpSQznceOPqumbdwKkAXAg9qp/DuUCqQ27ddTxe', 'Dana', 'Reyes', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'GUEST', NULL, true, '2026-09-29 17:14:06.891-04', '2026-09-29 17:14:06.891-04');
INSERT INTO public.users (id, email, password_hash, first_name, last_name, phone, address_line1, address_line2, city, state_province, postal_code, country_code, role, home_property_id, is_active, created_at, updated_at) VALUES ('01a0ef14-b2e2-7579-9f61-0972d5924729', 'step6.guest@example.com', '$2b$12$t7M52ErZteO44yiVxaV64eJx5rBIdZagWdBcoMvwrACVx/h1wBPRW', 'Step6', 'Guest', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'GUEST', NULL, true, '2026-09-29 17:31:46.273-04', '2026-09-29 17:31:46.273-04');
INSERT INTO public.users (id, email, password_hash, first_name, last_name, phone, address_line1, address_line2, city, state_province, postal_code, country_code, role, home_property_id, is_active, created_at, updated_at) VALUES ('01a0ef20-a3e4-75d6-8243-bbc4e6649f96', 'angular.step7.1790718288501@example.com', '$2b$12$XT/0MoXLChKblaJRrxPkiu0dqZZ4TYdHJHCc/wx6kRcTAOnEcy2la', 'Danielle', 'Reyes', NULL, '44 Elm Street', NULL, 'Portland', 'ME', '04102', 'US', 'GUEST', NULL, true, '2026-09-29 17:44:48.868-04', '2026-09-29 17:50:24.73-04');
INSERT INTO public.users (id, email, password_hash, first_name, last_name, phone, address_line1, address_line2, city, state_province, postal_code, country_code, role, home_property_id, is_active, created_at, updated_at) VALUES ('01a0ef26-4208-7515-887e-b9843f42582a', 'angular.step7b.1790718656724@example.com', '$2b$12$hc0sEhvqEpQCXh8ECxPeKu2tH5zVIo5Fi4sFqIAXc3k6zOHoN/iSm', 'Dana', 'Reyes', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'GUEST', NULL, true, '2026-09-29 17:50:57.031-04', '2026-09-29 17:51:08.252-04');


--
-- Data for Name: reservations; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.reservations (id, confirmation_number, guest_user_id, property_id, room_id, room_type_id, check_in_date, check_out_date, num_guests, rate_category, base_rate_amount, discount_percent_applied, nightly_rate_amount, total_amount, currency, status, booked_at, cancellation_deadline, checked_in_at, checked_out_at, cancelled_at, cancelled_by_user_id, was_refundable, created_at, updated_at) VALUES ('01a0e5b2-5e7a-732f-906e-a685d32cc078', 'HAB1HWQP7C', '01a0e5b2-09d2-7bb6-aa8c-dadf9dc803da', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e583-f9f4-7233-adfb-21d854415a3d', '01a0e55e-4703-7643-953f-6a43f080563d', '2026-11-14', '2026-11-17', 2, 'AAA_CAA', 249.00, 10.00, 224.10, 672.30, 'USD', 'CANCELLED', '2026-09-27 21:47:47.193924-04', '2026-11-12 00:00:00-05', NULL, NULL, '2026-09-27 22:08:33.949594-04', '01a0e5b2-09d2-7bb6-aa8c-dadf9dc803da', true, '2026-09-27 21:47:47.193924-04', '2026-09-27 21:47:47.193924-04');
INSERT INTO public.reservations (id, confirmation_number, guest_user_id, property_id, room_id, room_type_id, check_in_date, check_out_date, num_guests, rate_category, base_rate_amount, discount_percent_applied, nightly_rate_amount, total_amount, currency, status, booked_at, cancellation_deadline, checked_in_at, checked_out_at, cancelled_at, cancelled_by_user_id, was_refundable, created_at, updated_at) VALUES ('01a0e958-888f-7432-ab63-08540c859af4', 'HA2CVRRQP5', '01a0e87f-75e9-7eed-b414-16f263b7a3c1', '01a0e22c-ac77-7412-96e5-3f2c6ca2c40c', '01a0e89f-85a4-7c12-afa3-423e4b565057', '01a0e89f-859e-7e44-b568-3af16f49e1fc', '2026-10-01', '2026-10-05', 2, 'AARP', 229.00, 0.00, 229.00, 916.00, 'USD', 'CONFIRMED', '2026-09-28 14:48:08.590965-04', '2026-09-29 00:00:00-04', NULL, NULL, NULL, NULL, NULL, '2026-09-28 14:48:08.590965-04', '2026-09-29 13:41:12.566242-04');
INSERT INTO public.reservations (id, confirmation_number, guest_user_id, property_id, room_id, room_type_id, check_in_date, check_out_date, num_guests, rate_category, base_rate_amount, discount_percent_applied, nightly_rate_amount, total_amount, currency, status, booked_at, cancellation_deadline, checked_in_at, checked_out_at, cancelled_at, cancelled_by_user_id, was_refundable, created_at, updated_at) VALUES ('01a0ee79-cd4b-793b-bcbd-4a7dc2adaee6', 'HAKKQP5P31', '01a0e87f-75e9-7eed-b414-16f263b7a3c1', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e8a4-8c50-7fe2-9f2c-e994d7b44a6f', '01a0e8a4-8c4c-7826-ad3d-be75aa424036', '2026-11-03', '2026-11-04', 1, 'NONE', 349.00, 0.00, 349.00, 349.00, 'USD', 'CONFIRMED', '2026-09-29 14:42:34.953919-04', '2026-11-01 01:00:00-04', NULL, NULL, NULL, NULL, NULL, '2026-09-29 14:42:34.953919-04', '2026-09-29 14:42:34.953919-04');
INSERT INTO public.reservations (id, confirmation_number, guest_user_id, property_id, room_id, room_type_id, check_in_date, check_out_date, num_guests, rate_category, base_rate_amount, discount_percent_applied, nightly_rate_amount, total_amount, currency, status, booked_at, cancellation_deadline, checked_in_at, checked_out_at, cancelled_at, cancelled_by_user_id, was_refundable, created_at, updated_at) VALUES ('01a0ef04-c0b3-76b5-b6fc-42cefeac8b62', 'HA51MT530D', '01a0ef04-88ab-776d-a9e5-ed0312edbcda', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e583-f9f4-7233-adfb-21d854415a3d', '01a0e55e-4703-7643-953f-6a43f080563d', '2026-11-14', '2026-11-17', 2, 'NONE', 249.00, 0.00, 249.00, 747.00, 'USD', 'CONFIRMED', '2026-09-29 17:14:21.233375-04', '2026-11-12 00:00:00-05', NULL, NULL, NULL, NULL, NULL, '2026-09-29 17:14:21.233375-04', '2026-09-29 17:14:21.233375-04');
INSERT INTO public.reservations (id, confirmation_number, guest_user_id, property_id, room_id, room_type_id, check_in_date, check_out_date, num_guests, rate_category, base_rate_amount, discount_percent_applied, nightly_rate_amount, total_amount, currency, status, booked_at, cancellation_deadline, checked_in_at, checked_out_at, cancelled_at, cancelled_by_user_id, was_refundable, created_at, updated_at) VALUES ('01a0ef06-20e9-7e0f-9333-75d3cd64784a', 'HAF0X4E1KD', '01a0ef04-88ab-776d-a9e5-ed0312edbcda', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e583-f9f4-7233-adfb-21d854415a3d', '01a0e55e-4703-7643-953f-6a43f080563d', '2026-12-01', '2026-12-04', 2, 'NONE', 249.00, 0.00, 249.00, 747.00, 'USD', 'CONFIRMED', '2026-09-29 17:15:51.400884-04', '2026-11-29 00:00:00-05', NULL, NULL, NULL, NULL, NULL, '2026-09-29 17:15:51.400884-04', '2026-09-29 17:15:51.400884-04');
INSERT INTO public.reservations (id, confirmation_number, guest_user_id, property_id, room_id, room_type_id, check_in_date, check_out_date, num_guests, rate_category, base_rate_amount, discount_percent_applied, nightly_rate_amount, total_amount, currency, status, booked_at, cancellation_deadline, checked_in_at, checked_out_at, cancelled_at, cancelled_by_user_id, was_refundable, created_at, updated_at) VALUES ('01a0ef15-37ed-7991-ba6e-bdc743834d2a', 'HAC185WVVW', '01a0ef14-b2e2-7579-9f61-0972d5924729', '01a0e22c-ac6d-7a75-89f2-030097892f4f', '01a0e583-f9f5-713a-8b8f-52f7c759fc1b', '01a0e55e-4703-7643-953f-6a43f080563d', '2026-11-12', '2026-11-16', 2, 'NONE', 249.00, 0.00, 249.00, 996.00, 'USD', 'CANCELLED', '2026-09-29 17:32:20.331085-04', '2026-11-10 00:00:00-05', NULL, NULL, '2026-09-29 17:34:45.125-04', '01a0ef14-b2e2-7579-9f61-0972d5924729', true, '2026-09-29 17:32:20.331085-04', '2026-09-29 17:34:45.126706-04');
INSERT INTO public.reservations (id, confirmation_number, guest_user_id, property_id, room_id, room_type_id, check_in_date, check_out_date, num_guests, rate_category, base_rate_amount, discount_percent_applied, nightly_rate_amount, total_amount, currency, status, booked_at, cancellation_deadline, checked_in_at, checked_out_at, cancelled_at, cancelled_by_user_id, was_refundable, created_at, updated_at) VALUES ('01a0ef2c-5ea2-7e94-a830-f3e2d4102ca1', 'HA65MJVNT2', '01a0e87f-75e9-7eed-b414-16f263b7a3c1', '01a0e22c-ac77-7412-96e5-3f2c6ca2c40c', '01a0e89f-85a5-750a-9fbb-cc0b1cb43b31', '01a0e89f-859f-7412-94c2-8bf8925ddc44', '2026-12-16', '2026-12-18', 2, 'GOVERNMENT_PER_DIEM', 259.00, 0.00, 259.00, 518.00, 'USD', 'CONFIRMED', '2026-09-29 17:57:37.568707-04', '2026-12-14 00:00:00-05', NULL, NULL, NULL, NULL, NULL, '2026-09-29 17:57:37.568707-04', '2026-09-29 17:57:37.568707-04');


--
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.payments (id, reservation_id, amount, currency, status, method, card_brand, card_last_four, cardholder_name, processed_at, created_at) VALUES ('01a0e5b2-5e7e-7b1d-86fd-bd427666b928', '01a0e5b2-5e7a-732f-906e-a685d32cc078', 747.00, 'USD', 'REFUNDED', 'DUMMY_CARD', 'VISA', '4242', 'Dana Reyes', '2026-09-27 21:47:47.193924-04', '2026-09-27 21:47:47.193924-04');
INSERT INTO public.payments (id, reservation_id, amount, currency, status, method, card_brand, card_last_four, cardholder_name, processed_at, created_at) VALUES ('01a0e958-8892-7d9f-9f6f-7483ff5f0a39', '01a0e958-888f-7432-ab63-08540c859af4', 229.00, 'USD', 'SUCCEEDED', 'DUMMY_CARD', 'VISA', '4242', 'Michael E Jones', '2026-09-28 14:48:08.590965-04', '2026-09-28 14:48:08.590965-04');
INSERT INTO public.payments (id, reservation_id, amount, currency, status, method, card_brand, card_last_four, cardholder_name, processed_at, created_at) VALUES ('01a0ee79-cd4d-7c38-bbbe-2d6bd07a71ee', '01a0ee79-cd4b-793b-bcbd-4a7dc2adaee6', 349.00, 'USD', 'SUCCEEDED', 'DUMMY_CARD', 'VISA', '4242', 'Michael E Jones', '2026-09-29 14:42:34.957-04', '2026-09-29 14:42:34.957-04');
INSERT INTO public.payments (id, reservation_id, amount, currency, status, method, card_brand, card_last_four, cardholder_name, processed_at, created_at) VALUES ('01a0ef04-c0b7-7239-ae63-ebb93015d83c', '01a0ef04-c0b3-76b5-b6fc-42cefeac8b62', 747.00, 'USD', 'SUCCEEDED', 'DUMMY_CARD', 'VISA', '4242', 'Dana Reyes', '2026-09-29 17:14:21.238-04', '2026-09-29 17:14:21.238-04');
INSERT INTO public.payments (id, reservation_id, amount, currency, status, method, card_brand, card_last_four, cardholder_name, processed_at, created_at) VALUES ('01a0ef06-20eb-78d5-b2d5-0c8887504a53', '01a0ef06-20e9-7e0f-9333-75d3cd64784a', 747.00, 'USD', 'SUCCEEDED', 'DUMMY_CARD', 'VISA', '4242', 'Dana Reyes', '2026-09-29 17:15:51.403-04', '2026-09-29 17:15:51.403-04');
INSERT INTO public.payments (id, reservation_id, amount, currency, status, method, card_brand, card_last_four, cardholder_name, processed_at, created_at) VALUES ('01a0ef15-37f0-77f3-acb7-95f6ebcd6141', '01a0ef15-37ed-7991-ba6e-bdc743834d2a', 498.00, 'USD', 'REFUNDED', 'DUMMY_CARD', 'VISA', '4242', 'Step Six', '2026-09-29 17:32:20.336-04', '2026-09-29 17:32:20.336-04');
INSERT INTO public.payments (id, reservation_id, amount, currency, status, method, card_brand, card_last_four, cardholder_name, processed_at, created_at) VALUES ('01a0ef2c-5ea5-77de-a581-89541bfd8a9b', '01a0ef2c-5ea2-7e94-a830-f3e2d4102ca1', 518.00, 'USD', 'SUCCEEDED', 'DUMMY_CARD', 'VISA', '4242', 'Michael E Jones', '2026-09-29 17:57:37.573-04', '2026-09-29 17:57:37.573-04');


--
-- Data for Name: rate_plans; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.rate_plans (id, property_id, rate_category, discount_percent, is_active, created_at, updated_at) VALUES ('01a0e583-f9f6-74b7-8dd0-1355b7fbd5de', '01a0e22c-ac6d-7a75-89f2-030097892f4f', 'AAA_CAA', 10.00, true, '2026-09-27 20:57:06.803603-04', '2026-09-27 20:57:06.803603-04');


--
-- Data for Name: room_type_amenities; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e55e-4703-7643-953f-6a43f080563d', '01a0e22b-c08a-7f80-a9a3-a06da32ae06a');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e55e-4703-7643-953f-6a43f080563d', '01a0e22b-c08b-79a4-b7d1-2f2e4902b7f9');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e55e-4703-7643-953f-6a43f080563d', '01a0e22b-c08b-7a5a-9a55-6eee49a56b19');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e55e-4705-70d3-998c-71c21a833f87', '01a0e22b-c08a-7f80-a9a3-a06da32ae06a');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e55e-4705-70d3-998c-71c21a833f87', '01a0e22b-c08b-79a4-b7d1-2f2e4902b7f9');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e55e-4705-70d3-998c-71c21a833f87', '01a0e22b-c08b-7a5a-9a55-6eee49a56b19');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e89f-859d-78c2-8dee-0214cb0e4b1a', '01a0e22b-c08a-7f80-a9a3-a06da32ae06a');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e89f-859d-78c2-8dee-0214cb0e4b1a', '01a0e22b-c08b-79a4-b7d1-2f2e4902b7f9');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e89f-859d-78c2-8dee-0214cb0e4b1a', '01a0e22b-c08b-7a07-b349-ff6a40accc4e');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e89f-859d-78c2-8dee-0214cb0e4b1a', '01a0e22b-c08b-7a1c-bdab-15dcfd424159');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e89f-859f-7412-94c2-8bf8925ddc44', '01a0e22b-c08a-7f80-a9a3-a06da32ae06a');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e89f-859f-7412-94c2-8bf8925ddc44', '01a0e22b-c08b-79a4-b7d1-2f2e4902b7f9');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e89f-859f-7412-94c2-8bf8925ddc44', '01a0e22b-c08b-7a07-b349-ff6a40accc4e');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e89f-859f-7412-94c2-8bf8925ddc44', '01a0e22b-c08b-7a1c-bdab-15dcfd424159');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e89f-859e-7e44-b568-3af16f49e1fc', '01a0e22b-c08a-7f80-a9a3-a06da32ae06a');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e89f-859e-7e44-b568-3af16f49e1fc', '01a0e22b-c08b-79a4-b7d1-2f2e4902b7f9');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e89f-859e-7e44-b568-3af16f49e1fc', '01a0e22b-c08b-7a07-b349-ff6a40accc4e');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e89f-859e-7e44-b568-3af16f49e1fc', '01a0e22b-c08b-7a1c-bdab-15dcfd424159');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e8a4-8c4c-7826-ad3d-be75aa424036', '01a0e22b-c08a-7f80-a9a3-a06da32ae06a');
INSERT INTO public.room_type_amenities (room_type_id, amenity_id) VALUES ('01a0e8a4-8c4c-7826-ad3d-be75aa424036', '01a0e22b-c08b-7a1c-bdab-15dcfd424159');


--
-- Data for Name: room_type_photos; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.room_type_photos (id, room_type_id, url, caption, sort_order, is_primary) VALUES ('01a0e55e-4711-7713-8d41-867976028399', '01a0e55e-4705-70d3-998c-71c21a833f87', 'https://image-tc.galaxy.tf/wijpeg-f4dxdp3d4ewv7yj7a7rrki9e5/zpla-ckhn-01_wide.jpg?width=1200&crop=0%2C150%2C1600%2C900', 'Accessible Suite, Harbor View', 0, true);
INSERT INTO public.room_type_photos (id, room_type_id, url, caption, sort_order, is_primary) VALUES ('01a0e55e-470e-7e5c-970e-803825f32162', '01a0e55e-4703-7643-953f-6a43f080563d', 'https://image-tc.galaxy.tf/wijpeg-egbz1xzkckp5uaypw69agtp9d/zpla-ckshn-01_wide.jpg?width=1200&crop=0%2C150%2C1600%2C900', 'Deluxe King, Harbor View', 0, true);
INSERT INTO public.room_type_photos (id, room_type_id, url, caption, sort_order, is_primary) VALUES ('01a0e89f-85a2-77e2-9970-4b304ffb0565', '01a0e89f-859d-78c2-8dee-0214cb0e4b1a', 'https://image-tc.galaxy.tf/wijpeg-8vobp31n3ldi7n1q4auiroj0/zpla-cqtn-01_wide.jpg?crop=0%2C150%2C1600%2C900&width=1140', 'Double Queen, Harbor View', 0, true);
INSERT INTO public.room_type_photos (id, room_type_id, url, caption, sort_order, is_primary) VALUES ('01a0e89f-85a3-71b5-a46b-63224914a8af', '01a0e89f-859e-7e44-b568-3af16f49e1fc', 'https://elmhursthotelqueens.reservandohoteles.com/wp-content/uploads/elementor/thumbs/213225220-1-qr2d3nma34q3kuhqjll4624uskcqu74g04d7wnmb5s.jpg', 'Classic King, Lakeside Inn', 0, true);
INSERT INTO public.room_type_photos (id, room_type_id, url, caption, sort_order, is_primary) VALUES ('01a0e89f-85a3-7833-9d07-25d8946b1098', '01a0e89f-859f-7412-94c2-8bf8925ddc44', 'https://elmhursthotelqueens.reservandohoteles.com/wp-content/uploads/elementor/thumbs/198582382-qr1ynhpk1onqpa25xr7jcbjwec6d843vtjq166vegw.jpg', 'Double Queen, Lakeside Inn', 0, true);
INSERT INTO public.room_type_photos (id, room_type_id, url, caption, sort_order, is_primary) VALUES ('01a0e8a4-8c50-75e4-be60-8643e8b6f338', '01a0e8a4-8c4c-7826-ad3d-be75aa424036', 'https://image-tc.galaxy.tf/wijpeg-d3zy4zj3cdfxk69e01xpdilxi/zpla-meeting-05.jpg?width=1920', 'Meeting Room, Harbor View', 0, true);


--
-- Data for Name: sessions; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.sessions (id, user_id, token_hash, issued_at, expires_at, revoked_at, user_agent, ip_address) VALUES ('01a0e5b2-09e0-7f4a-a51d-abf2f9d4d1b0', '01a0e5b2-09d2-7bb6-aa8c-dadf9dc803da', '5bca22dbc938dab107f5e298ea64d018e318a4cb8b0d179b57264c6eb1545758', '2026-09-27 21:47:25.174191-04', '2026-09-28 06:29:52.014934-04', NULL, NULL, NULL);
INSERT INTO public.sessions (id, user_id, token_hash, issued_at, expires_at, revoked_at, user_agent, ip_address) VALUES ('01a0e5d9-f8e2-7146-9efa-6ee693063400', '01a0e5d9-f8e0-7a88-a009-f34a87322d3a', 'b588817f82b9d4bd4b25a4f7f15cd096a98b6f5b2855488a0be4d1e269ccc3cc', '2026-09-27 22:31:02.338461-04', '2026-09-28 06:31:02.624555-04', NULL, NULL, NULL);
INSERT INTO public.sessions (id, user_id, token_hash, issued_at, expires_at, revoked_at, user_agent, ip_address) VALUES ('01a0e5e0-c352-73c4-b9d8-ea9eb86622bd', '01a0e5d9-f8e0-7a88-a009-f34a87322d3a', '7b698cb64270b96564ba4e2246bf627c81630c52d052c70e9226e2266ae3a80f', '2026-09-27 22:38:27.665981-04', '2026-09-28 06:38:27.665083-04', NULL, NULL, NULL);
INSERT INTO public.sessions (id, user_id, token_hash, issued_at, expires_at, revoked_at, user_agent, ip_address) VALUES ('01a0ee40-e3e2-730d-b7ca-f5a8bc3c9760', '01a0e87f-75e9-7eed-b414-16f263b7a3c1', '900ad322ef3a13087d4e4e0f49073319f6cf5c6caab5262675414248af645281', '2026-09-29 13:40:25.184-04', '2026-09-29 21:40:25.184-04', '2026-09-29 13:42:00.778-04', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36', '::1');
INSERT INTO public.sessions (id, user_id, token_hash, issued_at, expires_at, revoked_at, user_agent, ip_address) VALUES ('01a0ee54-0b39-7309-a3a5-9f041cce9b06', '01a0e87f-75e9-7eed-b414-16f263b7a3c1', '1964bd8ae8a94533bd7225cf7de21d7b9f73b91fc94a51ff0f911b9be80de8a1', '2026-09-29 14:01:20.438-04', '2026-09-29 22:01:20.438-04', '2026-09-29 14:04:20.991-04', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36', '::1');
INSERT INTO public.sessions (id, user_id, token_hash, issued_at, expires_at, revoked_at, user_agent, ip_address) VALUES ('01a0ef04-88af-7175-ab0f-a4edc86aeb1e', '01a0ef04-88ab-776d-a9e5-ed0312edbcda', '432156af195332a72db1907ac22304ab59dc1146cd505fc66d3aa671e4f0eef4', '2026-09-29 17:14:06.891-04', '2026-09-30 01:31:35.662-04', NULL, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Code/1.139.1 Chrome/150.0.7871.250 Electron/43.6.0 Safari/537.36', '::1');
INSERT INTO public.sessions (id, user_id, token_hash, issued_at, expires_at, revoked_at, user_agent, ip_address) VALUES ('01a0e87f-75f1-7d5f-a66c-926e186a6d53', '01a0e87f-75e9-7eed-b414-16f263b7a3c1', 'df3f57491094c4a30da30e2ebf543eee5296dc50d8ed6509a227aaac796951d9', '2026-09-28 10:51:02.237833-04', '2026-09-29 02:15:50.691868-04', NULL, NULL, NULL);
INSERT INTO public.sessions (id, user_id, token_hash, issued_at, expires_at, revoked_at, user_agent, ip_address) VALUES ('01a0ef14-b2e6-7be4-a91d-6db0736c100f', '01a0ef14-b2e2-7579-9f61-0972d5924729', 'ba6af15329997529d255928d9e2999cf19d019deae0876e20882e7052d2c661f', '2026-09-29 17:31:46.275-04', '2026-09-30 01:44:44.585-04', NULL, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Code/1.139.1 Chrome/150.0.7871.250 Electron/43.6.0 Safari/537.36', '::1');
INSERT INTO public.sessions (id, user_id, token_hash, issued_at, expires_at, revoked_at, user_agent, ip_address) VALUES ('01a0ef20-a3e8-70d8-9fcb-7de16a4d885e', '01a0ef20-a3e4-75d6-8243-bbc4e6649f96', '143b2857642b26eda8200fbada6113304211f6c374ce6df1011997cbc5e8c553', '2026-09-29 17:44:48.869-04', '2026-09-30 01:50:05.03-04', NULL, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Code/1.139.1 Chrome/150.0.7871.250 Electron/43.6.0 Safari/537.36', '::1');
INSERT INTO public.sessions (id, user_id, token_hash, issued_at, expires_at, revoked_at, user_agent, ip_address) VALUES ('01a0ef26-420b-7a6c-bb29-1aa63ad458dc', '01a0ef26-4208-7515-887e-b9843f42582a', '37c4e246bbda77acbe840336d71c59c5e8d67c119695b7d550434e76fc0e37fb', '2026-09-29 17:50:57.033-04', '2026-09-30 01:50:57.033-04', NULL, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Code/1.139.1 Chrome/150.0.7871.250 Electron/43.6.0 Safari/537.36', '::1');
INSERT INTO public.sessions (id, user_id, token_hash, issued_at, expires_at, revoked_at, user_agent, ip_address) VALUES ('01a0ee75-5b2b-72de-b460-de7d2cc0f760', '01a0e87f-75e9-7eed-b414-16f263b7a3c1', 'e02bea6bc3f0022cb2d4a3c7930bf34c9e5424ece2d31ea0166ef0277c9ee439', '2026-09-29 14:37:43.589-04', '2026-09-30 01:55:47.841-04', '2026-09-29 17:56:04.449-04', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36', '::1');
INSERT INTO public.sessions (id, user_id, token_hash, issued_at, expires_at, revoked_at, user_agent, ip_address) VALUES ('01a0ef2b-3f20-7a37-a19f-295e3691da2f', '01a0e87f-75e9-7eed-b414-16f263b7a3c1', '59c8b2be8a7177872b412eaa13759e7edf3f15059ef7bd163702e9af05e7cc9e', '2026-09-29 17:56:23.966-04', '2026-09-30 01:56:23.966-04', NULL, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36', '::1');


--
-- PostgreSQL database dump complete
--

\unrestrict DjdRh6tdoipdGXaXDJR0maxkmoShmBS9rOMhrLAxEYY12qR3eqRvpi6rCyoYD67

