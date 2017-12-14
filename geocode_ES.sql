\echo 'geocoding Spain'

\echo 'Parse addresses'
UPDATE amadeus_extract SET rue = regexp_replace(substr(substr(regexp_replace(adresse, '\(.*\)', ''), 1, position(',' in regexp_replace(adresse, '\(.*\)', ''))-1), 4), ' -.*', '') where iso_pays ='ES' AND length(split_part(adresse, ' ', 1))=2 AND position(',' in regexp_replace(adresse, '\(.*\)', ''))>0;

UPDATE amadeus_extract SET rue=adresse WHERE iso_pays='ES' AND position(',' in regexp_replace(adresse, '\(.*\)', ''))=0;

UPDATE amadeus_extract SET numero = btrim(regexp_replace(substr(regexp_replace(adresse, '\(.*\)', ''), position(',' in regexp_replace(adresse, '\(.*\)', ''))+1), ' -.*', '')) WHERE iso_pays='ES' AND position(',' in adresse)>0 AND substr(adresse, position(',' in adresse)+1) !~ 'S/N' AND substr(adresse, position(',' in adresse)+1) !~ 'KM';
UPDATE amadeus_extract SET numero=btrim(reverse(split_part(reverse(numero), ',', 1))) where iso_pays ='ES' and numero ~ ',';
UPDATE amadeus_extract SET numero=split_part(numero, '-', 1) where iso_pays ='ES' and numero ~ '-';
UPDATE amadeus_extract SET numero=split_part(numero, ' ', 1) where iso_pays ='ES' and numero ~ ' ';

\echo 'Then extract data and use geocode_ES.py for geocoding'
