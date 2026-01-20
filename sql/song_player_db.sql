-------------------------------------- STWORZENIE TABEL --------------------------------------
-- Artists
CREATE TABLE Artists(
    artist_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE
);
-- MusicGenres
CREATE TABLE MusicGenres(
    genre_id INTEGER  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    genre VARCHAR(255) NOT NULL UNIQUE
);
-- Languages
CREATE TABLE Languages(
    language_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    language VARCHAR(255) NOT NULL UNIQUE
);
-- VersionTypes
CREATE TABLE VersionTypes (
    version_type_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
);
-- MusicAlbums
CREATE TABLE MusicAlbums(
    album_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    artist_id INTEGER NOT NULL REFERENCES Artists(artist_id)
		ON UPDATE CASCADE
        ON DELETE RESTRICT,
    release_year INTEGER NOT NULL,
	UNIQUE (title, artist_id)
);
-- Songs
CREATE TABLE Songs(
    song_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    album_id INTEGER NOT NULL REFERENCES MusicAlbums(album_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    release_year INTEGER NOT NULL CHECK (release_year>1860),
    language_id INTEGER NOT NULL REFERENCES Languages(language_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    UNIQUE (title, album_id)
);
-- SongsArtists
CREATE TABLE SongsArtists(
	song_id INTEGER NOT NULL REFERENCES Songs(song_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    artist_id INTEGER NOT NULL REFERENCES Artists(artist_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
	PRIMARY KEY (song_id, artist_id)
);
-- SongsGenres
CREATE TABLE SongsGenres(
	song_id INTEGER NOT NULL REFERENCES Songs(song_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    genre_id INTEGER NOT NULL REFERENCES MusicGenres(genre_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
	PRIMARY KEY (song_id, genre_id)
);
-- SongVersions
CREATE TABLE SongVersions(
    song_version_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    song_id INTEGER NOT NULL REFERENCES Songs(song_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    version_type_id INTEGER NOT NULL REFERENCES VersionTypes(version_type_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    duration INTEGER NOT NULL CHECK (duration > 0),
    created_at DATE NOT NULL,
    UNIQUE (song_id, version_type_id, created_at)
);
-- Playlists
CREATE TABLE Playlists(
    playlist_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at DATE NOT NULL
);
-- PlaylistItems
CREATE TABLE PlaylistItems(
    playlist_id INTEGER NOT NULL REFERENCES Playlists(playlist_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    song_version_id INTEGER NOT NULL REFERENCES SongVersions(song_version_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK (position > 0),
    added_at DATE NOT NULL,
	PRIMARY KEY (playlist_id, position)
);
-- ListeningHistory
CREATE TABLE ListeningHistory(
    record_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    song_version_id INTEGER NOT NULL REFERENCES SongVersions(song_version_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    listened_at TIMESTAMP NOT NULL,
    listened_seconds INTEGER NOT NULL CHECK (listened_seconds >= 0),
    is_full_played BOOLEAN NOT NULL
);

-------------------------------------- NASZ DATABASE --------------------------------------
-- Artists
INSERT INTO Artists (name) VALUES 
('Ewelina Flinta'), 
('Natalia Kukulska'), 
('Afromental'),
('Happysad'), 
('Edyta Gorniak'), 
('Cali Y El Dandee'),
('David Bisbal'), 
('Xavi Sarria'), 
('Starset'),
('Myslovitz'),
('Rozni');

-- MusicGenres
INSERT INTO MusicGenres (genre) VALUES ('pop'), ('rock'), ('latin'), ('alternative rock'), ('electronic');

-- Languages
INSERT INTO Languages (language) VALUES ('pl'), ('en'), ('es'), ('ca'), ('fr');

-- VersionTypes
INSERT INTO VersionTypes (name) VALUES ('original'), ('acoustic'), ('remix'), ('nightcore');

-- MusicAlbums
INSERT INTO MusicAlbums (title, artist_id, release_year) VALUES 
('Przeznaczenie', 1, 2003), 
('Playing with Pop', 3, 2009),
('To nie tak, jak myslisz, kotku! (Soundtrack)', 5, 2008),
('Wszystko jedno', 4, 2004),
('3 A.M. (Deluxe)', 6, 2012),
('La nit ferida - Single', 8, 2022), 
('Vessels', 9, 2017),
('Milosc w czasach popkultury', 10, 1999),
('Single / Non-album', 11, 1984);

-- Songs
-- album_id = 9 <=> 'Single / Non-album'
INSERT INTO Songs (title, album_id, release_year, language_id) VALUES
('zaluje (Insanity)', 1, 2003, 1),
('Nie klam ze mnie kochasz', 9, 2008, 1),
('Wiernosc jest nudna - Och Karol 2 OST', 9, 2011, 1),
('Radio Song', 2, 2009, 1),
('To nie tak jak myslisz', 3, 2008, 1),
('Zanim pojde', 4, 2004, 1),
('No Hay 2 Sin 3 (Gol)', 5, 2012, 3),
('La nit ferida', 6, 2022, 4),
('Satellite', 7, 2017, 2),
('Dlugosc dzwieku samotnosci', 8, 1999, 1);

-- SongsArtists
INSERT INTO SongsArtists (song_id, artist_id) VALUES 
(1, 1), 
(2, 1), 
(3, 2), 
(4, 3), 
(5, 5), 
(6, 4), 
(7, 6), 
(7, 7), 
(8, 8), 
(9, 9), 
(10, 10);

-- SongsGenres
INSERT INTO SongsGenres (song_id, genre_id) VALUES 
(1, 1), 
(2, 1), 
(3, 1), 
(4, 2), 
(5, 1), 
(6, 2), 
(7, 3), 
(8, 4), 
(9, 4), 
(10, 1);

-- SongVersions
INSERT INTO SongVersions (song_id, version_type_id, duration, created_at) VALUES
(1, 1, 213, '2003-04-24'),
(2, 1, 186, '2008-01-01'),
(3, 1, 226, '2011-05-19'),
(4, 1, 231, '2009-03-06'),
(5, 1, 166, '2008-11-17'),
(6, 1, 253, '2004-03-08'),
(7, 1, 226, '2012-01-01'),
(8, 1, 222, '2022-01-14'),
(9, 1, 239, '2017-01-20'),
(9, 2, 230, '2018-01-12'),
(10, 1, 251, '1999-10-18'),
(10, 2, 251, '2002-02-14'),
(10, 3, 373, '2019-10-18'),
(10, 4, 289, '2018-06-06');

-- Playlists
INSERT INTO Playlists (name, created_at) VALUES 
('40-letnia rozwodka zmienia swoje zycie', '2022-10-09'),
('Ulubione', '2026-01-09');

-- PlaylistItems
INSERT INTO PlaylistItems (playlist_id, song_version_id, position, added_at) VALUES 
(1, 1, 1, '2026-01-09'),
(1, 2, 2, '2026-01-09'),
(1, 3, 3, '2026-01-09'),
(1, 4, 4, '2026-01-09'),
(1, 5, 5, '2026-01-09'),
(1, 6, 6, '2026-01-09'),
(2, 10, 1, '2026-01-09'),
(2, 9, 2, '2026-01-09');

-- ListeningHistory
-- dane beda dopisowane poprzez R;
INSERT INTO ListeningHistory (song_version_id, listened_at, listened_seconds, is_full_played) VALUES
(13, '2026-01-17 09:00:00', 373, TRUE),
(13, '2026-01-17 12:15:00', 373, TRUE),
(13, '2026-01-18 18:40:00', 373, TRUE),
(13, '2026-01-19 21:05:00', 373, TRUE),
(1,  '2026-01-17 10:10:00', 213, TRUE),
(1,  '2026-01-18 11:25:00', 213, TRUE),
(1,  '2026-01-19 14:55:00', 213, TRUE),
(10, '2026-01-17 16:00:00', 230, TRUE),
(10, '2026-01-18 16:30:00', 230, TRUE),
(4,  '2026-01-17 20:10:00', 231, FALSE),
(7,  '2026-01-17 22:00:00', 226, TRUE);


-------------------------------------- BOTTOM LINE --------------------------------------
-- Importowanie
-- \i 'C:/Users/Saskia/Desktop/Studia/Bazy danych/PROJEKT/song_player_db.sql'

-- Usuwanie tabel z pamięci
-- DROP TABLE IF EXISTS ListeningHistory, PlaylistItems, Playlists, SongVersions, SongsGenres, SongsArtists, Songs, MusicAlbums, VersionTypes, Languages, MusicGenres, Artists CASCADE;

-- Fajne wyswietlanie TABEL
-- \x off
-- \pset pager off
-- \pset format aligned
-- \pset expanded off


