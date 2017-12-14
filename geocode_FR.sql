\echo 'PREPARATION OF ADDRESS DATA'


\echo 'GET LIST OF CODES AND NAMES OF COMMUNES'
-- CREATE TABLE fr_villes AS select distinct a.code_insee, c.nom, ST_X(ST_Centroid(ST_Transform(a.geom, 4326))) as x, ST_Y(ST_Centroid(ST_Transform(a.geom, 4326))) as y from arrondissement a JOIN commune c ON ST_Within(a.geom, c.geom) order by a.code_insee;
-- INSERT INTO fr_villes select distinct code_insee, nom, ST_X(ST_Centroid(ST_Transform(geom, 4326))) as x, ST_Y(ST_Centroid(ST_Transform(geom, 4326))) as y from commune order by a.code_insee;


\echo 'NORMALISE NAMES OF COMMUNES AND PLACES (LIEUX-DITS)'
CREATE OR REPLACE FUNCTION unaccent_string(text)
RETURNS text
IMMUTABLE
STRICT
LANGUAGE SQL
AS $$
SELECT translate(
        $1,
            'âãäåāăàąÀÁÂÃÄÅĀĂĄèéêëēĕėęěÊËÈÉĒĔĖĘĚEìíîïìĩīĭÌÍÎÏÌĨĪĬóôõöōŏőÒÓÔÕÖŌŎŐùúûüũūŭůÙÚÛÜŨŪŬŮçÇ',
            'aaaaaaaaaaaaaaaaaeeeeeeeeeeeeeeeeeeeiiiiiiiiiiiiiiiiooooooooooooooouuuuuuuuuuuuuuuucc'
            );
