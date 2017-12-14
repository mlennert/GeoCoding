\echo 'DECODE ADDRESSES'

\echo 'Simple method for street name and house number extraction, only keeps the first house number, no ranges and no letter modifiers'

UPDATE amadeus_extract SET
rue = btrim(substring(adresse, 1, position(btrim(array_to_string(regexp_matches(regexp_replace(right(adresse, 11), 'B[0-9A-Z]+$', ''), '^[0-9]| [0-9]+'), '')) in adresse)-1)),
numero = btrim(array_to_string(regexp_matches(regexp_replace(right(adresse, 11), 'B[0-9A-Z]+$', ''), '^[0-9]+| [0-9]+'), ''))::int
WHERE iso_pays='BE';

\echo 'More complex method trying to keep modifiers and ranges'
\echo 'In WITH-clause: regexp to identify all possible forms of house letter box numbers and letters and put them into an array'
\echo 'In CASE-clause: decide which of the array elements is the house number depending on their number and type'
\echo 'In regexp_replace of UPDATE clause:  clean out last issue with [0-9]B[0-9] housenumbers which in certain cases are special cases of letter boxes'

UPDATE amadeus_extract SET rue=btrim(t.rue), numero=btrim(regexp_replace(t.numero, '([0-9])[B][0-9]+$', '\1'))
FROM
(
	WITH adresses AS (select bvd_id, adresse, array(SELECT btrim(array_to_string(regexp_matches(adresse, '[0-9]+|[0-9]+[\. /_-][0-9]+|[0-9]+[A-Z]$|[0-9]+ [A-Z]$|[0-9](?=B[0-9]+$)|[0-9]+ [A-Z](?=[ ]*[0-9]*B[ ]*[0-9]+)|[0-9](?= B [0-9]+)|[0-9]+ [A-Z] (?=[B])|E[0-9]+|[B][0-9A-Z]+$|[0-9]B[0-9]+$|B [0-9]+$', 'g'), ''))) num_tot, cp, ville FROM amadeus_extract where iso_pays ='BE')
        SELECT bvd_id, adresse, num_tot,
        CASE WHEN array_length(num_tot, 1) > 2
                THEN substring(adresse, 1, position(num_tot[2] in adresse)-1)
        ELSE
                CASE WHEN array_length(num_tot, 1) = 2
                        THEN CASE WHEN num_tot[2] ~ '^B' OR (num_tot[2] ~ '[0-9]B[0-9]' AND num_tot[1] ~ '[0-9] [A-Z]')
                                THEN substring(adresse, 1, position(num_tot[1] in adresse)-1)
                        ELSE
                                substring(adresse, 1, position(num_tot[2] in adresse)-1)
                        END
                ELSE
                        CASE WHEN array_length(num_tot, 1) = 1 AND num_tot[1] ~ '[0-9]' AND num_tot[1] !~ '^[A-Z]'
                                THEN substring(adresse, 1, position(num_tot[1] in adresse)-1)
                        ELSE
                                adresse
                        END
                END
        END as rue,
        CASE WHEN array_length(num_tot, 1) > 2
                THEN num_tot[2]
        ELSE
                CASE WHEN array_length(num_tot, 1) = 2
                        THEN CASE WHEN num_tot[2] ~ '^B' OR (num_tot[2] ~ '[0-9]B[0-9]' AND num_tot[1] ~ '[0-9] [A-Z]')
                                THEN num_tot[1]
                        ELSE
                                num_tot[2]
                        END
                ELSE
                        CASE WHEN array_length(num_tot, 1) = 1 AND num_tot[1] ~ '[0-9]' AND num_tot[1] !~ '^[A-Z]'
                                THEN regexp_replace(num_tot[1], 'B[0-9]', '')
                        ELSE
                                NULL
                        END
                END
        END as numero,
        cp, ville
        FROM adresses
) t WHERE amadeus_extract.bvd_id=t.bvd_id AND iso_pays='BE';

\echo 'FLANDERS'

\echo 'INITIALISE'
UPDATE amadeus_extract SET x=NULL, y=NULL, status=NULL, rue_trouvee=NULL, ville_trouvee=NULL WHERE  iso_pays='BE' AND ((cp > '1499' AND cp < '4000') OR cp > '7999');


