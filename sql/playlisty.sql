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
RETURNS VOID AS $$
BEGIN
    DELETE FROM PlaylistItems 
    WHERE playlist_id = p_id AND position = p_pos;
END;
$$ LANGUAGE plpgsql;