$$;
--ALTER TABLE geocode.fr_villes ADD nom_normalise varchar;
UPDATE geocode.fr_villes SET nom_normalise = replace(replace(replace(upper(unaccent_string(nom)) , 'SAINT', 'ST')   , '-', ' '), '''', ' ');

\echo 'ADD NAMES OF COMMUNES/ARRONDISSEMENTS TO ADDRESS AND TO LIEUX_DITS TABLE'
--ALTER TABLE geocode.fr_adresses ADD COLUMN nom_commune varchar;
UPDATE geocode.fr_adresses SET nom_commune= t.nom_normalise from geocode.fr_villes t WHERE geocode.fr_adresses.code_insee = t.code_insee;

\echo 'EXPAND ABBREVIATIONS OF STREET TYPES TO FIT AMADEUS STYLE'
--ALTER table geocode.fr_adresses ADD COLUMN rue varchar;
--ALTER table geocode.fr_adresses ADD COLUMN rue_alias varchar;
--ALTER table geocode.fr_adresses ADD COLUMN lieu_dit varchar;

UPDATE geocode.fr_adresses SET rue = (SELECT mot FROM geocode.fr_abbreviations WHERE abbreviation = split_part(nom_voie, ' ', 1)) || substr(nom_voie, position(' ' in nom_voie)), rue_alias = (SELECT mot FROM geocode.fr_abbreviations WHERE abbreviation = split_part(alias, ' ', 1)) || substr(alias, position(' ' in alias)), lieu_dit = (SELECT mot FROM geocode.fr_abbreviations WHERE abbreviation = split_part(nom_ld, ' ', 1)) || substr(nom_ld, position(' ' in nom_ld));

\echo 'For those names where no abbreviations were found, just copy the name as such'
UPDATE geocode.fr_adresses SET rue = nom_voie WHERE rue is null;
UPDATE geocode.fr_adresses SET rue_alias = alias WHERE rue_alias is null;
UPDATE geocode.fr_adresses SET lieu_dit = nom_ld WHERE lieu_dit is null;

\echo 'Erase all hyphens and apostrophes'
UPDATE geocode.fr_adresses SET rue = replace(replace(rue, '-', ' '), '''', ' ');
UPDATE geocode.fr_adresses SET rue_alias = replace(replace(rue_alias, '-', ' '), '''', ' ');
UPDATE geocode.fr_adresses SET lieu_dit = replace(replace(lieu_dit, '-', ' '), '''', ' ');

CREATE INDEX idx_fradresses_codepost ON geocode.fr_adresses (code_post);
CREATE INDEX idx_fradresses_rue ON geocode.fr_adresses (rue);
CREATE INDEX idx_fradresses_rue_trgm ON geocode.fr_adresses USING gin (rue gin_trgm_ops);
CREATE INDEX idx_fradresses_ruealias ON geocode.fr_adresses (rue_alias);
CREATE INDEX idx_fradresses_ruealias_trgm ON geocode.fr_adresses USING gin (rue_alias gin_trgm_ops);
CREATE INDEX idx_fradresses_lieudit ON geocode.fr_adresses (lieu_dit);
CREATE INDEX idx_fradresses_lieudit_trgm ON geocode.fr_adresses USING gin (lieu_dit gin_trgm_ops);
CREATE INDEX idx_fradresses_nomcommune ON geocode.fr_adresses (nom_commune);
ANALYZE geocode.fr_adresses;

\echo 'ADD NAMES OF COMMUNES/ARRONDISSEMENTS TO ROUTE_ADRESSE TABLE (TO BE USED FOR INTERPOLATION OF ADDRESSES FOR WHICH ONLY STREET NAME IS KNOWN)'
--ALTER TABLE geocode.fr_route_adresse ADD COLUMN nom_commune_g varchar;
--ALTER TABLE geocode.fr_route_adresse ADD COLUMN nom_commune_d varchar;
--UPDATE geocode.fr_route_adresse SET nom_commune_d = nom_normalise FROM geocode.fr_villes WHERE fr_route_adresse.inseecom_d = fr_villes.code_insee;
--UPDATE geocode.fr_route_adresse SET nom_commune_g = nom_normalise FROM geocode.fr_villes WHERE fr_route_adresse.inseecom_g = fr_villes.code_insee;

\echo 'EXPAND ABBREVIATIONS OF STREET TYPES IN THE TABLE OF ALL STREETS IN FRANCE' 
--ALTER TABLE geocode.fr_route_adresse ADD COLUMN rue_g varchar;
--ALTER TABLE geocode.fr_route_adresse ADD COLUMN rue_d varchar;
UPDATE geocode.fr_route_adresse SET rue_d = (SELECT mot FROM geocode.fr_abbreviations WHERE abbreviation = split_part(nom_voie_d, ' ', 1)) || substr(nom_voie_d, position(' ' in nom_voie_d)), rue_g = (SELECT mot FROM geocode.fr_abbreviations WHERE abbreviation = split_part(nom_voie_g, ' ', 1)) || substr(nom_voie_g, position(' ' in nom_voie_g));
UPDATE geocode.fr_route_adresse SET rue_d = nom_voie_d WHERE rue_d is null;
UPDATE geocode.fr_route_adresse SET rue_g = nom_voie_g WHERE rue_g is null;
UPDATE geocode.fr_route_adresse SET rue_g = replace(replace(rue_g, '-', ' '), '''', ' ');
UPDATE geocode.fr_route_adresse SET rue_d = replace(replace(rue_d, '-', ' '), '''', ' ');
CREATE INDEX idx_frrouteadresse_rue_d ON geocode.fr_route_adresse (rue_d);
CREATE INDEX idx_frrouteadresse_rue_g ON geocode.fr_route_adresse (rue_g);
ANALYZE geocode.fr_route_adresse;

\echo 'create table with average coordinates per street, street_alias, place name in postal zone and commune'
DROP TABLE geocode.fr_rues_moyennes;
CREATE TABLE geocode.fr_rues_moyennes AS (SELECT rue, rue_alias, lieu_dit, code_post, nom_commune, avg(x) x, avg(y) y, count(*) nb_adresses, stddev(x) stddev_x, stddev(y) stddev_y FROM geocode.fr_adresses GROUP BY rue, rue_alias, lieu_dit, code_post, nom_commune);
CREATE INDEX idx_frruesmoyenne_rue ON geocode.fr_rues_moyennes (rue);
CREATE INDEX idx_frruesmoyenne_rue_alias ON geocode.fr_rues_moyennes (rue_alias);
CREATE INDEX idx_frruesmoyenne_lieudit ON geocode.fr_rues_moyennes (lieu_dit);
CREATE INDEX idx_frruesmoyenne_codepost ON geocode.fr_rues_moyennes (code_post);
CREATE INDEX idx_frruesmoyenne_nomcommune ON geocode.fr_rues_moyennes (nom_commune);
ANALYZE geocode.fr_rues_moyennes;

\echo 'clean names of places (lieux dits)'
--ALTER table geocode.fr_lieux_dits ADD nom_normalise varchar;
UPDATE geocode.fr_lieux_dits SET nom_normalise = upper(replace(replace(unaccent_string(nom), '-', ' '), '''', ' '));

\echo 'add postal codes and names of communes to places'
--ALTER table geocode.fr_lieux_dits ADD COLUMN codepost varchar;
UPDATE geocode.fr_lieux_dits l SET codepost = t.codepost FROM geocode.fr_codeinsee_codepostal t WHERE code_insee = t.codeinsee;
--ALTER TABLE geocode.fr_lieux_dits ADD COLUMN nom_commune varchar;
UPDATE geocode.fr_lieux_dits SET nom_commune= t.nom_normalise FROM geocode.fr_villes t WHERE fr_lieux_dits.code_insee = t.code_insee;


\echo 'geocoding France'

\echo 'prepare Amadeus database'

\echo 'delete DOM-TOM addresses'
DELETE FROM amadeus_extract WHERE iso_pays ='FR' AND (cp LIKE '97%' OR cp LIKE '98%');

\echo 'reset street names and house numbers to null'
UPDATE amadeus_extract SET rue = NULL, numero = NULL WHERE iso_pays='FR';

\echo 'extract street names and house numbers'

\echo 'house numbers are at the beginning of the address'
UPDATE amadeus_extract SET numero= array_to_string(regexp_matches(substr(adresse, 1, position(' ' in adresse)-1), '[0-9]+'), ' ') WHERE iso_pays='FR' AND position(' ' in adresse)>0 AND adresse SIMILAR TO '[0-9]%';
UPDATE amadeus_extract SET rue = regexp_replace(replace(substr(adresse, position(' ' in adresse)+1), '&', ' et '), '( )+', ' ', 'g') WHERE iso_pays = 'FR' AND position(' ' in adresse)>0 AND adresse SIMILAR TO '[0-9]%';
UPDATE amadeus_extract SET rue = regexp_replace(replace(adresse, '&', ' et '), '( )+', ' ', 'g') WHERE iso_pays='FR' AND (position(' ' in adresse)=0 OR adresse NOT SIMILAR TO '[0-9]%');

\echo 'clean street names'

\echo 'erase any house number suffix trailing before the street name'
UPDATE amadeus_extract SET rue = regexp_replace(rue, '^[A-Z] ', '') WHERE iso_pays = 'FR';
\echo 'erase anything that comes after a comma'
UPDATE amadeus_extract SET rue = substr(rue, 1, position(',' in rue)-1) WHERE iso_pays ='FR' and rue like '%,%';
\echo 'erase words LIEU DIT'
UPDATE amadeus_extract SET rue = replace(rue, 'LIEU DIT ', '') WHERE iso_pays ='FR' and rue like 'LIEU DIT %';

\echo 'replace apostrophes by space'
UPDATE amadeus_extract SET rue=regexp_replace(rue, '''''', ' ') WHERE iso_pays='FR' and rue ~ '''';
UPDATE amadeus_extract SET rue=regexp_replace(rue, '''', ' ') WHERE iso_pays='FR' and rue ~ '''';

\echo 'Erase any trace of previous geocoding'
UPDATE amadeus_extract SET x=NULL, y=NULL, rue_trouvee=NULL, ville_trouvee=NULL, status=NULL, num_above=NULL, num_below=NULL WHERE iso_pays='FR';

\echo 'exact match including locality name with street either equal to street name or to alias of street name or to place name (lieu-dit)'
UPDATE amadeus_extract amadeus SET x = geocode.fr_adresses.x, y = geocode.fr_adresses.y, status='exact' FROM geocode.fr_adresses WHERE iso_pays='FR' AND cp=code_post AND (amadeus.rue = fr_adresses.rue OR amadeus.rue=fr_adresses.rue_alias OR amadeus.rue = fr_adresses.lieu_dit) AND amadeus.numero::int = fr_adresses.numero AND amadeus.ville = fr_adresses.nom_commune;

SET work_mem = '1024MB';
SET temp_tablespaces = 'tempspace';
SELECT set_limit(0.60001);

\echo 'find closest locality name'
UPDATE amadeus_extract amadeus SET ville_trouvee=t4.nom_commune FROM (SELECT id, nom_commune FROM (SELECT t1.id, t2.nom_commune, similarity(t1.ville, t2.nom_commune) as similarity, rank() OVER (PARTITION BY t1.id ORDER BY similarity(t1.ville, t2.nom_commune) DESC) FROM amadeus_extract t1 JOIN geocode.fr_adresses t2 ON (t1.cp = t2.code_post AND t1.ville % t2.nom_commune) WHERE t1.x is null AND t1.iso_pays='FR') t3 WHERE rank=1) t4 WHERE amadeus.id=t4.id;

\echo 'Find closest locality name in cp using only first word of the city name in Amadeus'
UPDATE amadeus_extract amadeus SET ville_trouvee=t4.nom_commune, status='ville_1er_mot' FROM (SELECT id, nom_commune FROM (SELECT t1.id, t2.nom_commune, similarity(t1.ville, t2.nom_commune) as similarity, rank() OVER (PARTITION BY t1.id ORDER BY similarity(t1.ville, t2.nom_commune) DESC) FROM amadeus_extract t1 JOIN geocode.fr_adresses t2 ON (t1.cp = t2.code_post AND btrim(split_part(t1.ville, ' ', 1)) = btrim(t2.nom_commune)) WHERE t1.x is null AND t1.iso_pays='FR') t3 WHERE rank=1) t4 WHERE amadeus.id=t4.id;

\echo 'find corresponding streets, aliases or place names within (found) locality'
UPDATE amadeus_extract SET rue_trouvee=t4.rue FROM
        (SELECT id, rue FROM
            (SELECT t1.id,
                CASE
                        WHEN similarity(t1.rue, t2.rue) >= greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) THEN t2.rue
                        WHEN similarity(t1.rue, t2.rue_alias) >= greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) THEN t2.rue_alias
                        WHEN similarity(t1.rue, t2.lieu_dit) >= greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) THEN t2.lieu_dit
                         ELSE NULL
                  END as rue,
                  greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) as similarity,
                  rank()
                OVER (PARTITION BY t1.id ORDER BY greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) DESC)
                FROM amadeus_extract t1 JOIN geocode.fr_adresses t2
                ON (t1.cp = t2.code_post AND t1.ville_trouvee = t2.nom_commune
                   AND (t1.rue % t2.rue OR t1.rue % t2.rue_alias OR t1.rue % t2.lieu_dit))
                 WHERE t1.x is null AND t1.iso_pays='FR') t3
           WHERE rank=1) t4
        WHERE amadeus_extract.id=t4.id;

RESET work_mem;
RESET temp_tablespaces;

\echo 'exact match with found locality and street equal to found street name or to alias of street name or to place name (lieu-dit)'
UPDATE amadeus_extract amadeus SET x = geocode.fr_adresses.x, y = geocode.fr_adresses.y, status='exact_fnd_ville_rue' FROM geocode.fr_adresses WHERE iso_pays='FR' AND cp=code_post AND (amadeus.rue_trouvee = fr_adresses.rue OR amadeus.rue_trouvee=fr_adresses.rue_alias OR amadeus.rue_trouvee = fr_adresses.lieu_dit) AND amadeus.numero::int = fr_adresses.numero AND amadeus.ville_trouvee = fr_adresses.nom_commune AND amadeus.x IS NULL AND amadeus.rue_trouvee is not null AND amadeus.ville_trouvee IS NOT NULL;

\echo 'getting street names based only on last word of street (+ postal code and commune name)'
SET work_mem = '1024MB';
SET temp_tablespaces = 'tempspace';
SELECT set_limit(0.3);
UPDATE amadeus_extract SET rue_trouvee=t4.rue, status='rue_dernier_mot' FROM
        (SELECT id, rue FROM
            (SELECT t1.id,
                CASE
                        WHEN similarity(t1.rue, t2.rue) >= greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) THEN t2.rue
                        WHEN similarity(t1.rue, t2.rue_alias) >= greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) THEN t2.rue_alias
                        WHEN similarity(t1.rue, t2.lieu_dit) >= greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) THEN t2.lieu_dit
                         ELSE NULL
                  END as rue,
                  greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) as similarity,
                  rank()
                OVER (PARTITION BY t1.id ORDER BY greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) DESC)
                FROM amadeus_extract t1 JOIN geocode.fr_adresses t2
                ON (t1.cp = t2.code_post AND t1.ville_trouvee = t2.nom_commune
                   AND  (split_part(reverse(t1.rue), ' ', 1) = split_part(reverse(t2.rue), ' ', 1) OR split_part(reverse(t1.rue), ' ', 1) = split_part(reverse(t2.rue_alias), ' ', 1) OR split_part(reverse(t1.rue), ' ', 1) = split_part(reverse(t2.lieu_dit), ' ', 1)))
                 WHERE t1.x is null AND t1.iso_pays='FR') t3
           WHERE rank=1) t4
        WHERE amadeus_extract.id=t4.id;