\echo 'Extract Flanders data'
SELECT id, rue, numero, cp, ville FROM amadeus_extract where iso_pays ='BE' AND ((cp > '1499' AND cp < '4000') OR cp > '7999');

\echo 'Extract table as csv and run data through the HALE metadata transformation machine to match the crab xml schema (The HUMBOLDT Alignment Editor, http://www.dhpanel.eu/humboldt-framework/hale.html)'

\echo 'Submit zipped xml file to crabmatch via Lara (https://crab.agiv.be/Lara/)'

\echo 'Transform resulting xml file to unix format and to one line per entry:'
dos2unix 20140328120352_ondernemingen.xml_result.xml
sed "s/<AC_record id/\n&/g" 20140328120352_ondernemingen.xml_result.xml | sed "s/<\/ns1:Adresconfrontatie/\n&/g" | grep AC_record > ondernemingen_results_for_import.xml

\echo 'Create table to receive xml file and load transformed results file into that table'
CREATE TABLE vla_geocoded (crabxml xml);

\echo 'Create new table that contains the result of parsing the xml into the respective fields'
CREATE TABLE vla_geocoded_parsed AS SELECT (xpath('/AC_record/@id', crabxml))[1]::text::int id, (xpath('/AC_record/Output/Adressen/Adres/Adrespositie/Xcoord/text()', crabxml))[1]::text::double precision x, (xpath('/AC_record/Output/Adressen/Adres/Adrespositie/Ycoord/text()', crabxml))[1]::text::double precision y, (xpath('/AC_record/Output/Straatnaam/text()', crabxml))[1]::text rue_trouvee, (xpath('/AC_record/Output/Adressen/Adres/Huisnummer/text()', crabxml))[1]::text num_trouvee, (xpath('/AC_record/Output/Adressen/Adres/Postcode/text()', crabxml))[1] cp, (xpath('/AC_record/Output/Gemeentenaam/text()', crabxml))[1]::text ville_trouvee, (xpath('/AC_record/Output/Adressen/Adres/Adrespositie/Herkomst/text()', crabxml))[1]::text origin FROM vla_geocoded;

\echo 'Update x,y of amadeus_extract from vla_geocoded_parsed linking the two via the id_links'
UPDATE amadeus_extract a
SET x = ST_X(ST_Transform(ST_SetSRID(ST_POINT(c.x, c.y), 31370), 4326)), y = ST_Y(ST_Transform(ST_SetSRID(ST_POINT(c.x, c.y), 31370), 4326)), rue_trouvee=c.rue_trouvee, ville_trouvee=c.ville_trouvee, status='crabmatch_'|| c.origin
FROM vla_geocoded_parsed c 
WHERE a.iso_pays='BE' AND ((a.cp > '1499' AND a.cp < '4000') OR a.cp > '7999') AND a.id = c.id;

\echo 'For meaning of origin of data, see Lara manual'

\echo 'The non-geocoded addresses can be sent to the SOAP service to find similar addresses and their location (cf geocode_vla.py)'

\echo 'create table to receive remaining addresses'
CREATE TABLE vla_remaining (id int, rue_trouvee varchar, numero_trouvee varchar, cp varchar, ville_trouvee varchar, x double precision, y double precision, status varchar, nb_adresses int);
\copy vla_remaining from adresses_geocodees.csv with delimiter '|' null ''

\echo 'update amadeus table with remaining address coordinates'
UPDATE amadeus_extract a SET x = ST_X(ST_Transform(ST_SetSrid(ST_Point(r.x, r.y), 31370), 4326)), y = ST_Y(ST_Transform(ST_SetSrid(ST_Point(r.x, r.y), 31370), 4326)), rue_trouvee = r.rue_trouvee, ville_trouvee=r.ville_trouvee, status = r.status, num_trouvee = (CASE WHEN r.status = 'house' THEN numero_trouvee ELSE NULL END) FROM vla_remaining r WHERE a.id = r.id AND a.iso_pays='BE' AND ((a.cp > '1499' AND a.cp < '4000') OR a.cp > '7999') and a.x is null;


\echo 'WALLONIA'

\echo 'Transform all Excel files (one per municipality) into one big csv file'
for i in *.xls; do name=$(basename $i .xls); libreoffice --headless --convert-to csv $i; iconv -f cp1252 -t utf-8 $name.csv | sed 's/"\([0-9]*\),[0-9]*"/\1/g' > temp; mv temp $name.csv; done
	for i in *.csv; do tail -n +2 $i >> ../tout.csv; done


