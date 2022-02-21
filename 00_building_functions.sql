/*
Source: https://github.com/mapbox/postgis-vt-util/blob/master/postgis-vt-util.sql

Copyright (c), Mapbox All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

    Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


*/ 


/******************************************************************************
### OrientedEnvelope ###
Returns an oriented minimum-bounding rectangle for a geometry.
__Parameters:__
- `geometry` g - A geometry.
__Returns:__ `geometry(polygon)`
******************************************************************************/
create or replace function OrientedEnvelope (g geometry)
    returns geometry(polygon)
    language plpgsql immutable as
$func$
declare
    p record;
    p0 geometry(point);
    p1 geometry(point);
    ctr geometry(point);
    angle_min float;
    angle_cur float;
    area_min float;
    area_cur float;
begin
    -- Approach is based on the rotating calipers method:
    -- <https://en.wikipedia.org/wiki/Rotating_calipers>
    g := ST_ConvexHull(g);
    ctr := ST_Centroid(g);
    for p in (select (ST_DumpPoints(g)).geom) loop
        p0 := p1;
        p1 := p.geom;
        if p0 is null then
            continue;
        end if;
        angle_cur := ST_Azimuth(p0, p1) - pi()/2;
        area_cur := ST_Area(ST_Envelope(ST_Rotate(g, angle_cur, ctr)));
        if area_cur < area_min or area_min is null then
            area_min := area_cur;
            angle_min := angle_cur;
        end if;
    end loop;
    return ST_Rotate(ST_Envelope(ST_Rotate(g, angle_min, ctr)), -angle_min, ctr);
end;
$func$;

-- Extension for orientation

/******************************************************************************
### Orientiation ###
__Returns:__ `numeric`
******************************************************************************/
drop function if exists feature_orientation;
create or replace function feature_orientation (g geometry)
    returns numeric
    language plpgsql immutable as
$func$
declare
    p record;
    p0 geometry(point);
    p1 geometry(point);
    ctr geometry(point);
    angle_min float;
    angle_cur float;
    area_min float;
    area_cur float;
begin
    -- Approach is based on the rotating calipers method:
    -- <https://en.wikipedia.org/wiki/Rotating_calipers>
    g := ST_ConvexHull(g);
    ctr := ST_Centroid(g);
    for p in (select (ST_DumpPoints(g)).geom) loop
        p0 := p1;
        p1 := p.geom;
        if p0 is null then
            continue;
        end if;
        angle_cur := ST_Azimuth(p0, p1) - pi()/2;
        area_cur := ST_Area(ST_Envelope(ST_Rotate(g, angle_cur, ctr)));
        if area_cur < area_min or area_min is null then
            area_min := area_cur;
            angle_min := angle_cur;
        end if;
    end loop;
    return degrees(angle_min) + 90 ;
end;
$func$;

