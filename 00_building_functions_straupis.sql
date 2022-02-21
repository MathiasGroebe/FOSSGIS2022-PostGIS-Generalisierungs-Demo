/*
Source https://github.com/openmaplt/vector-map/tree/master/db/func

MIT License

Copyright (c) 2017 Asociacija "Atvirasis žemėlapis"

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

create or replace function stc_simplify_building_line(r geometry, t integer, l integer default 100, d boolean default false) returns geometry as $$
/*******************************************************************
* Simplify building line (exterior or interior ring).
* @g = line geometry (not polygon!)
* @t = tolerance
* @d = debug true|false
*******************************************************************/
declare
fg geometry;     -- final geometry
prev geometry;   -- previous geometry
smallest float;  -- length of smallest edge
sn integer;      -- position of second vertex of smallest edge
len float;       -- length of current vertex
i integer;
aze float;       -- azimuth of chosen (shortest) edge
azp float;       -- azimuth of shortest element + 1
azm float;       -- azimuth of shortest element - 1
intrusion boolean; -- true - intrusion, false - extrusion
lp float;        -- length of shortest element + 1
lm float;        -- length of shortest element - 1
ac integer;      -- azimuth change (between edge-1 and edge+1)
az float;        -- working azimuth (usage depending on case)
azc integer;     -- working azimuth change (usage depending on case)
l1 geometry;     -- first new point search line
l2 geometry;     -- second new point search line
np geometry;     -- new point (points will be moved to this position for simplification)
np2 geometry;    -- new point2 (for some calculations 2 new point positions are calculated)
ex geometry=ST_GeomFromText('LINESTRING EMPTY', 25833); -- excluded edges
ig geometry;     -- initial iteration geometry
dg boolean = d;  -- debug (insert debug geomeries)
edge geometry;   -- shortest edge
ew geometry;     -- working edge (usage depending on case)
max integer = l;
begin
  fg = stc_simplify_angle(r);
  loop
    if max = 0 then
      return fg;
    else
      max = max - 1;
    end if;
    --raise notice 'remaining iterations %', max+1;
    ig = fg;

    if dg then delete from temp where id != 0; end if; -- debug
    -- Do not try to simplify geometry if it only has 4 vertexes
    if st_numpoints(fg) <= 5 then
      return fg;
    end if;
    if dg then insert into temp values (1, fg); end if; -- debug

    ------------------------------------
    -- Find shortest not excluded edge
    ------------------------------------
    smallest = 1000000;
    -- loop through all edges and find the smallest one
    for i in 1..st_numpoints(fg) loop
      if i > 1 then
        -- calculate length of line made of vertexes i-1 and i
        edge = st_makeline(prev, st_pointn(fg, i));
        len = st_length(edge);
        --raise notice 'length % = %', i, len; -- debug
        if len < smallest and len <= t then
          if not st_isempty(st_difference(edge, st_buffer(ex, 0.1))) then
            smallest = len;
            sn = i;
          --else
          --  raise notice 'edge in exclusion list';
          end if;
        end if;
      end if;
      prev = st_pointn(fg, i);
    end loop;
    edge = st_makeline(st_pointn(fg, sn-1), st_pointn(fg, sn));

    if smallest = 1000000 then
      -- there are no edges to be simplified
      return fg;
    else
      --raise notice 'smallest edge is % (%)', sn, smallest;
      if dg then insert into temp values (5, st_makeline(st_pointn(fg, sn - 1), st_pointn(fg, sn))); end if; -- debug
      -- if smallest edge is close to the end/start of the line - move all vertexes
      -- so that we could easily reach neighbouring elements
      -- TODO: modify "move_up" to be able to rotate vertexes not +1, but +/-n positions in one go
      if sn = 2 then
        fg = stc_move_up(fg);
        fg = stc_move_up(fg);
        sn = sn + 2;
      elseif sn = 3 then
        fg = stc_move_up(fg);
        sn = sn + 1;
      elseif sn = st_numpoints(fg) then
        fg = stc_move_up(fg);
        fg = stc_move_up(fg);
        fg = stc_move_up(fg);
        sn = 4;
      elseif sn = st_numpoints(fg) - 1 then
        fg = stc_move_up(fg);
        fg = stc_move_up(fg);
        fg = stc_move_up(fg);
        fg = stc_move_up(fg);
        sn = 4;
      end if;
      ig = fg;
    end if;

    ----------------------------------------------------------------------
    -- calculate lengths and azimuths of shortest and neighbouring edges
    ----------------------------------------------------------------------
    aze = degrees(st_azimuth(st_pointn(fg, sn-1),   st_pointn(fg, sn)));

    azp = degrees(st_azimuth(st_pointn(fg, sn),   st_pointn(fg, sn+1)));
    lp  = st_length(st_makeline(st_pointn(fg, sn), st_pointn(fg, sn+1)));
    if dg then insert into temp values (7, (st_makeline(st_pointn(fg, sn), st_pointn(fg, sn+1)))); end if;

    azm = degrees(st_azimuth(st_pointn(fg, sn-2), st_pointn(fg, sn-1)));
    lm  = st_length(st_makeline(st_pointn(fg, sn-2), st_pointn(fg, sn-1)));
    if dg then insert into temp values (7, (st_makeline(st_pointn(fg, sn-2), st_pointn(fg, sn-1)))); end if;
    --raise notice 'degrees % %', azm, azp;

    if dg then
      insert into temp values (99,  st_pointn(fg, sn-1));
      insert into temp values (100, st_pointn(fg, sn));
      insert into temp values (101, st_pointn(fg, sn+1));
    end if;

    -- Calculat if it is an extrusion or intrusion
    ac = azp - aze;
    if ac > 180 then ac = ac - 360;
    elseif ac < -180 then ac = ac + 360;
    end if;
    --raise notice 'ac=%', ac;
    intrusion = ac < 0;

    -- calculate change of angles between shortest and neighbouring edges
    ac := azp - azm;