\echo 'CREATE DB TABLE AND LOAD THE DATA INTO GEOCODING DATA DB'
CREATE TABLE wal_adresses (
    cle bigint,
    x bigint,
    y bigint,
    rue character varying,
    numero character varying,
    code_postal integer,
    commune character varying,
    ancienne_commune character varying,
    route_regional character varying,
    code_batiment integer,
    type_batiment character varying
);

\echo 'IN AMADEUS DB CREATE FOREIGN TABLE WITH RELEVANT INFO FROM wal_adresses'
create foreign table wal_adresses (cle bigint, x bigint, y bigint, rue character varying, numero character varying, code_postal integer, commune character varying, ancienne_commune character varying) SERVER geocoding;

\echo 'THEN CREATE LOCAL TABLE FOR GEOCODING, TRANSFORMING coordinates to EPSG 4326 and all names to capital letters'

CREATE SEQUENCE myseq;
CREATE TABLE geocode.wal_adresses as select nextval('myseq') as id, ST_X(ST_Transform(ST_SetSRID(ST_Point(x, y), 31370), 4326)) x, ST_Y(ST_Transform(ST_SetSRID(ST_Point(x, y), 31370), 4326)) y, upper(rue) rue, upper(unaccent_string(rue)) rue_ss_accents, numero, code_postal::varchar, upper(unaccent_string(commune)) commune, regexp_replace(upper(unaccent_string(ancienne_commune)), '\(.*\)', '') ancienne_commune FROM wal_adresses ;

\echo 'Remove duplicate addresses by chosing one of the addresses at random'
DELETE FROM geocode.wal_adresses WHERE id IN (SELECT id FROM (SELECT id, row_number() over (partition BY rue, numero, code_postal, commune, ancienne_commune ORDER BY id) AS rnum FROM geocode.wal_adresses) t WHERE t.rnum > 1);

UPDATE geocode.wal_adresses SET numero = NULL WHERE numero = '?';

\echo 'Add a column with simple form of housenumbers, without ranges, modifiers, or other special characters'
ALTER TABLE geocode.wal_adresses ADD column numero_int int;
UPDATE geocode.wal_adresses SET numero_int=(regexp_matches(numero, '^[0-9]+'))[1]::int;

\echo 'Create indices'
ALTER TABLE geocode.wal_adresses ADD PRIMARY KEY (id);
CREATE INDEX idx_waladresses_codepostal ON geocode.wal_adresses (code_postal);
CREATE INDEX idx_waladresses_rue ON geocode.wal_adresses (rue);
CREATE INDEX idx_waladresses_ruessaccents ON geocode.wal_adresses (rue_ss_accents);
CREATE INDEX idx_waladresses_commune ON geocode.wal_adresses (commune);
CREATE INDEX idx_waladresses_anciennecommune ON geocode.wal_adresses (ancienne_commune);
CREATE INDEX trgmidx_waladresses_rue ON geocode.wal_adresses USING gist (rue gist_trgm_ops);
CREATE INDEX trgmidx_waladresses_ruessaccents ON geocode.wal_adresses USING gist (rue_ss_accents gist_trgm_ops);
CREATE INDEX trgmidx_waladresses_commune ON geocode.wal_adresses USING gist (commune gist_trgm_ops);
CREATE INDEX trgmidx_waladresses_anciennecommune ON geocode.wal_adresses USING gist (ancienne_commune gist_trgm_ops);


\echo 'GEOCODING'

\echo 'INITIALISE'
UPDATE amadeus_extract SET x=NULL, y=NULL, status=NULL, rue_trouvee=NULL, ville_trouvee=NULL WHERE  iso_pays='BE' AND ((cp > '3999' AND cp < '8000') OR (cp > '1299' AND cp< '1500'));

\echo 'FIND CLOSEST STREET NAME AND CLOSEST MUNICIPALITY NAME (OLD OR CURRENT)'
SET work_mem = '1024MB';
SET temp_tablespaces = 'tempspace';
SELECT set_limit(0.60001);

