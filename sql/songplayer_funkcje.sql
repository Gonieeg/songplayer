-------------------------------------- FUNKCJE --------------------------------------
------------------ DODAJ PIOSENKE ------------------
CREATE OR REPLACE FUNCTION add_song(
    artysci VARCHAR(255)[],      -- max 3 artystow
    tytul VARCHAR(255),
    album VARCHAR(255),
    jezyk VARCHAR(255),
    rok_wydania INTEGER,
    gatunki INTEGER[],           -- max 3 gatunki, zbieramy "wektor"
    wersja VARCHAR(255),
    ile_trwa INTEGER,
    data_wersji DATE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    id_artysty_albumu INTEGER; 	-- ID pierwszego artysty przypisanego do albumu 
    id_albumu INTEGER;
    id_jezyka INTEGER; 			-- Languages
    id_piosenki INTEGER;		-- Songs
    id_typu_wersji INTEGER;		-- VersionTypes
    nazwa_artysty VARCHAR(255);	-- do petli
    id_artysty INTEGER;			-- do petli
	nazwa_gatunku VARCHAR(255);	-- do petli
    id_gatunku INTEGER;			-- do petli
BEGIN
    -- USTAWIENIE LIMITOW
	-- max 3 artystow
    IF artysci IS NULL OR array_length(artysci, 1) IS NULL OR array_length(artysci, 1) = 0 THEN
        RAISE EXCEPTION 'Musisz podac co najmniej 1 artyste.';
    END IF;
    IF array_length(artysci, 1) > 3 THEN
        RAISE EXCEPTION 'Maksymalnie 3 artystow.';
    END IF;
	-- max 3 gatunki
    IF gatunki IS NULL OR array_length(gatunki, 1) IS NULL OR array_length(gatunki, 1) = 0 THEN
        RAISE EXCEPTION 'Musisz podac co najmniej 1 gatunek.';
    END IF;
    IF array_length(gatunki, 1) > 3 THEN
        RAISE EXCEPTION 'Maksymalnie 3 gatunki.';
    END IF;
	-- upewniamy sie ze czas trwania jest ok
    IF ile_trwa IS NULL OR ile_trwa <= 0 THEN
        RAISE EXCEPTION 'Czas trwania musi byc > 0.';
    END IF;
	-- pierwsza nagrana piosenka "Au Clair de la Lune", nie moze byc wczesniejszy rok
    IF rok_wydania IS NULL OR rok_wydania <= 1860 THEN
        RAISE EXCEPTION 'Rok wydania musi byc > 1860.';
    END IF;

    -- JEZYK: istnieje -> wpisujemy, nie istnieje -> dodajemy ID i nazwe 
    INSERT INTO Languages(language)
    VALUES (jezyk)
    ON CONFLICT (language) DO UPDATE SET language = EXCLUDED.language
    RETURNING language_id INTO id_jezyka;

    -- ARTYSTA ALBUMU: istnieje -> pierwszy z listy, nie istnieje -> dodaj
    nazwa_artysty := artysci[1];
    INSERT INTO Artists(name)
    VALUES (nazwa_artysty)
    ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
    RETURNING artist_id INTO id_artysty_albumu;

    -- ALBUM: istnieje -> wpisujemy, nie istnieje -> dodaj
    INSERT INTO MusicAlbums(title, artist_id, release_year)
    VALUES (album, id_artysty_albumu, rok_wydania)
    ON CONFLICT (title, artist_id) DO UPDATE SET release_year = EXCLUDED.release_year
    RETURNING album_id INTO id_albumu;

    -- PIOSENKA: istnieje -> wpisujemy, nie istnieje -> dodaj
    INSERT INTO Songs(title, album_id, release_year, language_id)
    VALUES (tytul, id_albumu, rok_wydania, id_jezyka)
    ON CONFLICT (title, album_id) DO UPDATE
      SET release_year = EXCLUDED.release_year,
          language_id  = EXCLUDED.language_id
    RETURNING Songs.song_id INTO id_piosenki;

    -- ARTYSCI: loop dla i<=3, nie istnieja -> dodaj + relacja
    FOREACH nazwa_artysty IN ARRAY artysci LOOP
        INSERT INTO Artists(name)
        VALUES (nazwa_artysty)
        ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
        RETURNING artist_id INTO id_artysty;

        INSERT INTO SongsArtists(song_id, artist_id)
        VALUES (id_piosenki, id_artysty)
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- GATUNKI: loop dla i<=3, nie istnieja -> dodaj + relacja
    FOREACH nazwa_gatunku IN ARRAY gatunki LOOP
        INSERT INTO MusicGenres(genre)
        VALUES (nazwa_gatunku)
        ON CONFLICT (genre) DO UPDATE SET genre = EXCLUDED.genre
        RETURNING genre_id INTO id_gatunku;

        INSERT INTO SongsGenres(song_id, genre_id)
        VALUES (id_piosenki, id_gatunku)
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- WERSJA: nie istnieja -> dodaj + relacja
    INSERT INTO VersionTypes(name)
	VALUES (wersja)
	ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
	RETURNING version_type_id INTO id_typu_wersji;

    INSERT INTO SongVersions(song_id, version_type_id, duration, created_at)
	VALUES (id_piosenki, id_typu_wersji, ile_trwa, data_wersji)
	ON CONFLICT (song_id, version_type_id, created_at) DO UPDATE
		SET duration = EXCLUDED.duration;

    RETURN 'Dodano/uzupelniono piosenke (song_id=' || id_piosenki || ').';
END;
$$;
-- Przyklady uzycia
-- SELECT add_song( ARRAY['Dea Matrona', 'David Bisbal'], 'Red Button', 'For Your Sins', 'en', 2024, ARRAY[2, 3], 'original', 176, DATE '2024-10-18' );

------------------ USUŃ PIOSENKE ------------------
CREATE OR REPLACE FUNCTION delete_song(id_piosenki INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE ile_wersji INTEGER;
BEGIN
    -- sprawdzamy czy piosenka istnieje
    IF NOT EXISTS (SELECT 1 FROM Songs WHERE song_id = id_piosenki) THEN
        RETURN 'Nie ma piosenki o id=' || id_piosenki || '.';
    END IF;

    -- usuwamy najpierw jej relacje z artystą i gatunkiem
    DELETE FROM SongsArtists WHERE song_id = id_piosenki;
    DELETE FROM SongsGenres  WHERE song_id = id_piosenki;

    -- liczymy ile wersji usunie sie kaskadowo
    SELECT COUNT(*) INTO ile_wersji
    FROM SongVersions
    WHERE song_id = id_piosenki;

    -- usun (tez z SongVersions, PlaylistItems i ListeningHistory przez kaskady)
    DELETE FROM Songs
    WHERE song_id = id_piosenki;

    RETURN 'Usunieto piosenke id=' || id_piosenki || ' oraz jej ' || ile_wersji || ' wersji.';
END;
$$;
-- Przyklady uzycia
-- SELECT song_id FROM Songs WHERE title = 'To nie tak jak myslisz';
-- SELECT delete_song(5);

------------------ DODAJ NOWA WERSJE PIOSENKI ------------------
CREATE OR REPLACE FUNCTION add_version(
    id_piosenki INTEGER,
    wersja VARCHAR(255),
    ile_trwa INTEGER,
    data_wersji DATE DEFAULT CURRENT_DATE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    id_typu_wersji INTEGER;
    id_wersji INTEGER;
BEGIN
    -- sprawdzamy czy piosenka istnieje
    IF NOT EXISTS (SELECT 1 FROM Songs WHERE song_id = id_piosenki) THEN
        RETURN 'Nie ma piosenki o id=' || id_piosenki || '.';
    END IF;

    -- WERSJA: nie istnieje -> dodaj typ
    INSERT INTO VersionTypes(name)
    VALUES (wersja)
    ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
    RETURNING version_type_id INTO id_typu_wersji;

    -- upewniamy sie ze czas trwania jest ok
    IF ile_trwa IS NULL OR ile_trwa <= 0 THEN
        RAISE EXCEPTION 'Czas trwania musi byc > 0.';
    END IF;

    -- mamy UNIQUE(song_id, version_type_id, created_at) dodajemy/uzupelniamy
    INSERT INTO SongVersions(song_id, version_type_id, duration, created_at)
    VALUES (id_piosenki, id_typu_wersji, ile_trwa, data_wersji)
    ON CONFLICT (song_id, version_type_id, created_at) DO UPDATE
      SET duration = EXCLUDED.duration
    RETURNING song_version_id INTO id_wersji;

    RETURN 'Dodano nowa wersje piosenki.';
END;
$$;

-- Przyklady uzycia
-- SELECT song_id FROM Songs WHERE title = 'Dlugosc dzwieku samotnosci';
-- SELECT add_version(10, 'nightcore', 190, DATE '2026-01-17');
-- SELECT add_version(10, 'remix dj', 193);

------------------ USUN WERSJE PIOSENKI ------------------
CREATE OR REPLACE FUNCTION delete_version(id_wersji INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    id_piosenki INTEGER;
    ile_wersji INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM SongVersions WHERE song_version_id = id_wersji) THEN
        RETURN 'Nie ma wersji o id=' || id_wersji || '.';
    END IF;

    DELETE FROM SongVersions
    WHERE song_version_id = id_wersji;

    RETURN 'Usunieto wersje piosenki.';
END;
$$;

-- Przyklady uzycia
-- SELECT sv.song_version_id, vt.name AS typ_wersji, sv.duration, sv.created_at FROM Songs s JOIN SongVersions sv ON sv.song_id = s.song_id JOIN VersionTypes vt ON vt.version_type_id = sv.version_type_id WHERE s.title = 'Dlugosc dzwieku samotnosci';
-- SELECT delete_version(12);

------------------ ZMODYFIKUJ PIOSENKE ------------------
CREATE OR REPLACE FUNCTION modify_song(
    id_piosenki INTEGER,
    nowy_jezyk VARCHAR(255) DEFAULT NULL,

    dodaj_artyste VARCHAR(255) DEFAULT NULL,
    usun_artyste VARCHAR(255) DEFAULT NULL,

    dodaj_gatunek VARCHAR(255) DEFAULT NULL,
    usun_gatunek VARCHAR(255) DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    id_jezyka INTEGER;
    id_artysty INTEGER;
    id_gatunku INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Songs WHERE song_id = id_piosenki) THEN
        RETURN 'Nie ma piosenki o id=' || id_piosenki || '.';
    END IF;

    -- ZMIANA JEZYKA (opcjonalne, nie istnieje -> dodajemy)
    IF nowy_jezyk IS NOT NULL THEN
        INSERT INTO Languages(language)
        VALUES (nowy_jezyk)
        ON CONFLICT (language) DO UPDATE SET language = EXCLUDED.language
        RETURNING language_id INTO id_jezyka;

        UPDATE Songs
        SET language_id = id_jezyka
        WHERE song_id = id_piosenki;
    END IF;

    -- DODAJ ARTYSTE (opcjonalne, nie istnieje -> dodajemy)
    IF dodaj_artyste IS NOT NULL THEN
        INSERT INTO Artists(name)
        VALUES (dodaj_artyste)
        ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
        RETURNING artist_id INTO id_artysty;

        INSERT INTO SongsArtists(song_id, artist_id)
        VALUES (id_piosenki, id_artysty)
        ON CONFLICT DO NOTHING;
    END IF;

    -- USUN ARTYSTE (opcjonalne)
    IF usun_artyste IS NOT NULL THEN
        SELECT artist_id INTO id_artysty
        FROM Artists
        WHERE name = usun_artyste
        LIMIT 1;
		
        IF id_artysty IS NOT NULL THEN
            DELETE FROM SongsArtists
            WHERE song_id = id_piosenki AND artist_id = id_artysty;
        END IF;
    END IF;

    -- DODAJ GATUNEK (opcjonalne, nie istnieje -> dodajemy)
    IF dodaj_gatunek IS NOT NULL THEN
        INSERT INTO MusicGenres(genre)
        VALUES (dodaj_gatunek)
        ON CONFLICT (genre) DO UPDATE SET genre = EXCLUDED.genre
        RETURNING genre_id INTO id_gatunku;
        INSERT INTO SongsGenres(song_id, genre_id)
        VALUES (id_piosenki, id_gatunku)
        ON CONFLICT DO NOTHING;
    END IF;

    -- USUN GATUNEK (opcjonalne)
    IF usun_gatunek IS NOT NULL THEN
        SELECT genre_id INTO id_gatunku
        FROM MusicGenres
        WHERE genre = usun_gatunek
        LIMIT 1;
        IF id_gatunku IS NOT NULL THEN
            DELETE FROM SongsGenres
            WHERE song_id = id_piosenki AND genre_id = id_gatunku;
        END IF;
    END IF;

    RETURN 'Zmodyfikowano piosenke o id=' || id_piosenki || '.';
END;
$$;

-- Przyklady uzycia
-- SELECT modify_song(10, dodaj_gatunek => 'rock');
-- SELECT modify_song(10, dodaj_artyste => 'Rozni');
-- SELECT modify_song(10, usun_artyste => 'Rozni');

----------------- ODSŁUCHIWANIE -------------------
------ sluchanie 1 piosenki bez next (przed automatyzacja)
CREATE OR REPLACE FUNCTION play_song(svid INTEGER, sec INTEGER)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO ListeningHistory
        (song_version_id, listened_at, listened_seconds, is_full_played)
    SELECT
        svid,
        now(),
        sec,
        sec >= duration * 0.8
    FROM SongVersions
    WHERE song_version_id = svid;
END;
$$;

-- Odtwarzanie - start
CREATE OR REPLACE FUNCTION start_playback(sv_id INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE sid INTEGER;
BEGIN
    INSERT INTO PlaybackSessions(song_version_id, started_at, last_update)
    VALUES (sv_id, now(), now())
    RETURNING session_id INTO sid;

    RETURN sid;
END;
$$;

-- Odtwarzanie - pauza/stop
CREATE OR REPLACE FUNCTION pause_playback(p_session_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE PlaybackSessions
    SET
        listened_seconds = listened_seconds
            + EXTRACT(EPOCH FROM (now() - last_update))::INTEGER,
        last_update = now(),
        is_active = FALSE
    WHERE session_id = p_session_id;
END;
$$;

-- Odtwarzanie - zakonczenie
CREATE OR REPLACE FUNCTION finish_playback(p_session_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    sv_id INTEGER;
    sec INTEGER;
    dur INTEGER;
BEGIN
    SELECT ps.song_version_id, ps.listened_seconds, sv.duration
    INTO sv_id, sec, dur
    FROM PlaybackSessions ps
    JOIN SongVersions sv USING(song_version_id)
    WHERE ps.session_id = p_session_id;

    INSERT INTO ListeningHistory(song_version_id, listened_at, listened_seconds, is_full_played)
    VALUES (sv_id, now(), sec, sec >= dur * 0.8);

    DELETE FROM PlaybackSessions WHERE session_id = p_session_id;
END;
$$;

-------------------------------------- PLAYLISTY --------------------------------------
-- 1. Pobieranie wszystkich playlist
CREATE OR REPLACE FUNCTION get_all_playlists()
RETURNS TABLE(playlist_id INTEGER, name VARCHAR, created_at DATE) AS $$
BEGIN
    RETURN QUERY SELECT p.playlist_id, p.name, p.created_at 
                 FROM Playlists p ORDER BY p.playlist_id DESC;
END;
$$ LANGUAGE plpgsql;

-- 2. Pobieranie opcji do wyszukiwarki utworów
CREATE OR REPLACE FUNCTION get_song_version_choices()
RETURNS TABLE(id INTEGER, display_label TEXT) AS $$
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
$$ LANGUAGE plpgsql;

-- 3.Pobieranie zawartości konkretnej playlisty
CREATE OR REPLACE FUNCTION get_playlist_contents(p_id INTEGER)
RETURNS TABLE(
    item_position INTEGER, 
    song_title VARCHAR, 
    album_title VARCHAR, 
    authors TEXT, 
    version VARCHAR, 
    duration INTEGER, 
    song_version_id INTEGER
) AS $$
BEGIN
    RETURN QUERY 
    SELECT 
        pi.position,
        s.title, 
        a.title, 
        STRING_AGG(art.name, ', '), 
        vt.name, 
        sv.duration, 
        pi.song_version_id
    FROM PlaylistItems pi
    JOIN SongVersions sv ON pi.song_version_id = sv.song_version_id
    JOIN Songs s ON sv.song_id = s.song_id
    JOIN MusicAlbums a ON s.album_id = a.album_id
    JOIN VersionTypes vt ON sv.version_type_id = vt.version_type_id
    LEFT JOIN SongsArtists sa ON s.song_id = sa.song_id
    LEFT JOIN Artists art ON sa.artist_id = art.artist_id
    WHERE pi.playlist_id = p_id
    GROUP BY pi.position, s.title, a.title, vt.name, sv.duration, pi.song_version_id
    ORDER BY pi.position;
END;
$$ LANGUAGE plpgsql;

-- 4. Dodawanie utworu do playlisty
-- FUNKCJA TECHNICZNA – NIE WOLAC Z UI
CREATE OR REPLACE FUNCTION add_song_to_playlist_at(p_id INTEGER, sv_id INTEGER, p_pos INTEGER)
RETURNS VOID AS $$
BEGIN
    -- walidacja playlisty
    IF NOT EXISTS (SELECT 1 FROM Playlists WHERE playlist_id = p_id) THEN
        RAISE EXCEPTION 'Nie ma playlisty o id=%', p_id;
    END IF;

    -- walidacja wersji piosenki
    IF NOT EXISTS (SELECT 1 FROM SongVersions WHERE song_version_id = sv_id) THEN
        RAISE EXCEPTION 'Nie ma song_version o id=%', sv_id;
    END IF;

    -- walidacja pozycji
    IF p_pos IS NULL OR p_pos <= 0 THEN
        RAISE EXCEPTION 'Pozycja musi byc liczba > 0';
    END IF;

    INSERT INTO PlaylistItems (playlist_id, song_version_id, position, added_at)
    VALUES (p_id, sv_id, p_pos, CURRENT_DATE);
END;
$$ LANGUAGE plpgsql;

-- 4.2 Dodawanie utworu do playlisty, ale automatycznie
CREATE OR REPLACE FUNCTION add_song_to_playlist_auto(p_id INTEGER, sv_id INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    new_pos INTEGER;
BEGIN
    -- walidacja playlisty 
    IF NOT EXISTS (SELECT 1 FROM Playlists WHERE playlist_id = p_id) THEN
        RAISE EXCEPTION 'Nie ma playlisty o id=%', p_id;
    END IF;

    -- walidacja wersji
    IF NOT EXISTS (SELECT 1 FROM SongVersions WHERE song_version_id = sv_id) THEN
        RAISE EXCEPTION 'Nie ma song_version o id=%', sv_id;
    END IF;

    -- automat - pozycja na koncu
    SELECT COALESCE(MAX(position), 0) + 1
    INTO new_pos
    FROM PlaylistItems
    WHERE playlist_id = p_id;

    -- uzycie funkcji z 4
    PERFORM add_song_to_playlist_at(p_id, sv_id, new_pos);
    RETURN new_pos;
END;
$$;

-- 5. Dodawanie playlisty
CREATE OR REPLACE FUNCTION add_new_playlist(p_name VARCHAR)
RETURNS VOID AS $$
BEGIN
    INSERT INTO Playlists (name, created_at) 
    VALUES (p_name, CURRENT_DATE);
END;
$$ LANGUAGE plpgsql;

-- 6. Usuwanie playlisty
CREATE OR REPLACE FUNCTION delete_playlist(p_id INTEGER)
RETURNS VOID AS $$
BEGIN
    DELETE FROM Playlists WHERE playlist_id = p_id;
END;
$$ LANGUAGE plpgsql;


-- 7. Usuwanie utworu z playlisty
CREATE OR REPLACE FUNCTION remove_song_from_playlist(p_id INTEGER, p_pos INTEGER)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE max_pos INTEGER;
BEGIN
     -- walidacja playlisty
    IF NOT EXISTS (SELECT 1 FROM Playlists WHERE playlist_id = p_id) THEN
        RAISE EXCEPTION 'Nie ma playlisty o id=%', p_id;
    END IF;

    -- sprawdzamy ile elementow ma lista
    SELECT MAX(position)
    INTO max_pos
    FROM PlaylistItems
    WHERE playlist_id = p_id;

    IF max_pos IS NULL THEN
        RAISE EXCEPTION 'Playlista % jest pusta', p_id;
    END IF;

    -- usuwamy element
    DELETE FROM PlaylistItems 
    WHERE playlist_id = p_id AND position = p_pos;

    -- domykamy pozycje
    UPDATE PlaylistItems
    SET position = position - 1
    WHERE playlist_id = p_id
      AND position > p_pos;
END;
$$;

-- 8. Zmiana pozycji na playliscie
CREATE OR REPLACE FUNCTION move_playlist_item(p_id INTEGER, old_pos INTEGER, new_pos INTEGER)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    max_pos INTEGER;
BEGIN
    -- walidacja istnienia playlisty
    IF NOT EXISTS (SELECT 1 FROM Playlists WHERE playlist_id = p_id) THEN
        RAISE EXCEPTION 'Nie ma playlisty o id=%', p_id;
    END IF;

    -- max pozycja
    SELECT MAX(position)
    INTO max_pos
    FROM PlaylistItems
    WHERE playlist_id = p_id;

    -- chcemy zmienic pozycje na playliscie bez utworow
    IF max_pos IS NULL THEN
        RAISE EXCEPTION 'Playlista % jest pusta', p_id;
    END IF;

    -- walidacja pozycji
    IF old_pos < 1 OR old_pos > max_pos THEN
        RAISE EXCEPTION 'old_pos=% poza zakresem 1..%', old_pos, max_pos;
    END IF;
    IF new_pos < 1 OR new_pos > max_pos THEN
        RAISE EXCEPTION 'new_pos=% poza zakresem 1..%', new_pos, max_pos;
    END IF;

    -- nic nie robimy, bo old=new
    IF old_pos = new_pos THEN
        RETURN;
    END IF;

    -- tymczasowo przenosimy pozycje poza liste
    UPDATE PlaylistItems
    SET position = max_pos + 1
    WHERE playlist_id = p_id AND position = old_pos;

    -- tworzymy dziure / przesuwamy pozostale w zaleznosci czy chcemy
    -- pozycje nizej
    IF old_pos < new_pos THEN
        UPDATE PlaylistItems
        SET position = position - 1
        WHERE playlist_id = p_id
          AND position > old_pos
          AND position <= new_pos;
    -- pozycje wyzej
    ELSE
        UPDATE PlaylistItems
        SET position = position + 1
        WHERE playlist_id = p_id
          AND position >= new_pos
          AND position < old_pos;
    END IF;

    -- wstawiamy nasza piosenke na odpowiednie miejsce
    UPDATE PlaylistItems
    SET position = new_pos
    WHERE playlist_id = p_id AND position = max_pos + 1;
END;
$$;

-- 9. Odtworz utwor (zalozenie - user nie zna id, po prostu wybiera utwor)
CREATE OR REPLACE FUNCTION play_playlist_item(p_id INTEGER, p_pos INTEGER, listened_sec INTEGER)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    sv_id INTEGER;
    dur INTEGER;
BEGIN
    -- walidacja playlisty
    IF NOT EXISTS (SELECT 1 FROM Playlists WHERE playlist_id = p_id) THEN
        RAISE EXCEPTION 'Nie ma playlisty o id=%', p_id;
    END IF;

    -- bierzemy song_version_id i duration
    SELECT sv.song_version_id, sv.duration
    INTO sv_id, dur
    FROM PlaylistItems pi
    JOIN SongVersions sv ON pi.song_version_id = sv.song_version_id
    WHERE pi.playlist_id = p_id
      AND pi.position = p_pos;

    IF sv_id IS NULL THEN
        RAISE EXCEPTION 'Brak elementu playlisty (playlist_id=%, pos=%)', p_id, p_pos;
    END IF;

    -- walidacja czasu
    IF listened_sec < 0 THEN
        RAISE EXCEPTION 'listened_sec musi byc >= 0';
    END IF;

    INSERT INTO ListeningHistory(song_version_id, listened_at, listened_seconds, is_full_played)
    VALUES (sv_id, now(), listened_sec, listened_sec >= dur * 0.8);
END;
$$;

-------------------------------------- STATYSTYKI --------------------------------------
--- STATYSTYKI Z CAŁEJ HISTORII SŁUCHANIA
CREATE VIEW statistics_all AS
WITH base_stats AS (
    SELECT
        SUM(listened_seconds) AS total_listened_time,
        COUNT(*) AS playcount,
        COUNT(*) FILTER (WHERE is_full_played) AS fullplaycount
    FROM ListeningHistory
),
most_listened_version AS (
    SELECT
        vt.name AS version_type,
        s.title
    FROM ListeningHistory lh
    JOIN SongVersions sv USING(song_version_id)
    JOIN VersionTypes vt USING(version_type_id)
    JOIN Songs s USING(song_id)
	WHERE lh.is_full_played = TRUE
    GROUP BY vt.name, s.title
    ORDER BY COUNT(*) DESC
    LIMIT 1
),
most_listened_song AS (
    SELECT
        s.title
    FROM ListeningHistory lh
    JOIN SongVersions sv USING(song_version_id)
    JOIN Songs s USING(song_id)
	WHERE lh.is_full_played = TRUE
    GROUP BY s.song_id, s.title
    ORDER BY COUNT(*) DESC
    LIMIT 1
),
favourite_genre AS (
    SELECT
        mg.genre
    FROM ListeningHistory lh
    JOIN SongVersions sv USING(song_version_id)
    JOIN SongsGenres sg USING(song_id)
    JOIN MusicGenres mg USING(genre_id)
	WHERE lh.is_full_played = TRUE
    GROUP BY mg.genre
    ORDER BY COUNT(*) DESC
    LIMIT 1
)
SELECT
    ms.title AS most_listened_song,
    mv.title AS most_listened_version_title,
	mv.version_type AS most_listened_song_version,
    fg.genre AS favourite_genre,
    bs.playcount AS total_playcount,
    bs.fullplaycount AS songs_fully_played,
    bs.total_listened_time / 60 AS total_minutes_listened
FROM base_stats bs
CROSS JOIN most_listened_version mv
CROSS JOIN most_listened_song ms
CROSS JOIN favourite_genre fg;


<<<<<<< Updated upstream
=======
--- STATYSTYKI OD DO
----- np. SELECT * FROM monthly_stats('2026-01-01', '2026-01-21');

CREATE OR REPLACE FUNCTION monthly_stats(od_dnia DATE, do_dnia DATE)
RETURNS TABLE(
	most_listened_song VARCHAR(255),
	most_listened_version_title VARCHAR(255),
	most_listened_song_version VARCHAR(255),
	favourite_genre VARCHAR(255),
	total_playcount INT,
	songs_fully_played INT,
	total_minutes_listened INT)
LANGUAGE plpgsql
AS $$
BEGIN
	RETURN QUERY
	WITH base_stats AS (
	SELECT
		SUM(listened_seconds) AS total_listened_time,
		COUNT(*) AS playcount,
		COUNT(*) FILTER (WHERE is_full_played) AS fullplaycount
	FROM ListeningHistory
	WHERE listened_at >= od_dnia
	  AND listened_at < do_dnia + INTERVAL '1 day'
	),
	most_listened_version AS (
		SELECT
			vt.name AS version_type,
			s.title
		FROM ListeningHistory lh
		JOIN SongVersions sv USING(song_version_id)
		JOIN VersionTypes vt USING(version_type_id)
		JOIN Songs s USING(song_id)
		WHERE (lh.is_full_played = TRUE 
			AND (lh.listened_at >= od_dnia 
				AND lh.listened_at < do_dnia + INTERVAL '1 day'))
		GROUP BY vt.name, s.title
		ORDER BY COUNT(*) DESC
		LIMIT 1
	),
	most_listened_song AS (
		SELECT
			s.title
		FROM ListeningHistory lh
		JOIN SongVersions sv USING(song_version_id)
		JOIN Songs s USING(song_id)
		WHERE (lh.is_full_played = TRUE
			AND (lh.listened_at >= od_dnia 
				AND lh.listened_at < do_dnia + INTERVAL '1 day'))
		GROUP BY s.song_id, s.title
		ORDER BY COUNT(*) DESC
		LIMIT 1
	),
	favourite_genre AS (
		SELECT
			mg.genre
		FROM ListeningHistory lh
		JOIN SongVersions sv USING(song_version_id)
		JOIN SongsGenres sg USING(song_id)
		JOIN MusicGenres mg USING(genre_id)
		WHERE (lh.is_full_played = TRUE
			AND (lh.listened_at >= od_dnia 
				AND lh.listened_at < do_dnia + INTERVAL '1 day'))
		GROUP BY mg.genre
		ORDER BY COUNT(*) DESC
		LIMIT 1
	)
	SELECT
		ms.title AS most_listened_song,
		mv.title AS most_listened_version_title,
		mv.version_type AS most_listened_song_version,
		fg.genre AS favourite_genre,
		bs.playcount::INT AS total_playcount,
		bs.fullplaycount::INT AS songs_fully_played,
		(bs.total_listened_time / 60)::INT AS total_minutes_listened
	FROM base_stats bs
	CROSS JOIN most_listened_version mv
	CROSS JOIN most_listened_song ms
	CROSS JOIN favourite_genre fg;
END;
$$;
