--[[
osm2pgsql -c -C 4000 -O flex -S _place.lua -d postgres://...  beispiel.osm.pbf
--]]


print('osm2pgsql version: ' .. osm2pgsql.version)

local tables = {}
local mySchema = 'import'


tables.places = osm2pgsql.define_node_table('places', {
    { column = 'name',    type = 'text' },
    { column = 'type',    type = 'text' },
    { column = 'population', type = 'text' },
    { column = 'capital', type = 'text' },
    { column = 'geom',    type = 'point' },
}
, {schema = mySchema}
)
tables.peaks = osm2pgsql.define_node_table('peaks', {
    { column = 'name',    type = 'text' },
    { column = 'name_en',    type = 'text' },
    { column = 'type',    type = 'text' },
    { column = 'ele', type = 'text' },  
    { column = 'geom',    type = 'point', projection = 4326 },
}, {schema = mySchema})


function osm2pgsql.process_node(object)


    if object.tags.place then
        tables.places:add_row({
            name = object.tags.name,
            type = object.tags.place,
			population = object.tags.population,
            capital = object.tags.capital,
        })
    end
	
    if object.tags.natural == 'peak' or object.tags.natural == 'vulcano' then
        tables.peaks:add_row({
            name = object.tags.name,
            name_en = object.tags['name:en'],
            type = object.tags.natural,
			ele = object.tags.ele,
        })
    end
	
	
end