UPDATE amadeus_extract amadeus SET rue_trouvee=t4.rue FROM (SELECT id, rue FROM (SELECT t1.id, t2.rue AS rue, similarity(t1.rue, t2.rue) AS similarity, rank() OVER (PARTITION BY t1.id ORDER BY similarity(t1.rue, t2.rue) DESC) FROM amadeus_extract t1 JOIN geocode.wal_adresses t2 ON (t1.cp = t2.code_postal AND t1.rue % t2.rue AND (t1.ville = t2.commune OR t1.ville = t2.ancienne_commune)) WHERE t1.x IS NULL AND t1.iso_pays='BE' AND ((cp > '3999' AND cp < '8000') OR (cp > '1299' AND cp< '1500'))) t3 WHERE rank=1) t4 WHERE amadeus.iso_pays='BE' AND ((cp > '3999' AND cp < '8000') OR (cp > '1299' AND cp< '1500')) AND amadeus.id=t4.id;

UPDATE amadeus_extract SET ville_trouvee=t4.ville FROM
        (SELECT id, ville FROM
            (SELECT t1.id,
                CASE
                        WHEN similarity(t1.ville, t2.commune) >= similarity(t1.ville, t2.ancienne_commune) THEN t2.commune
                        WHEN similarity(t1.ville, t2.ancienne_commune) >= similarity(t1.ville, t2.commune) THEN t2.ancienne_commune
                         ELSE NULL
                  END as ville,
                  greatest(similarity(t1.ville, t2.commune), similarity(t1.ville, t2.ancienne_commune)) as similarity,
                  rank()
                OVER (PARTITION BY t1.id ORDER BY greatest(similarity(t1.ville, t2.commune), similarity(t1.ville, t2.ancienne_commune)) DESC)
                FROM amadeus_extract t1 JOIN geocode.wal_adresses t2
                ON (t1.cp = t2.code_postal 
                   AND (t1.ville % t2.commune OR t1.ville % t2.ancienne_commune))
                 WHERE t1.x is null AND t1.iso_pays='BE' AND ((cp > '3999' AND cp < '8000') OR (cp > '1299' AND cp< '1500'))) t3
           WHERE rank=1) t4
        WHERE amadeus_extract.id=t4.id;

RESET work_mem;
RESET temp_tablespaces;

\echo 'EXACT MATCH WITH EITHER ORIGINAL STREET NAME OR FOUND STREET NAME'
UPDATE amadeus_extract a SET x=t.x, y=t.y, status='exact', rue_trouvee=t.rue, ville_trouvee=(CASE WHEN a.ville=t.commune THEN t.commune ELSE t.ancienne_commune END) FROM geocode.wal_adresses t WHERE iso_pays='BE' AND ((cp > '3999' AND cp < '8000') OR (cp > '1299' AND cp< '1500')) AND (a.rue = t.rue OR a.rue_trouvee = t.rue) AND (a.numero = t.numero OR regexp_replace(a.numero, '([0-9]+) ([A-Z])', '\1\2') = t.numero OR regexp_replace(a.numero, '-[0-9A-Z]*|/[0-9A-Z]*', '') = t.numero OR regexp_replace(a.numero, '[A-Z/ -]+[0-9]*[A-Z]*', '', 'g') = t.numero) AND (a.ville = t.commune OR a.ville = t.ancienne_commune OR a.ville_trouvee = t.commune OR a.ville_trouvee = t.ancienne_commune);

\echo 'SIMPLER VERSION OF THE SAME, USING SIMPLER HOUSENUMBERS'
UPDATE amadeus_extract a SET x=t.x, y=t.y, status='exact', rue_trouvee=t.rue, ville_trouvee=(CASE WHEN a.ville=t.commune THEN t.commune ELSE t.ancienne_commune END) FROM geocode.wal_adresses t WHERE iso_pays='BE' AND ((cp > '3999' AND cp < '8000') OR (cp > '1299' AND cp< '1500')) AND (a.rue = t.rue OR a.rue_trouvee = t.rue) AND a.numero::int = t.numero_int AND (a.ville = t.commune OR a.ville = t.ancienne_commune OR a.ville_trouvee = t.commune OR a.ville_trouvee = t.ancienne_commune);

