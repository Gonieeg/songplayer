------------------ FUNKCJE DOT. PIOSENEK ------------------
-- DODAJ PIOSENKE
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

-- USUŃ PIOSENKE
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

-- ZMODYFIKUJ PIOSENKE
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

-- DODAJ NOWA WERSJE PIOSENKI
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

-- USUN WERSJE PIOSENKI
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