\echo 'geocoding United Kingdom (called 'GB' in Amadeus)'

\echo 'Erase any trace of previous geocoding'
UPDATE amadeus_extract SET x=NULL, y=NULL, rue_trouvee=NULL, status=NULL, num_above=NULL, num_below=NULL WHERE iso_pays='GB';

\echo 'begin geocoding'

\echo 'exact match of postcdes using variable length postcodes in address base'
UPDATE amadeus SET x = gb_postcodes.x, y = gb_postcodes.y, status = 'postcode' FROM geocode.gb_postcodes WHERE cp = gb_postcodes.cp_var;

\echo' Using average on cp-1 in geocoding table on total available cp in amadeus if length(cp) in amadeus > 4'
UPDATE amadeus SET amadeus.x = t.x, amadeus.y = t.y, status='exact cp = avg of -1' FROM (SELECT substr(cp_var, 1, length(cp_var)-1) AS cp, avg(x) AS x, avg(y) AS y FROM geocode.gb_postcodes WHERE x is not null GROUP BY cp_1) t WHERE amadeus.cp = t.cp AND length(amadeus.cp) > 4 AND amadeus.x is null AND amadeus.iso_pays='GB';

\echo' Using average on cp-1 in geocoding table on cp-1 in amadeus if length(cp) in amadeus > 4'
UPDATE amadeus SET x = t.x, y = t.y, status='cp-1 = avg -1' FROM (SELECT substr(cp_var, 1, length(cp_var)-1) AS cp, avg(x) AS x, avg(y) AS y FROM geocode.gb_postcodes WHERE x is not null GROUP BY cp) t WHERE substr(amadeus.cp, 1, length(amadeus.cp)-1) = t.cp AND length(amadeus.cp) > 4 AND amadeus.x is null AND amadeus.iso_pays='GB';

\echo' Using average on cp-2 in geocoding table on total available cp in amadeus if length(cp) in amadeus > 4'
UPDATE amadeus SET x = t.x, y = t.y, status='postcode avg des -2' FROM (SELECT substr(cp_var, 1, length(cp_var)-2) AS cp, avg(x) AS x, avg(y) AS y FROM geocode.gb_postcodes WHERE x is not null GROUP BY cp) t WHERE amadeus.cp = t.cp AND length(amadeus.cp) > 4 AND amadeus.x is null AND amadeus.iso_pays='GB';

\echo' Using average on cp-2 in geocoding table on cp-1 in amadeus if length(cp) in amadeus > 4'
UPDATE amadeus SET x = t.x, y = t.y, status='postcode avg des -2' FROM (SELECT substr(cp_var, 1, length(cp_var)-2) AS cp, avg(x) AS x, avg(y) AS y FROM geocode.gb_postcodes WHERE x is not null GROUP BY cp) t WHERE substr(amadeus.cp, 1, length(amadeus.cp)-1) = t.cp AND length(amadeus.cp) > 4 AND amadeus.x is null AND amadeus.iso_pays='GB';

\echo' Using average on cp-2 in geocoding table on cp-2 in amadeus if length(cp) in amadeus > 4'
UPDATE amadeus SET x = t.x, y = t.y, status='postcode avg des -2' FROM (SELECT substr(cp_var, 1, length(cp_var)-2) AS cp, avg(x) AS x, avg(y) AS y FROM geocode.gb_postcodes WHERE x is not null GROUP BY cp) t WHERE substr(amadeus.cp, 1, length(amadeus.cp)-2) = t.cp AND length(amadeus.cp) > 4 AND amadeus.x is null AND amadeus.iso_pays='GB';
