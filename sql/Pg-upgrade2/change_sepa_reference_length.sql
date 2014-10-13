-- @tag: change_sepa_reference_length
-- @description: Verwendungszweck von SEPA Überweisungen auf 140 Zeichen ändern
-- @depends: release_3_2_0

ALTER TABLE sepa_export_items ALTER COLUMN reference TYPE CHARACTER VARYING(140);
