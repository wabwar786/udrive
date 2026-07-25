# Testing checklist

- [ ] Customer Home app bar shows correct Pakistan-time greeting and first name.
- [ ] Notification and profile icons appear on the right.
- [ ] Profile icon opens the authenticated Customer profile.
- [ ] Booking hero starts near the top with no duplicate greeting card.
- [ ] Scheduled vehicles load without waiting for optional marketplace endpoints.
- [ ] Search `Neelum`, `Muzaffarabad`, `Coaster`, or a registration and confirm filtering.
- [ ] No more than 10 vehicle cards display at once.
- [ ] Each card shows real vehicle, route, departure, per-seat fare and free seats.
- [ ] A full vehicle disables booking.
- [ ] Tapping an available vehicle opens its booking detail.
- [ ] Per-seat seat counter cannot exceed available seats.
- [ ] Whole-vehicle flow still works.
- [ ] `Open in Google Maps` calls the new authenticated vehicle-location endpoint.
- [ ] Fresh Driver GPS opens the exact live point.
- [ ] Missing/stale Driver GPS uses the destination point and does not display a fake live position.
