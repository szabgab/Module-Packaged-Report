CREATE TABLE distributor (
    id      INTEGER PRIMARY KEY,
    name    VARCHAR(100)
);

CREATE TABLE cpan_dist (
    id      INTEGER PRIMARY KEY,
    name    VARCHAR(100)
);

CREATE TABLE version (
    distributor   INTEGER,
    cpan_dist     INTEGER,
    no            VARCHAR(50)
);
    