\echo 'FOR THOSE STREETS THAT ONLY EXIST IN ONE OLD (SMALLER) MUNICIPALITY WITHIN A GIVEN POSTCODE, DO NOT COMPARE CITY NAME'
WITH doublons AS 
	(SELECT rue, code_postal FROM (SELECT rue, code_postal, count(*) AS nombre FROM (SELECT DISTINCT rue, ancienne_commune, code_postal FROM geocode.wal_adresses) t GROUP BY rue, code_postal) u WHERE nombre > 1)
	UPDATE amadeus_extract a SET x=t.x, y=t.y, status='exact_ss_ville', rue_trouvee=t.rue, ville_trouvee=(CASE WHEN a.ville=t.commune THEN t.commune ELSE t.ancienne_commune END) FROM geocode.wal_adresses t, doublons d WHERE iso_pays='BE' AND ((cp > '3999' AND cp < '8000') OR (cp > '1299' AND cp< '1500')) AND (a.rue = t.rue OR a.rue_trouvee = t.rue) AND (a.numero = t.numero OR regexp_replace(a.numero, '([0-9]+) ([A-Z])', '\1\2') = t.numero OR regexp_replace(a.numero, '-[0-9A-Z]*|/[0-9A-Z]*', '') = t.numero OR regexp_replace(a.numero, '[A-Z/ -]+[0-9]*[A-Z]*', '', 'g')=t.numero) AND (a.rue, a.cp) NOT IN (SELECT rue, code_postal FROM doublons) AND (a.rue_trouvee, a.cp) NOT IN (SELECT rue, code_postal FROM doublons) AND a.x IS NULL;

\echo 'AGAIN SIMPLER VERSION OF THE SAME WITH SIMPLER HOUSE NUMBERS'
WITH doublons AS 
	(SELECT rue, code_postal FROM (SELECT rue, code_postal, count(*) AS nombre FROM (SELECT DISTINCT rue, ancienne_commune, code_postal FROM geocode.wal_adresses) t GROUP BY rue, code_postal) u WHERE nombre > 1)
	UPDATE amadeus_extract a SET x=t.x, y=t.y, status='exact_ss_ville', rue_trouvee=t.rue, ville_trouvee=(CASE WHEN a.ville=t.commune THEN t.commune ELSE t.ancienne_commune END) FROM geocode.wal_adresses t, doublons d WHERE iso_pays='BE' AND ((cp > '3999' AND cp < '8000') OR (cp > '1299' AND cp< '1500')) AND (a.rue = t.rue OR a.rue_trouvee = t.rue) AND a.numero::int = t.numero_int AND (a.rue, a.cp) NOT IN (SELECT rue, code_postal FROM doublons) AND (a.rue_trouvee, a.cp) NOT IN (SELECT rue, code_postal FROM doublons) AND a.x IS NULL;


\echo 'interpolation'

\echo 'create interpolation function with differentiation between even and odd numbers'

