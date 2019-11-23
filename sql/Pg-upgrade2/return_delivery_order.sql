-- @tag: return_delivery_order
-- @description: Retoure Lieferschein
-- @depends: delivery_orders
ALTER TABLE delivery_orders ADD COLUMN returns smallint default 0;
ALTER TABLE defaults ADD COLUMN rdonumber text;
ALTER TABLE defaults ADD COLUMN transfer_returns_into_components smallint default 0;
UPDATE defaults SET rdonumber = '0';
INSERT INTO transfer_type (direction, description, sortkey) VALUES ('in', 'cancelled', (SELECT COALESCE(MAX(sortkey), 0) + 1 FROM transfer_type));