RESET work_mem;
RESET temp_tablespaces;

\echo 'exact match with found locality and street equal to found street name or to alias of street name or to place name (lieu-dit)'
UPDATE amadeus_extract amadeus SET x = geocode.fr_adresses.x, y = geocode.fr_adresses.y, status='xact_fnd_rue_drn_mot' FROM geocode.fr_adresses WHERE iso_pays='FR' AND cp=code_post AND (amadeus.rue_trouvee = fr_adresses.rue OR amadeus.rue_trouvee=fr_adresses.rue_alias OR amadeus.rue_trouvee = fr_adresses.lieu_dit) AND amadeus.numero::int = fr_adresses.numero AND amadeus.ville_trouvee = fr_adresses.nom_commune AND amadeus.x IS NULL AND amadeus.rue_trouvee is not null AND amadeus.ville_trouvee IS NOT NULL AND status = 'rue_dernier_mot';

\echo 'create house number interpolation function with city name'
CREATE OR REPLACE FUNCTION interpoler_numero(datatable TEXT, data_champ_rue TEXT, data_champ_ville TEXT, addresstable TEXT, pays TEXT, whereclause TEXT, address_champ_rue1 TEXT, address_champ_rue2 TEXT, address_champ_rue3 TEXT, address_champ_cp TEXT, address_champ_numero TEXT, address_champ_ville TEXT) RETURNS INTEGER AS $$
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

        EXECUTE 'SELECT addr.' || quote_ident(address_champ_numero) || ' as numero, addr.x, addr.y FROM geocode.' || quote_ident(addresstable) || '  addr WHERE (' || quote_ident(address_champ_rue1) || ' = $1 OR ' || quote_ident(address_champ_rue1) || ' = $1 OR ' || quote_ident(address_champ_rue1) || ' = $1) AND ' || quote_ident(address_champ_cp) || ' = $2 AND ' || quote_ident(address_champ_ville) || ' = $3 AND ' || quote_ident(address_champ_numero) || ' < $4  ORDER BY numero desc LIMIT 1' INTO num_below_data USING rec_data.rue, rec_data.cp, rec_data.ville, data_num;
        EXECUTE 'SELECT addr.' || quote_ident(address_champ_numero) || ' as numero, addr.x, addr.y FROM geocode.' || quote_ident(addresstable) || '  addr WHERE (' || quote_ident(address_champ_rue1) || ' = $1 OR ' || quote_ident(address_champ_rue1) || ' = $1 OR ' || quote_ident(address_champ_rue1) || ' = $1) AND ' || quote_ident(address_champ_cp) || ' = $2 AND ' || quote_ident(address_champ_ville) || ' = $3 AND ' || quote_ident(address_champ_numero) || ' >= $4  ORDER BY numero ASC LIMIT 1' INTO num_above_data USING rec_data.rue, rec_data.cp, rec_data.ville, data_num;

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