/*    if ac > 180 then
      ac := -180 + (ac % 180);
    elseif ac < -180 then
      ac :=  180 - (abs(ac) % 180);
    end if;*/
    if ac > 180 then ac = ac - 360;
    elseif ac < -180 then ac = ac + 360;
    end if;
    --if dg then raise notice 'diff ac=% edgelength=%', ac, st_length(edge); end if; -- debug

    --------------
    -- CHANGE ~0
    --------------
    if ac between -40 and 40 then
      if dg then raise notice 'CHANGE 0 (ac=% edgelength=%)', ac, st_length(edge); end if; -- debug
      if lm > lp then
        --raise notice '>';
        l1 = st_makeline(
               st_pointn(fg, sn-1),
               st_transform(st_project(st_transform(st_pointn(fg, sn-1), 4326), 1000, pi() * azm / 180.0)::geometry, 25833)
             );
        az = degrees(st_azimuth(st_pointn(fg, sn+1), st_pointn(fg, sn+2)));
        ew = st_makeline(st_pointn(fg, sn+1), st_pointn(fg, sn+2));
        if dg then insert into temp values (10, ew); end if;
        np = st_intersection(l1, ew);
        if st_isempty(np) then
          l2 = st_makeline(
                 st_pointn(fg, sn+1),
                 st_transform(st_project(st_transform(st_pointn(fg, sn+1), 4326), -1000, pi() * az / 180.0)::geometry, 25833)
               );
          np = st_intersection(l1, l2);
        end if;
        if st_isempty(np) then
          ex = st_union(ex, edge);
        else
          fg = st_setpoint(fg, sn-1, np);
          fg = st_setpoint(fg, sn, np);
        end if;
      else
        --raise notice '<';
        l1 = st_makeline(
               st_pointn(fg, sn),
               st_transform(st_project(st_transform(st_pointn(fg, sn), 4326), -1000, pi() * azp / 180.0)::geometry, 25833)
             );
        az = degrees(st_azimuth(st_pointn(fg, sn-2), st_pointn(fg, sn-3)));
        ew = st_makeline(st_pointn(fg, sn-2), st_pointn(fg, sn-3));
        if dg then insert into temp values (10, ew); end if;
        np = st_intersection(l1, ew);
        if st_isempty(np) then
          l2 = st_makeline(
                 st_pointn(fg, sn-2),
                 st_transform(st_project(st_transform(st_pointn(fg, sn-2), 4326), -1000, pi() * az / 180.0)::geometry, 25833)
               );
          np = st_intersection(l1, l2);
          if st_isempty(np) then
            if sn-4 = 0 then
              az = degrees(st_azimuth(st_pointn(fg, -2), st_pointn(fg, sn-3)));
            else
              az = degrees(st_azimuth(st_pointn(fg, sn-4), st_pointn(fg, sn-3)));
            end if;
            l2 = st_makeline(
                   st_pointn(fg, sn-3),
                   st_transform(st_project(st_transform(st_pointn(fg, sn-3), 4326), 1000, pi() * az / 180.0)::geometry, 25833)
                 );
            np = st_intersection(l1, l2);
          end if;
        end if;
        if st_isempty(np) then
          ex = st_union(ex, edge);
        else
          fg = st_setpoint(fg, sn-1, np);
          fg = st_setpoint(fg, sn-2, np);
          fg = st_setpoint(fg, sn-3, np);
        end if;
      end if;

    -------------------
    -- CHANGE 180 EXT
    -------------------
    elseif (ac between 160 and 180 or ac between -180 and -160) and not intrusion then
      if dg then raise notice 'CHANGE +180 EXT (ac=% edgelength=%)', ac, st_length(edge); end if; -- debug
      if lp > t and lm > t then
        if lp > lm then
          az = degrees(st_azimuth(st_pointn(fg, sn), st_pointn(fg, sn-1)));
          np = st_transform(st_project(st_transform(st_pointn(fg, sn-1), 4326), t - st_length(edge) + 0.1, pi() * az / 180.0)::geometry, 25833);
          az = degrees(st_azimuth(st_pointn(fg, sn-1), st_pointn(fg, sn-2)));
          l1 = st_makeline(
                 np,
                 st_transform(st_project(st_transform(np, 4326), 1000, pi() * az / 180.0)::geometry, 25833)
               );
          np2 = st_closestpoint(st_intersection(fg, l1), np);
          if not st_isempty(np2) then
            fg = st_setpoint(fg, sn-2, np);
            fg = st_setpoint(fg, sn-3, np2);
          else
            az = degrees(st_azimuth(st_pointn(fg, sn), st_pointn(fg, sn-1)));
            l1 = st_makeline(
                   st_pointn(fg, sn-1),
                   st_transform(st_project(st_transform(st_pointn(fg, sn-1), 4326), 1000, pi() * az / 180.0)::geometry, 25833)
                 );
            if sn - 4 = 0 then
              az = degrees(st_azimuth(st_pointn(fg, -2),   st_pointn(fg, sn-3)));
            else
              az = degrees(st_azimuth(st_pointn(fg, sn-4), st_pointn(fg, sn-3)));
            end if;
            l2 = st_makeline(
                   st_pointn(fg, sn-3),
                   st_transform(st_project(st_transform(st_pointn(fg, sn-3), 4326), 1000, pi() * az / 180.0)::geometry, 25833)
                 );
            np = st_intersection(l1, l2);
            if not st_isempty(np) then
              if st_distance(np, fg) > t then
                ex = st_union(ex, edge);
              else
                fg = st_setpoint(fg, sn-2, np);
                fg = st_setpoint(fg, sn-3, np);
                --fg = st_setpoint(fg, sn-3, np);
              end if;
            else
              raise notice 'TODO A';
              ex = st_union(ex, edge);
            end if;
          end if;
        else
          az = degrees(st_azimuth(st_pointn(fg, sn-1), st_pointn(fg, sn)));
          np = st_transform(st_project(st_transform(st_pointn(fg, sn), 4326), t - st_length(edge) + 0.1, pi() * az / 180.0)::geometry, 25833);
          az = degrees(st_azimuth(st_pointn(fg, sn), st_pointn(fg, sn+1)));
          l1 = st_makeline(
                 np,
                 st_transform(st_project(st_transform(np, 4326), 1000, pi() * az / 180.0)::geometry, 25833)
               );
          np2 = st_closestpoint(st_intersection(fg, l1), np);
          if not st_isempty(np) and not st_isempty(np2) then
            fg = st_setpoint(fg, sn-1, np);
            fg = st_setpoint(fg, sn, np2);
          else
            raise notice 'TODO B';
            ex = st_union(ex, edge);
          end if;
        end if;
      else
        az = degrees(st_azimuth(st_pointn(fg, sn-3), st_pointn(fg, sn-2)));
        l1 = st_makeline(
               st_pointn(fg, sn-2),
               st_transform(st_project(st_transform(st_pointn(fg, sn-2), 4326), 1000, pi() * az / 180.0)::geometry, 25833)
             );
        ew = st_makeline(st_pointn(fg, sn), st_pointn(fg, sn+1));
        np = st_intersection(l1, ew);

        az = degrees(st_azimuth(st_pointn(fg, sn+2), st_pointn(fg, sn+1)));
        l2 = st_makeline(
               st_pointn(fg, sn+1),
               st_transform(st_project(st_transform(st_pointn(fg, sn+1), 4326), 1000, pi() * az / 180.0)::geometry, 25833)
             );
        np2 = st_intersection(l1, l2);
        if not st_isempty(np2) and st_contains(st_makepolygon(fg), np2) then
          fg = st_setpoint(fg, sn-3, np2);
          fg = st_setpoint(fg, sn-2, np2);
          fg = st_setpoint(fg, sn-1, np2);
          fg = st_setpoint(fg, sn, np2);
          np = np2;
        else
          ew = st_makeline(st_pointn(fg, sn-1), st_pointn(fg, sn-2));
          np2 = st_intersection(l2, ew);
          if st_isempty(np) and not st_isempty(np2) then
            fg = st_setpoint(fg, sn, np2);
            fg = st_setpoint(fg, sn-1, np2);
            fg = st_setpoint(fg, sn-2, np2);
          elseif st_isempty(np2) and not st_isempty(np) then
            fg = st_setpoint(fg, sn-1, np);
            fg = st_setpoint(fg, sn-2, np);
            fg = st_setpoint(fg, sn-3, np);
          else
            ew = st_makeline(st_pointn(fg, sn-3), st_pointn(fg, sn-2));
            np = st_intersection(l2, ew);
            if not st_isempty(np) then
              fg = st_setpoint(fg, sn, np);
              fg = st_setpoint(fg, sn-1, np);
              fg = st_setpoint(fg, sn-2, np);
              fg = st_setpoint(fg, sn-3, np);
            else
              raise notice 'TODO C';
              ex = st_union(ex, edge);
            end if;
          end if;
        end if;
      end if;

    -------------------
    -- CHANGE 180 INT
    -------------------
    elseif (ac between 160 and 180 or ac between -180 and -160) and intrusion then
      if dg then raise notice 'CHANGE +180 INT (ac=% edgelength=%)', ac, st_length(edge); end if; -- debug
      az = degrees(st_azimuth(st_pointn(fg, sn-3), st_pointn(fg, sn-2)));
      l1 = st_makeline(
             st_pointn(fg, sn-2),
             st_transform(st_project(st_transform(st_pointn(fg, sn-2), 4326), 1000, pi() * az / 180.0)::geometry, 25833)
           );
      ew = st_makeline(st_pointn(fg, sn), st_pointn(fg, sn+1));
      np = st_intersection(l1, ew);

      az = degrees(st_azimuth(st_pointn(fg, sn+2), st_pointn(fg, sn+1)));
      l2 = st_makeline(
             st_pointn(fg, sn+1),
             st_transform(st_project(st_transform(st_pointn(fg, sn+1), 4326), 1000, pi() * az / 180.0)::geometry, 25833)
           );
      np2 = st_intersection(l1, l2);
      if not st_isempty(np2) and st_contains(st_makepolygon(fg), np2) then
        raise notice 'TODO D';
        ex = st_union(ex, edge);
        -- perkelti visus taškus į np2?
      else
        ew = st_makeline(st_pointn(fg, sn-1), st_pointn(fg, sn-2));
        np2 = st_intersection(l2, ew);
        if st_isempty(np) and not st_isempty(np2) then
          fg = st_setpoint(fg, sn, np2);
          fg = st_setpoint(fg, sn-1, np2);
          fg = st_setpoint(fg, sn-2, np2);
        elseif st_isempty(np2) and not st_isempty(np) then
          fg = st_setpoint(fg, sn-1, np);
          fg = st_setpoint(fg, sn-2, np);
          fg = st_setpoint(fg, sn-3, np);
        else
          ew = st_makeline(st_pointn(fg, sn-3), st_pointn(fg, sn-2));
          np = st_intersection(l2, ew);
          if not st_isempty(np) then
            fg = st_setpoint(fg, sn, np);
            fg = st_setpoint(fg, sn-1, np);
            fg = st_setpoint(fg, sn-2, np);
            fg = st_setpoint(fg, sn-3, np);
          else
            raise notice 'TODO E';
            ex = st_union(ex, edge);
          end if;
        end if;
      end if;

    --------------
    -- CHANGE 90
    --------------
    elseif (ac between 50 and 110) or
           (ac between -110 and -50) then
      if dg then raise notice 'CHANGE 90 (ac=% edgelength=%)', ac, st_length(edge); end if; -- debug
      l1 = st_makeline(
             st_pointn(fg, sn-2),
             st_transform(st_project(st_transform(st_pointn(fg, sn-1), 4326), 100, pi() * azm / 180.0)::geometry, 25833)
           );
      l2 = st_makeline(
             st_pointn(fg, sn+1),
             st_transform(st_project(st_transform(st_pointn(fg, sn), 4326), -1000, pi() * azp / 180.0)::geometry, 25833)
           );
      np = st_intersection(l1, l2);
      if not st_isempty(np) then
        fg = st_setpoint(fg, sn-1, np);
        fg = st_setpoint(fg, sn-2, np);
      else
        ex = st_union(ex, edge);
      end if;

    ------------------
    -- UNPROCESSABLE
    ------------------
    elseif (ac between -160 and -110) or
           (ac between -50 and -40) or
           (ac between 40 and 50) or
           (ac between 110 and 160) then
      ex = st_union(ex, edge);

    else
      if dg then raise notice 'UNSUPPORTED ac=%', ac;
      else raise 'UNSUPPORTED ac=%', ac; end if;
      ex = st_union(ex, edge);
    end if;

    -- remove irrelevant vertexes
    fg = stc_simplify_turbo(fg);

    -- debug
    if dg then
      insert into temp values (2, l1);
      insert into temp values (2, l2);
      insert into temp values (3, np);
      insert into temp values (3, np2);
      insert into temp values (4, fg);
      insert into temp values (9, ex);
    end if;

    fg = stc_remove_spike(fg);
    fg = stc_simplify_angle(fg);
    fg = stc_simplify_angle(fg);

    if st_numpoints(fg) < 5 then
      raise notice 'EXCEPTION. TOO MANY NODES REMOVED';
      return ig;
    elseif not st_issimple(fg) then
      raise notice 'EXCEPTION. NOT SIMPLE RESULT';
      ex = st_union(ex, edge);
      if dg then insert into temp values (9, ex); end if;
      fg = stc_simplify_turbo(ig);
    --raise notice '% / % = %', st_area(st_makepolygon(fg)), st_area(st_makepolygon(r)), st_area(st_makepolygon(fg)) * 1.0 / st_area(st_makepolygon(r));
    --if (st_area(st_makepolygon(fg)) * 1.0 / st_area(st_makepolygon(r)) < 0.67) or
    elseif (st_area(st_makepolygon(fg)) < t ^ 2) then
      raise notice 'EXCEPTION. FINAL AREA < %', t ^ 2;
      ex = st_union(ex, edge);
      if dg then insert into temp values (9, ex); end if;
      fg = stc_simplify_turbo(ig);
    end if;
  end loop;
