
--[[
osm2pgsql -c -C 4000 -O flex -S _place.lua -d postgres://...  beispiel.osm.pbf
--]]

print('osm2pgsql version: ' .. osm2pgsql.version)

local tables = {}
local mySchema = 'import'

-- helper function
function clean_tags(tags)
    tags.odbl = nil
    tags.created_by = nil
    tags.source = nil
    tags['source:ref'] = nil

    return next(tags) == nil
end

tables.forest = osm2pgsql.define_area_table('forest', {
	{ column = 'fid', sql_sql_type = 'serial', create_only = true },
    { column = 'name', type = 'text' },
    { column = 'geom', type = 'multipolygon' },
}, {schema = mySchema})

tables.water = osm2pgsql.define_area_table('water', {
	{ column = 'fid', sql_type = 'serial', create_only = true },
    { column = 'name', type = 'text' },
    { column = 'geom', type = 'multipolygon' },
}, {schema = mySchema})

tables.waterway = osm2pgsql.define_way_table('waterway', {
	{ column = 'fid', sql_type = 'serial', create_only = true },
    { column = 'name', type = 'text' },
	{ column = 'type', type = 'text' },
	{ column = 'tunnel', type = 'text' },
	{ column = 'layer', type = 'text' },
	{ column = 'intermittent', type = 'text' },
    { column = 'geom', type = 'linestring' },
}, {schema = mySchema})

tables.building = osm2pgsql.define_area_table('building', {
	{ column = 'fid', sql_type = 'serial', create_only = true },
    { column = 'name', type = 'text' },
	{ column = 'house_number', type = 'text' },
    { column = 'geom', type = 'multipolygon' },
}, {schema = mySchema})

tables.address = osm2pgsql.define_node_table('address', {
	{ column = 'fid', sql_type = 'serial', create_only = true },
	{ column = 'street', type = 'text' },
	{ column = 'house_number', type = 'text' },
	{ column = 'postcode', type = 'text' },
	{ column = 'city', type = 'text' },
    { column = 'geom', type = 'point' },
}, {schema = mySchema})

tables.traffic = osm2pgsql.define_way_table('traffic', {
	{ column = 'fid', sql_type = 'serial', create_only = true },
    { column = 'name', type = 'text' },
	{ column = 'highway', type = 'text' },
	{ column = 'railway', type = 'text' },
	{ column = 'service', type = 'text' },
	{ column = 'usage', type = 'text' },
	{ column = 'tracktype', type = 'text' },
	{ column = 'oneway', type = 'text' },
	{ column = 'bridge', type = 'text' },
	{ column = 'tunnel', type = 'text' },
	{ column = 'layer', type = 'text' },
	{ column = 'ref', type = 'text' },
    { column = 'geom', type = 'linestring' },
}, {schema = mySchema})

function osm2pgsql.process_node(object)

    if clean_tags(object.tags) then
        return
    end

	if object.tags['addr:housenumber'] or object.tags['addr:street'] then
        tables.address:add_row({
			street = object.tags['addr:street'],
			house_number = object.tags['addr:housenumber'],
			postcode = object.tags['addr:postcode'],
			city = object.tags['addr:city']
        })	
	end
end	

function osm2pgsql.process_way(object)

    if clean_tags(object.tags) then
        return
    end

    -- A closed way that also has the right tags for an area is a polygon.
    if object.is_closed and (object.tags.landuse == 'forest' or object.tags.natural == 'wood') then
        tables.forest:add_row({
            name = object.tags.name,
            geom = { create = 'area' }
        })
    end
	
    if object.is_closed and (object.tags.natural == 'water' or object.tags.waterway == 'riverbank') then
        tables.water:add_row({
            name = object.tags.name,
            geom = { create = 'area' }
        })
    end
	
    if object.tags.waterway == 'stream' or object.tags.waterway == 'river' or object.tags.waterway == 'canal' or object.tags.waterway == 'drain' or object.tags.waterway == 'ditch' then
        tables.waterway:add_row({
            name = object.tags.name,
			type = object.tags.waterway,
			tunnel = object.tags.tunnel,
			layer = object.tags.layer,
			intermittent = object.tags.intermittent,			
            geom = { create = 'line' }
        })
    end
	
	if object.is_closed and object.tags.building then
        tables.building:add_row({
            name = object.tags.name,
			house_number = object.tags['addr:housenumber'],
            geom = { create = 'area' }
        })
    end
	
	if object.tags.highway or object.tags.railway then
        tables.traffic:add_row({
            name = object.tags.name,
			highway = object.tags.highway,
			railway = object.tags.railway,
			service = object.tags.service,
			usage = object.tags.usage,
			tracktype = object.tags.tracktype,
			oneway = object.tags.oneway,
			bridge = object.tags.bridge,
			tunnel = object.tags.tunnel,
			layer = object.tags.layer,
			ref = object.tags.ref,
            geom = { create = 'line' }
        })
    end
	
end

function osm2pgsql.process_relation(object)

    if clean_tags(object.tags) then
        return
    end

    local type = object:grab_tag('type')

    -- Store multipolygon relations as polygons
    if type == 'multipolygon' and (object.tags.landuse == 'forest' or object.tags.natural == 'wood') then
        tables.forest:add_row({
            name = object.tags.name,
            geom = { create = 'area' }
        })
    end
	
    if type == 'multipolygon' and (object.tags.natural == 'water' or object.tags.waterway == 'riverbank') then
        tables.water:add_row({
            name = object.tags.name,
            geom = { create = 'area' }
        })
    end
	
	if type == 'multipolygon' and object.tags.building then
        tables.building:add_row({
            name = object.tags.name,
			house_number = object.tags['addr:housenumber'],
            geom = { create = 'area' }
        })
    end

end