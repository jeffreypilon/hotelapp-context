# Phase 7 Step 2 — property detail, room types

Produced `hotelapp-client-react@353ec32`.

```
HotelApp — React Phase 7, Step 2: public browsing (item 2 — property detail, room types)

Read first: shared/api-contracts.md (GET /properties/{propertyId}, GET
/properties/{propertyId}/room-types, GET /room-types/{roomTypeId}), stacks/react/
ui-specifications.md section 2's S2 entry, stacks/react/architecture-specification.md (folder
layout and routing table), stacks/react/state-management.md (per-query staleTime overrides),
stacks/react/security-implementation.md (the safeImageUrl requirement, below). Stay in
stacks/react/ only.

CURRENT STATE (confirmed by reading the actual files — Phase 7 Step 1 is commit fbcd8df):
routes.tsx has only S1 ("/" and "/properties"). api/queryKeys.ts already has property(id),
roomTypes(propertyId), and roomType(id) entries scaffolded but unused. api/types.ts has only
PropertySummary/Address/Pagination — nothing for a property's full detail shape or a room type.
PropertyListScreen's card is NOT yet a link to anything (there was nothing to link to before this
step). No <img src> in the codebase goes through a URL-safety check yet, despite
security-implementation.md requiring one for every image built from API data.

PRE-STEP: seed data. The dev database (hotelapp, local Postgres) has 2 properties and ZERO room
types — this screen cannot be meaningfully verified in a browser without at least one. Amenities
are already seeded (7 rows: WIFI, AIR_CONDITIONING, REFRIGERATOR, TELEVISION, MICROWAVE, WET_BAR,
SAFE) and room_type_code is an enum {SINGLE, DOUBLE, KING, SUITE, CONFERENCE_ROOM}. Run this
against the hotelapp database before starting (psql -U postgres -h localhost -d hotelapp), or ask
first if you'd rather I run it:

  INSERT INTO room_types (property_id, code, name, description, base_rate, max_occupancy,
                           bed_configuration, is_accessible)
  VALUES
    ('01a0e22c-ac6d-7a75-89f2-030097892f4f', 'KING', 'Deluxe King, Harbor View',
     'Corner room with a king bed and harbor-facing windows.', 249.00, 2, 'one king bed', false),
    ('01a0e22c-ac6d-7a75-89f2-030097892f4f', 'SUITE', 'Accessible Suite, Harbor View',
     'Ground-floor suite with a roll-in shower and wide doorways.', 329.00, 4,
     'one king bed, one sofa bed', true);

  INSERT INTO room_type_amenities (room_type_id, amenity_id)
  SELECT rt.id, a.id FROM room_types rt, amenities a
  WHERE rt.property_id = '01a0e22c-ac6d-7a75-89f2-030097892f4f'
    AND a.code IN ('WIFI', 'AIR_CONDITIONING', 'SAFE');

  INSERT INTO room_type_photos (room_type_id, url, caption, sort_order, is_primary)
  SELECT id, 'https://picsum.photos/seed/' || code || '/800/450', name, 0, true
  FROM room_types WHERE property_id = '01a0e22c-ac6d-7a75-89f2-030097892f4f';

Leave Lakeside Inn with zero room types deliberately — it's the real fixture for S2's "This hotel
has no rooms listed yet." empty state, which otherwise has nothing to test against.

SCOPE — S2 only (property detail, its Rooms section, and room-type detail). Do NOT build S3
(search/availability), S5 (login), or anything past this screen.

1. api/types.ts: add RoomType, Amenity, Photo interfaces from the GET
   /properties/{propertyId}/room-types shape in api-contracts.md (code, name, description,
   baseRate as a string, maxOccupancy, bedConfiguration, isAccessible, amenities: {code, name}[],
   photos: {id, url, caption, sortOrder, isPrimary}[]).

   THE ONE GENUINELY UNCERTAIN PART: GET /properties/{propertyId} embeds a `roomTypes` array
   described in api-contracts.md only as "summary form" -- no example given. The Spring Boot
   implementer already made an interpretive call here (flagged in that repo's own outcome notes:
   flat fields, no amenities/photos) that was never confirmed against a frontend. Don't guess --
   curl the live endpoint (backend on :8080) and look at what actually comes back before typing
   it. If it's flat fields as suspected, this screen doesn't need to render from it at all: the
   Rooms section is populated from the separate GET /properties/{propertyId}/room-types call,
   which does carry the full shape. Type the embedded field loosely (or omit it from the
   TypeScript interface entirely, capturing only what this screen actually reads) rather than
   inventing a richer shape nobody has verified. If the real response disagrees with the flat-form
   assumption, say so -- that's a live contract-vs-implementation drift worth surfacing, not
   silently working around.

2. api/endpoints/properties.ts: add getProperty(propertyIdOrSlug) -- pass the path segment
   through unchanged, the server disambiguates UUID vs. slug, don't add client-side format
   detection.
   api/endpoints/roomTypes.ts (new file, per architecture-specification.md's endpoint-per-resource
   layout): getRoomTypes(propertyId), getRoomType(roomTypeId).

3. lib/safeImageUrl.ts (new): the exact function in security-implementation.md -- validates a URL
   is http(s), rejects everything else (blocks javascript:/data: reaching an <img src> attribute),
   returns null on rejection so the caller falls back to the placeholder. Apply it to every <img
   src> built from API data in this step's new code, AND retrofit PropertyListScreen's
   PropertyCard, which currently renders property.photoUrl directly with no check -- that gap
   predates this step but this is the right point to fix it, before a second and third
   photo-rendering path copies the same omission.

4. features/properties/PropertyDetailScreen.tsx + hooks/useProperty.ts, useRoomTypes.ts: hero
   photo, name, address, phone, description; the "Rooms" section as horizontal cards (photo via
   safeImageUrl, name, category label from `code`, bed configuration, "Sleeps N", amenity chips
   from the amenities array -- names from the API, never hardcoded -- accessible badge with a
   real accessible name when isAccessible, "From {baseRate} / night" via the existing
   lib/format.ts money formatter). "Check availability" per card, and the date/guest form near
   the top of the screen, both navigate to /properties/:propertyId/search with the relevant query
   params per architecture-specification.md's routing table -- that route doesn't exist until
   Step 3, so it 404s to S15 for now. Same deferred-target pattern Step 1 used for the /login
   redirect target; don't build S3 to avoid the 404, and don't skip building the navigation either.

   Loading: hero + two card skeletons. Empty (zero room types): "This hotel has no rooms listed
   yet." Error NOT_FOUND: full-page "We couldn't find that hotel." + link to S1. Never render
   room numbers or a room count anywhere on this screen -- physical inventory isn't in this
   endpoint's response, so there's nothing to accidentally leak, but don't invent a count from
   roomTypeCount either; that field belongs to S1's card, not this screen.

5. Room-type detail: modal on desktop, full route on mobile, but route-addressable either way at
   /room-types/:roomTypeId per ui-specifications.md -- meaning a direct load of that URL must
   render the detail standalone, not just as an overlay with nothing behind it. Use React Router's
   background-location pattern (navigate with `state: { backgroundLocation: location }` from the
   property-detail screen so it renders behind the modal; a direct hit on the URL has no
   background state and renders the full-page form instead). Content: photo gallery (each image
   through safeImageUrl), full description, complete amenity list with names, bed configuration,
   max occupancy, accessibility flag. NOT_FOUND: same full-page treatment as the property 404.

6. routes.tsx: add /properties/:propertyId and /room-types/:roomTypeId per
   architecture-specification.md's route tree. Update PropertyListScreen's card to actually link
   to /properties/:propertyId (or slug) -- ui-specifications.md's S1 spec calls for "whole card is
   one link target" and this is the first point that target has existed.

7. Query staleTime: state-management.md's per-query overrides table puts properties/room-types at
   5 minutes, not the 30-second global default Step 1 set on the QueryClient. Set staleTime:
   5 * 60_000 explicitly on useProperty/useRoomTypes/useRoomType -- the global default will work
   without erroring, just refetch more than the spec intends, which is easy to miss since nothing
   breaks.

NOT in scope: S3, S5, any auth-gated screen, admin. Don't scaffold their folders speculatively.

VERIFICATION: npm run lint / typecheck / test:run / build all green. Manually, against the seeded
data: Harborview Grand's detail page renders both room types with amenity chips, one shows the
Accessible badge, "From $249.00 / night" (not $249 or 249.00 unstyled); Lakeside Inn's detail page
renders the "no rooms listed yet" empty state; an unknown property id/slug renders the
"couldn't find that hotel" page; clicking a room-type card opens the modal on a wide viewport,
and pasting /room-types/<that-id> directly into the address bar (fresh load, no prior navigation)
renders the same content as a full page, not a blank modal shell; "Check availability" navigates
to the not-yet-built search route and lands on the S15 not-found page rather than crashing.

Flag judgment calls in code and summarize them at the end, same discipline as every prior step --
especially whatever you find when you curl the property-detail endpoint's embedded roomTypes
shape.
```