end
$$ language plpgsql;

create or replace function stc_simplify_building(r geometry, t integer, mi integer default 100, d boolean default false) returns geometry as $$
/*********************************************************************
* Simplify building
*********************************************************************/
declare
tp text := st_geometrytype(r);
n geometry;
e geometry;
g geometry[];
i integer;
j integer;
m1 text;
m2 text;
m3 text;
begin
  --raise notice 'Geometry type %, mi=%', tp, mi;
  if tp = 'ST_LineString' then
    return stc_simplify_building_line(stc_simplify_turbo(r), t, mi, d);
  elseif tp = 'ST_Polygon' then
    n := stc_simplify_building(st_exteriorring(r), t, mi, d);
    j := 0;
    for i in 1..st_numinteriorrings(r) loop
      --raise notice 'interior % % %', i, st_area(st_makepolygon(st_interiorringn(r, i))), st_numpoints(st_interiorringn(r, i));
      e = st_interiorringn(r, i);
      if st_area(st_makepolygon(e)) > t ^ 2 then
        e = stc_simplify_building(st_interiorringn(r, i), t, mi, d);
        if st_area(st_makepolygon(e)) > t ^ 2 then
          j := j + 1;
          g[j] = e;
        end if;
      end if;
    end loop;
    if j = 0 then
      return st_makepolygon(n);
    else
      return st_makepolygon(n, g);
    end if;
  elseif tp = 'ST_MultiPolygon' then
    if st_numgeometries(r) = 1 then
      return st_multi(stc_simplify_building(st_geometryn(r, 1), t, mi, d));
    else
      n = st_multi(st_union(st_buffer(st_buffer(r, t, 'join=mitre'), -t, 'join=mitre'), r));
      if st_numgeometries(n) = st_numgeometries(r) then
        n = r;
      end if;
      g := null;
      for i in 1..st_numgeometries(n) loop
        if st_area(st_geometryn(n, i)) > 100 then
          g[i] := stc_simplify_building(st_geometryn(n, i), t, mi, d);
        end if;
      end loop;
      return st_multi(st_union(g));
    end if;
  else
    raise notice 'ERROR: Unknown geometry type';
    return r;
  end if;
