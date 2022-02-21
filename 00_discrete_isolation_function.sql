/*
Source: https://github.com/MathiasGroebe/discrete_isolation

BSD 3-Clause License

Copyright (c) 2021, Mathias
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


*/

CREATE OR REPLACE FUNCTION discrete_isolation(peak_table text, peak_table_geom_column_name text, elevation_column text, peak_geometry geometry, elevation_value numeric) returns decimal as
$$
DECLARE isolation_value decimal;
BEGIN

IF elevation_value IS NULL THEN RETURN NULL;

ELSE
	
	EXECUTE  'SELECT ST_Distance(''' || peak_geometry::text || '''::geometry, ' || peak_table_geom_column_name || ') as distance
	FROM ' || peak_table || '
	WHERE '|| elevation_column ||' > ' || elevation_value || '
	ORDER BY distance
	LIMIT 1' INTO isolation_value;

	IF isolation_value IS NULL THEN RETURN 30000000; -- set value for the highest peak
	END IF;

RETURN isolation_value;
END IF;

END;
$$ LANGUAGE plpgsql PARALLEL SAFE;

-- Second version of the function with a reduced complexity by limiting the search radius

CREATE OR REPLACE FUNCTION discrete_isolation(peak_table text, peak_table_geom_column_name text, elevation_column text, peak_geometry geometry, elevation_value numeric, max_search_radius numeric) returns decimal as
$$
DECLARE isolation_value decimal;
BEGIN

IF elevation_value IS NULL THEN RETURN NULL;

ELSE
	
	EXECUTE  'SELECT ST_Distance(''' || peak_geometry::text || '''::geometry, ' || peak_table_geom_column_name || ') as distance
	FROM ' || peak_table || '
	WHERE '|| elevation_column ||' > ' || elevation_value || ' AND ST_DWithin(''' || peak_geometry::text || '''::geometry, ' || peak_table_geom_column_name ||', ' || max_search_radius || ')
	ORDER BY distance
	LIMIT 1' INTO isolation_value;

	IF isolation_value IS NULL THEN RETURN max_search_radius; -- set value maxium distance
	END IF;

RETURN isolation_value;
END IF;

END;
$$ LANGUAGE plpgsql PARALLEL SAFE;

CREATE OR REPLACE FUNCTION to_elevation(elevation_value text) RETURNS numeric AS $$
DECLARE
tmp text;
elevation NUMERIC;
BEGIN
	tmp = replace(elevation_value, 'm', '');
	tmp = replace(tmp, ',', '.');
	elevation = to_number(tmp, '9999D99');
    RETURN elevation;
	EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION to_population(population_value text) RETURNS numeric AS $$
DECLARE
tmp text;
population numeric;
BEGIN
	tmp = replace(population_value, ',', '');
	tmp = replace(tmp, '.', '');
	population = to_number(tmp, '999999999');
    RETURN population;
	EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION estimate_population(place_type text) RETURNS numeric AS $$
DECLARE
population numeric;
BEGIN
	CASE
	WHEN place_type IN ('city') THEN population = 100000 + random();
	WHEN place_type IN ('town') THEN population = 5000 + random();
	WHEN place_type IN ('village') THEN population = 500 + random();
	WHEN place_type IN ('hamlet') THEN population = 50 + random();
	WHEN place_type IN ('isolated_dwelling', 'farm') THEN population = 3 + random();
	WHEN place_type IN ('locality') THEN population = 0 + random();
	ELSE NULL;
	END CASE;
    RETURN population;
END;
$$
LANGUAGE plpgsql;
