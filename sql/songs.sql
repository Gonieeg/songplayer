------------------ FUNKCJE DOT. PIOSENEK ------------------
-- DODAJ PIOSENKE
CREATE OR REPLACE FUNCTION add_song(
    artists VARCHAR(255)[],      -- max 3 artystow
    songtitle VARCHAR(255),
    album VARCHAR(255),
    lang VARCHAR(255),
    year_published INTEGER,
    genres VARCHAR(255)[],           -- max 3 gatunki, zbieramy "wektor" nazw
    songversion VARCHAR(255),
    dur INTEGER,
    version_date DATE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    albumartid INTEGER; 	-- ID pierwszego artysty przypisanego do albumu 
    albumid INTEGER;
    langid INTEGER; 			-- Languages
    sid INTEGER;		-- Songs (song id)
    vtid INTEGER;		-- VersionTypes (id_typu_wersji)
    artist_name VARCHAR(255);	-- do petli
    artid INTEGER;			-- do petli
	genre_name VARCHAR(255);	-- do petli
    gid INTEGER;			-- do petli (genre id)
BEGIN
    -- USTAWIENIE LIMITOW
	-- max 3 artystow
    IF artists IS NULL OR array_length(artists, 1) IS NULL OR array_length(artists, 1) = 0 THEN
        RAISE EXCEPTION 'Musisz podac co najmniej 1 artyste.';
    END IF;
    IF array_length(artists, 1) > 3 THEN
        RAISE EXCEPTION 'Maksymalnie 3 artystow.';
    END IF;
	-- max 3 gatunki
    IF genres IS NULL OR array_length(genres, 1) IS NULL OR array_length(genres, 1) = 0 THEN
        RAISE EXCEPTION 'Musisz podac co najmniej 1 gatunek.';
    END IF;
    IF array_length(genres, 1) > 3 THEN
        RAISE EXCEPTION 'Maksymalnie 3 gatunki.';
    END IF;
	-- upewniamy sie ze czas trwania jest ok
    IF dur IS NULL OR dur <= 0 THEN
        RAISE EXCEPTION 'Czas trwania musi byc > 0.';
    END IF;
	-- pierwsza nagrana piosenka "Au Clair de la Lune", nie moze byc wczesniejszy rok
    IF year_published IS NULL OR year_published <= 1860 THEN
        RAISE EXCEPTION 'Rok wydania musi byc > 1860.';
    END IF;

    -- JEZYK: istnieje -> wpisujemy, nie istnieje -> dodajemy ID i nazwe 
    INSERT INTO Languages(language)
    VALUES (lang)
    ON CONFLICT (language) DO UPDATE SET language = EXCLUDED.language
    RETURNING language_id INTO langid;

    -- ARTYSTA ALBUMU: istnieje -> pierwszy z listy, nie istnieje -> dodaj
    artist_name := artists[1];
    INSERT INTO Artists(name)
    VALUES (artist_name)
    ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
    RETURNING artist_id INTO albumartid;

    -- ALBUM: istnieje -> wpisujemy, nie istnieje -> dodaj
    INSERT INTO MusicAlbums(title, artist_id, release_year)
    VALUES (album, albumartid, year_published)
    ON CONFLICT (title, artist_id) DO UPDATE SET release_year = EXCLUDED.release_year
    RETURNING album_id INTO albumid;

    -- PIOSENKA: istnieje -> wpisujemy, nie istnieje -> dodaj
    INSERT INTO Songs(title, album_id, release_year, language_id)
    VALUES (songtitle, albumid, year_published, langid)
    ON CONFLICT (title, album_id) DO UPDATE
      SET release_year = EXCLUDED.release_year,
          language_id  = EXCLUDED.language_id
    RETURNING Songs.song_id INTO sid;

    -- ARTYSCI: loop dla i<=3, nie istnieja -> dodaj + relacja
    FOREACH artist_name IN ARRAY artists LOOP
        INSERT INTO Artists(name)
        VALUES (artist_name)
        ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
        RETURNING artist_id INTO artid;

        INSERT INTO SongsArtists(song_id, artist_id)
        VALUES (sid, artid)
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- GATUNKI: loop dla i<=3, nie istnieja -> dodaj + relacja
    FOREACH genre_name IN ARRAY genres LOOP
        INSERT INTO MusicGenres(genre)
        VALUES (genre_name)
        ON CONFLICT (genre) DO UPDATE SET genre = EXCLUDED.genre
        RETURNING genre_id INTO gid;

        INSERT INTO SongsGenres(song_id, genre_id)
        VALUES (sid, gid)
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- WERSJA: nie istnieja -> dodaj + relacja
    INSERT INTO VersionTypes(name)
	VALUES (songversion)
	ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
	RETURNING version_type_id INTO vtid;

    INSERT INTO SongVersions(song_id, version_type_id, duration, created_at)
	VALUES (sid, vtid, dur, version_date)
	ON CONFLICT (song_id, version_type_id, created_at) DO UPDATE
		SET duration = EXCLUDED.duration;

    RETURN 'Dodano/uzupelniono piosenke (song_id=' || sid || ').';
END;
$$;

-- USUŃ PIOSENKE
CREATE OR REPLACE FUNCTION delete_song(sid INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE ile_wersji INTEGER;
BEGIN
    -- sprawdzamy czy piosenka istnieje
    IF NOT EXISTS (SELECT 1 FROM Songs WHERE song_id = sid) THEN
        RETURN 'Nie ma piosenki o id=' || sid || '.';
    END IF;

    -- usuwamy najpierw jej relacje z artystą i gatunkiem
    DELETE FROM SongsArtists WHERE song_id = sid;
    DELETE FROM SongsGenres  WHERE song_id = sid;

    -- liczymy ile wersji usunie sie kaskadowo
    SELECT COUNT(*) INTO ile_wersji
    FROM SongVersions
    WHERE song_id = sid;

    -- usun (tez z SongVersions, PlaylistItems i ListeningHistory przez kaskady)
    DELETE FROM Songs
    WHERE song_id = sid;

    RETURN 'Usunieto piosenke id=' || sid || ' oraz jej ' || ile_wersji || ' wersji.';
END;
$$;

-- ZMODYFIKUJ PIOSENKE
CREATE OR REPLACE FUNCTION modify_song(
    sid INTEGER,
    new_lang VARCHAR(255) DEFAULT NULL,

    add_artist VARCHAR(255) DEFAULT NULL,
    delete_artist VARCHAR(255) DEFAULT NULL,

    add_genre VARCHAR(255) DEFAULT NULL,
    delete_genre VARCHAR(255) DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    langid INTEGER;
    artid INTEGER;
    gid INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Songs WHERE song_id = sid) THEN
        RETURN 'Nie ma piosenki o id=' || sid || '.';
    END IF;

    -- ZMIANA JEZYKA (opcjonalne, nie istnieje -> dodajemy)
    IF new_lang IS NOT NULL THEN
        INSERT INTO Languages(language)
        VALUES (new_lang)
        ON CONFLICT (language) DO UPDATE SET language = EXCLUDED.language
        RETURNING language_id INTO langid;

        UPDATE Songs
        SET language_id = langid
        WHERE song_id = sid;
    END IF;

    -- DODAJ ARTYSTE (opcjonalne, nie istnieje -> dodajemy)
    IF add_artist IS NOT NULL THEN
        INSERT INTO Artists(name)
        VALUES (add_artist)
        ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
        RETURNING artist_id INTO artid;

        INSERT INTO SongsArtists(song_id, artist_id)
        VALUES (sid, artid)
        ON CONFLICT DO NOTHING;
    END IF;

    -- USUN ARTYSTE (opcjonalne)
    IF delete_artist IS NOT NULL THEN
        SELECT artist_id INTO artid
        FROM Artists
        WHERE name = delete_artist
        LIMIT 1;
		
        IF artid IS NOT NULL THEN
            DELETE FROM SongsArtists
            WHERE song_id = sid AND artist_id = artid;
        END IF;
    END IF;

    -- DODAJ GATUNEK (opcjonalne, nie istnieje -> dodajemy)
    IF add_genre IS NOT NULL THEN
        INSERT INTO MusicGenres(genre)
        VALUES (add_genre)
        ON CONFLICT (genre) DO UPDATE SET genre = EXCLUDED.genre
        RETURNING genre_id INTO gid;
        INSERT INTO SongsGenres(song_id, genre_id)
        VALUES (sid, gid)
        ON CONFLICT DO NOTHING;
    END IF;

    -- USUN GATUNEK (opcjonalne)
    IF delete_genre IS NOT NULL THEN
        SELECT genre_id INTO gid
        FROM MusicGenres
        WHERE genre = delete_genre
        LIMIT 1;
        IF gid IS NOT NULL THEN
            DELETE FROM SongsGenres
            WHERE song_id = sid AND genre_id = gid;
        END IF;
    END IF;

    RETURN 'Zmodyfikowano piosenke o id=' || sid || '.';
END;
$$;

-- DODAJ NOWA WERSJE PIOSENKI
CREATE OR REPLACE FUNCTION add_version(
    sid INTEGER,
    songversion VARCHAR(255),
    dur INTEGER,
    version_date DATE DEFAULT CURRENT_DATE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    vtid INTEGER;
    vid INTEGER;
BEGIN
    -- sprawdzamy czy piosenka istnieje
    IF NOT EXISTS (SELECT 1 FROM Songs WHERE song_id = sid) THEN
        RETURN 'Nie ma piosenki o id=' || sid || '.';
    END IF;

    -- WERSJA: nie istnieje -> dodaj typ
    INSERT INTO VersionTypes(name)
    VALUES (songversion)
    ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
    RETURNING version_type_id INTO vtid;

    -- upewniamy sie ze czas trwania jest ok
    IF dur IS NULL OR dur <= 0 THEN
        RAISE EXCEPTION 'Czas trwania musi byc > 0.';
    END IF;

    -- mamy UNIQUE(song_id, version_type_id, created_at) dodajemy/uzupelniamy
    INSERT INTO SongVersions(song_id, version_type_id, duration, created_at)
    VALUES (sid, vtid, dur, version_date)
    ON CONFLICT (song_id, version_type_id, created_at) DO UPDATE
      SET duration = EXCLUDED.duration
    RETURNING song_version_id INTO vid;

    RETURN 'Dodano nowa wersje piosenki.';
END;
$$;

-- USUN WERSJE PIOSENKI
CREATE OR REPLACE FUNCTION delete_version(vid INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    sid INTEGER;
    ile_wersji INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM SongVersions WHERE song_version_id = vid) THEN
        RETURN 'Nie ma wersji o id=' || vid || '.';
    END IF;

    DELETE FROM SongVersions
    WHERE song_version_id = vid;

    RETURN 'Usunieto wersje piosenki.';
END;
$$;


-- Zwracania wszystkich wersji danego tytułu
CREATE OR REPLACE FUNCTION get_versions_for_song(p_title VARCHAR)
RETURNS TABLE (
    song_id INTEGER,
    song_title VARCHAR,
    album_title VARCHAR,
    artist_name VARCHAR,
    version_type VARCHAR,
    duration INTEGER,
    created_at DATE
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.song_id,
        s.title AS song_title,
        ma.title AS album_title,
        ar.name AS artist_name,
        vt.name AS version_type,
        sv.duration,
        sv.created_at
    FROM Songs s
    JOIN MusicAlbums ma ON ma.album_id = s.album_id
    JOIN Artists ar ON ar.artist_id = ma.artist_id
    JOIN SongVersions sv ON sv.song_id = s.song_id
    JOIN VersionTypes vt ON vt.version_type_id = sv.version_type_id
    WHERE s.title = p_title
    ORDER BY sv.created_at;
END;
$$;


-- Pobieranie opcji do wyszukiwarki utworów
CREATE OR REPLACE FUNCTION get_song_version_choices()
RETURNS TABLE(id INTEGER, display_label TEXT) 
LANGUAGE plpgsql 
AS $$ 
BEGIN 
    RETURN QUERY 
    SELECT 
        sv.song_version_id, 
        s.title || ' - ' || COALESCE(STRING_AGG(art.name, ', '), 'Unknown') || ' (' || vt.name || ')'
    FROM SongVersions sv
    JOIN Songs s ON sv.song_id = s.song_id
    JOIN VersionTypes vt ON sv.version_type_id = vt.version_type_id
    LEFT JOIN SongsArtists sa ON s.song_id = sa.song_id
    LEFT JOIN Artists art ON sa.artist_id = art.artist_id
    GROUP BY sv.song_version_id, s.title, vt.name
    ORDER BY s.title;
END;
$$;


--- wyświetl wszystkie piosenki (bibliotekę) - widok i funkcja z niego korzystająca 
CREATE OR REPLACE VIEW view_all_songs AS
SELECT
    s.title AS song_title,
    vt.name AS version_type,
    ma.title AS album_title,
    a.name AS artist_name,
    sv.duration AS duration
FROM SongVersions sv
    JOIN Songs s USING (song_id)
    JOIN MusicAlbums ma ON s.album_id = ma.album_id
    JOIN SongsArtists sa ON sa.song_id = s.song_id
    JOIN Artists a ON sa.artist_id = a.artist_id
    JOIN VersionTypes vt USING (version_type_id)
ORDER BY s.title;
---- funkcja do R
CREATE OR REPLACE FUNCTION get_all_songs()
RETURNS TABLE(
    song_title VARCHAR(255),
    version_type VARCHAR(255),
    album_title VARCHAR(255),
    artist_name VARCHAR(255),
    duration INT)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        song_title,
        version_type,
        album_title,
        artist_name,
        duration
    FROM view_all_songs;
END;
$$;
