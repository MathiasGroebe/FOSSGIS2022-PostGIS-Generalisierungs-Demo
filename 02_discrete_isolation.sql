DROP TABLE IF EXISTS map.peaks;
CREATE TABLE map.peaks AS
SELECT node_id AS fid, name, to_elevation(ele) AS elevation, 0::numeric AS elevation_isolation, 
ST_Transform(geom, 3857) AS geom
FROM import.peaks;
CREATE INDEX map_peaks_geom ON map.peaks USING gist(geom); 
CREATE INDEX map_peaks_elevation ON map.peaks(elevation); 
ALTER TABLE map.peaks ADD PRIMARY KEY (fid);

UPDATE map.peaks
SET elevation_isolation = discrete_isolation('map.peaks', 'geom', 'elevation', geom, elevation, 300000);

DROP TABLE IF EXISTS map.places;
CREATE TABLE map.places AS
SELECT node_id AS fid, name, type, to_population(population) AS population, 0::numeric AS population_isolation, 
ST_Transform(geom, 3857) AS geom
FROM import.places
WHERE type IN ('city', 'town', 'village');
CREATE INDEX map_places_geom ON map.places USING gist(geom); 
CREATE INDEX map_places_population ON map.places(population); 
ALTER TABLE map.places ADD PRIMARY KEY (fid);

UPDATE map.places
SET population = estimate_population(type)
WHERE population IS NULL;

UPDATE map.places
SET population_isolation = discrete_isolation('map.places', 'geom', 'population', geom, population, 300000);

DROP TABLE IF EXISTS map.places;
CREATE TABLE map.places AS
SELECT node_id AS fid, name, type, to_population(population) AS population, 0::numeric AS population_isolation, 
ST_Transform(geom, 3857) AS geom
FROM import.places
WHERE type IN ('city', 'town', 'village', 'hamlet', 'isolated_dwelling', 'farm', 'locality');
CREATE INDEX map_places_geom ON map.places USING gist(geom); 
CREATE INDEX map_places_population ON map.places(population); 
ALTER TABLE map.places ADD PRIMARY KEY (fid);