exception when others then
  get stacked diagnostics m1 = message_text,
                          m2 = pg_exception_detail,
                          m3 = pg_exception_hint;
  raise notice 'EXCEPTION OCCURED: % % %', m1, m2, m3;
  return r;
end
$$ language plpgsql;

create or replace function stc_simplify_turbo(g geometry) returns geometry as $$
/***********************************************************************
* Performes an improved simplification. If first/last vertex of a line
* making a poligon is on the same line as 2nd and 1 before last node:
* (last-1)-------------(last/first)---------(2nd)
* st_simplify does not remove such last/first node
* simplify_turbo moves all nodes so that st_simplify could remove
* such excess vertex.
***********************************************************************/
declare
l geometry;
p geometry[];
i integer;
begin
  -- simplify given line
  l := st_simplify(g, 0.5);

  -- move vertexes up
  l := stc_move_up(l);

  -- simplify again
  l := st_simplify(l, 0.5);

  return l;
end
$$ language plpgsql;

create or replace function stc_move_up(g geometry) returns geometry as $$
/*******************************************************
* Move (rotate) all line points "up"
* point number 2 becomes point 1
* point number 3 becomes point 2
* etc.
* last point becomes point 1
* Used to move area of interest further away from
* line end (for simplification or altering/calculation)
*******************************************************/
declare
i integer;
p geometry[];
begin
  for i in 1..st_numpoints(g)-1 loop
    p[i+1] = st_pointn(g, i);
  end loop;
  p[1] := p[st_numpoints(g)];

  return st_makeline(p);