\echo 'interpolating based on closest integer house numbers in the found street'
SELECT interpoler_numero('amadeus_extract', 'rue_trouvee', 'ville_trouvee', 'fr_adresses', 'FR', 'x is null AND rue_trouvee is not null AND numero is not null AND ville_trouvee is not null', 'rue', 'rue_alias', 'lieu_dit', 'code_post', 'numero', 'nom_commune');
 

\echo 'when no house number is known, match of found street in postal code area and municipality; x, y SET to centerpoint of line defined by PostGIS ST_LineInterpolatePoint() function with a_fraction = 0.5'
UPDATE amadeus_extract amadeus SET x = fr_route_adresse.x, y = fr_route_adresse.y, status = 'exact_rue_seule' FROM geocode.fr_route_adresse WHERE iso_pays = 'FR' AND (cp = fr_route_adresse.codepost_g OR cp = fr_route_adresse.codepost_d) AND (ville_trouvee = fr_route_adresse.nom_commune_g OR ville_trouvee = fr_route_adresse.nom_commune_d) AND (rue_trouvee = fr_route_adresse.rue_g OR rue_trouvee = fr_route_adresse.rue_d) AND amadeus.x is null AND amadeus.numero is null and amadeus.rue_trouvee is not null;

\echo 'exact match of found street name with place names (lieux dits)'
UPDATE amadeus_extract amadeus SET x = ld.x, y = ld.y, status='exact_lieu_dit' FROM geocode.fr_lieux_dits ld WHERE iso_pays='FR' AND cp=ld.codepost AND amadeus.rue_trouvee = ld.nom_normalise AND amadeus.ville_trouvee = ld.nom_commune AND amadeus.x IS NULL AND amadeus.rue_trouvee is not null AND amadeus.ville_trouvee IS NOT NULL AND numero IS NULL;

