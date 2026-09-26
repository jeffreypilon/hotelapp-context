# HotelApp — Project Overview

## Purpose

HotelApp is a hotel booking and guest management web application. It allows guests to
search for and book hotel rooms, and allows hotel staff and management to manage
bookings, room inventory, and rates. This document describes the application in plain,
non-technical language — what it does and who it's for — as a foundation for the
technical specifications that follow it.

## Users & Roles

There are three levels of access:

1. **Public (no login required)** — Anyone visiting the site can browse hotel
   properties, view room types and photos, view amenities, and search room
   availability. No account is needed to look around.

2. **Guest (registered account, login required)** — A guest must create an account or
   log in to actually complete a booking, or to view/manage their own reservations. A
   guest can only see and manage their own bookings, not anyone else's.

3. **Admin (registered account, login required)** — Hotel staff and management use a
   separate administrative area. There are two admin permission levels:
   - **Front-Desk Staff** — can view all bookings, and check guests in and out of
     their reservation.
   - **Property Manager / Owner** — can do everything Front-Desk Staff can do, plus
     manage room inventory, manage rates, and add new hotel properties.

## Core Workflows

### Guest booking flow (public browsing → account required to complete)

1. Browse available hotel properties — each property has its own page with a photo
   and a short description.
2. View room types offered at a property, including photos and a list of amenities.
3. Search for available rooms by:
   - Check-in date and check-out date (dates only, no specific times)
   - Room type
   - Number of guests
4. Optionally select a special rate category to see discounted pricing (see Special
   Rates below).
5. Sort and filter search results (e.g., by price, by room type).
6. Select a room and review a booking summary (dates, room, rate, total price).
7. If not already logged in, the guest is prompted to log in or create an account
   before continuing.
8. Enter payment details on a payment form. (This is a demo — no real payment
   processor is used; the form collects and validates card-shaped input but does not
   charge or store real payment information.)
9. Confirm the booking. The guest receives a confirmation number and a booking
   confirmation summary. (A confirmation email may be simulated/logged for the demo,
   or sent for real as a stretch goal — not required.)

### Guest account management (login required)

- View profile / contact information; edit contact details.
- View booking history (past and upcoming stays).
- View, modify (where cancellation policy allows), or cancel an existing reservation.

### Front-Desk Staff workflow (login required)

- View all bookings across the property/properties, with search and filtering (by
  date, guest name, status).
- Check a guest in on their arrival date (marks the reservation as checked-in).
- Check a guest out on their departure date (marks the reservation as checked-out).

### Property Manager / Owner workflow (login required)

Everything Front-Desk Staff can do, plus:

- Add a new hotel property (name, address, description, photo).
- Add and edit room types for a property (name, description, photos, amenities, base
  rate, maximum occupancy).
- Manage special rate discounts (see Special Rates below).
- View an admin room/rate calendar — a table showing rooms across dates and their
  availability status, at a glance.
- View basic operational reporting: current occupancy rate, upcoming arrivals.

## Properties, Room Types & Amenities

- The application supports **multiple hotel properties**, each with its own name,
  address, description, and photo.
- Each property offers one or more **room types**:
  - Single
  - Double
  - King
  - Suite
  - Conference Room (a bookable meeting space, booked by full day like any other
    room type — not by the hour, to keep booking logic consistent across all room
    types)
- Each room type lists:
  - Photos
  - Maximum occupancy (used in availability search)
  - An accessible/ADA-compliant flag, where applicable
  - Bed configuration (e.g., one king bed, two queen beds)
  - Amenities, which may include:
    - Wi-Fi
    - Air conditioning / climate control
    - Refrigerator
    - Television
    - Microwave
    - Wet bar
    - Safe for valuables

## Special Rates

A guest may optionally select one special rate category when searching or booking, to
see discounted pricing. For simplicity, this is a single-select choice (not a text code
entry):

- None
- AAA/CAA
- AARP
- Government/Per Diem
- Military/Veteran
- Senior
- Corporate Code
- Group Code

(A "clear selection" option is available in the interface to reset back to no special
rate — this is a UI convenience, not a rate category itself.)

## Business Rules

- **Cancellation policy:** A reservation may be cancelled free of charge up to 48
  hours before the check-in date. Cancellations inside that 48-hour window are
  non-refundable.
- **No overbooking:** The application never allows a room to be booked for dates that
  overlap with an existing reservation for that same room. If a room is unavailable
  for any part of the requested date range, it will not appear in search results for
  those dates.
- **Dates only, no check-in/check-out times:** Bookings are made and tracked by date
  only; specific arrival/departure times are not part of the booking model.

## What's Out of Scope for This Demo

To keep the project focused, the following are explicitly **not** included:

- Real payment processing or integration with a third-party payment processor (a
  dummy payment form only).
- Loyalty / rewards programs.
- Guest reviews or ratings.
- Overbooking logic or revenue-management-style dynamic pricing.
- Hourly/time-slot booking for conference rooms (they follow the same full-day
  booking rules as guest rooms).
- Housekeeping, maintenance, or staff-scheduling workflows.
- Channel manager or third-party OTA (Online Travel Agency) integrations.

## Possible Future Enhancements (not required for initial build)

- Real transactional email for booking confirmations.
- More detailed admin reporting/analytics (ADR, RevPAR, revenue by segment).
- Guest loyalty program.
- Guest reviews.
