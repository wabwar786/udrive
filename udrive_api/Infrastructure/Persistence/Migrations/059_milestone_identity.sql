-- Let a milestone keep its identity when an admin reorders the list.
--
-- A milestone's identity was its position. The admin upsert in
-- AdminGrowthService wrote:
--
--     ON CONFLICT (campaign_id, sort_order) DO UPDATE SET
--         title = EXCLUDED.title, reward_amount = EXCLUDED.reward_amount,
--         condition_type = EXCLUDED.condition_type, ...
--
-- so "the milestone at position 2" was the row being edited, not "the
-- milestone the admin was looking at". Swap two milestones in the panel and
-- the rows do not move: their contents do.
--
-- That matters because driver_campaign_progress points at milestone ids, and
-- a row already 'Credited' is never reopened — on purpose, so a recalculated
-- metric cannot pay twice. Put the two together and a reorder means:
--
--   * the milestone whose row was already Credited for a driver now holds the
--     OTHER milestone's condition and reward, and that driver can never be
--     paid for it — the row is finished;
--   * the row at the other position was not credited, so the delete above it
--     removes it and the insert creates a fresh id — and the driver who had
--     already been paid for that content under the old position gets paid for
--     it a second time under the new one.
--
-- One milestone double-paid, one never paid, from dragging a row in a list.
--
-- The fix is in the service: the admin now sends back each milestone's id, the
-- id is what gets updated, and sort_order becomes an ordinary editable column
-- like the title. The database's part is to stop refusing the intermediate
-- state. Swapping positions 1 and 2 passes through a moment where two rows
-- both claim position 2, which a plain UNIQUE rejects even though the
-- transaction ends up valid. Deferring the check to COMMIT allows the swap and
-- still refuses a list that really does have two rows at the same position.
--
-- INITIALLY IMMEDIATE keeps the old behaviour everywhere else; only the
-- milestone upsert asks for the deferral, with SET CONSTRAINTS inside its own
-- transaction.

ALTER TABLE udrive.growth_campaign_milestones
    DROP CONSTRAINT IF EXISTS growth_campaign_milestones_campaign_id_sort_order_key;

ALTER TABLE udrive.growth_campaign_milestones
    DROP CONSTRAINT IF EXISTS ux_growth_milestone_position;

ALTER TABLE udrive.growth_campaign_milestones
    ADD CONSTRAINT ux_growth_milestone_position
        UNIQUE (campaign_id, sort_order)
        DEFERRABLE INITIALLY IMMEDIATE;