\echo 'match with found street (or street alias or place name), found city name and postal code, using average of x,y for this combination in address table'
UPDATE amadeus_extract amadeus SET x = moy.x, y = moy.y, status='moyenne_rue' FROM geocode.fr_rues_moyennes moy WHERE iso_pays='FR' AND cp=code_post AND (amadeus.rue_trouvee = moy.rue OR amadeus.rue_trouvee=moy.rue_alias OR amadeus.rue_trouvee = moy.lieu_dit) AND amadeus.ville_trouvee = moy.nom_commune AND amadeus.x IS NULL AND amadeus.rue_trouvee is not null AND amadeus.ville_trouvee IS NOT NULL AND amadeus.numero is null;

\echo 'exact match using first two numbers of postal code (= departement) and street name and commune'
UPDATE amadeus_extract amadeus SET x = geocode.fr_adresses.x, y = geocode.fr_adresses.y, status='exact_wo_ville_cp2ch' FROM geocode.fr_adresses WHERE iso_pays='FR' AND substr(cp,1,2)=substr(code_post,1,2) AND amadeus.rue = fr_adresses.rue AND amadeus.ville_trouvee=nom_commune AND amadeus.numero::int = fr_adresses.numero AND amadeus.x is null;

\echo 'prepare enough memory and disk space'
SET work_mem = '1024MB';
SET temp_tablespaces = 'tempspace';
SELECT set_limit(0.60001);

