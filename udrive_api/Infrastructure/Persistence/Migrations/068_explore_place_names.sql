-- Place names without "Valley".
--
-- Explore Kashmir shows the destination catalogue to customers in large
-- type, and the seeded rows called several places "… Valley" (and "وادی …"
-- in Urdu). That word is not to be used in customer-facing copy, so the
-- catalogue drops it here. Only udrive.destinations changes; an admin can
-- still edit any name in the portal afterwards.
--
-- "Jhelum Valley" is both a place row and a district. It becomes Hattian
-- Bala, the district's headquarters, rather than a bare "Jhelum", which
-- would read as the city in Punjab.

UPDATE udrive.destinations
SET name_en = 'Hattian Bala',
    name_ur = 'ہٹیاں بالا',
    updated_at = now()
WHERE name_en = 'Jhelum Valley';

UPDATE udrive.destinations
SET district = 'Hattian Bala',
    updated_at = now()
WHERE district = 'Jhelum Valley';

UPDATE udrive.destinations
SET name_en    = btrim(regexp_replace(name_en,    '\s*\mValley\M', '', 'gi')),
    summary_en = regexp_replace(
                     regexp_replace(summary_en, 'Jhelum Valley', 'Hattian Bala', 'g'),
                     '\s*\mValley\M', '', 'gi'),
    district   = btrim(regexp_replace(district,   '\s*\mValley\M', '', 'gi')),
    name_ur    = btrim(regexp_replace(regexp_replace(name_ur, 'وادیِ?\s*', '', 'g'), '\s*ویلی', '', 'g')),
    summary_ur = regexp_replace(regexp_replace(summary_ur, 'وادیِ?\s*', '', 'g'), '\s*ویلی', '', 'g'),
    updated_at = now()
WHERE name_en ~* '\mValley\M'
   OR summary_en ~* '\mValley\M'
   OR district ~* '\mValley\M'
   OR name_ur ~ '(وادی|ویلی)'
   OR summary_ur ~ '(وادی|ویلی)';
