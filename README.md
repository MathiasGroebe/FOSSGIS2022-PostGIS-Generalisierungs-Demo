# FOSSGIS2022-PostGIS-Generalisierungs-Demo

Code zur Demosession bei der FOSSGIS 2022 

## Inhalt

 - Lua-Skripte zum Import der OSM-Daten in eine Datenbank (Zielschema "import")
 - Funktionen für die Generalisierung (jeweils mit Verweise auf Quellen)
 - Abfolge von SQL-Befehlen zur Erstellung und Befüllung der Tabellen (Zielschema "map"

## Vorbereiten der PostgreSQL/PostGIS Datenbank

    CREATE EXTENSION PostGIS;
    CREATE SCHEMA import;
    CREATE SCHEMA map;