\echo 'find corresponding streets, aliases or place names within postal code zone, ignoring name of city'
UPDATE amadeus_extract SET rue_trouvee=t4.rue, status = 'rue_trouvee_cp_only' FROM
        (SELECT id, rue FROM
            (SELECT t1.id,
                CASE
                        WHEN similarity(t1.rue, t2.rue) >= greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) THEN t2.rue
                        WHEN similarity(t1.rue, t2.rue_alias) >= greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) THEN t2.rue_alias
                        WHEN similarity(t1.rue, t2.lieu_dit) >= greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) THEN t2.lieu_dit
                         ELSE NULL
                  END as rue,
                  greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) as similarity,
                  rank()
                OVER (PARTITION BY t1.id ORDER BY greatest(similarity(t1.rue, t2.rue), similarity(t1.rue, t2.rue_alias), similarity(t1.rue, t2.lieu_dit)) DESC)
                FROM amadeus_extract t1 JOIN geocode.fr_adresses t2
                ON (t1.cp = t2.code_post
                   AND (t1.rue % t2.rue OR t1.rue % t2.rue_alias OR t1.rue % t2.lieu_dit))
                 WHERE t1.x is null AND t1.iso_pays='FR') t3
           WHERE rank=1) t4
        WHERE amadeus_extract.id=t4.id;