CREATE OR REPLACE FUNCTION interpoler_diff_num(datatable TEXT, data_champ_rue TEXT, data_champ_ville TEXT, addresstable TEXT, pays TEXT, whereclause TEXT, address_champ_rue TEXT, address_champ_cp TEXT, address_champ_numero TEXT, address_champ_ville TEXT) RETURNS INTEGER AS $$
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
        EXECUTE 'SELECT id, ' || quote_ident(data_champ_rue) || ' as rue, numero, cp, ' || quote_ident(data_champ_ville) || ' as ville, x, y FROM ' || quote_ident(datatable) || ' WHERE iso_pays =' || quote_literal(pays) || ' AND ' || whereclause
        LOOP

        counter := counter + 1;
        data_num := regexp_replace(rec_data.numero, '[^0-9]', '', 'g')::int;


	IF data_num % 2 = 0 THEN
        	EXECUTE 'SELECT addr.' || quote_ident(address_champ_numero) || ' as numero, addr.x, addr.y FROM geocode.' || quote_ident(addresstable) || '  addr WHERE ' || quote_ident(address_champ_numero) || '%2 = 0 AND upper(' || quote_ident(address_champ_rue) || ') = upper($1) AND ' || quote_ident(address_champ_cp) || ' = $2 AND ' || quote_ident(address_champ_ville) || ' = $3 AND ' || quote_ident(address_champ_numero) || ' < $4  AND ' || quote_ident(address_champ_numero) || ' IS NOT NULL ORDER BY numero desc LIMIT 1' INTO num_below_data USING rec_data.rue, rec_data.cp, rec_data.ville, data_num;
	        EXECUTE 'SELECT addr.' || quote_ident(address_champ_numero) || ' as numero, addr.x, addr.y FROM geocode.' || quote_ident(addresstable) || '  addr WHERE ' || quote_ident(address_champ_numero) || '%2 = 0 AND upper(' || quote_ident(address_champ_rue) || ') = upper($1) AND ' || quote_ident(address_champ_cp) || ' = $2 AND ' || quote_ident(address_champ_ville) || ' = $3 AND ' || quote_ident(address_champ_numero) || ' >= $4 AND ' || quote_ident(address_champ_numero) || ' IS NOT NULL ORDER BY numero desc LIMIT 1' INTO num_above_data USING rec_data.rue, rec_data.cp, rec_data.ville, data_num;
	ELSE
        	EXECUTE 'SELECT addr.' || quote_ident(address_champ_numero) || ' as numero, addr.x, addr.y FROM geocode.' || quote_ident(addresstable) || '  addr WHERE ' || quote_ident(address_champ_numero) || '%2 = 1 AND upper(' || quote_ident(address_champ_rue) || ') = upper($1) AND ' || quote_ident(address_champ_cp) || ' = $2 AND ' || quote_ident(address_champ_ville) || ' = $3 AND ' || quote_ident(address_champ_numero) || ' < $4 AND ' || quote_ident(address_champ_numero) || ' IS NOT NULL ORDER BY numero desc LIMIT 1' INTO num_below_data USING rec_data.rue, rec_data.cp, rec_data.ville, data_num;
	        EXECUTE 'SELECT addr.' || quote_ident(address_champ_numero) || ' as numero, addr.x, addr.y FROM geocode.' || quote_ident(addresstable) || '  addr WHERE ' || quote_ident(address_champ_numero) || '%2 = 1 AND upper(' || quote_ident(address_champ_rue) || ') = upper($1) AND ' || quote_ident(address_champ_cp) || ' = $2 AND ' || quote_ident(address_champ_ville) || ' = $3 AND ' || quote_ident(address_champ_numero) || ' >= $4 AND ' || quote_ident(address_champ_numero) || ' IS NOT NULL ORDER BY numero desc LIMIT 1' INTO num_above_data USING rec_data.rue, rec_data.cp, rec_data.ville, data_num;
	END IF;


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

\echo 'interpolate with old municipality names'
select interpoler_diff_num('amadeus_extract', 'rue_trouvee', 'ville_trouvee', 'wal_adresses', 'BE', E'((cp > \'3999\' AND cp < \'8000\') OR (cp > \'1299\' AND cp< \'1500\')) AND x is null AND rue_trouvee is not null', 'rue', 'code_postal', 'numero_int', 'ancienne_commune');

\echo 'interpolate with new municipality names'
select interpoler_diff_num('amadeus_extract', 'rue_trouvee', 'ville_trouvee', 'wal_adresses', 'BE', E'((cp > \'3999\' AND cp < \'8000\') OR (cp > \'1299\' AND cp< \'1500\')) AND x is null AND rue_trouvee is not null', 'rue', 'code_postal', 'numero_int', 'commune');

\echo 'now interpolation function without differentiation of even and odd numbers'


CREATE OR REPLACE FUNCTION interpoler_num(datatable TEXT, data_champ_rue TEXT, data_champ_ville TEXT, addresstable TEXT, pays TEXT, whereclause TEXT, address_champ_rue TEXT, address_champ_cp TEXT, address_champ_numero TEXT, address_champ_ville TEXT) RETURNS INTEGER AS $$
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
        EXECUTE 'SELECT id, ' || quote_ident(data_champ_rue) || ' as rue, numero, cp, ' || quote_ident(data_champ_ville) || ' as ville, x, y FROM ' || quote_ident(datatable) || ' WHERE iso_pays =' || quote_literal(pays) || ' AND ' || whereclause
        LOOP

        counter := counter + 1;
        data_num := regexp_replace(rec_data.numero, '[^0-9]', '', 'g')::int;


       	EXECUTE 'SELECT addr.' || quote_ident(address_champ_numero) || ' as numero, addr.x, addr.y FROM geocode.' || quote_ident(addresstable) || '  addr WHERE upper(' || quote_ident(address_champ_rue) || ') = upper($1) AND ' || quote_ident(address_champ_cp) || ' = $2 AND ' || quote_ident(address_champ_ville) || ' = $3 AND ' || quote_ident(address_champ_numero) || ' < $4  AND ' || quote_ident(address_champ_numero) || ' IS NOT NULL ORDER BY numero desc LIMIT 1' INTO num_below_data USING rec_data.rue, rec_data.cp, rec_data.ville, data_num;
        EXECUTE 'SELECT addr.' || quote_ident(address_champ_numero) || ' as numero, addr.x, addr.y FROM geocode.' || quote_ident(addresstable) || '  addr WHERE upper(' || quote_ident(address_champ_rue) || ') = upper($1) AND ' || quote_ident(address_champ_cp) || ' = $2 AND ' || quote_ident(address_champ_ville) || ' = $3 AND ' || quote_ident(address_champ_numero) || ' >= $4 AND ' || quote_ident(address_champ_numero) || ' IS NOT NULL ORDER BY numero desc LIMIT 1' INTO num_above_data USING rec_data.rue, rec_data.cp, rec_data.ville, data_num;

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

