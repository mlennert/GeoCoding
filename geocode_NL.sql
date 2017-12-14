\echo 'geocoding Netherlands'

\echo 'reset street names and house numbers to NULL'
UPDATE amadeus SET rue = NULL, numero = NULL WHERE iso_pays='NL';

\echo 'prepare addresses in amadeus'
UPDATE amadeus SET rue=substr(adresse, 1, position(array_to_string(regexp_matches(adresse, '[0-9]'), ' ') in adresse)-1) WHERE iso_pays='NL';
UPDATE amadeus SET rue = adresse WHERE iso_pays='NL' AND (position(' ' in adresse)=0 OR adresse NOT SIMILAR TO '%[0-9]%');
UPDATE amadeus SET rue=btrim(rue) WHERE iso_pays='NL';
UPDATE amadeus SET numero = array_to_string(regexp_matches(substr(adresse, position(array_to_string(regexp_matches(adresse, '[0-9]'), ' ') in adresse)), '[0-9]*'), '')::numeric WHERE iso_pays='NL';

\echo 'Erase any trace of previous geocoding'
UPDATE amadeus SET x=NULL, y=NULL, rue_trouvee=NULL, status=NULL, num_above=NULL, num_below=NULL WHERE iso_pays='NL';

\echo 'begin geocoding' 

\echo 'exact match'
UPDATE amadeus SET x = nl_adresses.x , y = nl_adresses.y, rue_trouvee=straatnaam, status='exact' FROM geocode.nl_adresses WHERE iso_pays='NL' AND cp = postcode AND upper(rue)=upper(straatnaam) AND numero::numeric = huisnummer;

\echo 'find streets for those that are not yet geocoded'
SELECT set_limit(0.60001);
UPDATE amadeus set rue_trouvee=t4.rue FROM (SELECT id, rue FROM (SELECT t1.id, t2.rue, similarity(t1.rue, t2.rue) as similarity, rank() OVER (PARTITION BY t1.id ORDER BY similarity(t1.rue, t2.rue) DESC) FROM amadeus t1 JOIN geocode.nl_adresses t2 ON cp = t2.postcode AND t1.rue % t2.straatnaam) WHERE t1.x is null AND t1.iso_pays='NL') t3 WHERE rank=1) t4 WHERE amadeus.id=t4.id;

\echo 'geocode with found streets'
UPDATE amadeus SET x = nl_adresses.x , y = nl_adresses.y, status='rue_trouvee_exact' FROM geocode.nl_adresses WHERE iso_pays='NL' AND cp = nl_adresses.postcode AND amadeus.rue_trouvee=nl_adresses.straatnaam AND amadeus.numero::numeric = nl_adresses.huisnummer AND amadeus.x is null;

\echo 'create house number interpolation function'


CREATE OR REPLACE FUNCTION interpoler_numero(datatable TEXT, data_champ_rue TEXT, addresstable TEXT, pays TEXT, whereclause TEXT, address_champ_rue TEXT, address_champ_cp TEXT, address_champ_numero TEXT) RETURNS INTEGER AS $$
DECLARE

counter integer;
counter_found integer;
counter_found_above integer;
counter_found_below integer;
counter_not_found integer;
rec_data RECORD;
data_num integer;
num_below_data RECORD;
num_above_data RECORD;



dist_num_from_below double precision;
interpol_x double precision;
interpol_y double precision;

