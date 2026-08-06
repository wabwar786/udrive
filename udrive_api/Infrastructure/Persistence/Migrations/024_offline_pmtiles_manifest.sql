CREATE TABLE IF NOT EXISTS udrive.offline_map_packs (
    id text PRIMARY KEY,
    name text NOT NULL,
    region text NOT NULL,
    south_west_latitude double precision NOT NULL,
    south_west_longitude double precision NOT NULL,
    north_east_latitude double precision NOT NULL,
    north_east_longitude double precision NOT NULL,
    file_url text NOT NULL DEFAULT '',
    file_size bigint NOT NULL DEFAULT 0 CHECK (file_size >= 0),
    version text NOT NULL DEFAULT '1.0.0',
    checksum text NOT NULL DEFAULT '',
    status text NOT NULL DEFAULT 'inactive' CHECK (status IN ('active','inactive')),
    published_at timestamptz NULL,
    minimum_app_version text NULL,
    updated_at timestamptz NULL,
    display_order integer NOT NULL DEFAULT 0,
    CONSTRAINT offline_map_bounds_valid CHECK (
        south_west_latitude < north_east_latitude AND
        south_west_longitude < north_east_longitude AND
        south_west_latitude BETWEEN -90 AND 90 AND north_east_latitude BETWEEN -90 AND 90 AND
        south_west_longitude BETWEEN -180 AND 180 AND north_east_longitude BETWEEN -180 AND 180)
);

INSERT INTO udrive.offline_map_packs
(id,name,region,south_west_latitude,south_west_longitude,north_east_latitude,north_east_longitude,file_url,file_size,version,checksum,status,display_order)
VALUES
('muzaffarabad-region','Muzaffarabad Region','Muzaffarabad',33.95,73.35,34.65,74.05,'',0,'1.0.0','','inactive',10),
('neelum-valley','Neelum Valley Route','Neelum Valley',34.15,73.40,35.20,74.60,'',0,'1.0.0','','inactive',20),
('rawalakot-banjosa','Rawalakot–Banjosa','Rawalakot and Banjosa',33.70,73.55,34.15,74.15,'',0,'1.0.0','','inactive',30),
('bagh-region','Bagh Region','Bagh',33.75,73.55,34.30,74.15,'',0,'1.0.0','','inactive',40),
('mirpur-kotli','Mirpur–Kotli','Mirpur and Kotli',33.00,73.45,33.80,74.45,'',0,'1.0.0','','inactive',50),
('leepa-valley','Leepa Valley Route','Leepa Valley',34.05,73.75,34.55,74.45,'',0,'1.0.0','','inactive',60)
ON CONFLICT (id) DO NOTHING;
