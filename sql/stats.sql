------------------ FUNKCJE DOT. STATYSTYK ------------------
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