BEGIN

    counter := 0;
    counter_found := 0;
    counter_not_found := 0;
    counter_found_above := 0;
    counter_found_below := 0;

    FOR rec_data IN 
        EXECUTE 'SELECT id, ' || quote_ident(data_champ_rue) || ' as rue, numero, cp, x, y FROM ' || quote_ident(datatable) || ' WHERE iso_pays =' || quote_literal(pays) || ' AND ' || whereclause
        LOOP

        counter := counter + 1;
        data_num := regexp_replace(rec_data.numero, '[^0-9]', '', 'g')::int;

        EXECUTE 'SELECT addr.' || quote_ident(address_champ_numero) || ' as numero, addr.x, addr.y FROM geocode.' || quote_ident(addresstable) || '  addr WHERE upper(' || quote_ident(address_champ_rue) || ') = upper($1) AND ' || quote_ident(address_champ_cp) || ' = $2 AND ' || quote_ident(address_champ_numero) || ' < $3  ORDER BY numero desc LIMIT 1' INTO num_below_data USING rec_data.rue, rec_data.cp, data_num;
        EXECUTE 'SELECT addr.' || quote_ident(address_champ_numero) || ' as numero, addr.x, addr.y FROM geocode.' || quote_ident(addresstable) || '  addr WHERE upper(' || quote_ident(address_champ_rue) || ') = upper($1) AND ' || quote_ident(address_champ_cp) || ' = $2 AND ' || quote_ident(address_champ_numero) || ' >= $3  ORDER BY numero ASC LIMIT 1' INTO num_above_data USING rec_data.rue, rec_data.cp, data_num;

    CASE
        WHEN num_above_data.x IS NOT NULL AND num_below_data.x IS NOT NULL THEN
             dist_num_from_below = (data_num - num_below_data.numero)::float / (num_above_data.numero - num_below_data.numero)::float;
             IF num_below_data.x < num_above_data.x THEN
                 interpol_x = num_below_data.x + (num_above_data.x - num_below_data.x)*dist_num_from_below;
             ELSE
                 interpol_x = num_below_data.x - (num_below_data.x - num_above_data.x)*dist_num_from_below;
             END IF;
             IF num_below_data.y < num_above_data.y THEN
                 interpol_y = num_below_data.y + (num_above_data.y - num_below_data.y)*dist_num_from_below;
             ELSE
                 interpol_y = num_below_data.y - (num_below_data.y - num_above_data.y)*dist_num_from_below;
             END IF;

             EXECUTE 'UPDATE ' || quote_ident(datatable) || E' SET x = $1, y = $2, num_above = $3, num_below = $4, status=\'interpolated\' WHERE id = $5' USING interpol_x, interpol_y, num_above_data.numero, num_below_data.numero, rec_data.id;
             counter_found := counter_found + 1;

        WHEN num_above_data.x IS NOT NULL AND num_below_data.x IS NULL THEN
             EXECUTE 'UPDATE ' || quote_ident(datatable) || E' SET x = $1, y = $2, num_above = $3, num_below = $4, status=\'coords above\' WHERE id = $5' USING num_above_data.x, num_above_data.y, num_above_data.numero, num_below_data.numero, rec_data.id;
             counter_found_above := counter_found_above + 1;

        WHEN num_above_data.x IS NULL AND num_below_data.x IS NOT NULL THEN
             EXECUTE 'UPDATE ' || quote_ident(datatable) || E' SET x = $1, y = $2, num_above = $3, num_below = $4, status=\'coords below\' WHERE id = $5' USING num_below_data.x, num_below_data.y, num_above_data.numero, num_below_data.numero, rec_data.id;
             counter_found_below := counter_found_below + 1;

        ELSE
             counter_not_found := counter_not_found + 1;

        END CASE;

    END LOOP;

    RAISE INFO USING MESSAGE = 'Treated total of ' || counter || ' records, for ' || counter_found || ' relevant numbers were found on both sides, for ' || counter_found_above || ' a relevant number was found above, for ' || counter_found_below || ' a relevant number was found below, and for ' || counter_not_found || ' nothing was found';

    RETURN counter;

END

$$

LANGUAGE plpgsql;

\echo 'interpolating based on closest integer house numbers in the street'
SELECT interpoler_numero('amadeus', 'rue_trouvee', 'nl_adresses', 'NL', 'x is null AND rue_trouvee is not null AND numero is not null', 'straatnaam', 'postcode', 'huisnummer');

\echo 'use mean coordinates of postcode as approximation'
UPDATE amadeus SET x = nl_postcodes.x, y = nl_postcodes.y, status='postcode' FROM geocode.nl_postcodes WHERE iso_pays='NL' and amadeus.x is null and cp = postcode;