\echo 'reset to normal memory and disk space'
RESET work_mem;
RESET temp_tablespaces;

\echo 'exact match without locality, only cp and street equal to just found street name or to alias of street name or to place name (lieu-dit)'
UPDATE amadeus_extract amadeus SET x = geocode.fr_adresses.x, y = geocode.fr_adresses.y, status='xact_fnd_rue_no_vill' FROM geocode.fr_adresses WHERE iso_pays='FR' AND cp=code_post AND (amadeus.rue_trouvee = fr_adresses.rue OR amadeus.rue_trouvee=fr_adresses.rue_alias OR amadeus.rue_trouvee = fr_adresses.lieu_dit) AND amadeus.numero::int = fr_adresses.numero AND amadeus.ville_trouvee = fr_adresses.nom_commune AND amadeus.x IS NULL AND amadeus.rue_trouvee is not null AND amadeus.ville_trouvee IS NOT NULL AND status = 'rue_trouvee_cp_only';

\echo 'create house number interpolation function without city name'
CREATE OR REPLACE FUNCTION interpoler_numero(datatable TEXT, data_champ_rue TEXT, addresstable TEXT, pays TEXT, whereclause TEXT, address_champ_rue1 TEXT, address_champ_rue2 TEXT, address_champ_rue3 TEXT, address_champ_cp TEXT, address_champ_numero TEXT) RETURNS INTEGER AS $$
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

        EXECUTE 'SELECT addr.' || quote_ident(address_champ_numero) || ' as numero, addr.x, addr.y FROM geocode.' || quote_ident(addresstable) || '  addr WHERE (' || quote_ident(address_champ_rue1) || ' = $1 OR ' || quote_ident(address_champ_rue1) || ' = $1 OR ' || quote_ident(address_champ_rue1) || ' = $1) AND ' || quote_ident(address_champ_cp) || ' = $2 AND ' || quote_ident(address_champ_numero) || ' < $3  ORDER BY numero desc LIMIT 1' INTO num_below_data USING rec_data.rue, rec_data.cp, data_num;
        EXECUTE 'SELECT addr.' || quote_ident(address_champ_numero) || ' as numero, addr.x, addr.y FROM geocode.' || quote_ident(addresstable) || '  addr WHERE (' || quote_ident(address_champ_rue1) || ' = $1 OR ' || quote_ident(address_champ_rue1) || ' = $1 OR ' || quote_ident(address_champ_rue1) || ' = $1) AND ' || quote_ident(address_champ_cp) || ' = $2 AND ' || quote_ident(address_champ_numero) || ' >= $3  ORDER BY numero ASC LIMIT 1' INTO num_above_data USING rec_data.rue, rec_data.cp, data_num;

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


\echo 'interpolating based on closest integer house numbers in the found street without city name'
SELECT interpoler_numero('amadeus_extract', 'rue_trouvee', 'fr_adresses', 'FR', E'x is null AND rue_trouvee is not null AND numero is not null AND status = \'rue_trouvee_cp_only\'', 'rue', 'rue_alias', 'lieu_dit', 'code_post', 'numero');

\echo 'match with found street (or street alias or place name) and postal code (ignoring city name), using average of x,y for this combination in address table'
UPDATE amadeus_extract amadeus SET x = moy.x, y = moy.y, status='moy_rue_sans_ville' FROM geocode.fr_rues_moyennes moy WHERE iso_pays='FR' AND cp=code_post AND (amadeus.rue_trouvee = moy.rue OR amadeus.rue_trouvee=moy.rue_alias OR amadeus.rue_trouvee = moy.lieu_dit) AND amadeus.x IS NULL AND amadeus.rue_trouvee is not null AND amadeus.numero is null AND amadeus.status='rue_trouvee_cp_only';

\echo 'set to average address coordinate of commune within the cp'
UPDATE amadeus_extract am SET x=t.x, y=t.y, status = 'commune' FROM (SELECT nom_commune, code_post, avg(x) x, avg(y) y FROM geocode.fr_adresses GROUP BY nom_commune, code_post) t WHERE am.cp = t.code_post and am.ville_trouvee = t.nom_commune and am.iso_pays = 'FR' AND am.x is null;
