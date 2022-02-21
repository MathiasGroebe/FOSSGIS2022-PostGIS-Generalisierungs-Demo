-- Generalisiation buildings

-- Reporject buildings and add additional house numbers

DROP TABLE IF EXISTS map.building;
CREATE TABLE map.building AS
SELECT fid, name, house_number, ST_Transform(geom, 25833)::geometry(Multipolygon, 25833) AS geom
FROM import.building;
CREATE INDEX map_building_geom ON map.building USING gist(geom); 
ALTER TABLE map.building ADD PRIMARY KEY (fid);

UPDATE map.building
SET house_number = import.address.house_number
FROM import.address
WHERE ST_Intersects(map.building.geom, ST_Transform(import.address.geom, 25833)) AND building.house_number IS null;

-- Cluster buildings to find single buildings and blocks

DROP TABLE IF EXISTS map.building_cluster;
CREATE TABLE map.building_cluster AS
SELECT fid, geom, house_number, ST_ClusterDBScan(geom, 50, 2) OVER () AS region_id, ST_ClusterDBScan(geom, 0.1, 2) OVER () AS block_id
FROM map.building;
CREATE INDEX map_building_cluster_geom ON map.building_cluster USING gist(geom); 
ALTER TABLE map.building_cluster ADD PRIMARY KEY (fid);

-- Aggregate building_blocks

DROP TABLE IF EXISTS map.building_block;
CREATE TABLE map.building_block AS
SELECT row_number() OVER() as fid, array_remove(house_numbers, NULL) AS house_numbers, array_remove(region_id, NULL) AS region_id, block_id, geom::geometry(Multipolygon, 25833)
FROM
(
	SELECT array_agg(house_number) house_numbers, array_agg(region_id) region_id, block_id, ST_Multi(ST_Union(geom)) AS geom 
	FROM map.building_cluster
	WHERE block_id IS NOT null
	GROUP BY block_id
	UNION
	SELECT array[house_number] house_numbers, array[region_id] region_id, block_id, ST_Multi(geom) AS geom
	FROM map.building_cluster
	WHERE block_id IS null
	) as block_union;
CREATE INDEX map_building_block_geom ON map.building_block USING gist(geom); 
ALTER TABLE map.building_block ADD PRIMARY KEY (fid);

-- Simplify building_blocks

DROP TABLE IF EXISTS map.building_block_simple;
CREATE TABLE map.building_block_simple as
SELECT row_number() over() as fid, stc_simplify_building(geom, 5) as geom
FROM map.building_block
WHERE ST_Area(geom) > 300;
CREATE INDEX map_building_block_simpl_geom ON map.building_block_simple USING gist(geom); 
ALTER TABLE map.building_block_simple ADD PRIMARY KEY (fid);

-- Typifiy small buildings

DROP TABLE IF EXISTS map.building_point;
CREATE TABLE map.building_point as
SELECT row_number() over() as fid, region_id, house_numbers, ST_Centroid(geom)::geometry(Point, 25833) AS geom, feature_orientation(geom) as rotation
FROM map.building_block
WHERE ST_Area(geom) < 300 AND ST_Area(geom) > 80 OR
ST_Area(geom) < 300 AND region_id = '{}' OR 
ST_Area(geom) < 300 AND house_numbers != '{}';
CREATE INDEX map_building_point_geom ON map.building_point USING gist(geom); 
ALTER TABLE map.building_point ADD PRIMARY KEY (fid);