end
$$ language plpgsql;

create or replace function stc_simplify_angle(r geometry) returns geometry as $$
/*********************************************************************
*
*********************************************************************/
declare
i integer;
j integer;
prev geometry;
preva integer;
cura integer;
p geometry[];
begin
  for i in 1..st_numpoints(r) loop
    if i > 1 then
      cura := degrees(st_azimuth(prev, st_pointn(r, i)));
      --raise notice 'azimuth diff % at vertex %', cura - preva, i;
      if cura - preva between -3 and 3 then
        for j in i-1..st_numpoints(r) loop
          p[j] := st_pointn(r, j+1);
        end loop;
        return st_makeline(p);
      end if;
    else
      cura := 1000;
    end if;
    prev := st_pointn(r, i);
    p[i] := st_pointn(r, i);
    preva := cura;
  end loop;

  return r;
end
$$ language plpgsql;

create or replace function stc_remove_spike(r geometry) returns geometry as $$
/*********************************************************************
* Removes possible ONE internal spike:
* removes vertex, at which azimuth change is 180
*********************************************************************/
declare
i integer;
j integer;
prev geometry;
preva integer;
cura integer;
p geometry[];
begin
  for i in 1..st_numpoints(r) loop
    if i > 1 then
      cura := degrees(st_azimuth(prev, st_pointn(r, i)));
      --raise notice 'azimuth diff % at vertex %', cura - preva, i;
      if (cura - preva between 170 and 190) or
         (cura - preva between -190 and -170) then
        for j in i-1..st_numpoints(r) loop
          p[j] := st_pointn(r, j+1);
        end loop;
        return st_makeline(p);
      end if;
    else
      cura := 1000;
    end if;
    prev := st_pointn(r, i);
    p[i] := st_pointn(r, i);
    preva := cura;
  end loop;

  return r;
end
$$ language plpgsql;