\echo 'interpolate with old municipality names'
select interpoler_num('amadeus_extract', 'rue_trouvee', 'ville_trouvee', 'wal_adresses', 'BE', E'((cp > \'3999\' AND cp < \'8000\') OR (cp > \'1299\' AND cp< \'1500\')) AND x is null AND rue_trouvee is not null', 'rue', 'code_postal', 'numero_int', 'ancienne_commune');

\echo 'interpolate with new municipality names'
select interpoler_num('amadeus_extract', 'rue_trouvee', 'ville_trouvee', 'wal_adresses', 'BE', E'((cp > \'3999\' AND cp < \'8000\') OR (cp > \'1299\' AND cp< \'1500\')) AND x is null AND rue_trouvee is not null', 'rue', 'code_postal', 'numero_int', 'commune');


\echo 'BRUSSELS'


\echo 'Extract all Brussels address which have a at least a postal code from the database, replacing accented characters in order not to disturb the python-suds library'

\echo 'CREATE OR REPLACE FUNCTION unaccent_string(text) (cf geocode_FR2.sql)'

psql -tA -d amadeus -c "select id, upper(unaccent_string(rue)), numero, cp, upper(unaccent_string(ville)) FROM amadeus_extract where iso_pays='BE' and cp < '1300' AND cp <> '0'" > adresses.csv

\echo 'Launch geocode_BXL.py to geocode using the CIRB UrbIS SOAP service'

\echo 'Results are in adresses_geocoded'
\echo 'Watch out for addresses for which house number could not be found. '
\echo 'Numbers have a value of None'

\echo 'Create table to received geocoded data and load data into table'
CREATE TABLE bxl_geocoded ( id bigint, rue character varying, numero character varying, cp character varying, commune character varying, x double precision, y double precision, geomatchcode real, nb_adresses_trouvees integer
);

\echo 'Insert geocoded data into amadeus, avoiding for the time being those addresses '
\echo 'where the returned number is empty (i.e. address geocoded to the street '
\echo 'mean coordinates) and those for which the street name is below given threshold '
\echo 'of similarity (measured through trigram matching). The threshold is determined'
\echo 'empirically by looking at the results'
UPDATE amadeus_extract a SET x = ST_X(ST_Transform(ST_SetSRID(ST_Point(t.x, t.y), 31370), 4326)), y = ST_Y(ST_Transform(ST_SetSRID(ST_Point(t.x, t.y), 31370), 4326)), rue_trouvee=t.rue, ville_trouvee=t.commune, status='urbis_gmc' || geomatchcode || '_nb' || nb_adresses_trouvees FROM bxl_geocoded t WHERE a.id = t.id AND a.iso_pays='BE' and a.cp < '1300' AND a.id NOT IN (SELECT id FROM bxl_geocoded WHERE numero = 'None') AND similarity(a.rue, t.rue) > 0.57;

\echo 'Extract those where the geocoding did not work replacing - and [space] in the housenumbers'
select id, upper(unaccent_string(rue)), regexp_replace(regexp_replace(numero, '-[0-9]+', ''), ' ([A-Z])', '\1') numero, cp, upper(unaccent_string(ville)) from amadeus_extract WHERE iso_pays='BE' and cp < '1300' AND cp <> '0' AND (numero ~ '[A-Z]' or numero ~ '-') AND x is null

\echo 'Launch geocode.py on these addresses, etc'
