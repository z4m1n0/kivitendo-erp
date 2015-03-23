-- @tag: format_depositor_sepa_conform
-- @description: Formatiert die Datenbank-Daten für Kontoinhaber SEPA konform.
-- @depends: release_3_2_0

UPDATE customer SET depositor =
  replace(
    replace(
      replace(
        replace(
          replace(
            replace(
              replace(translate(depositor, 'àâáèéêóôùú&`', 'aaeeeoouu+'''),
                'ä', 'ae'),
              'ö', 'oe'),
            'ü', 'ue'),
          'Ä', 'Ae'),
        'Ö', 'Oe'),
      'Ü', 'Ue'),
    'ß', 'ss')
WHERE (depositor IS NOT NULL)
  AND (depositor <> '');

UPDATE vendor SET depositor =
  replace(
    replace(
      replace(
        replace(
          replace(
            replace(
              replace(translate(depositor, 'àâáèéêóôùú&`', 'aaeeeoouu+'''),
                'ä', 'ae'),
              'ö', 'oe'),
            'ü', 'ue'),
          'Ä', 'Ae'),
        'Ö', 'Oe'),
      'Ü', 'Ue'),
    'ß', 'ss')
WHERE (depositor IS NOT NULL)
  AND (depositor <> '');
