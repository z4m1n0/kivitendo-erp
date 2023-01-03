-- @tag: seperate_table_for_onhand
-- @description: Verschiebe onhand in extra Tabelle
-- @depends: release_3_6_1
CREATE TABLE stocks (
  id INT NOT NULL DEFAULT nextval('id'),
  part_id INT UNIQUE references parts(id) ON DELETE CASCADE,
  onhand NUMERIC(25,5),
  PRIMARY KEY (id)
);

-- lock all tables while updating values
LOCK TABLE stocks IN EXCLUSIVE MODE;
LOCK TABLE inventory IN EXCLUSIVE MODE;
LOCK TABLE parts IN EXCLUSIVE MODE;

-- delete old trigger
DROP TRIGGER  IF EXISTS trig_update_onhand ON inventory;
DROP FUNCTION IF EXISTS update_onhand();

CREATE OR REPLACE FUNCTION update_stock()
  RETURNS trigger
  LANGUAGE plpgsql
AS '
BEGIN
  IF tg_op = ''INSERT'' THEN
    UPDATE stocks SET onhand = COALESCE(onhand, 0) + new.qty WHERE part_id = new.parts_id;
    RETURN new;
  ELSIF tg_op = ''DELETE'' THEN
    UPDATE stocks SET onhand = COALESCE(onhand, 0) - old.qty WHERE part_id = old.parts_id;
    RETURN old;
  ELSE
    UPDATE stocks SET onhand = COALESCE(onhand, 0) - old.qty + new.qty WHERE part_id = old.parts_id;
    RETURN new;
  END IF;
END;
';

CREATE OR REPLACE TRIGGER trig_update_stock
  AFTER INSERT OR UPDATE OR DELETE ON inventory
  FOR EACH ROW EXECUTE PROCEDURE update_stock();

-- All parts get a onhand value;
CREATE OR REPLACE FUNCTION create_stock()
  RETURNS trigger
  LANGUAGE plpgsql
AS '
BEGIN
  INSERT INTO stocks (part_id, onhand) values (new.id, 0);
  RETURN new;
END;
';
CREATE OR REPLACE TRIGGER trig_create_stock
  AFTER INSERT ON parts
  FOR EACH ROW EXECUTE PROCEDURE create_stock();


INSERT INTO stocks (part_id, onhand) SELECT id, onhand FROM parts;
-- neu berechnen? UPDATE parts SET onhand = COALESCE((SELECT SUM(qty) FROM inventory WHERE inventory.parts_id = parts.id), 0);

ALTER TABLE parts DROP COLUMN onhand;
